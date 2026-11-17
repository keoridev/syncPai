import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/di/injection.dart';
import '../../features/winter_theme/domain/services/winter_theme_service.dart';

/// Классификация производительности устройства (Meta/Google Client Performance Classing)
enum DeviceTier {
  low,
  mid,
  high;

  String get labelRu {
    switch (this) {
      case DeviceTier.low:
        return 'Базовый (4 GB или меньше)';
      case DeviceTier.mid:
        return 'Сбалансированный (6 GB)';
      case DeviceTier.high:
        return 'Высокий (8 GB+ / Desktop)';
    }
  }

  String get shortLabelRu {
    switch (this) {
      case DeviceTier.low:
        return 'Энергоэффективный';
      case DeviceTier.mid:
        return 'Сбалансированный';
      case DeviceTier.high:
        return 'Высокий';
    }
  }
}

/// Сервис адаптивного управления производительностью устройства (Adaptive Device Performance Tier).
/// Автоматически определяет объем оперативной памяти и категорию устройства при запуске,
/// конфигурирует бюджет кэша декодированных изображений (PaintingBinding.instance.imageCache),
/// подключает очистку при memory pressure и выставляет умные дефолты (размытие, плотность снегопада).
class DevicePerformanceService extends ChangeNotifier with WidgetsBindingObserver {
  static final DevicePerformanceService instance = DevicePerformanceService._();

  DevicePerformanceService._();

  static const MethodChannel _perfChannel = MethodChannel('com.syncpai/device_perf');
  static const String prefLiquidGlassKey = 'settings_liquid_glass';
  static const String prefSnowDensityKey = 'syncpai_snow_density_multiplier';

  int? _totalRamMb;
  DeviceTier _tier = DeviceTier.high;
  DeviceTier? _simulatedTier;
  int? _simulatedRamMb;

  bool _isLiquidGlassBlurEnabled = true;
  double _snowDensityMultiplier = 1.0;
  bool _isInitialized = false;

  int? get totalRamMb => _simulatedRamMb ?? _totalRamMb;
  DeviceTier get tier => _simulatedTier ?? _tier;
  bool get isLiquidGlassBlurEnabled => _isLiquidGlassBlurEnabled;
  double get snowDensityMultiplier => _snowDensityMultiplier;
  bool get isInitialized => _isInitialized;

  /// Инициализация сервиса до runApp() в main.dart
  Future<void> init({SharedPreferences? prefs}) async {
    if (_isInitialized) return;
    _isInitialized = true;

    // 1. Определение реального объема ОЗУ и классификация по Tier
    await _detectDeviceTier();

    // 2. Настройка бюджетов кэша изображений PaintingBinding.instance.imageCache
    applyImageCacheBudget();

    // 3. Подписка на memory pressure события ОС
    WidgetsBinding.instance.addObserver(this);

    // 4. Применение умных дефолтов первого запуска с учетом пользовательских оверрайдов
    await _applyFirstLaunchDefaults(prefs);
  }

  /// Определение профиля устройства через MethodChannel на Android или по умолчанию на Desktop
  Future<void> _detectDeviceTier() async {
    final isAndroid = !kIsWeb && Platform.isAndroid;

    if (isAndroid) {
      try {
        final ram = await _perfChannel.invokeMethod<int>('getTotalRamMb');
        if (ram != null && ram > 0) {
          _totalRamMb = ram;
          _tier = classifyRam(ram);
          debugPrint('[DevicePerformanceService] Android RAM: $ram MB -> Tier: ${_tier.name}');
          return;
        }
      } catch (e) {
        debugPrint('[DevicePerformanceService] MethodChannel getTotalRamMb failed: $e');
      }
    }

    // Windows / macOS / Linux / Web или fallback Android
    _totalRamMb = null;
    _tier = DeviceTier.high;
    debugPrint('[DevicePerformanceService] Default Desktop/High Tier: ${_tier.name}');
  }

  /// Классификация объема оперативной памяти по 3 категориям
  static DeviceTier classifyRam(int ramMb) {
    if (ramMb <= 4096) {
      return DeviceTier.low;
    } else if (ramMb <= 6144) {
      return DeviceTier.mid;
    } else {
      return DeviceTier.high;
    }
  }

  /// Настройка лимитов кэша изображений в зависимости от DeviceTier
  void applyImageCacheBudget() {
    final imageCache = PaintingBinding.instance.imageCache;
    switch (tier) {
      case DeviceTier.low:
        imageCache.maximumSize = 80;
        imageCache.maximumSizeBytes = 45 << 20; // 45 MB
        break;
      case DeviceTier.mid:
        imageCache.maximumSize = 150;
        imageCache.maximumSizeBytes = 90 << 20; // 90 MB
        break;
      case DeviceTier.high:
        imageCache.maximumSize = 300;
        imageCache.maximumSizeBytes = 180 << 20; // 180 MB
        break;
    }
    debugPrint(
      '[DevicePerformanceService] ImageCache configured for ${tier.name}: '
      'maxSize=${imageCache.maximumSize}, maxSizeBytes=${(imageCache.maximumSizeBytes >> 20)} MB',
    );
  }

