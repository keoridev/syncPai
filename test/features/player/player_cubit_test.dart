import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/widgets/mascot/pai_companion_toast.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_entity.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/domain/entities/translation_entity.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_player_links_usecase.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_cubit.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_state.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';
import 'package:sync_pai/features/sync_room/domain/repositories/sync_room_repository.dart';

class _FakePlayerStream extends Fake implements mk.PlayerStream {
  final playingCtrl = StreamController<bool>.broadcast();
  final bufferingCtrl = StreamController<bool>.broadcast();
  final positionCtrl = StreamController<Duration>.broadcast();
  final durationCtrl = StreamController<Duration>.broadcast();
  final bufferCtrl = StreamController<Duration>.broadcast();
  final rateCtrl = StreamController<double>.broadcast();
  final completedCtrl = StreamController<bool>.broadcast();
  final errorCtrl = StreamController<String>.broadcast();

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

  Future<void> dispose() async {
    await playingCtrl.close();
    await bufferingCtrl.close();
    await positionCtrl.close();
    await durationCtrl.close();
    await bufferCtrl.close();
    await rateCtrl.close();
    await completedCtrl.close();
    await errorCtrl.close();
  }
}

class _FakeMkPlayerState extends Fake implements mk.PlayerState {
  @override
  bool buffering = false;
  @override
  Duration position = Duration.zero;
  @override
  mk.Playlist playlist = const mk.Playlist([]);
}

class _FakePlayer extends Fake implements mk.Player {
  final _FakePlayerStream _stream = _FakePlayerStream();
  final _FakeMkPlayerState _state = _FakeMkPlayerState();
  final List<mk.Media> openedMedias = [];
  final List<Duration> seeks = [];
  bool disposed = false;

  _FakePlayerStream get fakeStream => _stream;
  _FakeMkPlayerState get fakeState => _state;

  @override
  mk.PlayerStream get stream => _stream;

  @override
  mk.PlayerState get state => _state;

  @override
  mk.PlatformPlayer? get platform => null;

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    if (playable is mk.Media) {
      openedMedias.add(playable);
      _state.playlist = mk.Playlist([playable]);
    }
  }

  @override
  Future<void> play() async => _stream.playingCtrl.add(true);

  @override
  Future<void> pause() async => _stream.playingCtrl.add(false);

  @override
  Future<void> playOrPause() async {}

  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
    _state.position = duration;
  }

  @override
  Future<void> setRate(double rate) async => _stream.rateCtrl.add(rate);

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _stream.dispose();
  }
}

class _DelayedPlayerLinksUseCase extends Fake implements GetPlayerLinksUseCase {
  final Future<List<TranslationEntity>> Function(int releaseId) handler;
  _DelayedPlayerLinksUseCase(this.handler);

  @override
  Future<List<TranslationEntity>> call(
    int releaseId, {
    String? title,
    String? titleEn,
  }) =>
      handler(releaseId);
}

class _FakeSyncRepo extends Fake implements SyncRoomRepository {
  final packetCtrl = StreamController<SyncPacket>.broadcast();
  final presenceCtrl = StreamController<List<PeerPresence>>.broadcast();
  final List<int> changedEpisodes = [];

  @override
  Stream<SyncPacket> subscribeToPackets(String roomCode) => packetCtrl.stream;

  @override
  Stream<List<PeerPresence>> subscribeToPresence(String roomCode) =>
      presenceCtrl.stream;

  @override
  Future<Map<String, dynamic>?> getRoomData(String roomCode) async => null;

  @override
  Future<List<ChatMessage>> fetchChatHistory(
    String roomCode, {
    int limit = 50,
  }) async =>
      const [];

  @override
  Future<void> updatePresence({
    required String roomCode,
    required PeerPresence presence,
  }) async {}

  @override
  Future<void> sendBufferState({
    required String roomCode,
    required bool isBuffering,
    required String sender,
  }) async {}

  @override
  Future<void> sendHeartbeat({
    required String roomCode,
    required int positionMs,
    required bool isPlaying,
    required double rate,
    required String sender,
  }) async {}

  @override
  Future<void> sendChangeEpisode({
    required String roomCode,
    required int episodeNumber,
    required String quality,
    required String sender,
  }) async {
    changedEpisodes.add(episodeNumber);
  }

