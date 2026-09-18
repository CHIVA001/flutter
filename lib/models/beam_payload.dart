import 'dart:convert';

/// Represents the connection and metadata payload encoded within the BeamQR code.
/// This model enables offline peer-to-peer handshakes without needing an internet connection.
class BeamPayload {
  /// The Wi-Fi Direct or hotspot SSID name (if hosted via AP)
  final String? ssid;

  /// The Wi-Fi Direct or hotspot password (if hosted via AP)
  final String? password;

  /// The local IP address where the sender's HTTP file server is running
  final String ip;

  /// Candidate IP addresses across all active interfaces (Wi-Fi LAN, Hotspot, P2P)
  final List<String> candidateIps;

  /// The TCP port on which the sender's HTTP file server is listening
  final int port;

  /// The name of the video file being transferred (e.g., 'sample_video.mp4')
  final String fileName;

  /// Total file size in bytes
  final int fileSize;

  /// MIME type of the file (defaults to 'video/mp4')
  final String mimeType;

  /// Secure one-time session transfer token to prevent unauthorized access
  final String token;

  /// Protocol version for forward compatibility
  final int version;

  /// Public HTTPS URL if hosted via online cloud relay
  final String? onlineUrl;

  /// Whether this transfer is hosted online across public networks
  final bool isOnline;

  /// Optional base64 encoded micro-thumbnail for instant offline QR image preview
  final String? thumbnailBase64;

  const BeamPayload({
    this.ssid,
    this.password,
    required this.ip,
    this.candidateIps = const [],
    required this.port,
    required this.fileName,
    required this.fileSize,
    this.mimeType = 'video/mp4',
    required this.token,
    this.version = 1,
    this.onlineUrl,
    this.isOnline = false,
    this.thumbnailBase64,
  });

  /// Convenience constructor for online cloud transfers
  factory BeamPayload.online({
    required String onlineUrl,
    required String fileName,
    required int fileSize,
    String mimeType = 'video/mp4',
    String? thumbnailBase64,
  }) {
    final uri = Uri.parse(onlineUrl);
    return BeamPayload(
      ip: uri.host,
      port: uri.port != 0 ? uri.port : 443,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      token: '',
      onlineUrl: onlineUrl,
      isOnline: true,
      thumbnailBase64: thumbnailBase64,
    );
  }

  /// Serializes this payload into a JSON-compatible Map
  Map<String, dynamic> toJson() {
    return {
      'v': version,
      if (isOnline) 'online': true,
      if (onlineUrl != null) 'url': onlineUrl,
      if (ssid != null) 'ssid': ssid,
      if (password != null) 'pwd': password,
      'ip': ip,
      if (candidateIps.isNotEmpty) 'ips': candidateIps,
      'port': port,
      'name': fileName,
      'size': fileSize,
      'mime': mimeType,
      'token': token,
      if (thumbnailBase64 != null && thumbnailBase64!.isNotEmpty)
        'thumb': thumbnailBase64,
    };
  }

  /// Converts this payload to a compact JSON string suitable for QR encoding
  String toJsonString() => jsonEncode(toJson());

  /// Constructs a [BeamPayload] from a JSON map
  factory BeamPayload.fromJson(Map<String, dynamic> json) {
    if (json['name'] == null) {
      throw const FormatException('Invalid BeamQR payload: missing name field');
    }

    final isOnline = json['online'] as bool? ?? (json['url'] != null);
    final onlineUrl = json['url'] as String?;

    final primaryIp = json['ip'] as String? ?? (onlineUrl != null ? Uri.parse(onlineUrl).host : '');
    final ipsList = <String>[];
    if (json['ips'] is List) {
      for (final item in json['ips']) {
        if (item is String && item.isNotEmpty && !ipsList.contains(item)) {
          ipsList.add(item);
        }
      }
    }
    if (primaryIp.isNotEmpty && !ipsList.contains(primaryIp)) {
      ipsList.insert(0, primaryIp);
    }

    return BeamPayload(
      version: json['v'] as int? ?? 1,
      ssid: json['ssid'] as String?,
      password: json['pwd'] as String?,
      ip: primaryIp,
      candidateIps: ipsList,
      port: (json['port'] as num?)?.toInt() ?? 443,
      fileName: json['name'] as String,
      fileSize: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mime'] as String? ?? 'video/mp4',
      token: json['token'] as String? ?? '',
      onlineUrl: onlineUrl,
      isOnline: isOnline,
      thumbnailBase64: json['thumb'] as String?,
    );
  }

  /// Parses a raw string (e.g. from QR scanner or direct link) into a [BeamPayload]
  factory BeamPayload.fromJsonString(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      // Direct online download link was scanned or pasted
      final uri = Uri.parse(trimmed);
      final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'downloaded_video.mp4';
      return BeamPayload.online(
        onlineUrl: trimmed,
        fileName: fileName,
        fileSize: 0,
      );
    }

    final dynamic decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('QR payload must be a valid JSON object');
    }
    return BeamPayload.fromJson(decoded);
  }

  /// Formatted file size string (e.g., "14.2 MB", "1.2 GB")
  String get formattedSize {
    if (fileSize <= 0) return 'Unknown Size';
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// The HTTP download URL to fetch the video stream from
  String get downloadUrl =>
      (isOnline && onlineUrl != null && onlineUrl!.isNotEmpty)
          ? onlineUrl!
          : 'http://$ip:$port/stream?token=$token';

  /// The HTTP info URL to verify file metadata
  String get infoUrl =>
      (isOnline && onlineUrl != null && onlineUrl!.isNotEmpty)
          ? onlineUrl!
          : 'http://$ip:$port/info?token=$token';

  @override
  String toString() =>
      'BeamPayload(ip: $ip, port: $port, fileName: $fileName, size: $formattedSize)';
}
