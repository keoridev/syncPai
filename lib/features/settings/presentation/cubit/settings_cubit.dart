import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/services/device_performance_service.dart';
import '../../../../core/services/mascot_companion_service.dart';
import 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  final SharedPreferences? _injectedPrefs;

  SettingsCubit([this._injectedPrefs]) : super(const SettingsState()) {
    if (_injectedPrefs != null) {
      _applyLoadedPrefs(_injectedPrefs);
    } else {
      _loadSettings();
    }
  }

  static const String _keyGridColumns = 'grid_columns_count';
  static const String _keyIsListView = 'catalog_is_list_view';
  static const String _keyPlayerHudPreset = 'settings_player_hud_preset';
  static const String _keyPlayerButtonVisibility =
      'settings_player_button_visibility';
  static const String _keyPlayerButtonOrder = 'settings_player_button_order';
  static const String _keyPlayerHudLayoutV2 = 'settings_player_hud_layout_v2';
  static const String _keyAutoSkipOpenings = 'settings_auto_skip_openings';
  static const String _keyAutoPauseOnLeave = 'settings_auto_pause_on_leave';
  static const String _keyLiquidGlass = 'settings_liquid_glass';
  static const String _keyDefaultQuality = 'settings_default_quality';
  static const String _keyHasSeenPlayerOnboarding =
      'settings_has_seen_player_onboarding';
  static const String _keyPaiReactions = 'pai_companion_reactions_enabled';

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
      _applyLoadedPrefs(prefs);
    } catch (_) {}
  }

  void _applyLoadedPrefs(SharedPreferences prefs) {
    try {
      final cols = prefs.getInt(_keyGridColumns) ?? 3;
      final isList = prefs.getBool(_keyIsListView) ?? false;
      final presetStr = prefs.getString(_keyPlayerHudPreset);
      final preset = PlayerHudPreset.fromString(presetStr);
      final autoSkip = prefs.getBool(_keyAutoSkipOpenings) ?? true;
      final autoPause = prefs.getBool(_keyAutoPauseOnLeave) ?? true;
      final liquid = prefs.getBool(_keyLiquidGlass) ??
          DevicePerformanceService.instance.isLiquidGlassBlurEnabled;
      final quality = prefs.getString(_keyDefaultQuality) ?? '1080p FHD';
      final hasSeenOnboarding =
          prefs.getBool(_keyHasSeenPlayerOnboarding) ?? false;
      final paiReactions = prefs.getBool(_keyPaiReactions) ?? true;
      MascotCompanionService.instance.setEnabled(paiReactions);

      Map<String, bool> visibility = PlayerHudPresets.visibilityFor(preset);
      final rawVis = prefs.getString(_keyPlayerButtonVisibility);
      if (rawVis != null && rawVis.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawVis) as Map<String, dynamic>;
          visibility = {
            ...visibility,
            for (final e in decoded.entries) e.key: e.value == true,
          };
        } catch (_) {}
      }

      List<String> order = PlayerHudPresets.defaultOrder();
      final savedOrder = prefs.getStringList(_keyPlayerButtonOrder);
      if (savedOrder != null && savedOrder.isNotEmpty) {
        final missing = order.where((id) => !savedOrder.contains(id));
        order = [...savedOrder, ...missing];
      }

      Map<String, PlayerHudButtonConfig> hudLayout =
          Map<String, PlayerHudButtonConfig>.from(
        PlayerHud2DPresets.classicLayout(),
      );
      final rawLayout = prefs.getString(_keyPlayerHudLayoutV2);
      if (rawLayout != null && rawLayout.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawLayout) as Map<String, dynamic>;
          for (final entry in decoded.entries) {
            if (entry.value is Map<String, dynamic>) {
              hudLayout[entry.key] = PlayerHudButtonConfig.fromJson(
                entry.value as Map<String, dynamic>,
                fallbackId: entry.key,
              );
            }
          }
        } catch (_) {}
      }

      emit(state.copyWith(
        gridColumnCount: cols,
        isListView: isList,
        playerHudPreset: preset,
        playerButtonVisibility: visibility,
        playerButtonOrder: order,
        hudLayout: hudLayout,
        autoSkipOpenings: autoSkip,
        autoPauseOnLeave: autoPause,
        liquidGlassEffects: liquid,
        defaultQuality: quality,
        hasSeenPlayerOnboarding: hasSeenOnboarding,
        paiCompanionReactionsEnabled: paiReactions,
      ));
    } catch (_) {}
  }

  Future<void> setPaiCompanionReactionsEnabled(bool enabled) async {
    emit(state.copyWith(paiCompanionReactionsEnabled: enabled));
    MascotCompanionService.instance.setEnabled(enabled);
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyPaiReactions, enabled);
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
    final visibility = preset == PlayerHudPreset.custom
        ? state.playerButtonVisibility
        : PlayerHudPresets.visibilityFor(preset);
    final updatedLayout = _syncHudLayoutFromPreset(preset);
    emit(state.copyWith(
      playerHudPreset: preset,
      playerButtonVisibility: visibility,
      hudLayout: updatedLayout,
    ));
    await _persistPlayerHud(preset, visibility, state.playerButtonOrder);
    await persistHudLayout();
  }

  Map<String, PlayerHudButtonConfig> _syncHudLayoutFromPreset(
    PlayerHudPreset preset,
  ) {
    if (preset == PlayerHudPreset.custom) return state.hudLayout;
    final base = PlayerHud2DPresets.classicLayout();
    if (preset == PlayerHudPreset.minimal) {
      return {
        for (final e in base.entries)
          e.key: e.value.copyWith(
            visible: e.key == 'play_pause' ||
                e.key == 'skip_intro' ||
                e.key == 'quality_dub' ||
                e.key == 'lock_screen' ||
                e.key == 'fullscreen',
          ),
      };
    }
    return {
      for (final e in base.entries) e.key: e.value.copyWith(visible: true),
    };
  }

  Future<void> togglePlayerButton(String id, bool visible) async {
    // Защита от полной блокировки: нельзя скрыть одновременно 'back' и 'settings_gear'
    if (!visible && (id == 'back' || id == 'settings_gear')) {
      final otherId = id == 'back' ? 'settings_gear' : 'back';
      if (!state.isHudButtonVisible(otherId)) {
        return;
      }
    }
    final updated = Map<String, bool>.from(state.playerButtonVisibility)
      ..[id] = visible;
    final updatedLayout = Map<String, PlayerHudButtonConfig>.from(state.hudLayout);
    for (final mappedId in _mapped2DIdsForLegacyId(id)) {
      final prev = updatedLayout[mappedId] ?? state.hudConfigFor(mappedId);
      updatedLayout[mappedId] = prev.copyWith(visible: visible);
    }
    emit(state.copyWith(
      playerHudPreset: PlayerHudPreset.custom,
      playerButtonVisibility: updated,
      hudLayout: updatedLayout,
    ));
    await _persistPlayerHud(
      PlayerHudPreset.custom,
      updated,
      state.playerButtonOrder,
    );
    await persistHudLayout();
  }

  List<String> _mapped2DIdsForLegacyId(String id) {
    switch (id) {
      case 'seek_10s':
        return const ['seek_back', 'seek_forward'];
      case 'skip_op_ed':
        return const ['skip_intro'];
      case 'quality':
        return const ['quality_dub'];
      case 'pip':
        return const ['pip_mode'];
      default:
        return state.hudLayout.containsKey(id) ? [id] : const [];
    }
  }

  /// Обновление 2D-координат, масштаба или видимости конкретной кнопки HUD.
  Future<void> updateHudButtonConfig(
    String id, {
    double? nx,
    double? ny,
    double? scale,
    bool? visible,
    bool persist = true,
  }) async {
    final prev = state.hudConfigFor(id);
    final next = prev.copyWith(
      nx: nx,
      ny: ny,
      scale: scale,
      visible: visible,
    );
    if (next == prev) return;
    final updatedLayout = Map<String, PlayerHudButtonConfig>.from(state.hudLayout)
      ..[id] = next;
    emit(state.copyWith(
      playerHudPreset: PlayerHudPreset.custom,
      hudLayout: updatedLayout,
    ));
    if (persist) {
      await persistHudLayout();
    }
  }

  /// Применение встроенной 2D-раскладки («Классика» / «Под правую руку»).
  Future<void> applyHud2DPreset(HudLayoutPresetType preset) async {
    final layout = Map<String, PlayerHudButtonConfig>.from(
      PlayerHud2DPresets.forPreset(preset),
    );
    emit(state.copyWith(
      playerHudPreset: preset == HudLayoutPresetType.classic
          ? PlayerHudPreset.standard
          : PlayerHudPreset.custom,
      hudLayout: layout,
    ));
    await persistHudLayout();
  }

  Future<void> persistHudLayout() async {
    try {
      final prefs = await _getPrefs();
      final encoded = jsonEncode({
        for (final e in state.hudLayout.entries) e.key: e.value.toJson(),
      });
      await prefs.setString(_keyPlayerHudLayoutV2, encoded);
      await prefs.setString(_keyPlayerHudPreset, state.playerHudPreset.name);
    } catch (_) {}
  }

  Future<void> reorderPlayerButtons(
    int oldIndex,
    int newIndex, {
    bool adjustNewIndex = true,
  }) async {
    final list = List<String>.from(state.playerButtonOrder);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (adjustNewIndex && newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);

    emit(state.copyWith(
      playerHudPreset: PlayerHudPreset.custom,
      playerButtonOrder: list,
    ));
    await _persistPlayerHud(
      PlayerHudPreset.custom,
      state.playerButtonVisibility,
      list,
    );
  }

  Future<void> resetPlayerHudToDefault() async {
    final defaultOrder = PlayerHudPresets.defaultOrder();
    final defaultVis = PlayerHudPresets.visibilityFor(PlayerHudPreset.standard);
    final defaultLayout = Map<String, PlayerHudButtonConfig>.from(
      PlayerHud2DPresets.classicLayout(),
    );
    emit(state.copyWith(
      playerHudPreset: PlayerHudPreset.standard,
      playerButtonVisibility: defaultVis,
      playerButtonOrder: defaultOrder,
      hudLayout: defaultLayout,
    ));
    await _persistPlayerHud(PlayerHudPreset.standard, defaultVis, defaultOrder);
    await persistHudLayout();
  }

  Future<void> _persistPlayerHud(
    PlayerHudPreset preset,
    Map<String, bool> visibility,
    List<String> order,
  ) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyPlayerHudPreset, preset.name);
      await prefs.setString(_keyPlayerButtonVisibility, jsonEncode(visibility));
      await prefs.setStringList(_keyPlayerButtonOrder, order);
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

  Future<void> completePlayerOnboarding() async {
    emit(state.copyWith(hasSeenPlayerOnboarding: true));
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyHasSeenPlayerOnboarding, true);
    } catch (_) {}
  }

  Future<void> resetPlayerOnboarding() async {
    emit(state.copyWith(hasSeenPlayerOnboarding: false));
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyHasSeenPlayerOnboarding, false);
    } catch (_) {}
  }
}
