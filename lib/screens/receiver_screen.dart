import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/beam_payload.dart';
import '../models/transfer_progress.dart';
import '../services/p2p_service.dart';

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen>
    with SingleTickerProviderStateMixin {
  final P2pService _p2pService = P2pService();
  late final MobileScannerController _scannerController;

  late final AnimationController _scanAnimationController;
  late final Animation<double> _scanAnimation;

  BeamPayload? _scannedPayload;
  bool _isDownloading = false;
  File? _downloadedFile;
  String? _errorMessage;

  TransferProgress _progress = TransferProgress.idle();
  StreamSubscription<TransferProgress>? _progressSub;

  @override
  void initState() {
    super.initState();

    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scanAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _progressSub = _p2pService.receiverProgressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _progress = progress;
        });
      }
    });

    _requestInitialPermissions();
  }

  Future<void> _requestInitialPermissions() async {
    try {
      await _p2pService.requestReceiverPermissions();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _scanAnimationController.dispose();
    _scannerController.dispose();
    _p2pService.cancelReceiverTransfer();
    super.dispose();
  }

  /// Handles barcode detection from the scanner
  void _onDetect(BarcodeCapture capture) {
    if (_scannedPayload != null || _isDownloading) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        try {
          final payload = BeamPayload.fromJsonString(rawValue);
          setState(() {
            _scannedPayload = payload;
            _errorMessage = null;
          });
          _scannerController.stop();
          _showTransferConfirmationDialog(payload);
          break;
        } catch (e) {
          debugPrint('Scanned non-BeamQR code: $e');
        }
      }
    }
  }

  /// Prompts user with video metadata before initiating high-speed download
  void _showTransferConfirmationDialog(BeamPayload payload) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.download_rounded,
                        color: Colors.cyanAccent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Beam Incoming Video',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Sender verified & ready to stream',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildMetaRow(
                        Icons.movie_outlined,
                        'File Name',
                        payload.fileName,
                      ),
                      const Divider(color: Colors.white12, height: 16),
                      _buildMetaRow(
                        Icons.data_usage_rounded,
                        'File Size',
                        payload.formattedSize,
                      ),
                      if (payload.isOnline) ...[
                        const Divider(color: Colors.white12, height: 16),
                        _buildMetaRow(
                          Icons.public,
                          'Transit',
                          'Online Cloud Beam',
                        ),
                      ] else ...[
                        if (payload.ssid != null) ...[
                          const Divider(color: Colors.white12, height: 16),
                          _buildMetaRow(
                            Icons.wifi,
                            'Wi-Fi Hotspot',
                            payload.ssid!,
                          ),
                        ],
                        if (payload.password != null) ...[
                          const Divider(color: Colors.white12, height: 16),
                          Row(
                            children: [
                              const Icon(
                                Icons.lock_outline,
                                color: Colors.cyanAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Password',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Flexible(
                                child: Text(
                                  payload.password!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(text: payload.password!),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Password copied'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 1),
                                    ),
                                  );
                                },
                                child: const Icon(
                                  Icons.copy,
                                  color: Colors.cyanAccent,
                                  size: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(color: Colors.white12, height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetaRow(
                                Icons.lan_outlined,
                                'Stream IP',
                                '${payload.ip}:${payload.port}',
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () {
                                Navigator.of(ctx).pop();
                                _showEditIpDialog(payload);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit,
                                      color: Colors.cyanAccent,
                                      size: 11,
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      'Edit',
                                      style: TextStyle(
                                        color: Colors.cyanAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (payload.isOnline) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.purpleAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.public,
                          color: Colors.purpleAccent,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Online Cloud Stream',
                                style: TextStyle(
                                  color: Colors.purpleAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Works across cellular 4G/5G and different Wi-Fi networks worldwide.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (Platform.isIOS && payload.ssid != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.cyanAccent.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.cyanAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'iOS: If prompt appears, tap Join to connect to ${payload.ssid}.',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _resetScanner();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _startDownloading(payload);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.bolt, size: 20),
                        label: const Text(
                          'Start Download',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetaRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyanAccent, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const Spacer(),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  /// Initiates video download from the sender
  Future<void> _startDownloading(BeamPayload payload) async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    try {
      final file = await _p2pService.receiveVideo(payload);
      setState(() {
        _isDownloading = false;
        _downloadedFile = file;
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// Resets scanner to look for another QR code
  void _resetScanner() {
    setState(() {
      _scannedPayload = null;
      _downloadedFile = null;
      _errorMessage = null;
      _isDownloading = false;
      _progress = TransferProgress.idle();
    });
    _scannerController.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Receive Video (Beam In)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_scannedPayload == null && !_isDownloading) ...[
            IconButton(
              icon: const Icon(Icons.link_rounded, color: Colors.cyanAccent),
              tooltip: 'Paste Download Link',
              onPressed: _showPasteLinkDialog,
            ),
            IconButton(
              icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
              onPressed: () => _scannerController.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(
                Icons.flip_camera_ios_rounded,
                color: Colors.white,
              ),
              onPressed: () => _scannerController.switchCamera(),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_downloadedFile != null) {
      return _buildSuccessView();
    }

    if (_isDownloading) {
      return _buildDownloadProgressView();
    }

    if (_errorMessage != null) {
      return _buildErrorView();
    }

    // Default: Scanner with overlay
    return _buildScannerWithOverlay();
  }

  Widget _buildScannerWithOverlay() {
    return Stack(
      children: [
        MobileScanner(controller: _scannerController, onDetect: _onDetect),

        // Semi-transparent overlay with reticle
        LayoutBuilder(
          builder: (context, constraints) {
            final scanAreaSize = constraints.maxWidth * 0.72;
            final topOffset = (constraints.maxHeight - scanAreaSize) / 2.2;
            final leftOffset = (constraints.maxWidth - scanAreaSize) / 2;

            return Stack(
              children: [
                // Dark background cutout overlay
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.65),
                    BlendMode.srcOut,
                  ),
                  child: Stack(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                      ),
                      Positioned(
                        top: topOffset,
                        left: leftOffset,
                        width: scanAreaSize,
                        height: scanAreaSize,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Glowing reticle frame
                Positioned(
                  top: topOffset,
                  left: leftOffset,
                  width: scanAreaSize,
                  height: scanAreaSize,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.cyanAccent.withValues(alpha: 0.8),
                        width: 2.5,
                      ),
                    ),
                    child: AnimatedBuilder(
                      animation: _scanAnimation,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: _LaserScanPainter(
                            progress: _scanAnimation.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Prompt banner
                Positioned(
                  bottom: 50,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.cyanAccent,
                          size: 22,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Align BeamQR within the frame',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildDownloadProgressView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Downloading Stream...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _progress.formattedSpeed,
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: _progress.fraction,
                  minHeight: 16,
                  backgroundColor: const Color(0xFF21262D),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.cyanAccent,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progress.percentageString,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _progress.formattedTransferredSize,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: Colors.white38,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ETA: ${_progress.formattedEta}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  _p2pService.cancelReceiverTransfer();
                  _resetScanner();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 20),
                label: const Text('Cancel Download'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.download_done_rounded,
                  color: Colors.greenAccent,
                  size: 56,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Transfer Complete!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                Platform.isAndroid
                    ? 'Saved to device storage (Downloads / BeamQR)'
                    : 'Saved to Files app (On My iPhone > BeamQR)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              if (_downloadedFile != null &&
                  (_downloadedFile!.path.toLowerCase().endsWith('.jpg') ||
                      _downloadedFile!.path.toLowerCase().endsWith('.jpeg') ||
                      _downloadedFile!.path.toLowerCase().endsWith('.png') ||
                      _downloadedFile!.path.toLowerCase().endsWith('.webp') ||
                      _downloadedFile!.path.toLowerCase().endsWith('.gif'))) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.file(
                      _downloadedFile!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF21262D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined, color: Colors.cyanAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _downloadedFile?.path ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 16, color: Colors.cyanAccent),
                      tooltip: 'Copy Path',
                      onPressed: () {
                        if (_downloadedFile != null) {
                          Clipboard.setData(ClipboardData(text: _downloadedFile!.path));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('File path copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _resetScanner,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan Another Video'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    final payload = _scannedPayload;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Colors.redAccent,
                size: 56,
              ),
              const SizedBox(height: 16),
              const Text(
                'Connection Failed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _errorMessage ?? 'Failed to connect to sender.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (payload != null &&
                  payload.ssid != null &&
                  payload.password != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF21262D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connect your device Wi-Fi to:',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'SSID: ${payload.ssid}',
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Password: ${payload.password}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: payload.password!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Password copied to clipboard'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.copy,
                                color: Colors.cyanAccent,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (payload != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showEditIpDialog(payload),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent),
                    minimumSize: const Size(double.infinity, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.edit_location_alt_outlined, size: 16),
                  label: const Text('Enter Sender IP Manually'),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _resetScanner,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Scan Again'),
                    ),
                  ),
                  if (payload != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _startDownloading(payload),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text(
                          'Retry',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditIpDialog(BeamPayload payload) {
    final controller = TextEditingController(text: payload.ip);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.edit_location_alt_rounded, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text(
              'Enter Sender IP',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If testing with an emulator or PC, enter the reachable IP (e.g. 192.168.100.192):',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                hintText: 'e.g. 192.168.100.192',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF21262D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            if (payload.candidateIps.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Candidate IPs from QR code:',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: payload.candidateIps.map((ip) {
                  return ActionChip(
                    label: Text(
                      ip,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.cyanAccent,
                      ),
                    ),
                    backgroundColor: const Color(0xFF21262D),
                    side: BorderSide(
                      color: Colors.cyanAccent.withValues(alpha: 0.3),
                    ),
                    onPressed: () => controller.text = ip,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final newIp = controller.text.trim();
              Navigator.of(ctx).pop();
              if (newIp.isNotEmpty) {
                final updatedPayload = _p2pService.updatePayloadHostIp(
                  payload,
                  newIp,
                );
                setState(() {
                  _scannedPayload = updatedPayload;
                });
                _startDownloading(updatedPayload);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showPasteLinkDialog() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text?.trim() ?? '';
    final controller = TextEditingController(
      text: clipboardText.startsWith('http') ? clipboardText : '',
    );

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text(
              'Paste Beam Link',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter direct download link or BeamQR payload:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF21262D),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = controller.text.trim();
              Navigator.of(ctx).pop();
              if (raw.isNotEmpty) {
                try {
                  final payload = BeamPayload.fromJsonString(raw);
                  setState(() {
                    _scannedPayload = payload;
                    _errorMessage = null;
                  });
                  _showTransferConfirmationDialog(payload);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Invalid link or QR payload: $e'),
                      backgroundColor: Colors.redAccent.shade700,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Beam In'),
          ),
        ],
      ),
    );
  }
}

/// Custom laser line painter animating across the scanner reticle
class _LaserScanPainter extends CustomPainter {
  final double progress;

  _LaserScanPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.cyanAccent.withValues(alpha: 0.0),
          Colors.cyanAccent,
          Colors.cyanAccent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, y, size.width, 3))
      ..strokeWidth = 3;

    canvas.drawLine(Offset(10, y), Offset(size.width - 10, y), paint);
  }

  @override
  bool shouldRepaint(covariant _LaserScanPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
