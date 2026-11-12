import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioDeviceEndpoint {
  final String id;
  final String label;
  final String subtitle;
  final bool isInput;
  final String iconType; // 'default', 'usb', 'bluetooth', 'webcam', 'jack', 'hdmi'

  const AudioDeviceEndpoint({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.isInput,
    this.iconType = 'default',
  });
}

/// Сервис управления микрофоном (устройством ввода) и наушниками/динамиками (устройством вывода)
/// для комнат совместного просмотра «Вместе» на ПК и мобильных платформах.
class RoomAudioDevicesService extends ChangeNotifier {
  static final RoomAudioDevicesService instance = RoomAudioDevicesService._();

  RoomAudioDevicesService._() {
    _loadSavedPreferences();
  }

  static const String _prefInputIdKey = 'sync_room_audio_input_id';
  static const String _prefOutputIdKey = 'sync_room_audio_output_id';
  static const String _prefMicMutedKey = 'sync_room_mic_muted';
  static const String _prefNoiseSuppKey = 'sync_room_noise_suppression';
  static const String _prefMicVolumeKey = 'sync_room_mic_volume';

  List<AudioDeviceEndpoint> _inputDevices = List.of(_defaultInputDevices);
  List<AudioDeviceEndpoint> _outputDevices = List.of(_defaultOutputDevices);

  String _selectedInputId = 'default_input';
  String _selectedOutputId = 'auto';
  bool _isMicMuted = false;
  bool _isNoiseSuppression = true;
  double _micVolume = 0.85;
  bool _isRefreshing = false;

  List<AudioDeviceEndpoint> get inputDevices => _inputDevices;
  List<AudioDeviceEndpoint> get outputDevices => _outputDevices;
  String get selectedInputId => _selectedInputId;
  String get selectedOutputId => _selectedOutputId;
  bool get isMicMuted => _isMicMuted;
  bool get isNoiseSuppression => _isNoiseSuppression;
  double get micVolume => _micVolume;
  bool get isRefreshing => _isRefreshing;

  AudioDeviceEndpoint get selectedInputDevice => _inputDevices.firstWhere(
        (d) => d.id == _selectedInputId,
        orElse: () => _inputDevices.first,
      );

  AudioDeviceEndpoint get selectedOutputDevice => _outputDevices.firstWhere(
        (d) => d.id == _selectedOutputId,
        orElse: () => _outputDevices.first,
      );

  static const List<AudioDeviceEndpoint> _defaultInputDevices = [
    AudioDeviceEndpoint(
      id: 'default_input',
      label: 'По умолчанию (Системный микрофон)',
      subtitle: 'Основное устройство ввода ОС',
      isInput: true,
      iconType: 'default',
    ),
  ];

