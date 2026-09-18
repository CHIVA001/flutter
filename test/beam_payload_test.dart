import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_3_47_4/models/beam_payload.dart';

void main() {
  group('BeamPayload Model Tests', () {
    test('Serializes to JSON and deserializes back faithfully', () {
      const payload = BeamPayload(
        ssid: 'DIRECT-xy-BeamQR',
        password: 'secure_password_123',
        ip: '192.168.49.1',
        candidateIps: ['192.168.49.1', '192.168.1.50'],
        port: 8888,
        fileName: 'vacation_clip.mp4',
        fileSize: 104857600, // 100 MB
        token: 'auth_tok_abc',
      );

      final jsonStr = payload.toJsonString();
      final parsed = BeamPayload.fromJsonString(jsonStr);

      expect(parsed.ssid, equals('DIRECT-xy-BeamQR'));
      expect(parsed.password, equals('secure_password_123'));
      expect(parsed.ip, equals('192.168.49.1'));
      expect(parsed.candidateIps, containsAll(['192.168.49.1', '192.168.1.50']));
      expect(parsed.port, equals(8888));
      expect(parsed.fileName, equals('vacation_clip.mp4'));
      expect(parsed.fileSize, equals(104857600));
      expect(parsed.formattedSize, equals('100.0 MB'));
      expect(parsed.token, equals('auth_tok_abc'));
      expect(
        parsed.downloadUrl,
        equals('http://192.168.49.1:8888/stream?token=auth_tok_abc'),
      );
      expect(
        parsed.infoUrl,
        equals('http://192.168.49.1:8888/info?token=auth_tok_abc'),
      );
    });

    test('Throws FormatException on invalid payload', () {
      expect(
        () => BeamPayload.fromJsonString('{"invalid": "data"}'),
        throwsFormatException,
      );
      expect(
        () => BeamPayload.fromJsonString('not_json'),
        throwsFormatException,
      );
    });

    test('Formatted size formats correctly for bytes, KB, MB, and GB', () {
      const bPayload = BeamPayload(
        ip: '127.0.0.1',
        port: 8080,
        fileName: 'test.mp4',
        fileSize: 500,
        token: 'x',
      );
      expect(bPayload.formattedSize, equals('500 B'));

      const kbPayload = BeamPayload(
        ip: '127.0.0.1',
        port: 8080,
        fileName: 'test.mp4',
        fileSize: 51200,
        token: 'x',
      );
      expect(kbPayload.formattedSize, equals('50.0 KB'));

      const gbPayload = BeamPayload(
        ip: '127.0.0.1',
        port: 8080,
        fileName: 'test.mp4',
        fileSize: 2147483648,
        token: 'x',
      );
      expect(gbPayload.formattedSize, equals('2.00 GB'));
    });
  });
}
