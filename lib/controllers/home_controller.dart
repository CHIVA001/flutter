import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigController extends GetxController {
  final FirebaseRemoteConfig remoteConfig = FirebaseRemoteConfig.instance;

  Rx<Color> primaryColor = Colors.black.obs;
  Rx<Color> backgroundColor = Colors.white.obs;

  @override
  void onInit() {
    super.onInit();
    initRemoteConfig();
  }

  Future<void> initRemoteConfig() async {
    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(seconds: 5),
      ),
    );
    _updateColors();
    remoteConfig.onConfigUpdated.listen((event) async {
      log('Remote config updated: ${event.updatedKeys}');
      await remoteConfig.activate(); // Activate new values
      _updateColors(); // Apply new color values
    });
  }

  void _updateColors() {
    try {
      String primaryHex = remoteConfig.getString('primary_color');
      String backgroundHex = remoteConfig.getString('background_color');

      if (primaryHex.isNotEmpty) {
        primaryColor.value = _hexToColor(primaryHex);
      }
      if (backgroundHex.isNotEmpty) {
        backgroundColor.value = _hexToColor(backgroundHex);
      }
    } catch (e) {
      log("Error parsing remote config colors: $e");
    }
  }

  Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