  static const List<AudioDeviceEndpoint> _defaultOutputDevices = [
    AudioDeviceEndpoint(
      id: 'auto',
      label: 'По умолчанию (Системный вывод звука)',
      subtitle: 'Основное устройство воспроизведения ОС',
      isInput: false,
      iconType: 'default',
    ),
  ];

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedInputId = prefs.getString(_prefInputIdKey) ?? 'default_input';
      _selectedOutputId = prefs.getString(_prefOutputIdKey) ?? 'auto';
      _isMicMuted = prefs.getBool(_prefMicMutedKey) ?? false;
      _isNoiseSuppression = prefs.getBool(_prefNoiseSuppKey) ?? true;
      _micVolume = prefs.getDouble(_prefMicVolumeKey) ?? 0.85;
      notifyListeners();
    } catch (_) {}
  }

  /// Опрашивает реальные аудиоустройства Windows и `media_kit` плеера (если передан)
  Future<void> refreshDevices({Player? activePlayer}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();

    try {
      final discoveredInputs = <AudioDeviceEndpoint>[..._defaultInputDevices];
      final discoveredOutputs = <AudioDeviceEndpoint>[..._defaultOutputDevices];

      // 1. Считываем реальные устройства вывода из media_kit Player (если активен)
      if (activePlayer != null) {
        final mkDevices = activePlayer.state.audioDevices;
        for (final dev in mkDevices) {
          if (dev.name.isEmpty || dev.name == 'auto') continue;
          final label = dev.description.isNotEmpty ? dev.description : dev.name;
          final exists = discoveredOutputs.any(
            (e) => e.id == dev.name || e.label.toLowerCase() == label.toLowerCase(),
          );
          if (!exists) {
            discoveredOutputs.insert(
              1,
              AudioDeviceEndpoint(
                id: dev.name,
                label: label,
                subtitle: 'Устройство вывода MediaKit (${dev.name})',
                isInput: false,
                iconType: _detectIconType(label),
              ),
            );
          }
        }
      }

      // 2. На Windows опрашиваем активные устройства звука Win32_SoundDevice и AudioEndpoint
      if (!kIsWeb && Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST')) {
        try {
          final result = await Process.run(
            'powershell',
            [
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r"Get-CimInstance Win32_SoundDevice | Where-Object { $_.Status -eq 'OK' } | Select-Object -ExpandProperty Name",
            ],
            stdoutEncoding: utf8,
          ).timeout(const Duration(seconds: 3));

          if (result.exitCode == 0 && result.stdout is String) {
            final lines = (result.stdout as String)
                .split(RegExp(r'\r?\n'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toSet()
                .toList();

            for (final name in lines) {
              final lower = name.toLowerCase();
              final isMic = lower.contains('микрофон') ||
                  lower.contains('microphone') ||
                  lower.contains('input') ||
                  lower.contains('mic') ||
                  lower.contains('запись');

              if (isMic) {
                final id = 'win_in_${name.hashCode.abs()}';
                if (!discoveredInputs.any((e) => e.label.toLowerCase() == lower)) {
                  discoveredInputs.add(
                    AudioDeviceEndpoint(
                      id: id,
                      label: name,
                      subtitle: 'Реальный микрофон ПК ($name)',
                      isInput: true,
                      iconType: _detectIconType(name),
                    ),
                  );
                }
              } else {
                final id = 'win_out_${name.hashCode.abs()}';
                if (!discoveredOutputs.any((e) => e.label.toLowerCase() == lower)) {
                  discoveredOutputs.add(
                    AudioDeviceEndpoint(
                      id: id,
                      label: name,
                      subtitle: 'Реальное устройство вывода ПК ($name)',
                      isInput: false,
                      iconType: _detectIconType(name),
                    ),
                  );
                }
              }
            }
          }
        } catch (_) {}
      }

      _inputDevices = discoveredInputs;
      _outputDevices = discoveredOutputs;
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  static String _detectIconType(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('bluetooth') || lower.contains('airpods') || lower.contains('tws') || lower.contains('hands-free')) {
      return 'bluetooth';
    }
    if (lower.contains('webcam') || lower.contains('camera') || lower.contains('камер')) {
      return 'webcam';
    }
    if (lower.contains('usb') || lower.contains('hyperx') || lower.contains('fifine') || lower.contains('yeti') || lower.contains('razer')) {
      return 'usb';
    }
    if (lower.contains('hdmi') || lower.contains('displayport') || lower.contains('nvidia') || lower.contains('amd')) {
      return 'hdmi';
    }
    return 'jack';
  }

  Future<void> selectInputDevice(String deviceId) async {
    _selectedInputId = deviceId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefInputIdKey, deviceId);
    } catch (_) {}
  }

  Future<void> selectOutputDevice(String deviceId, {Player? activePlayer}) async {
    _selectedOutputId = deviceId;
    notifyListeners();

    if (activePlayer != null) {
      try {
        final match = activePlayer.state.audioDevices
            .where((d) => d.name == deviceId || d.description == selectedOutputDevice.label)
            .firstOrNull;
        if (match != null) {
          await activePlayer.setAudioDevice(match);
        } else if (deviceId == 'auto') {
          await activePlayer.setAudioDevice(AudioDevice.auto());
        }
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefOutputIdKey, deviceId);
    } catch (_) {}
  }

  Future<void> toggleMicMute() async {
    _isMicMuted = !_isMicMuted;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefMicMutedKey, _isMicMuted);
    } catch (_) {}
  }

  Future<void> setNoiseSuppression(bool enabled) async {
    _isNoiseSuppression = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefNoiseSuppKey, enabled);
    } catch (_) {}
  }

  Future<void> setMicVolume(double value) async {
    _micVolume = value.clamp(0.0, 1.0);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefMicVolumeKey, _micVolume);
    } catch (_) {}
  }
}

