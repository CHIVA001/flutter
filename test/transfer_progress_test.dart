import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_3_47_4/models/transfer_progress.dart';

void main() {
  group('TransferProgress Model Tests', () {
    test('Calculates fraction and percentage correctly', () {
      final progress = TransferProgress.transferring(
        transferredBytes: 50 * 1024 * 1024,
        totalBytes: 100 * 1024 * 1024,
        speedMBps: 15.5,
        eta: const Duration(seconds: 12),
      );

      expect(progress.fraction, closeTo(0.5, 0.001));
      expect(progress.percentageString, equals('50.0%'));
      expect(progress.formattedSpeed, equals('15.50 MB/s'));
      expect(progress.formattedEta, equals('12s'));
      expect(progress.formattedTransferredSize, equals('50.0 MB / 100.0 MB'));
    });

    test('Clamps fraction within [0.0, 1.0] on boundary values', () {
      final zeroTotal = TransferProgress.transferring(
        transferredBytes: 0,
        totalBytes: 0,
        speedMBps: 0.0,
      );
      expect(zeroTotal.fraction, equals(0.0));

      final completed = TransferProgress.completed(
        totalBytes: 1024,
        savedFilePath: '/path/to/video.mp4',
      );
      expect(completed.fraction, equals(1.0));
      expect(completed.state, equals(TransferState.completed));
      expect(completed.savedFilePath, equals('/path/to/video.mp4'));
    });

    test('Handles ETA formatting over 1 minute', () {
      final progress = TransferProgress.transferring(
        transferredBytes: 1000,
        totalBytes: 2000,
        speedMBps: 1.0,
        eta: const Duration(minutes: 2, seconds: 15),
      );
      expect(progress.formattedEta, equals('2m 15s'));
    });
  });
}
