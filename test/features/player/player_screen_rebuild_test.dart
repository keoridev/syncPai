import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_cubit.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_state.dart';
import 'package:sync_pai/features/player/presentation/screens/player_screen.dart';
import 'package:sync_pai/features/player/presentation/widgets/player_progress_bar.dart';
import 'package:sync_pai/features/player/services/global_mini_player_service.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';

class _RebuildFakeStream extends Fake implements mk.PlayerStream {
  final playingCtrl = StreamController<bool>.broadcast();
  final bufferingCtrl = StreamController<bool>.broadcast();
  final positionCtrl = StreamController<Duration>.broadcast();
  final durationCtrl = StreamController<Duration>.broadcast();
  final bufferCtrl = StreamController<Duration>.broadcast();
  final rateCtrl = StreamController<double>.broadcast();
  final completedCtrl = StreamController<bool>.broadcast();
  final errorCtrl = StreamController<String>.broadcast();
  final widthCtrl = StreamController<int?>.broadcast();
  final heightCtrl = StreamController<int?>.broadcast();
  final subtitleCtrl = StreamController<List<String>>.broadcast();

  @override
  Stream<bool> get playing => playingCtrl.stream;
  @override
  Stream<bool> get buffering => bufferingCtrl.stream;
  @override
  Stream<Duration> get position => positionCtrl.stream;
  @override
  Stream<Duration> get duration => durationCtrl.stream;
  @override
  Stream<Duration> get buffer => bufferCtrl.stream;
  @override
  Stream<double> get rate => rateCtrl.stream;
  @override
  Stream<bool> get completed => completedCtrl.stream;
  @override
  Stream<String> get error => errorCtrl.stream;
  @override
  Stream<int?> get width => widthCtrl.stream;
  @override
  Stream<int?> get height => heightCtrl.stream;
  @override
  Stream<List<String>> get subtitle => subtitleCtrl.stream;

  Future<void> dispose() async {
    await playingCtrl.close();
    await bufferingCtrl.close();
    await positionCtrl.close();
    await durationCtrl.close();
    await bufferCtrl.close();
    await rateCtrl.close();
    await completedCtrl.close();
    await errorCtrl.close();
    await widthCtrl.close();
    await heightCtrl.close();
    await subtitleCtrl.close();
  }
}

class _RebuildFakePlayer extends Fake implements mk.Player {
  final _stream = _RebuildFakeStream();

  @override
  mk.PlayerStream get stream => _stream;
  @override
  mk.PlayerState get state => const mk.PlayerState();
  @override
  mk.PlatformPlayer? get platform => null;
  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async => _stream.dispose();
}

class _FakeVideoController extends Fake implements VideoController {
  _FakeVideoController(this.player);

  @override
  final mk.Player player;

  @override
  final ValueNotifier<int?> id = ValueNotifier<int?>(null);

  @override
  final ValueNotifier<Rect?> rect = ValueNotifier<Rect?>(null);

  @override
  final ValueNotifier<PlatformVideoController?> notifier =
      ValueNotifier<PlatformVideoController?>(null);

  @override
  Future<void> get waitUntilFirstFrameRendered => Future<void>.value();
}

