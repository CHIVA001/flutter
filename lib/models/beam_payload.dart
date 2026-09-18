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

  const BeamPayload({
    this.ssid,
    this.password,
    required this.ip,
    required this.port,
    required this.fileName,
    required this.fileSize,
    this.mimeType = 'video/mp4',
    required this.token,
    this.version = 1,
  });

  /// Serializes this payload into a JSON-compatible Map
  Map<String, dynamic> toJson() {
    return {
      'v': version,
      'ssid': ssid,
      'pwd': password,
      'ip': ip,
      'port': port,
      'name': fileName,
      'size': fileSize,
      'mime': mimeType,
      'token': token,
    };
  }

  /// Converts this payload to a compact JSON string suitable for QR encoding
  String toJsonString() => jsonEncode(toJson());

  /// Constructs a [BeamPayload] from a JSON map
  factory BeamPayload.fromJson(Map<String, dynamic> json) {
    if (json['ip'] == null || json['port'] == null || json['name'] == null) {
      throw const FormatException('Invalid BeamQR payload: missing required fields');
    }
    return BeamPayload(
      version: json['v'] as int? ?? 1,
      ssid: json['ssid'] as String?,
      password: json['pwd'] as String?,
      ip: json['ip'] as String,
      port: (json['port'] as num).toInt(),
      fileName: json['name'] as String,
      fileSize: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mime'] as String? ?? 'video/mp4',
      token: json['token'] as String? ?? '',
    );
  }

  /// Parses a raw string (e.g. from QR scanner) into a [BeamPayload]
  factory BeamPayload.fromJsonString(String raw) {
    final dynamic decoded = jsonDecode(raw.trim());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('QR payload must be a valid JSON object');
    }
    return BeamPayload.fromJson(decoded);
  }

  /// Formatted file size string (e.g., "14.2 MB", "1.2 GB")
  String get formattedSize {
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
  String get downloadUrl => 'http://$ip:$port/stream?token=$token';

  /// The HTTP info URL to verify file metadata
  String get infoUrl => 'http://$ip:$port/info?token=$token';

  @override
  String toString() =>
      'BeamPayload(ip: $ip, port: $port, fileName: $fileName, size: $formattedSize)';
}