  @override
  Future<void> broadcastPlayback({
    required String roomCode,
    required double time,
    required bool isPlaying,
    required int episode,
    String? animeId,
    double? playbackRate = 1.0,
    String? updatedBy,
  }) async {}

  @override
  Future<void> sendControlAction({
    required String roomCode,
    required String action,
    required int positionMs,
    required String sender,
    double? playbackRate = 1.0,
    String? updatedBy,
    int? episode,
    bool? isPlaying,
    String? animeId,
  }) async {}

  @override
  Future<void> sendReaction({
    required String roomCode,
    required String emoji,
    required String sender,
    String? stickerId,
    String? senderId,
    String? reactionId,
  }) async {}

  Future<void> dispose() async {
    await packetCtrl.close();
    await presenceCtrl.close();
  }
}

AnimeTitle _sampleTitle({bool withUrls = true}) => AnimeTitle(
      id: 777,
      code: 'test_anime',
      russianTitle: 'Тестовое аниме',
      englishTitle: 'Test Anime',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      genres: const ['Экшен'],
      description: 'Описание',
      status: 'Онгоинг',
      episodes: [
        EpisodeItem(
          episode: 1,
          name: 'Серия 1',
          fhdUrl: withUrls ? 'https://anilibria.top/ep1_1080.m3u8' : null,
          hdUrl: withUrls ? 'https://anilibria.top/ep1_720.m3u8' : null,
          sdUrl: withUrls ? 'https://anilibria.top/ep1_480.m3u8' : null,
        ),
        EpisodeItem(
          episode: 2,
          name: 'Серия 2',
          fhdUrl: withUrls ? 'https://anilibria.top/ep2_1080.m3u8' : null,
          hdUrl: withUrls ? 'https://anilibria.top/ep2_720.m3u8' : null,
          sdUrl: withUrls ? 'https://anilibria.top/ep2_480.m3u8' : null,
        ),
        EpisodeItem(
          episode: 3,
          name: 'Серия 3',
          fhdUrl: withUrls ? 'https://anilibria.top/ep3_1080.m3u8' : null,
          hdUrl: withUrls ? 'https://anilibria.top/ep3_720.m3u8' : null,
          sdUrl: withUrls ? 'https://anilibria.top/ep3_480.m3u8' : null,
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (message) async =>
          const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);
    MascotCompanionService.instance.resetForTest();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('PlayerCubit — Buffer-aware errors, races, auto-next & disposal', () {
    test(
        'suppresses transient stream error when buffer has >= 2s ahead of position',
        () async {
      final fakePlayer = _FakePlayer();
      final title = _sampleTitle();
      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes.first,
        existingPlayer: fakePlayer,
        userIdOverride: 'u1',
      );

      await Future<void>.delayed(Duration.zero);
      fakePlayer.fakeStream.durationCtrl.add(const Duration(minutes: 24));
      fakePlayer.fakeStream.positionCtrl.add(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);
      fakePlayer.fakeStream.bufferCtrl.add(const Duration(seconds: 45));
      await Future<void>.delayed(Duration.zero);

      fakePlayer.fakeStream.errorCtrl
          .add('tcp: ffurl_write returned 0xffffff99');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.errorMessage, isNull);
      expect(fakePlayer.openedMedias.length, 1);

      await cubit.close();
    });

    test(
        'retries 5 times with CDN mirror rotation on empty buffer and resumes at exact live position',
        () async {
      final fakePlayer = _FakePlayer();
      final title = _sampleTitle();
      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes.first,
        existingPlayer: fakePlayer,
        userIdOverride: 'u1',
      );

      await Future<void>.delayed(Duration.zero);
      fakePlayer.fakeStream.durationCtrl.add(const Duration(minutes: 24));
      fakePlayer.fakeStream.positionCtrl.add(const Duration(seconds: 42));
      fakePlayer.fakeState.position = const Duration(seconds: 42);
      fakePlayer.fakeStream.bufferCtrl.add(const Duration(seconds: 42));
      await Future<void>.delayed(Duration.zero);

      // 1st transient error triggers attempt 1 (1s) -> cache.libria.fun at exact 42s
      fakePlayer.fakeStream.errorCtrl.add('connection reset by peer');
      await Future<void>.delayed(const Duration(milliseconds: 1150));

      expect(fakePlayer.openedMedias.length, 2);
      expect(fakePlayer.openedMedias.last.uri, contains('cache.libria.fun'));
      expect(fakePlayer.openedMedias.last.start, const Duration(seconds: 42));

      // Exhaust retries 2..5, then 6th error emits friendly errorMessage
      for (int i = 2; i <= 5; i++) {
        fakePlayer.fakeStream.errorCtrl.add('connection reset by peer');
        await Future<void>.delayed(Duration(seconds: i.clamp(1, 3), milliseconds: 150));
      }
      expect(fakePlayer.openedMedias.length, 6);

      fakePlayer.fakeStream.errorCtrl.add('connection reset by peer');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.errorMessage, isNotNull);

      await cubit.close();
    });

    test(
        'quality auto-fallback triggers only after 12s empty-buffer stall, not < 4s',
        () async {
      final fakePlayer = _FakePlayer();
      final title = _sampleTitle();
      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes.first,
        initialQuality: PlayerQuality.fhd,
        existingPlayer: fakePlayer,
        userIdOverride: 'u1',
      );

      await Future<void>.delayed(Duration.zero);
      fakePlayer.fakeStream.playingCtrl.add(true);
      fakePlayer.fakeStream.positionCtrl.add(const Duration(seconds: 10));
      fakePlayer.fakeStream.bufferCtrl.add(const Duration(seconds: 10));
      await Future<void>.delayed(Duration.zero);

      // Simulate brief < 4s micro-buffer (1.5s) -> clears before 12s
      fakePlayer.fakeState.buffering = true;
      fakePlayer.fakeStream.bufferingCtrl.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(cubit.state.selectedQuality, PlayerQuality.fhd);

      fakePlayer.fakeState.buffering = false;
      fakePlayer.fakeStream.bufferingCtrl.add(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cubit.state.selectedQuality, PlayerQuality.fhd);

      await cubit.close();
    });

    test(
        '_loadGeneration discards stale async stream resolution when switching episodes rapidly',
        () async {
      final fakePlayer = _FakePlayer();
      final ep2Completer = Completer<List<TranslationEntity>>();
      final ep3Completer = Completer<List<TranslationEntity>>();
      int useCaseCalls = 0;

      getIt.registerSingleton<GetPlayerLinksUseCase>(
        _DelayedPlayerLinksUseCase((id) {
          useCaseCalls++;
          if (useCaseCalls == 1) {
            return Future.value(const []);
          }
          if (useCaseCalls == 2) {
            return ep2Completer.future;
          }
          return ep3Completer.future;
        }),
      );

      final noUrlTitle = _sampleTitle(withUrls: false);
      final cubit = PlayerCubit(
        title: noUrlTitle,
        episode: noUrlTitle.episodes[0],
        existingPlayer: fakePlayer,
        userIdOverride: 'u1',
      );

      // Start ep2 load, then immediately switch to ep3 before ep2 resolves
      unawaited(cubit.switchEpisode(noUrlTitle.episodes[1]));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      unawaited(cubit.switchEpisode(noUrlTitle.episodes[2]));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Resolve ep3 first, then stale ep2 later
      ep3Completer.complete([
        const TranslationEntity(
          studioName: 'AniLibria',
          translationType: 'dub',
          isDirectStream: true,
          episodes: [
            EpisodeEntity(
              episode: 3,
              link: 'https://anilibria.top/ep3_fresh.m3u8',
              fhd: 'https://anilibria.top/ep3_fresh.m3u8',
            ),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      ep2Completer.complete([
        const TranslationEntity(
          studioName: 'AniLibria',
          translationType: 'dub',
          isDirectStream: true,
          episodes: [
            EpisodeEntity(
              episode: 2,
              link: 'https://anilibria.top/ep2_stale.m3u8',
              fhd: 'https://anilibria.top/ep2_stale.m3u8',
            ),
          ],
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        fakePlayer.openedMedias.map((m) => m.uri),
        contains('https://anilibria.top/ep3_fresh.m3u8'),
      );
      expect(
        fakePlayer.openedMedias.map((m) => m.uri),
        isNot(contains('https://anilibria.top/ep2_stale.m3u8')),
      );

      await cubit.close();
    });

    test(
        'completed auto-advances for solo/host, skips for guest, and resets autoNext state per episode',
        () async {
      final hostPlayer = _FakePlayer();
      final title = _sampleTitle();
      final hostCubit = PlayerCubit(
        title: title,
        episode: title.episodes[0],
        existingPlayer: hostPlayer,
        userIdOverride: 'host_1',
      );
      await Future<void>.delayed(Duration.zero);

      hostCubit.cancelAutoNextCountdown();
      hostPlayer.fakeStream.completedCtrl.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(hostCubit.state.episode.episode, 2);
      expect(hostCubit.state.autoNextCountdown, isNull);
      await hostCubit.close();

      // Guest in sync room must NOT auto-advance independently
      final guestPlayer = _FakePlayer();
      final syncRepo = _FakeSyncRepo();
      final guestCubit = PlayerCubit(
        title: title,
        episode: title.episodes[0],
        roomCode: 'ROOM1',
        isHost: false,
        syncRepository: syncRepo,
        existingPlayer: guestPlayer,
        userIdOverride: 'guest_1',
      );
      await Future<void>.delayed(Duration.zero);

      guestPlayer.fakeStream.completedCtrl.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(guestCubit.state.episode.episode, 1);

      await guestCubit.close();
      await syncRepo.dispose();
    });

    test(
        'close() cancels _awayDurationTimer, _spoilerShieldTimer, reactions & retry timers cleanly',
        () async {
      final fakePlayer = _FakePlayer();
      final syncRepo = _FakeSyncRepo();
      final title = _sampleTitle();
      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes[0],
        roomCode: 'ROOM2',
        isHost: false,
        syncRepository: syncRepo,
        existingPlayer: fakePlayer,
        userIdOverride: 'guest_2',
      );
      await Future<void>.delayed(Duration.zero);

      // Trigger away timer, spoiler shield timer (>15s jump), reaction timer, and retry timer
      syncRepo.presenceCtrl.add([
        PeerPresence(
          userId: 'host',
          name: 'Хост',
          avatar: '',
          status: PresenceStatus.away,
          lastSeen: DateTime.now(),
          isHost: true,
        ),
      ]);
      syncRepo.packetCtrl.add(
        SyncPacket(
          action: SyncActionTypes.heartbeat,
          sender: 'Хост',
          roomCode: 'ROOM2',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {'position_ms': 60000, 'is_playing': true},
        ),
      );
      cubit.sendReaction('excited');
      fakePlayer.fakeStream.errorCtrl.add('connection reset');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await cubit.close();
      await syncRepo.dispose();

      expect(fakePlayer.disposed, isTrue);
      // Wait past timer durations to verify zero unhandled post-close emissions
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });

  group('Season Finale Pai-chan Companion', () {
    test(
        'does NOT trigger on intermediate episode 1 of a multi-episode season, triggers once on final episode',
        () async {
      final fakePlayer = _FakePlayer();
      final title = _sampleTitle(); // 3 episodes
      int resolverCalls = 0;

      final cubit = PlayerCubit(
        title: title,
        episode: title.episodes[0], // Episode 1
        existingPlayer: fakePlayer,
        userIdOverride: 'u_finale_1',
        nextSeasonResolver: (t) async {
          resolverCalls++;
          return const SeasonFinaleNextSeason(
            name: 'Тестовый Тайтл 2',
            isAnnounced: false,
          );
        },
      );

      await Future<void>.delayed(Duration.zero);
      fakePlayer.fakeStream.durationCtrl.add(const Duration(minutes: 24));
      // Seek to last 30 seconds of Episode 1
      fakePlayer.fakeStream.positionCtrl
          .add(const Duration(minutes: 23, seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolverCalls, 0);
      expect(cubit.state.seasonFinalePrompt, isNull);

      // Switch to final episode (Episode 3) and seek to last 40 seconds
      await cubit.switchEpisode(title.episodes[2]);
      fakePlayer.fakeStream.durationCtrl.add(const Duration(minutes: 24));
      fakePlayer.fakeStream.positionCtrl
          .add(const Duration(minutes: 23, seconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(resolverCalls, 1);
      expect(cubit.state.seasonFinalePrompt, isNotNull);
      expect(cubit.state.seasonFinalePrompt!.titleId, title.id);
      expect(
        cubit.state.seasonFinalePrompt!.nextSeason?.name,
        'Тестовый Тайтл 2',
      );
      expect(cubit.state.seasonFinalePrompt!.nextSeason?.isAnnounced, isFalse);

      // Subsequent position updates in the same finale must NOT re-trigger
      fakePlayer.fakeStream.positionCtrl
          .add(const Duration(minutes: 23, seconds: 45));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(resolverCalls, 1);

      await cubit.close();
    });

    test(
        'emits null nextSeason on final episode when single-season anime has no sequel',
        () async {
      final fakePlayer = _FakePlayer();
      const singleSeasonTitle = AnimeTitle(
        id: 777,
        code: 'single_season',
        russianTitle: 'Одиночный Сезон',
        englishTitle: 'Single Season',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Драма'],
        description: '',
        status: 'Вышел',
        episodes: [
          EpisodeItem(
            episode: 1,
            fhdUrl: 'https://anilibria.top/single_1.m3u8',
          ),
        ],
      );

      final cubit = PlayerCubit(
        title: singleSeasonTitle,
        episode: singleSeasonTitle.episodes.first,
        existingPlayer: fakePlayer,
        userIdOverride: 'u_finale_single',
        nextSeasonResolver: (_) async => null,
      );

      await Future<void>.delayed(Duration.zero);
      fakePlayer.fakeStream.durationCtrl.add(const Duration(minutes: 24));
      fakePlayer.fakeStream.positionCtrl
          .add(const Duration(minutes: 23, seconds: 35));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.seasonFinalePrompt, isNotNull);
      expect(cubit.state.seasonFinalePrompt!.titleId, 777);
      expect(cubit.state.seasonFinalePrompt!.nextSeason, isNull);

      await cubit.close();
    });

    testWidgets(
        'PaiCompanionToast renders Case A (Playable Sequel), Case B (Announced), and Case C (No Sequel) with interactive CTAs',
        (tester) async {
      MascotCompanionService.instance.resetForTest();
      MascotCompanionService.instance.setPlayerActive(true);
      bool watchedSequel = false;
      bool addedPlanned = false;
      bool openedSimilar = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [PaiCompanionToast()],
            ),
          ),
        ),
      );

      // Case A: Playable Sequel
      MascotCompanionService.instance.onSeasonFinale(
        nextSeasonName: 'Магическая битва 2',
        hasPlayableSequel: true,
        hasAnnouncedSequel: false,
        onWatchSequel: () => watchedSequel = true,
      );
      await tester.pump();
      expect(find.text('Сезон завершён!'), findsOneWidget);
      expect(
        find.text('Дальше по хронологии: «Магическая битва 2». Газ в продолжение?'),
        findsOneWidget,
      );
      expect(find.text('Смотреть продолжение'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pai_companion_action_btn')));
      await tester.pump();
      expect(watchedSequel, isTrue);

      // Case B: Announced Sequel
      MascotCompanionService.instance.onSeasonFinale(
        nextSeasonName: 'Магическая битва 3',
        hasPlayableSequel: false,
        hasAnnouncedSequel: true,
        onAddPlanned: () => addedPlanned = true,
      );
      await tester.pump();
      expect(find.text('Финал сезона!'), findsOneWidget);
      expect(find.text('В планах'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_add_rounded), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pai_companion_action_btn')));
      await tester.pump();
      expect(addedPlanned, isTrue);

      // Case C: No Sequel
      MascotCompanionService.instance.onSeasonFinale(
        nextSeasonName: null,
        hasPlayableSequel: false,
        hasAnnouncedSequel: false,
        onFindSimilar: () => openedSimilar = true,
      );
      await tester.pump();
      expect(find.text('Сезон пройден!'), findsOneWidget);
      expect(
        find.text(
          'Извини, продолжения у этого тайтла пока нет. Подобрать похожее по вайбу?',
        ),
        findsOneWidget,
      );
      expect(find.text('Похожие тайтлы'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pai_companion_action_btn')));
      await tester.pump();
      expect(openedSimilar, isTrue);

      MascotCompanionService.instance.resetForTest();
    });
  });
}
