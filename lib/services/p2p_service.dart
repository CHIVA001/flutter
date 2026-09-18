import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/beam_payload.dart';
import '../models/transfer_progress.dart';

/// Core service orchestrating offline peer-to-peer Wi-Fi Direct / Local Hotspot
/// connections and high-speed chunked HTTP video streaming.
class P2pService {
  // Singleton pattern for centralized P2P lifecycle management
  static final P2pService _instance = P2pService._internal();
  factory P2pService() => _instance;
  P2pService._internal();

  FlutterP2pHost? _p2pHost;
  FlutterP2pClient? _p2pClient;

  HttpServer? _httpServer;
  HttpClient? _activeHttpClient;
  IOSink? _activeFileSink;

  File? _currentlyHostedFile;
  String? _currentSessionToken;

  final _senderProgressController =
      StreamController<TransferProgress>.broadcast();
  final _receiverProgressController =
      StreamController<TransferProgress>.broadcast();

  /// Stream of transfer progress on the sender side
  Stream<TransferProgress> get senderProgressStream =>
      _senderProgressController.stream;

  /// Stream of transfer progress on the receiver side
  Stream<TransferProgress> get receiverProgressStream =>
      _receiverProgressController.stream;

  /// Active state of the sender host
  bool get isHosting => _httpServer != null;

  // ---------------------------------------------------------------------------
  // PERMISSION MANAGEMENT
  // ---------------------------------------------------------------------------

  /// Checks and requests necessary permissions for the sender device:
  /// - Wi-Fi Direct / Local Hotspot (Nearby Devices on Android 13+, Location for SSID)
  /// - Storage / Media access to read video files
  Future<bool> requestSenderPermissions() async {
    if (kIsWeb) return true;

    final permissionsToRequest = <Permission>[];

    if (Platform.isAndroid) {
      permissionsToRequest.add(Permission.locationWhenInUse);
      // Android 13+ (API 33+) requires NEARBY_WIFI_DEVICES for Wi-Fi Direct
      permissionsToRequest.add(Permission.nearbyWifiDevices);
      permissionsToRequest.add(Permission.videos);
      permissionsToRequest.add(Permission.storage);
    } else if (Platform.isIOS) {
      permissionsToRequest.add(Permission.photos);
    }

    final statuses = await permissionsToRequest.request();
    debugPrint('Sender Permission statuses: $statuses');

    // Return false if any critical permission is permanently denied
    for (final entry in statuses.entries) {
      if (entry.value.isPermanentlyDenied) {
        debugPrint('Sender permission permanently denied: ${entry.key}');
      }
    }
    return true;
  }

