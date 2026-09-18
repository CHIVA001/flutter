import 'dart:io';
import 'package:flutter/material.dart';

extension ContextExt on BuildContext {
  double get h => MediaQuery.of(this).size.height;
  double get w => MediaQuery.of(this).size.width;
  //
  double get getMinHeight =>
      MediaQuery.of(this).size.height - AppBar().preferredSize.height - getTop;

  /// Screen width
  double get getWidth => MediaQuery.of(this).size.width;

  /// Screen height
  double get getHeight => MediaQuery.of(this).size.height;

  /// Bottom padding (safe area)
  double get getBottom => MediaQuery.of(this).padding.bottom;
  bool get isBottomZero => getBottom == 0;

  /// Top padding (status bar)
  double get getTop => MediaQuery.of(this).padding.top;

  /// Unfocus keyboard
  void unfocus() => FocusScope.of(this).unfocus();

  /// Percentage height (floating)
  double hp(double percent) => h * percent / 100;

  /// Percentage width (floating)
  double wp(double percent) => w * percent / 100;

  ///
  bool get isIos => Platform.isIOS;
  bool get isAndroid => Platform.isAndroid;
  //
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;

  // check ios version 26 up
  bool get isIOS26OrAbove {
    if (!isIos) return false;
    final versionStr = Platform.operatingSystemVersion;
    final match =
        RegExp(r'(?:Version|iOS)\s*(\d+)').firstMatch(versionStr) ??
        RegExp(r'(\d+)').firstMatch(versionStr);
    if (match == null) return false;
    final majorVersion = int.tryParse(match.group(1)!);
    if (majorVersion == null) return false;
    return majorVersion >= 26;
  }

  // is  Theme Mode
  bool get isDarkMode => theme.brightness == Brightness.dark;
  bool get isLightMode => theme.brightness == Brightness.light;

  //  BouncingScrollPhysics
  ScrollPhysics get bouncingScrollPhysics =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  /// Current language code ('km', 'en', etc.) safely handled with fallback
  String get langCode {
    try {
      return Localizations.localeOf(this).languageCode;
    } catch (_) {
      return 'km';
    }
  }

  String get languageCode => langCode;

  /// Check if the current locale is Khmer
  bool get isKhmer => langCode == 'km';

  // flutter run -d 00008030-000128560C9B802E --release --dart-define-from-file=.env
}
