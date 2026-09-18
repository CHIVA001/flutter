import 'package:flutter/material.dart';

extension DialogExt on BuildContext {
  Future<void> showErrorDialog(
    String rawMessage, {
    String? title,
    IconData icon = Icons.gpp_bad_rounded,
    Color iconColor = Colors.red,
    void Function()? onPressed,
  }) {
    // Clean message
    String cleanMessage = rawMessage
        .replaceAll('Exception: ', '')
        .replaceAll('Dio Error: ', '')
        .trim();

    // Extract message from map-like string
    if (cleanMessage.contains('message:')) {
      final match = RegExp(r'message:\s*([^,\}]+)').firstMatch(cleanMessage);
      if (match != null && match.group(1) != null) {
        cleanMessage = match.group(1)!.trim();
      }
    }

    if (cleanMessage.isEmpty) {
      cleanMessage = 'Something went wrong!';
    }

    return showDialog<void>(
      context: this,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 38),
            ),
            const SizedBox(height: 12),
            Text(
              title ?? 'Error',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          cleanMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onPressed?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
