import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/services/device_performance_service.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final SharedPreferences? _injectedPrefs;

  SettingsCubit([this._injectedPrefs]) : super(const SettingsState()) {
    _loadSettings();
  }

  static const String _keyGridColumns = 'grid_columns_count';
  static const String _keyIsListView = 'catalog_is_list_view';
  static const String _keyPlayerHudPreset = 'settings_player_hud_preset';
  static const String _keyAutoSkipOpenings = 'settings_auto_skip_openings';
  static const String _keyAutoPauseOnLeave = 'settings_auto_pause_on_leave';
  static const String _keyLiquidGlass = 'settings_liquid_glass';
  static const String _keyDefaultQuality = 'settings_default_quality';

  Future<SharedPreferences> _getPrefs() async {
    if (_injectedPrefs != null) return _injectedPrefs;
    if (getIt.isRegistered<SharedPreferences>()) {
      return getIt<SharedPreferences>();
    }
    return SharedPreferences.getInstance();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await _getPrefs();
      final cols = prefs.getInt(_keyGridColumns) ?? 3;
      final isList = prefs.getBool(_keyIsListView) ?? false;
      final presetStr = prefs.getString(_keyPlayerHudPreset);
      final preset = PlayerHudPreset.fromString(presetStr);
      final autoSkip = prefs.getBool(_keyAutoSkipOpenings) ?? true;
      final autoPause = prefs.getBool(_keyAutoPauseOnLeave) ?? true;
      final liquid = prefs.getBool(_keyLiquidGlass) ??
          DevicePerformanceService.instance.isLiquidGlassBlurEnabled;
      final quality = prefs.getString(_keyDefaultQuality) ?? '1080p FHD';

      emit(state.copyWith(
        gridColumnCount: cols,
        isListView: isList,
        playerHudPreset: preset,
        autoSkipOpenings: autoSkip,
        autoPauseOnLeave: autoPause,
        liquidGlassEffects: liquid,
        defaultQuality: quality,
      ));
    } catch (_) {}
  }

  Future<void> setGridColumnCount(int cols) async {
    final validCols = cols.clamp(2, 3);
    emit(state.copyWith(gridColumnCount: validCols));
    try {
      final prefs = await _getPrefs();
      await prefs.setInt(_keyGridColumns, validCols);
      await prefs.setInt('catalog_grid_density', validCols);
      await prefs.setInt('saved_anime_grid_columns', validCols);
    } catch (_) {}
  }

  Future<void> toggleGridColumnCount() async {
    final newCols = state.gridColumnCount == 2 ? 3 : 2;
    await setGridColumnCount(newCols);
  }

  Future<void> setIsListView(bool isList) async {
    emit(state.copyWith(isListView: isList));
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyIsListView, isList);
      await prefs.setString('catalog_view_mode', isList ? 'list' : 'grid');
      await prefs.setString('saved_anime_view_mode', isList ? 'list' : 'grid');
    } catch (_) {}
  }

  Future<void> toggleViewMode() async {
    await setIsListView(!state.isListView);
  }

  Future<void> setPlayerHudPreset(PlayerHudPreset preset) async {
    emit(state.copyWith(playerHudPreset: preset));
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyPlayerHudPreset, preset.name);
    } catch (_) {}
  }

  Future<void> setAutoSkipOpenings(bool val) async {
    emit(state.copyWith(autoSkipOpenings: val));
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyAutoSkipOpenings, val);
    } catch (_) {}
  }

  Future<void> setAutoPauseOnLeave(bool val) async {
    emit(state.copyWith(autoPauseOnLeave: val));
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyAutoPauseOnLeave, val);
    } catch (_) {}
  }

  Future<void> setLiquidGlassEffects(bool val) async {
    emit(state.copyWith(liquidGlassEffects: val));
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyLiquidGlass, val);
    } catch (_) {}
  }

  Future<void> setDefaultQuality(String quality) async {
    emit(state.copyWith(defaultQuality: quality));
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyDefaultQuality, quality);
    } catch (_) {}
  }
}