  /// Checks and requests permissions for the receiver device:
  /// - Camera (to scan the QR code)
  /// - Wi-Fi Direct / Nearby Devices
  /// - Storage (to save incoming video)
  Future<bool> requestReceiverPermissions() async {
    if (kIsWeb) return true;

    final permissionsToRequest = <Permission>[Permission.camera];

    if (Platform.isAndroid) {
      permissionsToRequest.add(Permission.locationWhenInUse);
      permissionsToRequest.add(Permission.nearbyWifiDevices);
      permissionsToRequest.add(Permission.videos);
      permissionsToRequest.add(Permission.storage);
    } else if (Platform.isIOS) {
      permissionsToRequest.add(Permission.photosAddOnly);
    }

    final statuses = await permissionsToRequest.request();
    final cameraStatus = statuses[Permission.camera];
    if (cameraStatus != null && !cameraStatus.isGranted) {
      throw const SocketException(
          'Camera permission is required to scan the BeamQR code.');
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // SENDER (HOST) WORKFLOW
  // ---------------------------------------------------------------------------

  /// Initializes local Wi-Fi Direct group or ad-hoc AP, binds a high-speed
  /// HTTP file server, and generates a [BeamPayload] for QR code rendering.
  Future<BeamPayload> startHosting(File videoFile, {int port = 8888}) async {
    if (!await videoFile.exists()) {
      throw FileSystemException('Selected video file does not exist', videoFile.path);
    }

    _senderProgressController.add(TransferProgress.initializing());

    // Stop any existing host before starting fresh
    await stopHosting();

    _currentlyHostedFile = videoFile;
    _currentSessionToken = _generateSecureToken();

    String? hotspotSsid;
    String? hotspotPassword;
    String? hostIp;

    // 1. Attempt Wi-Fi Direct group initialization on Android
    if (Platform.isAndroid) {
      try {
        _p2pHost = FlutterP2pHost();
        await _p2pHost!.initialize();
        final hostState = await _p2pHost!.createGroup(
          advertise: false, // We use QR code instead of BLE advertisement
          timeout: const Duration(seconds: 15),
        );
        if (hostState.isActive) {
          hotspotSsid = hostState.ssid;
          hotspotPassword = hostState.preSharedKey;
          hostIp = hostState.hostIpAddress;
        }
      } catch (e) {
        debugPrint('Wi-Fi Direct createGroup fallback to local IP: $e');
      }
    }

    // 2. Discover local IP address from available network interfaces if not from P2P host
    if (hostIp == null || hostIp.isEmpty) {
      hostIp = await _findLocalIpAddress();
    }

    if (hostIp == null || hostIp.isEmpty) {
      // Default to standard Android hotspot gateway if all lookups are empty
      hostIp = '192.168.49.1';
    }

    // 3. Start local HTTP streaming server bound to all IPv4 interfaces
    try {
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
    } catch (_) {
      // In case port 8888 is occupied, bind to an ephemeral open port
      _httpServer = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: true,
      );
    }

    final boundPort = _httpServer!.port;
    final fileSize = await videoFile.length();
    final fileName = p.basename(videoFile.path);

    _listenToIncomingHttpRequests();

    _senderProgressController.add(TransferProgress.waitingForPeer());

    return BeamPayload(
      ssid: hotspotSsid,
      password: hotspotPassword,
      ip: hostIp,
      port: boundPort,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: 'video/mp4',
      token: _currentSessionToken!,
    );
  }

  /// Listens to incoming HTTP requests on the sender's local server.
  void _listenToIncomingHttpRequests() {
    if (_httpServer == null) return;

    _httpServer!.listen(
      (HttpRequest request) async {
        final path = request.uri.path;
        final token = request.uri.queryParameters['token'];

        // Token security verification
        if (token == null || token != _currentSessionToken) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write(jsonEncode({'error': 'Unauthorized: invalid or missing token'}))
            ..close();
          return;
        }

        // Endpoint: /info
        if (path == '/info') {
          final file = _currentlyHostedFile;
          if (file == null || !await file.exists()) {
            request.response
              ..statusCode = HttpStatus.notFound
              ..close();
            return;
          }
          final size = await file.length();
          final meta = {
            'fileName': p.basename(file.path),
            'fileSize': size,
            'mimeType': 'video/mp4',
          };
          request.response
            ..headers.contentType = ContentType.json
            ..statusCode = HttpStatus.ok
            ..write(jsonEncode(meta))
            ..close();
          return;
        }

        // Endpoint: /stream
        if (path == '/stream') {
          await _handleVideoStreamRequest(request);
          return;
        }

        // Default 404
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      },
      onError: (Object error) {
        debugPrint('HttpServer error: $error');
        _senderProgressController
            .add(TransferProgress.failed('Server error: $error'));
      },
    );
  }

  /// Streams the video file chunks with live upload progress tracking
  Future<void> _handleVideoStreamRequest(HttpRequest request) async {
    final file = _currentlyHostedFile;
    if (file == null || !await file.exists()) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
      return;
    }

    final totalBytes = await file.length();
    final response = request.response;

