import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/di/injection.dart';

/// Сервис управления новогодней темой SyncPai «Зимняя сказка 2026».
/// Отвечает за:
/// 1. Включение/выключение сезонной зимней темы
/// 2. Независимое управление анимацией снегопада (Live Snowfall)
/// 3. Независимое переключение маскота Пай-тян в новогодний скин (Santa Hat & Winter details)
/// 4. Проверку периода сезонной доступности (1 дек 2026 – 15 янв 2027)
/// 5. Сохранение настроек в SharedPreferences
class WinterThemeService extends ChangeNotifier {
  static final WinterThemeService instance = WinterThemeService._();

  WinterThemeService._() {
    Future.microtask(_loadFromPreferences);
  }

  @override
  void notifyListeners() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks ||
        binding.schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
      binding.addPostFrameCallback((_) {
        if (hasListeners) {
          super.notifyListeners();
        }
      });
      return;
    }
    super.notifyListeners();
  }

  static const String _prefWinterThemeKey = 'syncpai_winter_theme_enabled';
  static const String _prefSnowfallKey = 'syncpai_snowfall_enabled';
  static const String _prefWinterMascotKey = 'syncpai_winter_mascot_enabled';
  static const String _prefManualOverrideKey = 'syncpai_winter_manual_override';

  bool _isWinterThemeEnabled = true;
  bool _isSnowfallEnabled = true;
  bool _isWinterMascotEnabled = true;
  bool _isManualOverride = true; // По умолчанию включено в рамках релиза Winter Update 2026

  bool get isWinterThemeEnabled => _isWinterThemeEnabled;
  bool get isSnowfallEnabled => _isSnowfallEnabled;
  bool get isWinterMascotEnabled => _isWinterMascotEnabled;
  bool get isManualOverride => _isManualOverride;

  /// Активна ли зимняя тема прямо сейчас (с учетом сезонного окна или ручного переключателя)
  bool get isWinterActive {
    if (_isManualOverride) return _isWinterThemeEnabled;
    return _isWinterThemeEnabled && isWithinSeasonalWindow();
  }

  /// Проверка даты: сезонная активность с 1 декабря 2026 по 15 января 2027
  static bool isWithinSeasonalWindow() {
    final now = DateTime.now();
    final start = DateTime(2026, 12, 1);
    final end = DateTime(2027, 1, 15, 23, 59, 59);
    // Для удобства разработки и тестирования обновления в ноябре 2026
    if (now.year == 2026 && now.month >= 11) return true;
    return now.isAfter(start) && now.isBefore(end);
  }

  Future<void> _loadFromPreferences() async {
    try {
      SharedPreferences? prefs;
      if (getIt.isRegistered<SharedPreferences>()) {
        prefs = getIt<SharedPreferences>();
      } else {
        prefs = await SharedPreferences.getInstance();
      }

      // По умолчанию для Winter Update 2026 включаем зимнюю сказку
      _isWinterThemeEnabled = prefs.getBool(_prefWinterThemeKey) ?? true;
      _isSnowfallEnabled = prefs.getBool(_prefSnowfallKey) ?? true;
      _isWinterMascotEnabled = prefs.getBool(_prefWinterMascotKey) ?? true;
      _isManualOverride = prefs.getBool(_prefManualOverrideKey) ?? true;
      notifyListeners();

      // Проверяем удаленный флаг app_config (если настроен в Supabase)
      try {
        final client = Supabase.instance.client;
        final res = await client
            .from('app_config')
            .select('value')
            .eq('key', 'winter_2026')
            .maybeSingle();
        if (res != null && res['value'] is Map) {
          final config = (res['value'] as Map).cast<String, dynamic>();
          if (config.containsKey('enabled') && prefs.getBool(_prefWinterThemeKey) == null) {
            _isWinterThemeEnabled = config['enabled'] == true;
            notifyListeners();
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> setWinterTheme(bool value) async {
    _isWinterThemeEnabled = value;
    notifyListeners();
    await _saveBool(_prefWinterThemeKey, value);
  }

  Future<void> setSnowfall(bool value) async {
    _isSnowfallEnabled = value;
    notifyListeners();
    await _saveBool(_prefSnowfallKey, value);
  }

  Future<void> setWinterMascot(bool value) async {
    _isWinterMascotEnabled = value;
    notifyListeners();
    await _saveBool(_prefWinterMascotKey, value);
  }

  Future<void> setManualOverride(bool value) async {
    _isManualOverride = value;
    notifyListeners();
    await _saveBool(_prefManualOverrideKey, value);
  }

  /// Сброс к дефолтной классической теме
  Future<void> resetToDefault() async {
    _isWinterThemeEnabled = false;
    _isSnowfallEnabled = false;
    _isWinterMascotEnabled = false;
    notifyListeners();
    await _saveBool(_prefWinterThemeKey, false);
    await _saveBool(_prefSnowfallKey, false);
    await _saveBool(_prefWinterMascotKey, false);
  }

  /// Включение полного зимнего набора (тема + снег + маскот)
  Future<void> enableFullWinterExperience() async {
    _isWinterThemeEnabled = true;
    _isSnowfallEnabled = true;
    _isWinterMascotEnabled = true;
    notifyListeners();
    await _saveBool(_prefWinterThemeKey, true);
    await _saveBool(_prefSnowfallKey, true);
    await _saveBool(_prefWinterMascotKey, true);
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      SharedPreferences? prefs;
      if (getIt.isRegistered<SharedPreferences>()) {
        prefs = getIt<SharedPreferences>();
      } else {
        prefs = await SharedPreferences.getInstance();
      }
      await prefs.setBool(key, value);
    } catch (_) {}
  }
}
