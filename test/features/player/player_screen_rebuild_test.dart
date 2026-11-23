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
  });
}
