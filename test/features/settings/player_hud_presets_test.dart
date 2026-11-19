import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/episode_quality_sheet.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/presentation/widgets/player_hud_editor_sheet.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SettingsCubit switches between 3 HUD presets and updates button visibility immediately',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = SettingsCubit(prefs);

    await cubit.setPlayerHudPreset(PlayerHudPreset.standard);
    expect(cubit.state.isHudButtonVisible('seek_10s'), isTrue);
    expect(cubit.state.isHudButtonVisible('speed'), isFalse);
    expect(cubit.state.isHudButtonVisible('pip'), isFalse);

    await cubit.setPlayerHudPreset(PlayerHudPreset.minimal);
    expect(cubit.state.isHudButtonVisible('seek_10s'), isFalse);
    expect(cubit.state.isHudButtonVisible('speed'), isFalse);

    await cubit.setPlayerHudPreset(PlayerHudPreset.advanced);
    expect(cubit.state.isHudButtonVisible('speed'), isTrue);
    expect(cubit.state.isHudButtonVisible('aspect_ratio'), isTrue);
    expect(cubit.state.isHudButtonVisible('screenshot'), isTrue);
    expect(cubit.state.isHudButtonVisible('pip'), isTrue);
    await cubit.close();
  });

  test('Manual toggle or reorder switches preset to custom and persists across restart',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = SettingsCubit(prefs);
    await cubit.setPlayerHudPreset(PlayerHudPreset.standard);

    await cubit.togglePlayerButton('speed', true);
    expect(cubit.state.playerHudPreset, PlayerHudPreset.custom);
    expect(cubit.state.isHudButtonVisible('speed'), isTrue);

    final firstBefore = cubit.state.playerButtonOrder.first;
    await cubit.reorderPlayerButtons(0, 3);
    expect(cubit.state.playerHudPreset, PlayerHudPreset.custom);
    expect(cubit.state.playerButtonOrder[2], firstBefore);
    await cubit.close();

    // Симулируем перезапуск приложения
    final reloaded = SettingsCubit(prefs);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(reloaded.state.playerHudPreset, PlayerHudPreset.custom);
    expect(reloaded.state.isHudButtonVisible('speed'), isTrue);
    expect(reloaded.state.playerButtonOrder[2], firstBefore);

    await reloaded.resetPlayerHudToDefault();
    expect(reloaded.state.playerHudPreset, PlayerHudPreset.standard);
    expect(reloaded.state.isHudButtonVisible('speed'), isFalse);
    await reloaded.close();
  });

  test('SettingsCubit prevents hiding both back and settings_gear simultaneously',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = SettingsCubit(prefs);

    await cubit.togglePlayerButton('back', false);
    expect(cubit.state.isHudButtonVisible('back'), isFalse);

    // Пытаемся скрыть settings_gear, когда back уже скрыт -> должно остаться true
    await cubit.togglePlayerButton('settings_gear', false);
    expect(cubit.state.isHudButtonVisible('settings_gear'), isTrue);
    await cubit.close();
  });

  testWidgets('EpisodeQualitySheet shows settings gear and PlayerHudEditorSheet updates live',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = SettingsCubit(prefs);

    const title = AnimeTitle(
      id: 1,
      code: 'test',
      russianTitle: 'Тест',
      englishTitle: 'Test',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: [],
      description: '',
      status: 'ongoing',
    );
    const ep = EpisodeItem(episode: 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodeQualitySheet(
            title: title,
            episode: ep,
            onQualitySelected: (_) {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('quality_sheet_hud_settings_btn')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerHudEditorSheet(cubit: cubit),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('hud_editor_preset_advanced')));
    await tester.pump();
    expect(cubit.state.playerHudPreset, PlayerHudPreset.advanced);
    expect(cubit.state.isHudButtonVisible('speed'), isTrue);

    // Проверка на узком экране (280px) в режиме Пользовательский -> 0 RenderFlex overflow
    await cubit.togglePlayerButton('speed', false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 500,
            child: PlayerHudEditorSheet(cubit: cubit),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Пользовательский'), findsOneWidget);

    await cubit.close();
  });
}

