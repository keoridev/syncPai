import 'dart:async';
import 'package:flutter/services.dart';

/// Service managing Android Picture-in-Picture (PiP) mode.
class PipService {
  PipService._() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  static final PipService instance = PipService._();

  static const MethodChannel _channel = MethodChannel('com.syncpai.app/pip');

  final StreamController<bool> _pipModeController =
      StreamController<bool>.broadcast();

  bool _isInPip = false;

  /// Returns whether the app is currently in Picture-in-Picture mode.
  bool get isInPip => _isInPip;

  /// Stream of changes to Picture-in-Picture state.
  Stream<bool> get pipModeStream => _pipModeController.stream;

  /// Checks if the device OS supports Picture-in-Picture (Android 8.0+).
  Future<bool> isSupported() async {
    try {
      final bool? supported = await _channel.invokeMethod<bool>('isPipSupported');
      return supported ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Triggers PiP mode immediately.
  Future<bool> enterPip({int numerator = 16, int denominator = 9}) async {
    try {
      final bool? entered = await _channel.invokeMethod<bool>('enterPip', {
        'numerator': numerator,
        'denominator': denominator,
      });
      return entered ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enables or disables automatic PiP when user leaves app during playback.
  Future<void> setAutoPip(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setAutoPip', {'enabled': enabled});
    } catch (_) {
      // Ignored on unsupported platforms.
    }
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onPipChanged') {
      final bool inPip = call.arguments as bool? ?? false;
      _isInPip = inPip;
      _pipModeController.add(inPip);
    }
  }

  /// Dispose stream controller resources.
  void dispose() {
    _pipModeController.close();
  }
}

