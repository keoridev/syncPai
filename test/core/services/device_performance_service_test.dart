import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/services/device_performance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DevicePerformanceService Tests', () {
    late DevicePerformanceService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = DevicePerformanceService.instance;
      service.resetSimulation();
    });

    tearDown(() {
      service.resetSimulation();
    });

    test('accurately classifies RAM into 3 performance tiers', () {
      // Low Tier: <= 4096 MB
      expect(DevicePerformanceService.classifyRam(2048), equals(DeviceTier.low));
      expect(DevicePerformanceService.classifyRam(3500), equals(DeviceTier.low));
      expect(DevicePerformanceService.classifyRam(4096), equals(DeviceTier.low));

      // Mid Tier: 4097 – 6144 MB
      expect(DevicePerformanceService.classifyRam(4097), equals(DeviceTier.mid));
      expect(DevicePerformanceService.classifyRam(6000), equals(DeviceTier.mid));
      expect(DevicePerformanceService.classifyRam(6144), equals(DeviceTier.mid));

      // High Tier: > 6144 MB
      expect(DevicePerformanceService.classifyRam(6145), equals(DeviceTier.high));
      expect(DevicePerformanceService.classifyRam(8192), equals(DeviceTier.high));
      expect(DevicePerformanceService.classifyRam(12288), equals(DeviceTier.high));
    });

    test('configures imageCache budgets adaptively per DeviceTier', () {
      final imageCache = PaintingBinding.instance.imageCache;

      // Low Tier: 80 images, 45 MB
      service.setSimulatedTier(DeviceTier.low, ramMb: 3500);
      expect(service.tier, equals(DeviceTier.low));
      expect(imageCache.maximumSize, equals(80));
      expect(imageCache.maximumSizeBytes, equals(45 << 20));

      // Mid Tier: 150 images, 90 MB
      service.setSimulatedTier(DeviceTier.mid, ramMb: 6000);
      expect(service.tier, equals(DeviceTier.mid));
      expect(imageCache.maximumSize, equals(150));
      expect(imageCache.maximumSizeBytes, equals(90 << 20));

      // High Tier: 300 images, 180 MB
      service.setSimulatedTier(DeviceTier.high, ramMb: 8192);
      expect(service.tier, equals(DeviceTier.high));
      expect(imageCache.maximumSize, equals(300));
      expect(imageCache.maximumSizeBytes, equals(180 << 20));
    });

    test('downscales memCacheWidth by 0.75x only on low-tier devices', () {
      service.setSimulatedTier(DeviceTier.low);
      // 360 * 0.75 = 270
      expect(service.downscaleMemCacheWidth(360), equals(270));
      // 480 * 0.75 = 360
      expect(service.downscaleMemCacheWidth(480), equals(360));

      service.setSimulatedTier(DeviceTier.mid);
      expect(service.downscaleMemCacheWidth(360), equals(360));

      service.setSimulatedTier(DeviceTier.high);
      expect(service.downscaleMemCacheWidth(360), equals(360));
    });

    test('didHaveMemoryPressure flushes image cache without crashing', () {
      service.didHaveMemoryPressure();
      final imageCache = PaintingBinding.instance.imageCache;
      expect(imageCache.currentSize, equals(0));
      expect(imageCache.currentSizeBytes, equals(0));
    });

    test('applies smart first-launch defaults on DeviceTier.low (blur=false, snow=0.4)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      service.setSimulatedTier(DeviceTier.low, ramMb: 3500);
      await service.resetToRecommendedDefaults();

      expect(service.isLiquidGlassBlurEnabled, isFalse);
      expect(service.snowDensityMultiplier, equals(0.4));
    });

    test('applies smart first-launch defaults on DeviceTier.high (blur=true, snow=1.0)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      service.setSimulatedTier(DeviceTier.high, ramMb: 8192);
      await service.resetToRecommendedDefaults();

      expect(service.isLiquidGlassBlurEnabled, isTrue);
      expect(service.snowDensityMultiplier, equals(1.0));
    });

    test('respects manual user override and does not overwrite existing preference', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Пользователь на low-end устройстве вручную включил размытие стекла
      service.setSimulatedTier(DeviceTier.low, ramMb: 3500);
      service.setLiquidGlassBlurEnabled(true, persist: true);
      await Future<void>.delayed(Duration.zero);

      expect(service.isLiquidGlassBlurEnabled, isTrue);

      // Проверяем сохранение в SharedPreferences
      expect(prefs.getBool('settings_liquid_glass'), isTrue);
    });
  });
}
