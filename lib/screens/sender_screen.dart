import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/beam_payload.dart';
import '../models/transfer_progress.dart';
import '../services/p2p_service.dart';

class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  final P2pService _p2pService = P2pService();
  final ImagePicker _picker = ImagePicker();

  File? _selectedVideo;
  int? _videoSize;
  String? _videoName;

  BeamPayload? _payload;
  TransferProgress _progress = TransferProgress.idle();
  StreamSubscription<TransferProgress>? _progressSub;

  bool _isInitializing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _progressSub = _p2pService.senderProgressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _progress = progress;
        });
      }
    });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _p2pService.stopHosting();
    super.dispose();
  }

  /// Picks a video from the gallery and reads its metadata
  Future<void> _pickVideo() async {
    try {
      final hasPermission = await _p2pService.requestSenderPermissions();
      if (!hasPermission) {
        _showSnackBar('Permissions are required to beam videos.');
        return;
      }

      final XFile? pickedFile = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(hours: 3),
      );

      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final size = await file.length();
      final name = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : file.path.split(Platform.pathSeparator).last;

      setState(() {
        _selectedVideo = file;
        _videoSize = size;
        _videoName = name;
        _payload = null;
        _progress = TransferProgress.idle();
        _statusMessage = null;
      });
    } catch (e) {
      _showSnackBar('Error selecting video: $e');
    }
  }

  /// Starts the local HTTP streaming server and generates the QR code payload
  Future<void> _startBeaming() async {
    if (_selectedVideo == null) return;

    setState(() {
      _isInitializing = true;
      _statusMessage = 'Initializing local P2P network & server...';
    });

    try {
      final payload = await _p2pService.startHosting(_selectedVideo!);
      setState(() {
        _payload = payload;
        _isInitializing = false;
        _statusMessage = 'Waiting for receiver to scan QR code...';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _statusMessage = null;
      });
      _showSnackBar('Failed to host video: $e');
    }
  }

  /// Stops hosting and resets state
  Future<void> _stopBeaming() async {
    await _p2pService.stopHosting();
    setState(() {
      _payload = null;
      _progress = TransferProgress.idle();
      _statusMessage = null;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.indigo.shade900,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
          'Beam Video (Sender)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step 1: Video Selection Card
            _buildVideoSelectionCard(),

            const SizedBox(height: 20),

            // Step 2: Hosting and QR Code or Live Progress
            if (_isInitializing)
              _buildLoadingCard()
            else if (_payload != null)
              _buildActiveTransferView()
            else if (_selectedVideo != null)
              _buildStartButton(),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSelectionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.video_library_rounded,
                  color: Colors.indigoAccent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video File',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Select an offline video to transmit',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedVideo == null) ...[
            OutlinedButton.icon(
              onPressed: _pickVideo,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: Colors.indigoAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(
                Icons.add_photo_alternate_rounded,
                color: Colors.indigoAccent,
              ),
              label: const Text(
                'Choose Video from Gallery',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.play_circle_fill,
                    color: Colors.indigoAccent,
                    size: 36,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _videoName ?? 'video.mp4',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatBytes(_videoSize ?? 0),
                          style: const TextStyle(
                            color: Colors.indigoAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_payload == null)
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: _pickVideo,
                      tooltip: 'Change Video',
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return ElevatedButton.icon(
      onPressed: _startBeaming,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.indigoAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 6,
        shadowColor: Colors.indigoAccent.withValues(alpha: 0.5),
      ),
      icon: const Icon(Icons.qr_code_rounded, size: 24),
      label: const Text(
        'Generate Beam QR',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(color: Colors.indigoAccent),
          const SizedBox(height: 20),
          Text(
            _statusMessage ?? 'Preparing server...',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTransferView() {
    final isTransferring = _progress.state == TransferState.transferring;
    final isCompleted = _progress.state == TransferState.completed;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isCompleted
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : isTransferring
              ? Colors.indigoAccent.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          if (isCompleted) ...[
            _buildCompletedView(),
          ] else if (isTransferring) ...[
            _buildLiveTransferMetrics(),
          ] else ...[
            _buildQrDisplay(),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _stopBeaming,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 20),
            label: Text(
              isCompleted ? 'Done / Host Another' : 'Stop Beaming',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrDisplay() {
    final qrData = _payload!.toJsonString();

    return Column(
      children: [
        const Text(
          'Ready to Beam',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Point the receiver phone camera at this QR code',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 20),
        // QR Code container with rounded white background
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.indigoAccent.withValues(alpha: 0.25),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: 220,
            gapless: true,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF0D1117),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.circle,
              color: Color(0xFF0D1117),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_payload!.ssid != null && _payload!.password != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.indigoAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.wifi_rounded,
                          color: Colors.indigoAccent,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Direct Wi-Fi Hotspot',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: _payload!.password!),
                        );
                        _showSnackBar('Password copied to clipboard');
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.indigoAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.copy,
                              color: Colors.indigoAccent,
                              size: 12,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Copy Pwd',
                              style: TextStyle(
                                color: Colors.indigoAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'SSID: ${_payload!.ssid}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Password: ${_payload!.password}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF21262D),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lan_outlined,
                color: Colors.indigoAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Stream Server: ${_payload!.ip}:${_payload!.port}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTransferMetrics() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Uploading Video...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.indigoAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _progress.formattedSpeed,
                style: const TextStyle(
                  color: Colors.indigoAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: _progress.fraction,
            minHeight: 14,
            backgroundColor: const Color(0xFF21262D),
            valueColor: const AlwaysStoppedAnimation<Color>(
              Colors.indigoAccent,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _progress.percentageString,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              _progress.formattedTransferredSize,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(Icons.timer_outlined, color: Colors.white38, size: 14),
            const SizedBox(width: 4),
            Text(
              'ETA: ${_progress.formattedEta}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompletedView() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Colors.greenAccent,
            size: 64,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Video Beamed Successfully!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Transferred ${_formatBytes(_progress.totalBytes)}',
          style: const TextStyle(color: Colors.white60, fontSize: 14),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
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