  /// Обработка memory pressure от Android OS для предотвращения фоновых OOM крэшей
  @override
  void didHaveMemoryPressure() {
    debugPrint('[DevicePerformanceService] Memory pressure received! Clearing image cache...');
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  /// Масштабирование ширины декодирования постеров в память (memCacheWidth)
  int downscaleMemCacheWidth(int baseWidth) {
    if (tier == DeviceTier.low) {
      return (baseWidth * 0.75).round();
    }
    return baseWidth;
  }

  /// Применение умных дефолтов первого запуска с сохранением ручных настроек пользователя
  Future<void> _applyFirstLaunchDefaults(SharedPreferences? customPrefs) async {
    SharedPreferences prefs;
    if (customPrefs != null) {
      prefs = customPrefs;
    } else if (getIt.isRegistered<SharedPreferences>()) {
      prefs = getIt<SharedPreferences>();
    } else {
      prefs = await SharedPreferences.getInstance();
    }

    // 1. Настройка жидкого стекла (BackdropFilter)
    if (prefs.containsKey(prefLiquidGlassKey)) {
      // Пользователь уже явно сохранил настройку — уважаем её
      _isLiquidGlassBlurEnabled = prefs.getBool(prefLiquidGlassKey) ?? true;
    } else {
      // Первый запуск: для low-end устройств отключаем размытие во избежание фризов GPU
      _isLiquidGlassBlurEnabled = tier != DeviceTier.low;
    }

    // 2. Настройка снегопада и плотности частиц
    final hasSnowOverride = prefs.containsKey('syncpai_snowfall_enabled');
    if (!hasSnowOverride && tier == DeviceTier.low) {
      final ram = totalRamMb;
      if (ram != null && ram < 3072) {
        // Устройства с менее чем 3 ГБ ОЗУ: полностью выключаем снегопад
        WinterThemeService.instance.resetToDefault().ignore();
      }
      _snowDensityMultiplier = 0.4; // 30 частиц вместо 75
    } else if (tier == DeviceTier.low) {
      _snowDensityMultiplier = 0.4;
    } else {
      _snowDensityMultiplier = 1.0;
    }

    notifyListeners();
  }

  /// Установить состояние жидкого стекла вручную
  void setLiquidGlassBlurEnabled(bool value, {bool persist = true}) {
    if (_isLiquidGlassBlurEnabled == value) return;
    _isLiquidGlassBlurEnabled = value;
    notifyListeners();

    if (persist) {
      try {
        if (getIt.isRegistered<SharedPreferences>()) {
          getIt<SharedPreferences>().setBool(prefLiquidGlassKey, value);
        } else {
          SharedPreferences.getInstance().then((prefs) => prefs.setBool(prefLiquidGlassKey, value));
        }
      } catch (_) {}
    }
  }

  /// Сбросить настройки на рекомендованные для текущего уровня устройства
  Future<void> resetToRecommendedDefaults() async {
    SharedPreferences? prefs;
    try {
      if (getIt.isRegistered<SharedPreferences>()) {
        prefs = getIt<SharedPreferences>();
      } else {
        prefs = await SharedPreferences.getInstance();
      }
    } catch (_) {}

    // Удаляем явные оверрайды
    await prefs?.remove(prefLiquidGlassKey);

    // Применяем рекомендуемые дефолты
    _isLiquidGlassBlurEnabled = tier != DeviceTier.low;
    await prefs?.setBool(prefLiquidGlassKey, _isLiquidGlassBlurEnabled);

    if (tier == DeviceTier.low) {
      _snowDensityMultiplier = 0.4;
      final ram = totalRamMb;
      if (ram != null && ram < 3072) {
        await prefs?.setBool('syncpai_snowfall_enabled', false);
      }
    } else {
      _snowDensityMultiplier = 1.0;
    }

    applyImageCacheBudget();
    notifyListeners();
  }

  /// Симуляция профиля устройства (для unit/widget-тестов)
  @visibleForTesting
  void setSimulatedTier(DeviceTier? simulatedTier, {int? ramMb}) {
    _simulatedTier = simulatedTier;
    _simulatedRamMb = ramMb;
    if (simulatedTier != null) {
      _isLiquidGlassBlurEnabled = simulatedTier != DeviceTier.low;
      _snowDensityMultiplier = simulatedTier == DeviceTier.low ? 0.4 : 1.0;
      applyImageCacheBudget();
    }
    notifyListeners();
  }

  /// Сброс симуляции
  @visibleForTesting
  void resetSimulation() {
    _simulatedTier = null;
    _simulatedRamMb = null;
    _tier = classifyRam(_totalRamMb ?? 8192);
    applyImageCacheBudget();
    notifyListeners();
  }
}
