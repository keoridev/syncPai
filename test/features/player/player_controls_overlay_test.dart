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

class _FakePlayerCubit extends Fake implements PlayerCubit {
  bool? lastHudEditMode;

  @override
  PlayerState get state => PlayerState(
        title: _testTitle(),
        episode: const EpisodeItem(
          episode: 1,
          opening: TimecodeRange(start: 85, stop: 175),
          ending: TimecodeRange(start: 1300, stop: 1390),
        ),
        duration: const Duration(minutes: 24),
        position: const Duration(seconds: 100),
      );

  @override
  Stream<PlayerState> get stream => const Stream.empty();

  @override
  void setHudEditMode(bool enabled) {
    lastHudEditMode = enabled;
  }

  @override
  void toggleScreenLock() {}

  @override
  void seek(Duration position) {}

  @override
  void playNextEpisode([EpisodeItem? nextEp]) {}
}

AnimeTitle _testTitle() => const AnimeTitle(
      id: 101,
      code: 'overlay_test',
      russianTitle: 'Тест Оверлея',
      englishTitle: 'Overlay Test',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: ['Экшен'],
      description: '',
      status: 'Онгоинг',
      episodes: [
        EpisodeItem(
          episode: 1,
          opening: TimecodeRange(start: 85, stop: 175),
          ending: TimecodeRange(start: 1300, stop: 1390),
        ),
        EpisodeItem(episode: 2),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('PlayerControlsOverlay — Portrait, Landscape & Lock Screen', () {
    testWidgets(
        'Portrait mode renders docked layout without duplicate Пропустить or 2D canvas',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final settingsCubit = SettingsCubit(prefs);
      getIt.registerSingleton<SettingsCubit>(settingsCubit);
      final fakeCubit = _FakePlayerCubit();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: SizedBox(
                width: 390,
                height: 844,
                child: PlayerControlsOverlay(
                  cubit: fakeCubit,
                  state: PlayerState(
                    title: _testTitle(),
                    episode: _testTitle().episodes.first,
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
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('player_portrait_docked_layout')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('hud_edit_grid_overlay')), findsNothing);
      expect(find.byKey(const ValueKey('hud_edit_skip_intro')), findsNothing);
      expect(find.byKey(const ValueKey('hud_action_settings_gear')), findsOneWidget);
      expect(find.byKey(const ValueKey('hud_center_seek_back')), findsOneWidget);
      expect(find.byKey(const ValueKey('hud_center_play_pause')), findsOneWidget);
      expect(find.byKey(const ValueKey('hud_center_seek_forward')), findsOneWidget);

      await settingsCubit.close();
    });

    testWidgets(
        'Landscape HUD edit mode docks editor bar at bottom and persists on Готово',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final settingsCubit = SettingsCubit(prefs);
      getIt.registerSingleton<SettingsCubit>(settingsCubit);
      final fakeCubit = _FakePlayerCubit();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(844, 390)),
            child: Scaffold(
              body: SizedBox(
                width: 844,
                height: 390,
                child: PlayerControlsOverlay(
                  cubit: fakeCubit,
                  state: PlayerState(
                    title: _testTitle(),
                    episode: _testTitle().episodes.first,
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
        ),
      );
      await tester.pump();

      final bannerFinder = find.byKey(const ValueKey('hud_edit_mode_banner'));
      final topLockFinder = find.byKey(const ValueKey('hud_canvas_btn_lock_screen'));
      expect(bannerFinder, findsOneWidget);
      expect(topLockFinder, findsOneWidget);

      // Editor banner is docked at bottom, well below top-row buttons
      final bannerRect = tester.getRect(bannerFinder);
      final topLockRect = tester.getRect(topLockFinder);
      expect(bannerRect.top, greaterThan(topLockRect.bottom));

      // Drag lock_screen left and tap Готово to commit
      final beforeNx = settingsCubit.state.hudConfigFor('lock_screen').nx;
      await tester.drag(topLockFinder, const Offset(-100, 0));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wysiwyg_done_btn')));
      await tester.pump();

      expect(fakeCubit.lastHudEditMode, isFalse);
      expect(
        settingsCubit.state.hudConfigFor('lock_screen').nx,
        lessThan(beforeNx),
      );

      await settingsCubit.close();
    });

    testWidgets(
        'Locked screen hides main HUD controls while keeping Пропустить and След. серия interactive',
        (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final settingsCubit = SettingsCubit(prefs);
      getIt.registerSingleton<SettingsCubit>(settingsCubit);

      final fakeCubit = _FakePlayerCubit();
      bool skipTapped = false;
      bool nextTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(844, 390)),
            child: Scaffold(
              body: SizedBox(
                width: 844,
                height: 390,
                child: Stack(
                  children: [
                    PlayerControlsOverlay(
                      cubit: fakeCubit,
                      state: PlayerState(
                        title: _testTitle(),
                        episode: _testTitle().episodes.first,
                        isScreenLocked: true,
                        areControlsVisible: true,
                      ),
                      onBack: () {},
                      onToggleOrientation: () {},
                      onMinimize: () {},
                    ),
                    Positioned(
                      right: 24,
                      bottom: 84,
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => skipTapped = true,
                            child: const Text('Пропустить'),
                          ),
                          TextButton(
                            onPressed: () => nextTapped = true,
                            child: const Text('След. серия'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('hud_center_play_pause')), findsNothing);
      expect(find.byKey(const ValueKey('hud_action_settings_gear')), findsNothing);
      expect(find.byKey(const ValueKey('hud_action_lock_screen')), findsNothing);

      await tester.tap(find.text('Пропустить'));
      await tester.tap(find.text('След. серия'));
      await tester.pump();
      expect(skipTapped, isTrue);
      expect(nextTapped, isTrue);

      await settingsCubit.close();
    });
  });
}
