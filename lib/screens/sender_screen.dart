import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
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

  /// Sets the selected file and reads its metadata
  void _onFileSelected(File file, String name, int size) {
    setState(() {
      _selectedVideo = file;
      _videoSize = size;
      _videoName = name;
      _payload = null;
      _progress = TransferProgress.idle();
      _statusMessage = null;
    });
  }

  /// Shows the bottom sheet with source options: Photo/Video Gallery, Camera, and Files
  void _showSourceBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Select File to Beam',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose source from your device storage or camera',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 20),
                _buildSourceOptionTile(
                  title: 'Photos & Videos',
                  subtitle: 'Pick from your gallery or camera roll',
                  icon: Icons.photo_library_rounded,
                  colors: [const Color(0xFF4F46E5), const Color(0xFF7C3AED)],
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickFromGallery();
                  },
                ),
                const SizedBox(height: 12),
                _buildSourceOptionTile(
                  title: 'Record Video with Camera',
                  subtitle: 'Capture a new high-definition video',
                  icon: Icons.videocam_rounded,
                  colors: [const Color(0xFFE11D48), const Color(0xFFF43F5E)],
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickFromCamera(isVideo: true);
                  },
                ),
                const SizedBox(height: 12),
                _buildSourceOptionTile(
                  title: 'Take Photo with Camera',
                  subtitle: 'Snap a picture directly',
                  icon: Icons.camera_alt_rounded,
                  colors: [const Color(0xFFD97706), const Color(0xFFF59E0B)],
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickFromCamera(isVideo: false);
                  },
                ),
                const SizedBox(height: 12),
                _buildSourceOptionTile(
                  title: 'Browse Files & Documents',
                  subtitle: 'Pick any file or document from device storage',
                  icon: Icons.folder_open_rounded,
                  colors: [const Color(0xFF0284C7), const Color(0xFF0D9488)],
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickFromFileSystem();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceOptionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF21262D),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white30,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Picks media (photo/video) from the gallery
  Future<void> _pickFromGallery() async {
    try {
      final hasPermission = await _p2pService.requestSenderPermissions();
      if (!hasPermission) {
        _showSnackBar('Storage/photos permission required.');
        return;
      }

      final XFile? pickedFile = await _picker.pickMedia();

      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final size = await file.length();
      final name = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : p.basename(file.path);

      _onFileSelected(file, name, size);
    } catch (e) {
      _showSnackBar('Error selecting media: $e');
    }
  }

  /// Captures video or photo from camera
  Future<void> _pickFromCamera({required bool isVideo}) async {
    try {
      final hasPermission = await _p2pService.requestSenderPermissions();
      if (!hasPermission) {
        _showSnackBar('Camera permission is required.');
        return;
      }

      final XFile? pickedFile = isVideo
          ? await _picker.pickVideo(
              source: ImageSource.camera,
              maxDuration: const Duration(hours: 1),
            )
          : await _picker.pickImage(source: ImageSource.camera);

      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final size = await file.length();
      final name = pickedFile.name.isNotEmpty
          ? pickedFile.name
          : p.basename(file.path);

      _onFileSelected(file, name, size);
    } catch (e) {
      _showSnackBar('Error capturing from camera: $e');
    }
  }

  /// Picks any file/document from filesystem storage
  Future<void> _pickFromFileSystem() async {
    try {
      final hasPermission = await _p2pService.requestSenderPermissions();
      if (!hasPermission) {
        _showSnackBar('Storage permission is required to browse files.');
        return;
      }

      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (files.isEmpty) return;

      final selected = files.first;
      final path = selected.path;
      if (path == null) return;

      final file = File(path);
      final size = await file.length();
      final name = selected.name;

      _onFileSelected(file, name, size);
    } catch (e) {
      _showSnackBar('Error picking file: $e');
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

  IconData _getFileIcon(String? name) {
    if (name == null) return Icons.insert_drive_file_rounded;
    final ext = p.extension(name).toLowerCase();
    if (['.mp4', '.mov', '.mkv', '.avi', '.webm'].contains(ext)) {
      return Icons.play_circle_fill;
    }
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['.pdf', '.doc', '.docx', '.txt', '.xlsx'].contains(ext)) {
      return Icons.description_rounded;
    }
    if (['.zip', '.rar', '.7z', '.tar'].contains(ext)) {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(String? name) {
    if (name == null) return Colors.cyanAccent;
    final ext = p.extension(name).toLowerCase();
    if (['.mp4', '.mov', '.mkv', '.avi', '.webm'].contains(ext)) {
      return Colors.indigoAccent;
    }
    if (['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic'].contains(ext)) {
      return Colors.pinkAccent;
    }
    if (['.pdf', '.doc', '.docx', '.txt'].contains(ext)) {
      return Colors.amberAccent;
    }
    return Colors.cyanAccent;
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
                  Icons.auto_awesome_motion_rounded,
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
                      'Source File to Beam',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Pick from files, photos, videos, or capture live',
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
              onPressed: _showSourceBottomSheet,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                side: const BorderSide(color: Colors.indigoAccent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: Colors.indigoAccent,
              ),
              label: const Text(
                'Choose File, Photo, or Video',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
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
                  Icon(
                    _getFileIcon(_videoName),
                    color: _getFileColor(_videoName),
                    size: 36,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _videoName ?? 'selected_file',
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
                          style: TextStyle(
                            color: _getFileColor(_videoName),
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
                        Icons.swap_horiz_rounded,
                        color: Colors.white70,
                        size: 24,
                      ),
                      onPressed: _showSourceBottomSheet,
                      tooltip: 'Change Source',
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
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.wifi_rounded,
                            color: Colors.indigoAccent,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Direct Wi-Fi Hotspot',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.lan_outlined,
                    color: Colors.indigoAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stream Server: ${_payload!.ip}:${_payload!.port}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              if (_payload!.candidateIps.length > 1) ...[
                const SizedBox(height: 6),
                Text(
                  'Candidates: ${_payload!.candidateIps.join(", ")}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
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
            const Expanded(
              child: Text(
                'Uploading Video...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
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
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _progress.formattedTransferredSize,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
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
