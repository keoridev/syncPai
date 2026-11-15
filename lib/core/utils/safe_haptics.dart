import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Безопасная обертка для HapticFeedback:
/// Исключает вызовы и ошибки MissingPluginException на десктопных платформах (Windows, macOS, Linux, Web).
/// Настоящий виброотклик вызывается исключительно на мобильных устройствах (Android, iOS).
class SafeHaptics {
  SafeHaptics._();

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> lightImpact() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  static Future<void> mediumImpact() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  static Future<void> heavyImpact() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  static Future<void> selectionClick() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  static Future<void> vibrate() async {
    if (!isSupported) return;
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }
}