AnimeTitle _rebuildTitle() => const AnimeTitle(
      id: 909,
      code: 'rebuild_test',
      russianTitle: 'Тест Перерисовок',
      englishTitle: 'Rebuild Test',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: ['Драма'],
      description: '',
      status: 'Онгоинг',
      episodes: [
        EpisodeItem(
          episode: 1,
          fhdUrl: 'https://anilibria.top/ep1.m3u8',
          opening: TimecodeRange(start: 85, stop: 175),
          ending: TimecodeRange(start: 1300, stop: 1390),
        ),
        EpisodeItem(
          episode: 2,
          fhdUrl: 'https://anilibria.top/ep2.m3u8',
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);
    getIt.registerSingleton<SettingsCubit>(SettingsCubit(prefs));
    GlobalMiniPlayerService.instance.close();
    MascotCompanionService.instance.resetForTest();
  });

  tearDown(() async {
    GlobalMiniPlayerService.instance.close();
    await getIt.reset();
  });

  group('PlayerScreen — Rebuild isolation & mini-player handoff', () {
    testWidgets(
        'Top-level shell does not rebuild on 10 consecutive 1s position ticks',
        (tester) async {
      final fakePlayer = _RebuildFakePlayer();
      final title = _rebuildTitle();
      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes.first,
        existingPlayer: fakePlayer,
        userIdOverride: 'u_rebuild',
      );
      addTearDown(cubit.close);

      int shellBuilds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<PlayerCubit>.value(
            value: cubit,
            child: BlocBuilder<PlayerCubit, PlayerState>(
              buildWhen: (previous, current) =>
                  previous.isPlaying != current.isPlaying ||
                  previous.isBuffering != current.isBuffering ||
                  previous.areControlsVisible != current.areControlsVisible ||
                  previous.selectedQuality != current.selectedQuality ||
                  previous.episode.episode != current.episode.episode ||
                  previous.isScreenLocked != current.isScreenLocked ||
                  previous.isHudEditMode != current.isHudEditMode ||
                  previous.errorMessage != current.errorMessage,
              builder: (context, state) {
                shellBuilds++;
                return Scaffold(
                  body: Column(
                    children: [
                      Text(state.title.displayTitle),
                      BlocSelector<PlayerCubit, PlayerState, int>(
                        selector: (s) => s.position.inSeconds,
                        builder: (context, sec) => Text('sec:$sec'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      final baselineBuilds = shellBuilds;

      for (int sec = 1; sec <= 10; sec++) {
        fakePlayer._stream.positionCtrl.add(Duration(seconds: sec));
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(shellBuilds, baselineBuilds);
      expect(find.text('sec:10'), findsOneWidget);
    });

    testWidgets(
        'Minimizing PlayerScreen to GlobalMiniPlayerService preserves MascotCompanionService.isPlayerActive',
        (tester) async {
      final fakePlayer = _RebuildFakePlayer();
      final title = _rebuildTitle();
      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes.first,
        existingPlayer: fakePlayer,
        userIdOverride: 'u_mini',
      );
      final fakeVc = _FakeVideoController(fakePlayer);

      // Pre-seed session so PlayerScreen claims it instead of spawning native VideoController
      GlobalMiniPlayerService.instance.minimize(
        cubit: cubit,
        videoController: fakeVc,
        onSaveProgress: () {},
      );

      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            title: title,
            initialEpisode: title.episodes.first,
          ),
        ),
      );
      await tester.pump();
      expect(MascotCompanionService.instance.isPlayerActive, isTrue);

      // Minimizing to GlobalMiniPlayerService preserves MascotCompanionService.isPlayerActive
      GlobalMiniPlayerService.instance.minimize(
        cubit: cubit,
        videoController: fakeVc,
        onSaveProgress: () {},
      );
      await tester.pump();

      expect(GlobalMiniPlayerService.instance.isMinimized, isTrue);
      expect(MascotCompanionService.instance.isPlayerActive, isTrue);

      GlobalMiniPlayerService.instance.close();
      await cubit.close();
      await tester.pump(const Duration(seconds: 3));
    });

    test(
        'PlayerScreen configures VideoController with androidAttachSurfaceAfterVideoParameters: false',
        () {
      expect(
        PlayerScreen.defaultVideoControllerConfig.enableHardwareAcceleration,
        isTrue,
      );
      expect(
        PlayerScreen
            .defaultVideoControllerConfig.androidAttachSurfaceAfterVideoParameters,
        isFalse,
      );
    });

    testWidgets(
        'Portrait mode renders 16:9 top video box + #0B0E14 companion episode list, and preserves Video GlobalKey across orientation switches',
        (tester) async {
      final fakePlayer = _RebuildFakePlayer();
      final title = _rebuildTitle();
      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes.first,
        existingPlayer: fakePlayer,
        userIdOverride: 'u_orient',
      );
      final fakeVc = _FakeVideoController(fakePlayer);

      GlobalMiniPlayerService.instance.minimize(
        cubit: cubit,
        videoController: fakeVc,
        onSaveProgress: () {},
      );

      // 1. Open in Portrait (390x844)
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            title: title,
            initialEpisode: title.episodes.first,
          ),
        ),
      );
      await tester.pump();

      final boxFinder = find.byKey(const ValueKey('player_portrait_16_9_box'));
      final overlayFinder =
          find.byKey(const ValueKey('player_portrait_docked_layout'));
      final companionFinder =
          find.byKey(const ValueKey('player_portrait_companion_panel'));
      final videoFinder = find.byType(Video);

      expect(boxFinder, findsOneWidget);
      expect(overlayFinder, findsOneWidget);
      expect(companionFinder, findsOneWidget);
      expect(find.text('Список серий'), findsOneWidget);
      expect(find.text('Серия 1'), findsWidgets);
      expect(find.text('Серия 2'), findsOneWidget);
      expect(videoFinder, findsOneWidget);

      final boxRect = tester.getRect(boxFinder);
      final overlayRect = tester.getRect(overlayFinder);
      final companionRect = tester.getRect(companionFinder);
      expect(boxRect.width / boxRect.height, closeTo(16 / 9, 0.02));
      expect(overlayRect.top, greaterThanOrEqualTo(boxRect.top - 0.5));
      expect(overlayRect.bottom, lessThanOrEqualTo(boxRect.bottom + 0.5));
      expect(companionRect.top, closeTo(boxRect.bottom, 1.0));

      final portraitVideoWidget = tester.widget<Video>(videoFinder);
      final portraitVideoKey = portraitVideoWidget.key;
      final portraitVideoState = tester.state(videoFinder);
      expect(portraitVideoKey, isA<GlobalKey>());

      // Tap episode 2 in portrait companion list -> switches active episode
      await tester.tap(find.byKey(const ValueKey('portrait_ep_item_2')));
      await tester.pump();
      expect(cubit.state.episode.episode, 2);

      // Toggle companion episodes view to Grid mode and back to List mode
      await tester.tap(
        find.byKey(const ValueKey('player_portrait_episodes_mode_toggle')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_portrait_episodes_grid')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('player_portrait_episodes_mode_toggle')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('player_portrait_episodes_list')),
        findsOneWidget,
      );

      // 2. Rotate to Landscape (844x390) -> fullscreen immersive, same Video State & GlobalKey
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();

      expect(find.byKey(const ValueKey('player_portrait_16_9_box')), findsNothing);
      expect(
        find.byKey(const ValueKey('player_portrait_companion_panel')),
        findsNothing,
      );
      expect(videoFinder, findsOneWidget);
      expect(tester.widget<Video>(videoFinder).key, same(portraitVideoKey));
      expect(tester.state(videoFinder), same(portraitVideoState));

      // 3. Rotate back to Portrait (390x844) -> 16:9 + companion restored, same Video State & GlobalKey
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();

      expect(find.byKey(const ValueKey('player_portrait_16_9_box')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_portrait_companion_panel')),
        findsOneWidget,
      );
      expect(tester.widget<Video>(videoFinder).key, same(portraitVideoKey));
      expect(tester.state(videoFinder), same(portraitVideoState));

      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
        'UnifiedEndingNextPill stays identical in locked/unlocked states, vertical swipes work while HUD visible, and scrubbing pauses auto-hide',
        (tester) async {
      final fakePlayer = _RebuildFakePlayer();
      final title = _rebuildTitle();
      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes.first,
        existingPlayer: fakePlayer,
        userIdOverride: 'u_ux_fixes',
      );
      final fakeVc = _FakeVideoController(fakePlayer);

      GlobalMiniPlayerService.instance.minimize(
        cubit: cubit,
        videoController: fakeVc,
        onSaveProgress: () {},
      );

      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            title: title,
            initialEpisode: title.episodes.first,
          ),
        ),
      );
      await tester.pump();

      // 1. Reach ending segment -> UnifiedEndingNextPill appears in exact same spot in unlocked & locked states
      final s = fakePlayer.stream as _RebuildFakeStream;
      s.bufferingCtrl.add(false);
      s.playingCtrl.add(true);
      s.durationCtrl.add(const Duration(seconds: 1440));
      s.positionCtrl.add(const Duration(seconds: 1320));
      await tester.pump(const Duration(milliseconds: 300));

      final pillFinder = find.byKey(const ValueKey('unified_ending_next_pill'));
      expect(pillFinder, findsOneWidget);
      expect(
        find.byKey(const ValueKey('player_locked_next_episode_pill')),
        findsNothing,
      );
      final unlockedRect = tester.getRect(pillFinder);

      cubit.setScreenLocked(true);
      await tester.pump();
      expect(pillFinder, findsOneWidget);
      final lockedRect = tester.getRect(pillFinder);
      expect(lockedRect, unlockedRect);

      // Unlock and show controls -> vertical swipes on left/right adjust brightness/volume while HUD is visible
      cubit.setScreenLocked(false);
      cubit.showControls();
      await tester.pump();
      expect(cubit.state.areControlsVisible, isTrue);

      final initialBrightness = cubit.state.brightness;
      await tester.dragFrom(const Offset(150, 220), const Offset(0, -100));
      await tester.pump();
      expect(cubit.state.brightness, lessThanOrEqualTo(initialBrightness));
      // Swipe down on left half lowers brightness
      await tester.dragFrom(const Offset(150, 150), const Offset(0, 120));
      await tester.pump();
      expect(cubit.state.brightness, lessThan(1.0));

      // Swipe down then up on right half adjusts volume while HUD is visible
      await tester.dragFrom(const Offset(700, 150), const Offset(0, 120));
      await tester.pump();
      expect(cubit.state.volume, lessThan(100.0));

      // 3. Scrubbing PlayerProgressBar pauses controls auto-hide for 6+ seconds until release
      final barFinder = find.byType(PlayerProgressBar);
      expect(barFinder, findsOneWidget);
      final barRect = tester.getRect(barFinder);
      final gesture = await tester.startGesture(
        Offset(barRect.center.dx, barRect.top + 17),
      );
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(seconds: 6));
      expect(cubit.state.areControlsVisible, isTrue);
      await gesture.up();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      await cubit.close();
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
