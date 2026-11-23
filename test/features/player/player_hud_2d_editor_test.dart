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
  PlayerState get state => PlayerState(
        title: _testTitle(),
        episode: const EpisodeItem(episode: 1),
      );

  @override
  Stream<PlayerState> get stream => const Stream.empty();

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
      'lock_screen',
      nx: 0.78,
      ny: 0.64,
      scale: 1.2,
      visible: false,
    );
    // Центральные кнопки (play_pause, seek_back, seek_forward) зафиксированы по центру
    await cubit.updateHudButtonConfig(
      'play_pause',
      nx: 0.90,
      ny: 0.10,
      scale: 1.2,
    );
    expect(cubit.state.hudConfigFor('play_pause').nx, closeTo(0.50, 0.001));
    expect(cubit.state.hudConfigFor('play_pause').ny, closeTo(0.50, 0.001));

    await cubit.setSeekStepSeconds(15);
    await cubit.setGestureSwipeSensitivity(1.5);
    await cubit.close();

    final reloaded = SettingsCubit(prefs);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final persistedSkip = reloaded.state.hudConfigFor('skip_intro');
    final persistedLock = reloaded.state.hudConfigFor('lock_screen');
    expect(persistedSkip.nx, PlayerHudButtonConfig.maxNx);
    expect(persistedLock.nx, closeTo(0.78, 0.001));
    expect(persistedLock.ny, closeTo(0.64, 0.001));
    expect(persistedLock.scale, closeTo(1.2, 0.001));
    expect(persistedLock.visible, isFalse);
    expect(reloaded.state.seekStepSeconds, 15);
    expect(reloaded.state.gestureSwipeSensitivity, closeTo(1.5, 0.001));

    await reloaded.applyHud2DPreset(HudLayoutPresetType.rightThumb);
    expect(reloaded.state.hudConfigFor('play_pause').nx, closeTo(0.50, 0.001));
    expect(reloaded.state.hudConfigFor('play_pause').visible, isTrue);

    await reloaded.applyHud2DPreset(HudLayoutPresetType.classic);
    expect(reloaded.state.hudConfigFor('lock_screen').nx, closeTo(0.66, 0.001));
    expect(reloaded.state.hudConfigFor('lock_screen').ny, closeTo(0.08, 0.001));
    expect(reloaded.state.hudConfigFor('speed').nx, closeTo(0.73, 0.001));
    expect(reloaded.state.hudConfigFor('speed').ny, closeTo(0.08, 0.001));
    expect(reloaded.state.hudConfigFor('quality_dub').nx, closeTo(0.80, 0.001));
    expect(reloaded.state.hudConfigFor('quality_dub').ny, closeTo(0.08, 0.001));
    expect(reloaded.state.hudConfigFor('pip_mode').nx, closeTo(0.87, 0.001));
    expect(reloaded.state.hudConfigFor('pip_mode').ny, closeTo(0.08, 0.001));
    expect(reloaded.state.hudConfigFor('seek_back').nx, closeTo(0.35, 0.001));
    expect(reloaded.state.hudConfigFor('seek_back').ny, closeTo(0.50, 0.001));
    expect(reloaded.state.hudConfigFor('play_pause').nx, closeTo(0.50, 0.001));
    expect(reloaded.state.hudConfigFor('play_pause').ny, closeTo(0.50, 0.001));
    expect(reloaded.state.hudConfigFor('seek_forward').nx, closeTo(0.65, 0.001));
    expect(reloaded.state.hudConfigFor('seek_forward').ny, closeTo(0.50, 0.001));
    expect(reloaded.state.hudConfigFor('next_episode').nx, closeTo(0.13, 0.001));
    expect(reloaded.state.hudConfigFor('next_episode').ny, closeTo(0.82, 0.001));
    expect(reloaded.state.hudConfigFor('fullscreen').nx, closeTo(0.94, 0.001));
    expect(reloaded.state.hudConfigFor('fullscreen').ny, closeTo(0.82, 0.001));
    expect(reloaded.state.hudConfigFor('skip_intro').nx, closeTo(0.88, 0.001));
    expect(reloaded.state.hudConfigFor('skip_intro').ny, closeTo(0.72, 0.001));
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
    expect(find.byKey(const ValueKey('wysiwyg_reset_btn')), findsOneWidget);
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

    // Центральная кнопка play_pause заблокирована от перетаскивания (остаётся 0.50, 0.50)
    await tester.drag(
      find.byKey(const ValueKey('hud_canvas_btn_play_pause')),
      const Offset(-500, -400),
    );
    await tester.pump();
    final lockedPlay = settingsCubit.state.hudConfigFor('play_pause');
    expect(lockedPlay.nx, closeTo(0.50, 0.001));
    expect(lockedPlay.ny, closeTo(0.50, 0.001));

    // Свободное перетаскивание lock_screen в край -> зажим в пределах SafeArea (minNx/minNy)
    await tester.drag(
      find.byKey(const ValueKey('hud_canvas_btn_lock_screen')),
      const Offset(-600, -400),
    );
    await tester.pump();
    final draggedLock = settingsCubit.state.hudConfigFor('lock_screen');
    expect(draggedLock.nx, PlayerHudButtonConfig.minNx);
    expect(draggedLock.ny, PlayerHudButtonConfig.minNy);

    // Проверка магнитного прилипания к центру при перемещении в зону ±0.02 от 0.5
    await settingsCubit.updateHudButtonConfig('lock_screen', nx: 0.465, ny: 0.22);
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('hud_canvas_btn_lock_screen')),
      const Offset(40, 0),
    );
    await tester.pump();
    expect(settingsCubit.state.hudConfigFor('lock_screen').nx, closeTo(0.50, 0.001));

    // Магнитное выравнивание по оси Y соседней кнопки (верхний ряд ny = 0.08)
    await settingsCubit.updateHudButtonConfig('skip_intro', nx: 0.88, ny: 0.14);
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('hud_canvas_btn_skip_intro')),
      const Offset(0, -44),
    );
    await tester.pump();
    expect(
      settingsCubit.state.hudConfigFor('skip_intro').ny,
      closeTo(0.08, 0.001),
    );

    // Скрытие выбранной кнопки -> появляется строка «Скрытые кнопки» и восстановление в 1 тап
    await tester.tap(find.byKey(const ValueKey('hud_canvas_btn_seek_forward')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('hud_toggle_vis_btn')));
    await tester.pump();
    expect(settingsCubit.state.hudConfigFor('seek_forward').visible, isFalse);
    expect(find.text('Скрытые кнопки:'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hud_restore_chip_seek_forward')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('hud_restore_chip_seek_forward')));
    await tester.pump();
    expect(settingsCubit.state.hudConfigFor('seek_forward').visible, isTrue);

    // Пресет «Под правую руку» (центрированная play_pause остаётся 0.50, skip_intro перемещается на 0.78)
    await tester.tap(find.byKey(const ValueKey('wysiwyg_preset_right_thumb')));
    await tester.pump();
    expect(
      settingsCubit.state.hudConfigFor('skip_intro').nx,
      closeTo(0.78, 0.001),
    );

    // Кнопка «Готово» выходит из режима редактирования
    await tester.tap(find.byKey(const ValueKey('wysiwyg_done_btn')));
    await tester.pump();
    expect(fakePlayerCubit.lastHudEditMode, isFalse);

    await settingsCubit.close();
  });

  testWidgets(
      'PlayerControlsOverlay uses docked portrait layout in portrait orientation',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final settingsCubit = SettingsCubit(prefs);
    getIt.registerSingleton<SettingsCubit>(settingsCubit);

    final fakePlayerCubit = _FakePlayerCubit();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Scaffold(
            body: SizedBox(
              width: 390,
              height: 844,
              child: PlayerControlsOverlay(
                cubit: fakePlayerCubit,
                state: PlayerState(
                  title: _testTitle(),
                  episode: const EpisodeItem(episode: 1),
                  isHudEditMode: false,
                  areControlsVisible: true,
                ),
                onBack: () {},
                onToggleOrientation: () {},
                onMinimize: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('player_portrait_docked_layout')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('hud_bottom_fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('hud_center_play_pause')), findsOneWidget);

    await settingsCubit.close();
  });
}

