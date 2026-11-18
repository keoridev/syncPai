import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsCubit Tests', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'grid_columns_count': 3,
        'catalog_is_list_view': false,
        'settings_player_hud_preset': 'standard',
      });
      prefs = await SharedPreferences.getInstance();
    });

    test('initializes with values from SharedPreferences', () async {
      final cubit = SettingsCubit(prefs);
      // Give async _loadSettings time to finish
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.gridColumnCount, 3);
      expect(cubit.state.isListView, false);
      expect(cubit.state.playerHudPreset, PlayerHudPreset.standard);
      await cubit.close();
    });

    test('toggleGridColumnCount switches between 2 and 3 and persists', () async {
      final cubit = SettingsCubit(prefs);
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.toggleGridColumnCount();
      expect(cubit.state.gridColumnCount, 2);
      expect(prefs.getInt('grid_columns_count'), 2);
      expect(prefs.getInt('catalog_grid_density'), 2);

      await cubit.toggleGridColumnCount();
      expect(cubit.state.gridColumnCount, 3);
      expect(prefs.getInt('grid_columns_count'), 3);
      await cubit.close();
    });

    test('toggleViewMode toggles between list and grid and persists', () async {
      final cubit = SettingsCubit(prefs);
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.toggleViewMode();
      expect(cubit.state.isListView, true);
      expect(prefs.getBool('catalog_is_list_view'), true);
      expect(prefs.getString('catalog_view_mode'), 'list');

      await cubit.toggleViewMode();
      expect(cubit.state.isListView, false);
      expect(prefs.getBool('catalog_is_list_view'), false);
      expect(prefs.getString('catalog_view_mode'), 'grid');
      await cubit.close();
    });

    test('setPlayerHudPreset updates state and persists', () async {
      final cubit = SettingsCubit(prefs);
      await Future.delayed(const Duration(milliseconds: 50));

      await cubit.setPlayerHudPreset(PlayerHudPreset.minimal);
      expect(cubit.state.playerHudPreset, PlayerHudPreset.minimal);
      expect(prefs.getString('settings_player_hud_preset'), 'minimal');

      await cubit.setPlayerHudPreset(PlayerHudPreset.advanced);
      expect(cubit.state.playerHudPreset, PlayerHudPreset.advanced);
      expect(prefs.getString('settings_player_hud_preset'), 'advanced');
      await cubit.close();
    });
  });
}
