import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:gal/gal.dart';
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
        'Camera permission is required to scan the BeamQR code.',
      );
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // SENDER (HOST) WORKFLOW
  // ---------------------------------------------------------------------------

  /// Initializes local Wi-Fi Direct group or ad-hoc AP, binds a high-speed
  /// HTTP file server, and generates a [BeamPayload] for QR code rendering.
  Future<BeamPayload> startHosting(
    File videoFile, {
    int port = 8888,
    bool enableWifiDirect = true,
    String? overrideHostIp,
  }) async {
    if (!await videoFile.exists()) {
      throw FileSystemException(
        'Selected video file does not exist',
        videoFile.path,
      );
    }

    _senderProgressController.add(TransferProgress.initializing());

    // Stop any existing host before starting fresh
    await stopHosting();

    _currentlyHostedFile = videoFile;
    _currentSessionToken = _generateSecureToken();

    String? hotspotSsid;
    String? hotspotPassword;
    final candidateIps = <String>{};

    // 1. Discover pre-existing network interfaces (e.g. connected Wi-Fi router / Hotspot)
    final existingIps = await _findAllLocalIpAddresses();
    candidateIps.addAll(existingIps);

    // 2. Attempt Wi-Fi Direct group initialization on Android if enabled
    if (Platform.isAndroid && enableWifiDirect) {
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
          if (hostState.hostIpAddress != null &&
              hostState.hostIpAddress!.isNotEmpty) {
            candidateIps.add(hostState.hostIpAddress!);
          }
        }
      } catch (e) {
        debugPrint('Wi-Fi Direct createGroup note: $e');
      }
    }

    // Refresh interfaces to catch newly established P2P interfaces (e.g. p2p-wlan0-0)
    final refreshedIps = await _findAllLocalIpAddresses();
    candidateIps.addAll(refreshedIps);

    // Filter out loopback and link-local addresses
    final validIps = candidateIps
        .where(
          (ip) =>
              ip.isNotEmpty && ip != '127.0.0.1' && !ip.startsWith('169.254.'),
        )
        .toList();

    // If only emulator NAT addresses are present (10.0.2.x), automatically include
    // the host PC's Wi-Fi LAN IP (192.168.100.192) so physical phones on the same Wi-Fi
    // can connect seamlessly via 'adb forward tcp:8888 tcp:8888'.
    if (validIps.isNotEmpty &&
        validIps.every((ip) => ip.startsWith('10.0.2.'))) {
      validIps.insert(0, '192.168.100.192');
    }

    // Determine primary IP:
    // If overrideHostIp is given, use it. Otherwise, prioritize standard routable Wi-Fi
    // LAN subnets, excluding Android Wi-Fi Direct (192.168.49.x) and emulator-internal NAT (10.0.2.x).
    String primaryIp;
    if (overrideHostIp != null && overrideHostIp.isNotEmpty) {
      primaryIp = overrideHostIp;
    } else {
      final lanIp = validIps.cast<String?>().firstWhere(
        (ip) =>
            ip != null &&
            !ip.startsWith('192.168.49.') &&
            !ip.startsWith('10.0.2.') &&
            (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                ip.startsWith('172.')),
        orElse: () => null,
      );

      if (lanIp != null) {
        primaryIp = lanIp;
      } else if (validIps.isNotEmpty) {
        primaryIp = validIps.first;
      } else {
        primaryIp = '192.168.49.1';
      }
    }

    if (!validIps.contains(primaryIp)) {
      validIps.insert(0, primaryIp);
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
    final mimeType = _detectMimeType(videoFile.path);
    final thumbBase64 = await generateThumbnailBase64(videoFile);

    _listenToIncomingHttpRequests();

    _senderProgressController.add(TransferProgress.waitingForPeer());

    debugPrint(
      'Hosting on primary IP $primaryIp:$boundPort (Candidates: $validIps)',
    );

    return BeamPayload(
      ssid: hotspotSsid,
      password: hotspotPassword,
      ip: primaryIp,
      candidateIps: validIps,
      port: boundPort,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      token: _currentSessionToken!,
      thumbnailBase64: thumbBase64,
    );
  }

  /// Updates an existing payload with a custom host IP (e.g. for emulator testing with PC LAN IP)
  BeamPayload updatePayloadHostIp(BeamPayload payload, String newIp) {
    final updatedCandidates = <String>[newIp];
    for (final ip in payload.candidateIps) {
      if (ip != newIp && !updatedCandidates.contains(ip)) {
        updatedCandidates.add(ip);
      }
    }
    return BeamPayload(
      ssid: payload.ssid,
      password: payload.password,
      ip: newIp,
      candidateIps: updatedCandidates,
      port: payload.port,
      fileName: payload.fileName,
      fileSize: payload.fileSize,
      mimeType: payload.mimeType,
      token: payload.token,
      version: payload.version,
      onlineUrl: payload.onlineUrl,
      isOnline: payload.isOnline,
      thumbnailBase64: payload.thumbnailBase64,
    );
  }

  /// Uploads video to high-speed online cloud relay for cross-network beaming
  /// (works across cellular 4G/5G, different Wi-Fi networks, and simulator-to-device worldwide).
  Future<BeamPayload> startOnlineHosting(File videoFile) async {
    if (!await videoFile.exists()) {
      throw FileSystemException('Selected file does not exist', videoFile.path);
    }

    _senderProgressController.add(TransferProgress.initializing());
    final fileSize = await videoFile.length();
    final fileName = p.basename(videoFile.path);
    final mimeType = _detectMimeType(videoFile.path);

    final boundary =
        '----WebKitFormBoundary${DateTime.now().millisecondsSinceEpoch}';
    final uploadUri = Uri.parse('https://uguu.se/upload');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 40);

    try {
      final header = utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="files[]"; filename="$fileName"\r\n'
        'Content-Type: $mimeType\r\n\r\n',
      );
      final footer = utf8.encode('\r\n--$boundary--\r\n');
      final totalContentLength = header.length + fileSize + footer.length;

      final request = await client.postUrl(uploadUri);
      request.headers.set(
        'Content-Type',
        'multipart/form-data; boundary=$boundary',
      );
      request.headers.set('Content-Length', totalContentLength.toString());

      int uploadedBytes = 0;
      int lastLoggedBytes = 0;
      DateTime lastLoggedTime = DateTime.now();

      // Write multipart header
      request.add(header);
      uploadedBytes += header.length;

      // Stream file chunks with live upload progress
      final fileStream = videoFile.openRead();
      await for (final chunk in fileStream) {
        request.add(chunk);
        uploadedBytes += chunk.length;

        final now = DateTime.now();
        final elapsedMs = now.difference(lastLoggedTime).inMilliseconds;
        if (elapsedMs >= 200 || uploadedBytes >= totalContentLength) {
          final bytesSinceLast = uploadedBytes - lastLoggedBytes;
          final speedMBps = elapsedMs > 0
              ? (bytesSinceLast / (1024 * 1024)) / (elapsedMs / 1000.0)
              : 0.0;

          Duration? eta;
          if (speedMBps > 0.05 && fileSize > 0) {
            final remaining = totalContentLength - uploadedBytes;
            final secs = (remaining / (speedMBps * 1024 * 1024)).round();
            eta = Duration(seconds: secs);
          }

          _senderProgressController.add(
            TransferProgress.transferring(
              transferredBytes: uploadedBytes.clamp(0, fileSize),
              totalBytes: fileSize,
              speedMBps: speedMBps,
              eta: eta,
            ),
          );
          lastLoggedBytes = uploadedBytes;
          lastLoggedTime = now;
        }
      }

      // Write footer and close request
      request.add(footer);
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Online cloud upload failed with status ${response.statusCode}',
        );
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final dynamic decoded = jsonDecode(responseBody);
      if (decoded is! Map || decoded['files'] == null) {
        throw const FormatException('Invalid response from online cloud relay');
      }

      final files = decoded['files'] as List;
      if (files.isEmpty) {
        throw const FormatException('No files returned from cloud relay');
      }

      final directDownloadUrl = files[0]['url'] as String;
      debugPrint('Online Cloud Relay URL generated: $directDownloadUrl');

      final thumbBase64 = await generateThumbnailBase64(videoFile);

      _senderProgressController.add(TransferProgress.waitingForPeer());

      return BeamPayload.online(
        onlineUrl: directDownloadUrl,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        thumbnailBase64: thumbBase64,
      );
    } catch (e) {
      _senderProgressController.add(TransferProgress.failed(e.toString()));
      rethrow;
    } finally {
      client.close(force: true);
    }
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
            ..write(
              jsonEncode({'error': 'Unauthorized: invalid or missing token'}),
            )
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

        // Endpoint: /preview
        if (path == '/preview') {
          final file = _currentlyHostedFile;
          if (file == null || !await file.exists()) {
            request.response
              ..statusCode = HttpStatus.notFound
              ..close();
            return;
          }
          final mimeType = _detectMimeType(file.path);
          request.response
            ..headers.contentType = ContentType.parse(mimeType)
            ..statusCode = HttpStatus.ok;
          await file.openRead().pipe(request.response);
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
        _senderProgressController.add(
          TransferProgress.failed('Server error: $error'),
        );
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
    final mime = _detectMimeType(file.path);
    final mimeParts = mime.split('/');

    response.headers
      ..contentType = mimeParts.length == 2
          ? ContentType(mimeParts[0], mimeParts[1])
          : ContentType('application', 'octet-stream')
      ..set(HttpHeaders.contentLengthHeader, totalBytes.toString())
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.connectionHeader, 'keep-alive')
      ..set(
        'Content-Disposition',
        'attachment; filename="${p.basename(file.path)}"',
      );

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

          _senderProgressController.add(
            TransferProgress.transferring(
              transferredBytes: transferredBytes,
              totalBytes: totalBytes,
              speedMBps: speedMBps,
              eta: eta,
            ),
          );

          lastLoggedBytes = transferredBytes;
          lastLoggedTime = now;
        }
      }

      await response.flush();
      await response.close();

      stopwatch.stop();
      _senderProgressController.add(
        TransferProgress.completed(totalBytes: totalBytes),
      );
    } on SocketException catch (e) {
      debugPrint('Sender socket disconnected: $e');
      _senderProgressController.add(
        TransferProgress.failed('Receiver disconnected prematurely'),
      );
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

    // 1. Auto-connect to Wi-Fi Direct group if offline payload with credentials on Android
    if (!payload.isOnline &&
        Platform.isAndroid &&
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
      }
    }

    // 2. Prepare target local storage directory
    final targetDir = await _getReceiverStorageDirectory();
    final safeFileName = _sanitizeFileName(payload.fileName);
    final targetFile = File(p.join(targetDir.path, safeFileName));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    _activeFileSink = targetFile.openWrite(mode: FileMode.writeOnly);

    try {
      // 3. Connect to sender's HTTP stream
      _receiverProgressController.add(TransferProgress.waitingForPeer());

      // Build ordered list of candidate URLs to attempt:
      final candidateUrls = <String>[];
      if (payload.isOnline) {
        candidateUrls.add(payload.downloadUrl);
      } else {
        candidateUrls.add(payload.downloadUrl);
        for (final ip in payload.candidateIps) {
          final altUrl =
              'http://$ip:${payload.port}/stream?token=${payload.token}';
          if (!candidateUrls.contains(altUrl)) {
            candidateUrls.add(altUrl);
          }
        }
      }

      _activeHttpClient = HttpClient()
        ..connectionTimeout = payload.isOnline
            ? const Duration(seconds: 25)
            : const Duration(seconds: 8);

      HttpClientResponse? response;
      String? connectedUrl;
      Exception? lastError;

      for (final targetUrl in candidateUrls) {
        try {
          debugPrint('Connecting to download stream at: $targetUrl');
          final request = await _activeHttpClient!
              .getUrl(Uri.parse(targetUrl))
              .timeout(const Duration(seconds: 6));
          final res = await request.close();
          if (res.statusCode == HttpStatus.ok) {
            response = res;
            connectedUrl = targetUrl;
            break;
          } else {
            lastError = HttpException(
              'HTTP ${res.statusCode}: ${res.reasonPhrase}',
              uri: Uri.parse(targetUrl),
            );
          }
        } catch (e) {
          debugPrint('Failed connecting to $targetUrl: $e');
          lastError = e is Exception ? e : Exception(e.toString());
        }
      }

      if (response == null) {
        await _cleanupFailedDownload(targetFile);
        final triedList = payload.candidateIps.isNotEmpty
            ? payload.candidateIps.join(', ')
            : payload.ip;
        throw TimeoutException(
          'Failed to connect to sender at [$triedList]:${payload.port}.\n\n'
          'Please ensure you are connected to the same Wi-Fi or Hotspot.'
          '${lastError != null ? " (Details: $lastError)" : ""}',
        );
      }

      debugPrint('Connected successfully to stream at $connectedUrl');

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

          _receiverProgressController.add(
            TransferProgress.transferring(
              transferredBytes: transferredBytes,
              totalBytes: totalBytes,
              speedMBps: speedMBps,
              eta: eta,
            ),
          );

          lastLoggedBytes = transferredBytes;
          lastLoggedTime = now;
        }
      }

      await _activeFileSink!.flush();
      await _activeFileSink!.close();
      _activeFileSink = null;

      // Automatically save images and videos to system Photos/Gallery on iOS and Android
      await _saveToDeviceGallery(targetFile);

      _receiverProgressController.add(
        TransferProgress.completed(
          totalBytes: transferredBytes,
          savedFilePath: targetFile.path,
        ),
      );

      return targetFile;
    } on SocketException catch (e) {
      debugPrint('Receiver SocketException: $e');
      await _cleanupFailedDownload(targetFile);
      _receiverProgressController.add(
        TransferProgress.failed(
          'Connection failed. Ensure both devices are on the same Wi-Fi/Hotspot network.',
        ),
      );
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

  /// Discovers all available IPv4 addresses across all active network interfaces
  Future<List<String>> _findAllLocalIpAddresses() async {
    final ips = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback &&
              !addr.isLinkLocal &&
              addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      debugPrint('Error discovering all local IPs: $e');
    }
    return ips.toList();
  }

  /// Generates a random alphanumeric token for transfer authentication
  String _generateSecureToken([int length = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (index) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  /// Detects MIME type from file extension
  static String _detectMimeType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.mkv':
        return 'video/x-matroska';
      case '.avi':
        return 'video/x-msvideo';
      case '.webm':
        return 'video/webm';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.pdf':
        return 'application/pdf';
      case '.zip':
        return 'application/zip';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }

  /// Sanitizes file names to prevent directory traversal or invalid characters
  String _sanitizeFileName(String name) {
    var cleaned = p.basename(name).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (!cleaned.contains('.')) {
      cleaned = '$cleaned.mp4';
    }
    return cleaned;
  }

  /// Resolves the optimal, accessible storage directory for downloaded files.
  /// On Android, saves to the public Download/BeamQR directory (visible in Files & Gallery).
  /// On iOS, saves to app Documents/BeamQR (visible in iOS Files app).
  Future<Directory> _getReceiverStorageDirectory() async {
    if (Platform.isAndroid) {
      try {
        final publicDownloadDir = Directory(
          '/storage/emulated/0/Download/BeamQR',
        );
        if (!await publicDownloadDir.exists()) {
          await publicDownloadDir.create(recursive: true);
        }
        return publicDownloadDir;
      } catch (e) {
        debugPrint('Could not create public Download/BeamQR folder: $e');
      }

      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final beamDir = Directory(p.join(extDir.path, 'BeamQR'));
          if (!await beamDir.exists()) {
            await beamDir.create(recursive: true);
          }
          return beamDir;
        }
      } catch (e) {
        debugPrint('Could not access external storage: $e');
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final beamDir = Directory(p.join(appDir.path, 'BeamQR'));
    if (!await beamDir.exists()) {
      await beamDir.create(recursive: true);
    }
    return beamDir;
  }

  /// Generates a compact base64 thumbnail string for image files using dart:ui
  static Future<String?> generateThumbnailBase64(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    final isImage = [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.gif',
      '.bmp',
    ].contains(ext);
    if (!isImage) return null;

    try {
      final bytes = await file.readAsBytes();
      // If original image is already tiny (< 2KB), encode directly
      if (bytes.length < 2000) {
        return base64Encode(bytes);
      }

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 100,
        targetHeight: 100,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final thumbBytes = byteData.buffer.asUint8List();
        // Keep QR payload compact
        if (thumbBytes.length < 4200) {
          return base64Encode(thumbBytes);
        }
      }
    } catch (e) {
      debugPrint('Note: Thumbnail generation skipped ($e)');
    }
    return null;
  }

  /// Automatically exports downloaded photos & videos directly into the device's
  /// native Photos / Gallery app on both iOS and Android.
  Future<bool> _saveToDeviceGallery(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    final isImage = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'].contains(ext);
    final isVideo = ['.mp4', '.mov', '.mkv', '.avi', '.webm'].contains(ext);

    if (!isImage && !isVideo) return false;

    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          debugPrint('Gallery permission not granted');
          return false;
        }
      }

      if (isImage) {
        await Gal.putImage(file.path, album: 'BeamQR');
        debugPrint('Image saved to Photos Gallery (BeamQR album)');
        return true;
      } else if (isVideo) {
        await Gal.putVideo(file.path, album: 'BeamQR');
        debugPrint('Video saved to Photos Gallery (BeamQR album)');
        return true;
      }
    } catch (e) {
      debugPrint('Gal save to gallery note: $e');
    }
    return false;
  }

  /// Total service disposal
  void dispose() {
    stopHosting();
    cancelReceiverTransfer();
    _senderProgressController.close();
    _receiverProgressController.close();
  }
}
