/// Represents the state lifecycle of a peer-to-peer file transfer.
enum TransferState {
  idle,
  initializing,
  waitingForPeer,
  transferring,
  extracting,
  completed,
  cancelled,
  failed,
}

/// Tracks real-time transfer progress, speed in MB/s, and completion metrics
/// for both sender (upload) and receiver (download).
class TransferProgress {
  final TransferState state;
  final int transferredBytes;
  final int totalBytes;
  final double speedMBps;
  final Duration? estimatedTimeRemaining;
  final String? errorMessage;
  final String? savedFilePath;

  /// For [TransferState.extracting]: index of the file currently being saved (1-based)
  final int currentFile;

  /// For [TransferState.extracting]: total number of files in the ZIP
  final int totalFiles;

  /// For [TransferState.extracting]: name of the file currently being saved
  final String? currentFileName;

  const TransferProgress({
    required this.state,
    this.transferredBytes = 0,
    this.totalBytes = 0,
    this.speedMBps = 0.0,
    this.estimatedTimeRemaining,
    this.errorMessage,
    this.savedFilePath,
    this.currentFile = 0,
    this.totalFiles = 0,
    this.currentFileName,
  });

  /// Factory for idle state
  factory TransferProgress.idle() => const TransferProgress(state: TransferState.idle);

  /// Factory for initializing state
  factory TransferProgress.initializing() =>
      const TransferProgress(state: TransferState.initializing);

  /// Factory for waiting for peer state
  factory TransferProgress.waitingForPeer() =>
      const TransferProgress(state: TransferState.waitingForPeer);

  /// Factory for active transfer state
  factory TransferProgress.transferring({
    required int transferredBytes,
    required int totalBytes,
    required double speedMBps,
    Duration? eta,
  }) {
    return TransferProgress(
      state: TransferState.transferring,
      transferredBytes: transferredBytes,
      totalBytes: totalBytes,
      speedMBps: speedMBps,
      estimatedTimeRemaining: eta,
    );
  }

  /// Factory for completion
  factory TransferProgress.completed({
    required int totalBytes,
    String? savedFilePath,
  }) {
    return TransferProgress(
      state: TransferState.completed,
      transferredBytes: totalBytes,
      totalBytes: totalBytes,
      speedMBps: 0.0,
      savedFilePath: savedFilePath,
    );
  }

  /// Factory for failure
  factory TransferProgress.failed(String message) {
    return TransferProgress(
      state: TransferState.failed,
      errorMessage: message,
    );
  }

  /// Factory for cancellation
  factory TransferProgress.cancelled() =>
      const TransferProgress(state: TransferState.cancelled);

  /// Factory for ZIP extraction progress
  factory TransferProgress.extracting({
    required int currentFile,
    required int totalFiles,
    String? currentFileName,
  }) {
    return TransferProgress(
      state: TransferState.extracting,
      currentFile: currentFile,
      totalFiles: totalFiles,
      currentFileName: currentFileName,
    );
  }

  /// Ratio of completion between 0.0 and 1.0
  double get fraction {
    if (totalBytes <= 0) return 0.0;
    final ratio = transferredBytes / totalBytes;
    return ratio.clamp(0.0, 1.0);
  }

  /// Percentage formatted string (e.g., "74.5%")
  String get percentageString => '${(fraction * 100).toStringAsFixed(1)}%';

  /// Formatted speed string (e.g., "14.8 MB/s")
  String get formattedSpeed => '${speedMBps.toStringAsFixed(2)} MB/s';

  /// Formatted transferred amount vs total (e.g., "45.2 MB / 120.5 MB")
  String get formattedTransferredSize {
    return '${_formatBytes(transferredBytes)} / ${_formatBytes(totalBytes)}';
  }

  /// Formatted ETA string (e.g. "00:12" or "1m 30s")
  String get formattedEta {
    if (estimatedTimeRemaining == null) return '--:--';
    final seconds = estimatedTimeRemaining!.inSeconds;
    if (seconds < 60) {
      return '${seconds}s';
    }
    final minutes = seconds ~/ 60;
    final remSeconds = seconds % 60;
    return '${minutes}m ${remSeconds}s';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
