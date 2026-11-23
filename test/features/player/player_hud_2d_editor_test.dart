import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_cubit.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_state.dart';
import 'package:sync_pai/features/player/presentation/widgets/player_controls_overlay.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_state.dart';

class _FakePlayerCubit extends Fake implements PlayerCubit {
  bool? lastHudEditMode;

  @override
  void setHudEditMode(bool enabled) {
    lastHudEditMode = enabled;
  }
}

AnimeTitle _testTitle() => const AnimeTitle(
      id: 1,
      code: 'test',
      russianTitle: 'Тестовое аниме',
      englishTitle: 'Test Anime',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      description: '',
      genres: ['Экшен'],
      year: 2026,
      status: 'Онгоинг',
      episodes: [EpisodeItem(episode: 1)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    if (getIt.isRegistered<SettingsCubit>()) {
      await getIt.unregister<SettingsCubit>();
    }
  });

  tearDown(() async {
    if (getIt.isRegistered<SettingsCubit>()) {
      await getIt.unregister<SettingsCubit>();
    }
  });

  test('PlayerHudButtonConfig clamps bounds and SettingsCubit persists 2D layout',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = SettingsCubit(prefs);

    await cubit.updateHudButtonConfig(
      'skip_intro',
      nx: 1.5,
      ny: -0.2,
      scale: 2.0,
      visible: true,
    );
    final clamped = cubit.state.hudConfigFor('skip_intro');
    expect(clamped.nx, PlayerHudButtonConfig.maxNx);
    expect(clamped.ny, PlayerHudButtonConfig.minNy);
    expect(clamped.scale, PlayerHudButtonConfig.maxScale);

    await cubit.updateHudButtonConfig(
      'play_pause',
      nx: 0.78,
      ny: 0.64,
      scale: 1.2,
      visible: false,
    );
    await cubit.close();

    final reloaded = SettingsCubit(prefs);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final persistedSkip = reloaded.state.hudConfigFor('skip_intro');
    final persistedPlay = reloaded.state.hudConfigFor('play_pause');
    expect(persistedSkip.nx, PlayerHudButtonConfig.maxNx);
    expect(persistedPlay.nx, closeTo(0.78, 0.001));
    expect(persistedPlay.ny, closeTo(0.64, 0.001));
    expect(persistedPlay.scale, closeTo(1.2, 0.001));
    expect(persistedPlay.visible, isFalse);

    await reloaded.applyHud2DPreset(HudLayoutPresetType.rightThumb);
    expect(reloaded.state.hudConfigFor('play_pause').nx, closeTo(0.84, 0.001));
    expect(reloaded.state.hudConfigFor('play_pause').visible, isTrue);

    await reloaded.applyHud2DPreset(HudLayoutPresetType.classic);
    expect(reloaded.state.hudConfigFor('play_pause').nx, closeTo(0.50, 0.001));
    expect(reloaded.state.hudConfigFor('play_pause').ny, closeTo(0.50, 0.001));
    await reloaded.close();
  });

  testWidgets(
      'PlayerControlsOverlay supports 2D dragging, center snap, scaling, hide/restore and presets',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settingsCubit = SettingsCubit(prefs);
    getIt.registerSingleton<SettingsCubit>(settingsCubit);

    final fakePlayerCubit = _FakePlayerCubit();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: PlayerControlsOverlay(
              cubit: fakePlayerCubit,
              state: PlayerState(
                title: _testTitle(),
                episode: const EpisodeItem(episode: 1),
                isHudEditMode: true,
                areControlsVisible: true,
              ),
              onBack: () {},
              onToggleOrientation: () {},
              onMinimize: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('hud_edit_grid_overlay')), findsOneWidget);
    expect(find.byKey(const ValueKey('hud_edit_mode_banner')), findsOneWidget);
    expect(find.text('Режим настройки HUD'), findsOneWidget);
    expect(find.byKey(const ValueKey('hud_canvas_btn_skip_intro')), findsOneWidget);

    // Тап по кнопке skip_intro открывает инспектор выбранной кнопки
    await tester.tap(find.byKey(const ValueKey('hud_canvas_btn_skip_intro')));
    await tester.pump();
    expect(find.byKey(const ValueKey('hud_selected_quick_bar')), findsOneWidget);
    expect(find.text('Пропустить опенинг'), findsOneWidget);

    // Масштабирование через кнопку +
    final scaleBefore = settingsCubit.state.hudConfigFor('skip_intro').scale;
    await tester.tap(find.byKey(const ValueKey('hud_scale_up_btn')));
    await tester.pump();
    expect(
      settingsCubit.state.hudConfigFor('skip_intro').scale,
      greaterThan(scaleBefore),
    );

    // Свободное перетаскивание play_pause в край -> зажим в пределах SafeArea (maxNx/maxNy)
    await tester.drag(
      find.byKey(const ValueKey('hud_canvas_btn_play_pause')),
      const Offset(-500, -400),
    );
    await tester.pump();
    final draggedPlay = settingsCubit.state.hudConfigFor('play_pause');
    expect(draggedPlay.nx, PlayerHudButtonConfig.minNx);
    expect(draggedPlay.ny, PlayerHudButtonConfig.minNy);

    // Проверка магнитного прилипания к центру при перемещении в зону ±0.02 от 0.5
    await settingsCubit.updateHudButtonConfig('seek_back', nx: 0.465, ny: 0.50);
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('hud_canvas_btn_seek_back')),
      const Offset(40, 0),
    );
    await tester.pump();
    expect(settingsCubit.state.hudConfigFor('seek_back').nx, closeTo(0.50, 0.001));

    // Скрытие выбранной кнопки -> появляется строка «Скрытые кнопки» и восстановление в 1 тап
    await tester.tap(find.byKey(const ValueKey('hud_canvas_btn_speed')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hud_toggle_vis_btn')));
    await tester.pump();
    expect(settingsCubit.state.hudConfigFor('speed').visible, isFalse);
    expect(find.text('Скрытые кнопки:'), findsOneWidget);
    expect(find.byKey(const ValueKey('hud_restore_chip_speed')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hud_restore_chip_speed')));
    await tester.pump();
    expect(settingsCubit.state.hudConfigFor('speed').visible, isTrue);

    // Пресет «Под правую руку»
    await tester.tap(find.byKey(const ValueKey('wysiwyg_preset_right_thumb')));
    await tester.pump();
    expect(
      settingsCubit.state.hudConfigFor('play_pause').nx,
      closeTo(0.84, 0.001),
    );

    // Кнопка «Готово» выходит из режима редактирования
    await tester.tap(find.byKey(const ValueKey('wysiwyg_done_btn')));
    await tester.pump();
    expect(fakePlayerCubit.lastHudEditMode, isFalse);

    await settingsCubit.close();
  });
}