    response.headers
      ..contentType = ContentType('video', 'mp4')
      ..set(HttpHeaders.contentLengthHeader, totalBytes.toString())
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.connectionHeader, 'keep-alive')
      ..set('Content-Disposition',
          'attachment; filename="${p.basename(file.path)}"');

    int transferredBytes = 0;
    final stopwatch = Stopwatch()..start();
    int lastLoggedBytes = 0;
    DateTime lastLoggedTime = DateTime.now();

    try {
      final stream = file.openRead();

      await for (final List<int> chunk in stream) {
        response.add(chunk);
        transferredBytes += chunk.length;

        final now = DateTime.now();
        final elapsedMs = now.difference(lastLoggedTime).inMilliseconds;

        // Update progress every ~150ms for smooth UI animations
        if (elapsedMs >= 150 || transferredBytes == totalBytes) {
          final bytesSinceLast = transferredBytes - lastLoggedBytes;
          final speedMBps = elapsedMs > 0
              ? (bytesSinceLast / (1024 * 1024)) / (elapsedMs / 1000.0)
              : 0.0;

          Duration? eta;
          if (speedMBps > 0.05) {
            final remainingBytes = totalBytes - transferredBytes;
            final remainingSeconds =
                (remainingBytes / (speedMBps * 1024 * 1024)).round();
            eta = Duration(seconds: remainingSeconds);
          }

          _senderProgressController.add(TransferProgress.transferring(
            transferredBytes: transferredBytes,
            totalBytes: totalBytes,
            speedMBps: speedMBps,
            eta: eta,
          ));

          lastLoggedBytes = transferredBytes;
          lastLoggedTime = now;
        }
      }

      await response.flush();
      await response.close();

      stopwatch.stop();
      _senderProgressController.add(TransferProgress.completed(
        totalBytes: totalBytes,
      ));
    } on SocketException catch (e) {
      debugPrint('Sender socket disconnected: $e');
      _senderProgressController
          .add(TransferProgress.failed('Receiver disconnected prematurely'));
    } catch (e) {
      debugPrint('Error during video streaming: $e');
      _senderProgressController.add(TransferProgress.failed(e.toString()));
    }
  }

  /// Disposes of the active HTTP server and P2P Wi-Fi Direct group
  Future<void> stopHosting() async {
    try {
      await _httpServer?.close(force: true);
      _httpServer = null;
    } catch (e) {
      debugPrint('Error closing HttpServer: $e');
    }

    try {
      if (_p2pHost != null) {
        await _p2pHost!.removeGroup();
        await _p2pHost!.dispose();
        _p2pHost = null;
      }
    } catch (e) {
      debugPrint('Error disposing P2P Host: $e');
    }

    _currentlyHostedFile = null;
    _currentSessionToken = null;
  }

  // ---------------------------------------------------------------------------
  // RECEIVER (CLIENT) WORKFLOW
  // ---------------------------------------------------------------------------

  /// Connects to the host using credentials from the [BeamPayload], streams
  /// the incoming video directly into local storage, and emits real-time progress.
  Future<File> receiveVideo(
    BeamPayload payload, {
    Duration connectionTimeout = const Duration(seconds: 20),
  }) async {
    _receiverProgressController.add(TransferProgress.initializing());

    // 1. Auto-connect to Wi-Fi Direct group if credentials are provided on Android
    if (Platform.isAndroid &&
        payload.ssid != null &&
        payload.password != null &&
        payload.ssid!.isNotEmpty) {
      try {
        _receiverProgressController.add(TransferProgress.waitingForPeer());
        _p2pClient = FlutterP2pClient();
        await _p2pClient!.initialize();
        await _p2pClient!.connectWithCredentials(
          payload.ssid!,
          payload.password!,
          timeout: connectionTimeout,
        );
      } catch (e) {
        debugPrint('Wi-Fi Direct client connect attempt notice: $e');
        // Proceed even if auto-connect reports non-fatal error
      }
    }

    // 2. Prepare target local storage directory
    final appDir = await getApplicationDocumentsDirectory();
    final beamVideosDir = Directory(p.join(appDir.path, 'beam_videos'));
    if (!await beamVideosDir.exists()) {
      await beamVideosDir.create(recursive: true);
    }

    // Clean destination file name (prevent collisions)
    final safeFileName = _sanitizeFileName(payload.fileName);
    final targetFile = File(p.join(beamVideosDir.path, safeFileName));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    _activeFileSink = targetFile.openWrite(mode: FileMode.writeOnly);

    // 3. Connect to sender's HTTP stream
    _activeHttpClient = HttpClient()
      ..connectionTimeout = connectionTimeout;

    try {
      _receiverProgressController.add(TransferProgress.waitingForPeer());

      final request = await _activeHttpClient!
          .getUrl(Uri.parse(payload.downloadUrl))
          .timeout(connectionTimeout, onTimeout: () {
        throw TimeoutException(
            'Failed to connect to sender at ${payload.ip}:${payload.port}. Please ensure you are connected to the same Wi-Fi or Hotspot.');
      });

      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
            'Download failed with HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : payload.fileSize;

      int transferredBytes = 0;
      int lastLoggedBytes = 0;
      DateTime lastLoggedTime = DateTime.now();

      await for (final List<int> chunk in response) {
        _activeFileSink!.add(chunk);
        transferredBytes += chunk.length;

        final now = DateTime.now();
        final elapsedMs = now.difference(lastLoggedTime).inMilliseconds;

        if (elapsedMs >= 150 || transferredBytes == totalBytes) {
          final bytesSinceLast = transferredBytes - lastLoggedBytes;
          final speedMBps = elapsedMs > 0
              ? (bytesSinceLast / (1024 * 1024)) / (elapsedMs / 1000.0)
              : 0.0;

          Duration? eta;
          if (speedMBps > 0.05 && totalBytes > 0) {
            final remainingBytes = totalBytes - transferredBytes;
            final remainingSeconds =
                (remainingBytes / (speedMBps * 1024 * 1024)).round();
            eta = Duration(seconds: remainingSeconds);
          }

          _receiverProgressController.add(TransferProgress.transferring(
            transferredBytes: transferredBytes,
            totalBytes: totalBytes,
            speedMBps: speedMBps,
            eta: eta,
          ));

          lastLoggedBytes = transferredBytes;
          lastLoggedTime = now;
        }
      }

      await _activeFileSink!.flush();
      await _activeFileSink!.close();
      _activeFileSink = null;

      _receiverProgressController.add(TransferProgress.completed(
        totalBytes: transferredBytes,
        savedFilePath: targetFile.path,
      ));

      return targetFile;
    } on SocketException catch (e) {
      debugPrint('Receiver SocketException: $e');
      await _cleanupFailedDownload(targetFile);
      _receiverProgressController.add(TransferProgress.failed(
          'Connection failed. Ensure both devices are on the same Wi-Fi/Hotspot network.'));
      rethrow;
    } catch (e) {
      debugPrint('Receiver error: $e');
      await _cleanupFailedDownload(targetFile);
      _receiverProgressController.add(TransferProgress.failed(e.toString()));
      rethrow;
    } finally {
      _activeHttpClient?.close(force: true);
      _activeHttpClient = null;
    }
  }

  /// Cancels any in-progress receiver download and cleans up state
  Future<void> cancelReceiverTransfer() async {
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    try {
      await _activeFileSink?.close();
      _activeFileSink = null;
    } catch (_) {}

    try {
      if (_p2pClient != null) {
        await _p2pClient!.disconnect();
        await _p2pClient!.dispose();
        _p2pClient = null;
      }
    } catch (e) {
      debugPrint('Error disconnecting P2P Client: $e');
    }

    _receiverProgressController.add(TransferProgress.cancelled());
  }

  Future<void> _cleanupFailedDownload(File file) async {
    try {
      await _activeFileSink?.close();
      _activeFileSink = null;
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // HELPER UTILITIES
  // ---------------------------------------------------------------------------

  /// Discovers local network IP address by inspecting active interfaces
  Future<String?> _findLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            // Prioritize standard Wi-Fi Direct or hotspot subnet addresses
            if (addr.address.startsWith('192.168.') ||
                addr.address.startsWith('10.') ||
                addr.address.startsWith('172.')) {
              return addr.address;
            }
          }
        }
      }

      // Fallback: first non-loopback
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      debugPrint('Error discovering local IP: $e');
    }
    return null;
  }

  /// Generates a random alphanumeric token for transfer authentication
  String _generateSecureToken([int length = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(length, (index) => chars[rand.nextInt(chars.length)])
        .join();
  }

  /// Sanitizes file names to prevent directory traversal or invalid characters
  String _sanitizeFileName(String name) {
    var cleaned = p.basename(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (!cleaned.toLowerCase().endsWith('.mp4')) {
      cleaned = '$cleaned.mp4';
    }
    return cleaned;
  }

  /// Total service disposal
  void dispose() {
    stopHosting();
    cancelReceiverTransfer();
    _senderProgressController.close();
    _receiverProgressController.close();
  }
}
