import 'dart:developer';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppConfig {
  static final FirebaseRemoteConfig _remoteConfig =
      FirebaseRemoteConfig.instance;

  // Colors as reactive variables
  static Rx<Color> primaryColor = Colors.blue.obs;
  static Rx<Color> backgroundColor = Colors.white.obs;

  static Future<void> init() async {
  try {
    // Default values
    await _remoteConfig.setDefaults({
      'primary_color1': '#000000',
      'background_color1': '#FFFFFF',
    });

    // Fetch remote config with 0 seconds cache for testing
    await _remoteConfig.fetch();
    await _remoteConfig.activate();

    _updateColors();
  } catch (e) {
    log('Remote Config fetch failed: $e');
  }
}

static Future<void> fetchRemoteConfig() async {
  try {
    await _remoteConfig.fetch();
    await _remoteConfig.activate();
    _updateColors();
  } catch (e) {
    log('Remote Config fetch failed: $e');
  }
}


  static void _updateColors() {
    primaryColor.value = _hexToColor(_remoteConfig.getString('primary_color'));
    backgroundColor.value = _hexToColor(
      _remoteConfig.getString('background_color'),
    );
  }


  static Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}
