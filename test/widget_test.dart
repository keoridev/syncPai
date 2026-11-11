import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/app/router/app_router.dart';
import 'package:sync_pai/features/sync_room/presentation/screens/join_room_screen.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_theme.dart';
import 'package:sync_pai/core/utils/player_navigation_guard.dart';
import 'package:sync_pai/core/widgets/glass_container.dart';
import 'package:sync_pai/features/anime_details/data/datasources/anime_reviews_provider.dart';
import 'package:sync_pai/features/anime_details/domain/entities/anime_video_item.dart';
import 'package:sync_pai/features/anime_details/domain/entities/related_anime_release.dart';
import 'package:sync_pai/features/anime_details/domain/entities/score_distribution_item.dart';
import 'package:sync_pai/features/anime_details/domain/entities/user_lists_stats.dart';
import 'package:sync_pai/features/anime_details/presentation/screens/anime_details_screen.dart';
import 'package:sync_pai/features/anime_details/presentation/screens/anime_videos_screen.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/anime_media_info_section.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/anime_reviews_section.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/anime_videos_section.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/episode_quality_sheet.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/franchise_progression_chart.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/related_releases_section.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/resume_progress_card.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/score_distribution_chart.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/user_lists_distribution_widget.dart';
import 'package:sync_pai/features/profile/presentation/widgets/profile_activity_chart.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/data/models/anime_catalog_model.dart';
import 'package:sync_pai/features/catalog/data/models/anime_player_data_model.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_entity.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_entity.dart';
import 'package:sync_pai/features/catalog/domain/entities/translation_entity.dart';
import 'package:sync_pai/features/catalog/domain/repositories/anime_catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_catalog_usecase.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_player_links_usecase.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_catalog_usecase.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/anime_poster_card.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/player/presentation/widgets/auto_next_episode_banner.dart';
import 'package:sync_pai/features/player/presentation/widgets/floating_reactions_layer.dart';
import 'package:sync_pai/features/player/presentation/widgets/player_progress_bar.dart';
import 'package:sync_pai/features/player/presentation/widgets/presence_radar_badge.dart';
import 'package:sync_pai/features/player/presentation/widgets/quick_phrase_toast_widget.dart';
import 'package:sync_pai/features/player/presentation/widgets/sync_buffer_banner.dart';
import 'package:sync_pai/features/player/presentation/widgets/twitch_chat_overlay.dart';
import 'package:sync_pai/features/player/presentation/widgets/double_tap_seek_overlay.dart';
import 'package:sync_pai/features/anime_lists/presentation/widgets/import_status_selector_dialog.dart';
import 'package:sync_pai/features/anime_lists/presentation/widgets/import_progress_dialog.dart';
import 'package:sync_pai/features/auth/presentation/screens/auth_screen.dart';
import 'package:sync_pai/features/sync_room/data/repositories/sync_room_repository_impl.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_room.dart';
import 'package:sync_pai/features/sync_room/domain/repositories/sync_room_repository.dart';
import 'package:sync_pai/features/sync_room/presentation/widgets/sync_room_lobby_sheet.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sync_pai/features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import 'package:sync_pai/features/anime_lists/data/datasources/anixart_backup_parser.dart';
import 'package:sync_pai/features/anime_lists/data/datasources/anixart_csv_parser.dart';
import 'package:sync_pai/features/anime_lists/data/datasources/anixart_remote_datasource.dart';
import 'package:sync_pai/features/anime_lists/data/repositories/anime_list_repository_impl.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/domain/repositories/anime_list_repository.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:sync_pai/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/auth/domain/repositories/auth_repository.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/auth/presentation/widgets/auth_modal_sheet.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_title_details.dart';
import 'package:sync_pai/features/shorts/domain/entities/anime_clip.dart';
import 'package:sync_pai/features/shorts/data/datasources/anime_clips_datasource.dart';
import 'package:sync_pai/features/shorts/data/repositories/anime_clips_repository_impl.dart';
import 'package:sync_pai/features/shorts/presentation/widgets/clip_bottom_overlay.dart';
import 'package:sync_pai/features/shorts/presentation/widgets/clip_side_actions.dart';
import 'package:sync_pai/features/shorts/data/models/anime_moment_model.dart';
import 'package:sync_pai/features/shorts/presentation/controllers/moments_player_pool.dart';
import 'package:sync_pai/features/shorts/presentation/widgets/moments_page_view.dart';
import 'package:sync_pai/features/shorts/presentation/widgets/short_video_player_item.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:sync_pai/core/widgets/sync_pai_logo.dart';
import 'package:sync_pai/core/theme/theme_preset.dart';
import 'package:sync_pai/core/theme/cubit/theme_cubit.dart';
import 'package:sync_pai/core/theme/widgets/theme_selector_sheet.dart';
import 'package:sync_pai/features/splash/presentation/screens/splash_screen.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/core/widgets/liquid_glass_nav_bar.dart';
import 'package:sync_pai/features/main/presentation/screens/main_screen.dart';
import 'package:sync_pai/features/sync_room/presentation/screens/watch_together_screen.dart';
import 'package:sync_pai/features/anime_lists/presentation/screens/saved_anime_screen.dart';
import 'package:sync_pai/features/profile/presentation/screens/profile_screen.dart';
import 'package:sync_pai/features/settings/presentation/screens/settings_screen.dart';
import 'package:sync_pai/features/watch_history/data/repositories/watch_history_repository_impl.dart';
import 'package:sync_pai/features/watch_history/domain/entities/watch_history_item.dart';
import 'package:sync_pai/features/watch_history/domain/repositories/watch_history_repository.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'package:sync_pai/core/widgets/tv_focusable.dart';
import 'package:sync_pai/features/downloads/domain/entities/download_task.dart';
import 'package:sync_pai/features/downloads/data/repositories/download_repository_impl.dart';
import 'package:sync_pai/features/downloads/domain/repositories/download_repository.dart';
import 'package:sync_pai/features/downloads/presentation/cubit/download_cubit.dart';
import 'package:sync_pai/features/downloads/presentation/cubit/download_state.dart';
import 'package:sync_pai/features/torrents/domain/entities/torrent_release.dart';
import 'package:sync_pai/features/torrents/presentation/widgets/torrent_releases_sheet.dart';
import 'package:sync_pai/features/player/services/pip_service.dart';
import 'package:sync_pai/features/player/domain/entities/reaction_heatmap.dart';
import 'package:sync_pai/features/sync_room/presentation/cubit/coop_match_cubit.dart';
import 'package:sync_pai/core/network/smart_mirror_interceptor.dart';
import 'package:sync_pai/core/widgets/steam_avatar_frame.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_state.dart';
import 'package:sync_pai/features/profile/domain/entities/steam_profile_customization.dart';
import 'package:sync_pai/features/kodik/domain/entities/kodik_translation.dart';
import 'package:sync_pai/features/kodik/data/datasources/kodik_remote_datasource.dart';
import 'package:sync_pai/features/kodik/data/datasources/kodik_stream_extractor.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_cubit.dart';
import 'package:sync_pai/features/kodik/presentation/widgets/voiceover_selector_sheet.dart';

const testTitle = AnimeTitle(
  id: 101,
  code: 'frieren',
  russianTitle: 'Провожающая в последний путь Фрирен',
  englishTitle: 'Sousou no Frieren',
  posterSmall: '',
  posterMedium: '',
  posterOriginal: '',
  episodesTotal: 28,
  latestEpisode: 28,
  season: 'Осень 2023',
  year: 2023,
  genres: ['Приключения', 'Фэнтези', 'Драма'],
  description: 'История эльфийки-волшебницы Фрирен после победы над Королем демонов.',
  status: 'Завершен',
  playerHost: null,
  episodes: [
    EpisodeItem(
      episode: 1,
      name: 'Конец приключения',
      fhdUrl: 'https://sample.com/1080.m3u8',
      hdUrl: 'https://sample.com/720.m3u8',
      sdUrl: 'https://sample.com/480.m3u8',
      previewUrl: 'https://sample.com/ep1.jpg',
      opening: TimecodeRange(start: 90, stop: 180),
    ),
    EpisodeItem(
      episode: 2,
      name: 'Магия цветов',
      fhdUrl: 'https://sample.com/1080_2.m3u8',
    ),
  ],
);

class FakeCatalogRepository implements CatalogRepository {
  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 15}) async => [testTitle];
  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int page = 1, int limit = 15}) async => [testTitle];
  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async => testTitle;
}

class FakeKodikRemoteDataSource implements KodikRemoteDataSource {
  final List<KodikTranslation> mockTranslations;

  FakeKodikRemoteDataSource({this.mockTranslations = const []});

  @override
  Future<List<KodikTranslation>> getTranslationsForAnime({
    int? shikimoriId,
    String? title,
  }) async {
    if (mockTranslations.isNotEmpty) return mockTranslations;
    return const [
      KodikTranslation(
        id: 1002,
        title: 'Dream Cast',
        type: 'voice',
        episodesCount: 24,
        embedLink: 'https://kodik.info/seria/1002/dream_cast',
        episodeEmbedLinks: {1: 'https://kodik.info/seria/1002/1', 2: 'https://kodik.info/seria/1002/2'},
      ),
      KodikTranslation(
        id: 609,
        title: 'StudioBand',
        type: 'voice',
        episodesCount: 24,
        embedLink: 'https://kodik.info/seria/609/studio_band',
        episodeEmbedLinks: {1: 'https://kodik.info/seria/609/1'},
      ),
      KodikTranslation(
        id: 10,
        title: 'Субтитры',
        type: 'subtitles',
        episodesCount: 24,
        embedLink: 'https://kodik.info/seria/10/subs',
      ),
    ];
  }
}

class FakeKodikStreamExtractor extends KodikStreamExtractor {
  @override
  Future<String?> extractDirectStream(String embedUrl, {String quality = '720p'}) async {
    return 'https://stream.kodikcdn.com/test_stream_$quality.m3u8';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return null;
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    if (!getIt.isRegistered<SharedPreferences>()) {
      getIt.registerSingleton<SharedPreferences>(prefs);
    }

    if (!getIt.isRegistered<CatalogRepository>()) {
      final fakeRepo = FakeCatalogRepository();
      getIt.registerLazySingleton<CatalogRepository>(() => fakeRepo);
      getIt.registerLazySingleton<GetUpdates>(() => GetUpdates(fakeRepo));
      getIt.registerLazySingleton<SearchTitles>(() => SearchTitles(fakeRepo));
      getIt.registerLazySingleton<GetTitleDetails>(() => GetTitleDetails(fakeRepo));
    }

    if (!getIt.isRegistered<SyncRoomRepository>()) {
      getIt.registerLazySingleton<SyncRoomRepository>(() => SyncRoomRepositoryImpl());
    }

    if (!getIt.isRegistered<AuthCubit>()) {
      final authRepo = AuthRepositoryImpl(prefs);
      getIt.registerLazySingleton<AuthRepository>(() => authRepo);
      getIt.registerLazySingleton<AuthCubit>(() => AuthCubit(repository: authRepo));
    }

    if (!getIt.isRegistered<ShikimoriRemoteDataSource>()) {
      getIt.registerLazySingleton<ShikimoriRemoteDataSource>(() => ShikimoriRemoteDataSourceImpl());
    }

    if (!getIt.isRegistered<AnixartRemoteDataSource>()) {
      getIt.registerLazySingleton<AnixartRemoteDataSource>(() => AnixartRemoteDataSourceImpl());
    }

    if (!getIt.isRegistered<AnimeListCubit>()) {
      final anixartDs = getIt<AnixartRemoteDataSource>();
      final listRepo = AnimeListRepositoryImpl(prefs, anixartRemoteDataSource: anixartDs);
      getIt.registerLazySingleton<AnimeListRepository>(() => listRepo);
      getIt.registerLazySingleton<AnimeListCubit>(() => AnimeListCubit(repository: listRepo));
    }

    if (!getIt.isRegistered<WatchHistoryCubit>()) {
      final historyRepo = WatchHistoryRepositoryImpl(prefs);
      getIt.registerLazySingleton<WatchHistoryRepository>(() => historyRepo);
      getIt.registerLazySingleton<WatchHistoryCubit>(() => WatchHistoryCubit(repository: historyRepo));
    }

    if (!getIt.isRegistered<ThemeCubit>()) {
      getIt.registerLazySingleton<ThemeCubit>(() => ThemeCubit(prefs));
    }

    if (!getIt.isRegistered<DownloadCubit>()) {
      final dlRepo = DownloadRepositoryImpl(prefs);
      getIt.registerLazySingleton<DownloadRepository>(() => dlRepo);
      getIt.registerLazySingleton<DownloadCubit>(() => DownloadCubit(dlRepo));
    }

    if (!getIt.isRegistered<KodikRemoteDataSource>()) {
      getIt.registerLazySingleton<KodikRemoteDataSource>(() => KodikRemoteDataSourceImpl());
    }

    if (!getIt.isRegistered<KodikStreamExtractor>()) {
      getIt.registerLazySingleton<KodikStreamExtractor>(() => KodikStreamExtractor());
    }

    if (!getIt.isRegistered<KodikCubit>()) {
      getIt.registerLazySingleton<KodikCubit>(() => KodikCubit(
        dataSource: getIt<KodikRemoteDataSource>(),
        extractor: getIt<KodikStreamExtractor>(),
        prefs: prefs,
      ));
    }
  });

  test('AppTheme configuration smoke test', () {
    final theme = AppTheme.cinemaDark;
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.primaryColor, AppColors.primary);
  });

  test('SyncRoomRepository creates room with SP-XXXX code and handles join', () async {
    final repo = SyncRoomRepositoryImpl();

    final room = await repo.createRoom(
      title: testTitle,
      episode: testTitle.episodes.first,
      quality: PlayerQuality.hd,
    );

    expect(room.code.startsWith('SP-'), isTrue);
    expect(room.quality, PlayerQuality.hd);
    expect(room.status, SyncRoomStatus.waiting);

    // Test join
    final joined = await repo.joinRoom(code: room.code, peerName: 'Алиса');
    expect(joined.status, SyncRoomStatus.connected);
    expect(joined.peerName, 'Алиса');

    // Test normalizer
    expect(SyncRoomRepositoryImpl.normalizeCode('sp4821'), 'SP-4821');
    expect(SyncRoomRepositoryImpl.normalizeCode('749301'), '749-301');
  });

  testWidgets('GlassContainer and GlassIconButton render and handle tap', (tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Center(
            child: GlassIconButton(
              icon: Icons.group_outlined,
              tooltip: 'Смотреть с другом',
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.group_outlined), findsOneWidget);
    await tester.tap(find.byType(GlassIconButton));
    expect(tapped, isTrue);
  });

  testWidgets('AnimePosterCard displays title and dot-separated metadata without heavy boxes', (tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 300,
            child: AnimePosterCard(
              title: testTitle,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text(testTitle.russianTitle), findsOneWidget);
    expect(find.text('2023 • Приключения • Фэнтези'), findsOneWidget);

    await tester.tap(find.byType(AnimePosterCard));
    expect(tapped, isTrue);
  });

  testWidgets('EpisodeQualitySheet displays options and returns selected quality', (tester) async {
    PlayerQuality? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  selected = await EpisodeQualitySheet.show(
                    ctx,
                    title: testTitle,
                    episode: testTitle.episodes.first,
                    initialQuality: PlayerQuality.fhd,
                  );
                },
                child: const Text('Open Quality Sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Quality Sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Выбор качества видео'), findsOneWidget);
    expect(find.text('1080p (FHD)'), findsOneWidget);
    expect(find.text('720p (HD)'), findsOneWidget);
    expect(find.text('480p (SD)'), findsOneWidget);

    // Switch to 720p HD
    await tester.tap(find.text('720p (HD)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Confirm play button with selected quality
    expect(find.text('Смотреть в 720p (HD)'), findsOneWidget);
    await tester.tap(find.text('Смотреть в 720p (HD)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(selected, PlayerQuality.hd);
  });

  testWidgets('AnimeDetailsScreen opens quality selection before launching episode', (tester) async {
    EpisodeItem? playedEpisode;
    PlayerQuality? playedQuality;
    EpisodeItem? syncEpisode;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: AnimeDetailsScreen(
          title: testTitle,
          onPlayEpisode: (t, ep, q) {
            playedEpisode = ep;
            playedQuality = q;
          },
          onStartSyncRoom: (t, ep) => syncEpisode = ep,
        ),
      ),
    );

    // Title and genres
    expect(find.text(testTitle.russianTitle), findsOneWidget);
    expect(find.text('Приключения • Фэнтези • Драма'), findsOneWidget);

    // Primary watch button
    expect(find.text('Смотреть'), findsOneWidget);

    // Companion watch with friend button
    expect(find.byIcon(Icons.group_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.group_outlined));
    await tester.pump();
    expect(syncEpisode?.episode, 1);
    // Закрываем открывшийся SyncRoomConfigSheet
    final navKey = tester.element(find.byType(AnimeDetailsScreen));
    Navigator.of(navKey).pop();
    await tester.pumpAndSettle();

    // Tap primary watch button -> Quality sheet appears
    await tester.tap(find.text('Смотреть'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Выбор качества видео'), findsOneWidget);
    expect(find.text('Смотреть в 1080p (FHD)'), findsOneWidget);

    // Choose and start watching
    await tester.tap(find.text('Смотреть в 1080p (FHD)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(playedEpisode?.episode, 1);
    expect(playedQuality, PlayerQuality.fhd);
  });

  testWidgets('SyncRoomLobbySheet displays room code and handles simulated peer join', (tester) async {
    SyncRoom? startedRoom;
    bool? startedAsHost;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () {
                  SyncRoomLobbySheet.show(
                    ctx,
                    title: testTitle,
                    episode: testTitle.episodes.first,
                    initialQuality: PlayerQuality.hd,
                    onStartPlayback: (room, isHost) {
                      startedRoom = room;
                      startedAsHost = isHost;
                    },
                  );
                },
                child: const Text('Open Sync Lobby'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sync Lobby'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Совместный просмотр'), findsOneWidget);
    expect(find.text('КОД КОМНАТЫ'), findsOneWidget);
    expect(find.text('Скопировать код'), findsOneWidget);
    expect(find.text('Ждем подключения друга...'), findsOneWidget);

    // Test tab switch to Join
    await tester.tap(find.text('Присоединиться'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Введите 6-значный код комнаты'), findsOneWidget);
    expect(find.text('Вставить из буфера обмена'), findsOneWidget);

    // Switch back to Host
    await tester.tap(find.text('Я хост (Создать)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Ensure the simulate button is scrolled into view and tap it
    final simButton = find.text('Симулировать подключение друга (Тест)');
    await tester.ensureVisible(simButton);
    await tester.pump();
    await tester.tap(simButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Verify playback started with room and host flag
    expect(startedRoom, isNotNull);
    expect(startedAsHost, isTrue);
    expect(startedRoom?.status, SyncRoomStatus.connected);
  });

  test('SyncRoomRepositoryImpl broadcasts packets and delivers via subscribeToPackets', () async {
    final repo = SyncRoomRepositoryImpl();
    const roomCode = 'SP-9999';

    final receivedPackets = <SyncPacket>[];
    final sub = repo.subscribeToPackets(roomCode).listen(receivedPackets.add);

    await repo.sendHeartbeat(
      roomCode: roomCode,
      positionMs: 42000,
      isPlaying: true,
      rate: 1.0,
      sender: 'Хост',
    );

    await repo.sendReaction(
      roomCode: roomCode,
      emoji: '🔥',
      sender: 'Алиса',
    );

    await repo.sendChatMessage(
      roomCode: roomCode,
      text: 'Привет всем!',
      sender: 'Хост',
      isHost: true,
    );

    await repo.sendBufferState(
      roomCode: roomCode,
      isBuffering: true,
      sender: 'Алиса',
    );

    await repo.sendSyncEvent(
      roomCode: roomCode,
      time: 125.5,
      isPlaying: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(receivedPackets.length, 5);
    expect(receivedPackets[0].action, SyncActionTypes.heartbeat);
    expect(receivedPackets[0].payload['position_ms'], 42000);
    expect(receivedPackets[1].action, SyncActionTypes.reaction);
    expect(receivedPackets[1].payload['emoji'], '🔥');
    expect(receivedPackets[2].action, SyncActionTypes.chatMessage);
    expect(receivedPackets[2].payload['text'], 'Привет всем!');
    expect(receivedPackets[3].action, SyncActionTypes.bufferWait);
    expect(receivedPackets[4].action, SyncActionTypes.controlAction);
    expect(receivedPackets[4].payload['time'], 125.5);
    expect(receivedPackets[4].payload['position_ms'], 125500);
    expect(receivedPackets[4].payload['is_playing'], true);

    await sub.cancel();
  });

  testWidgets('TwitchChatOverlay renders unobtrusive top-left chat messages and respects visibility', (tester) async {
    final messages = [
      ChatMessage(
        id: '1',
        sender: 'Хост',
        text: 'Привет в комнате!',
        isHost: true,
        timestamp: DateTime.now(),
      ),
      ChatMessage(
        id: '2',
        sender: 'Друг',
        text: 'Крутой опенинг!',
        isHost: false,
        timestamp: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Stack(
            children: [
              TwitchChatOverlay(
                messages: messages,
                isVisible: true,
                onToggleVisibility: () {},
              ),
            ],
          ),
        ),
      ),
    );

    // Должны отображаться сами реплики и ники без громоздких шапок
    expect(find.textContaining('Привет в комнате!'), findsOneWidget);
    expect(find.textContaining('Крутой опенинг!'), findsOneWidget);
    expect(find.textContaining('👑 Хост:'), findsOneWidget);
    expect(find.textContaining('Друг:'), findsOneWidget);

    // При скрытом чате — не отображается ничего лишнего, освобождая весь экран
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Stack(
            children: [
              TwitchChatOverlay(
                messages: messages,
                isVisible: false,
                onToggleVisibility: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Привет в комнате!'), findsNothing);
  });

  testWidgets('FloatingReactionsLayer and SyncBufferBanner render correctly', (tester) async {
    final reactions = [
      FloatingReaction(
        id: 'r1',
        emoji: '🔥',
        sender: 'Друг',
        startXOffset: 0.7,
        timestamp: DateTime.now(),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Stack(
            children: [
              FloatingReactionsLayer(reactions: reactions),
              const SyncBufferBanner(notice: 'У друга слабый сигнал, ждем…'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('🔥'), findsOneWidget);
    expect(find.text('У друга слабый сигнал, ждем…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PlayerProgressBar handles unlocked seek and locked host notice', (tester) async {
    Duration? seeked;
    bool lockedTapped = false;

    // 1. Unlocked (Host)
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: PlayerProgressBar(
                position: const Duration(seconds: 30),
                duration: const Duration(minutes: 24),
                buffer: const Duration(minutes: 5),
                onSeek: (pos) => seeked = pos,
                isLocked: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('00:30'), findsOneWidget);
    expect(find.text('24:00'), findsOneWidget);
    expect(find.text('Хост управляет'), findsNothing);

    await tester.tap(find.byType(PlayerProgressBar));
    expect(seeked, isNotNull);

    // 2. Locked (Guest)
    seeked = null;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: PlayerProgressBar(
                position: const Duration(seconds: 45),
                duration: const Duration(minutes: 24),
                buffer: const Duration(minutes: 5),
                onSeek: (pos) => seeked = pos,
                isLocked: true,
                onLockedTap: () => lockedTapped = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Хост управляет'), findsOneWidget);
    await tester.tap(find.byType(PlayerProgressBar));
    expect(seeked, isNull);
    expect(lockedTapped, isTrue);
  });

  testWidgets('PresenceRadarBadge renders cat avatar and reflects online and away states', (tester) async {
    final onlinePresence = PeerPresence(
      userId: 'p1',
      name: 'Сенпай',
      avatar: '🐱',
      status: PresenceStatus.online,
      lastSeen: DateTime(2024),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Center(
            child: PresenceRadarBadge(presence: onlinePresence),
          ),
        ),
      ),
    );

    expect(find.text('🐱'), findsOneWidget);
    expect(find.text('Сенпай в сети'), findsOneWidget);

    final awayPresence = PeerPresence(
      userId: 'p1',
      name: 'Сенпай',
      avatar: '🐱',
      status: PresenceStatus.away,
      lastSeen: DateTime(2024),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Center(
            child: PresenceRadarBadge(presence: awayPresence),
          ),
        ),
      ),
    );

    expect(find.text('Сенпай отошел'), findsOneWidget);
  });

  testWidgets('QuickPhraseToastWidget renders shortcut toast smoothly', (tester) async {
    final toast = QuickPhraseToast(
      id: 't1',
      sender: 'Друг',
      phrase: 'Останови, отойду на минуту',
      emoji: '⏸️',
      timestamp: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Stack(
            children: [
              QuickPhraseToastWidget(toast: toast),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Друг'), findsOneWidget);
    expect(find.text('Останови, отойду на минуту'), findsOneWidget);
    expect(find.text('⏸️'), findsOneWidget);
  });

  testWidgets('AutoNextEpisodeBanner displays countdown and triggers play now / cancel', (tester) async {
    bool playNowTapped = false;
    bool cancelTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Stack(
            children: [
              AutoNextEpisodeBanner(
                countdown: 5,
                nextEpisode: testTitle.episodes.last,
                isHost: true,
                onPlayNow: () => playNowTapped = true,
                onCancel: () => cancelTapped = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('5'), findsOneWidget);
    expect(find.text('Следующая серия'), findsOneWidget);
    expect(find.text('Серия 2 — Магия цветов'), findsOneWidget);
    expect(find.text('Включить сейчас'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);

    await tester.tap(find.text('Включить сейчас'));
    expect(playNowTapped, isTrue);

    await tester.tap(find.text('Отмена'));
    expect(cancelTapped, isTrue);
  });

  test('SyncRoomRepositoryImpl manages Presence, ChangeEpisode and QuickPhrases', () async {
    final repo = SyncRoomRepositoryImpl();
    const roomCode = 'SP-7777';

    final presences = <List<PeerPresence>>[];
    final sub = repo.subscribeToPresence(roomCode).listen(presences.add);

    await repo.updatePresence(
      roomCode: roomCode,
      presence: PeerPresence(
        userId: 'u1',
        name: 'Хост',
        avatar: '👑',
        status: PresenceStatus.online,
        lastSeen: DateTime.now(),
        isHost: true,
      ),
    );

    await repo.sendChangeEpisode(
      roomCode: roomCode,
      episodeNumber: 2,
      quality: 'hd',
      sender: 'Хост',
    );

    await repo.sendQuickPhrase(
      roomCode: roomCode,
      phrase: 'Что за трек?!',
      emoji: '🎵',
      sender: 'Друг',
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(presences.isNotEmpty, isTrue);
    expect(presences.last.first.name, 'Хост');
    expect(presences.last.first.avatar, '👑');

    await sub.cancel();
  });

  testWidgets('SyncRoomLobbySheet renders QR code with deep link format', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () {
                  SyncRoomLobbySheet.show(
                    ctx,
                    title: testTitle,
                    episode: testTitle.episodes.first,
                    initialQuality: PlayerQuality.hd,
                    onStartPlayback: (_, __) {},
                  );
                },
                child: const Text('Open QR Lobby'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open QR Lobby'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Наведите камеру смартфона для подключения'), findsOneWidget);

    // Tap share link button
    final shareButton = find.text('Поделиться');
    await tester.ensureVisible(shareButton);
    await tester.pump();
    await tester.tap(shareButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ссылка скопирована!'), findsOneWidget);
  });

  testWidgets('JoinRoomScreen automatically joins room and resolves deep link', (tester) async {
    final repo = getIt<SyncRoomRepository>();
    final room = await repo.createRoom(
      title: testTitle,
      episode: testTitle.episodes.first,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: JoinRoomScreen(code: room.code),
      ),
    );

    expect(find.textContaining('Подключение к комнате'), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });

  test('Full State Flow: Room creation -> PIN/Link join -> Presence -> Heartbeat -> Buffer -> AutoNext', () async {
    final repo = SyncRoomRepositoryImpl();

    // 1. Host creates room
    final room = await repo.createRoom(
      title: testTitle,
      episode: testTitle.episodes.first,
      quality: PlayerQuality.hd,
    );
    expect(room.shareUrl.startsWith('https://syncpai.app/room/'), isTrue);

    // 2. Guest connects via deep link or PIN
    final joined = await repo.joinRoom(code: room.code, peerName: 'Алиса');
    expect(joined.status, SyncRoomStatus.connected);

    // 3. Presence Tracker: check online status
    final presences = <List<PeerPresence>>[];
    final pSub = repo.subscribeToPresence(room.code).listen(presences.add);

    await repo.updatePresence(
      roomCode: room.code,
      presence: PeerPresence(
        userId: 'host_1',
        name: 'Хост',
        avatar: '👑',
        status: PresenceStatus.online,
        lastSeen: DateTime.now(),
        isHost: true,
      ),
    );

    await repo.updatePresence(
      roomCode: room.code,
      presence: PeerPresence(
        userId: 'guest_1',
        name: 'Алиса',
        avatar: '🐱',
        status: PresenceStatus.online,
        lastSeen: DateTime.now(),
        isHost: false,
      ),
    );

    // 4. Player Sync Stream: Heartbeat from Host
    final packets = <SyncPacket>[];
    final packSub = repo.subscribeToPackets(room.code).listen(packets.add);

    await repo.sendHeartbeat(
      roomCode: room.code,
      positionMs: 12000,
      isPlaying: true,
      rate: 1.0,
      sender: 'Хост',
    );

    // 5. Buffer drop: Mutual wait
    await repo.sendBufferState(
      roomCode: room.code,
      isBuffering: true,
      sender: 'Алиса',
    );

    // 6. Floating Reactions
    await repo.sendReaction(
      roomCode: room.code,
      emoji: '🔥',
      sender: 'Алиса',
    );

    // 7. Auto Next Episode: Change episode
    await repo.sendChangeEpisode(
      roomCode: room.code,
      episodeNumber: 2,
      quality: 'hd',
      sender: 'Хост',
    );

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(packets.any((p) => p.action == SyncActionTypes.heartbeat), isTrue);
    expect(packets.any((p) => p.action == SyncActionTypes.bufferWait), isTrue);
    expect(packets.any((p) => p.action == SyncActionTypes.reaction), isTrue);
    expect(packets.any((p) => p.action == SyncActionTypes.changeEpisode), isTrue);

    await pSub.cancel();
    await packSub.cancel();
  });

  test('WatchHistoryItem serialization, formatting and progress calculation', () {
    final item = WatchHistoryItem(
      titleId: 101,
      titleName: 'Фрирен',
      posterUrl: 'https://example.com/poster.jpg',
      episode: 4,
      episodeName: 'Конец пути',
      positionMs: 745000, // 12:25
      durationMs: 1440000, // 24:00
      updatedAt: DateTime(2026, 11, 5, 14, 40),
    );

    expect(item.formattedPosition, '12:25');
    expect(item.formattedDuration, '24:00');
    expect(item.progress, closeTo(0.517, 0.01));

    final json = item.toJson();
    expect(json['title_id'], 101);
    expect(json['last_episode'], 4);
    expect(json['position_ms'], 745000);

    final restored = WatchHistoryItem.fromJson(json);
    expect(restored.titleId, 101);
    expect(restored.episode, 4);
    expect(restored.positionMs, 745000);
  });

  test('WatchHistoryRepository saves and retrieves progress via SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = WatchHistoryRepositoryImpl(prefs);

    final item = WatchHistoryItem(
      titleId: 202,
      titleName: 'Магическая битва',
      posterUrl: 'https://example.com/jjk.jpg',
      episode: 2,
      positionMs: 600000, // 10:00
      durationMs: 1400000,
      updatedAt: DateTime.now(),
    );

    await repo.saveProgress(item);

    final retrieved = await repo.getProgress(202);
    expect(retrieved, isNotNull);
    expect(retrieved!.titleName, 'Магическая битва');
    expect(retrieved.episode, 2);
    expect(retrieved.positionMs, 600000);

    final all = await repo.getAllHistory();
    expect(all.length, 1);
    expect(all.first.titleId, 202);
  });

  testWidgets('ResumeProgressCard renders unfinished watch prompt and handles callbacks', (tester) async {
    bool resumed = false;
    bool restarted = false;

    final item = WatchHistoryItem(
      titleId: 101,
      titleName: 'Фрирен',
      posterUrl: '',
      episode: 4,
      positionMs: 745000, // 12:25
      durationMs: 1440000,
      updatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: ResumeProgressCard(
            item: item,
            onResume: () => resumed = true,
            onStartFromBeginning: () => restarted = true,
          ),
        ),
      ),
    );

    expect(find.text('Вы не досмотрели эту серию'), findsOneWidget);
    expect(find.text('Серия 4 • остановлено на 12:25'), findsOneWidget);
    expect(find.text('Продолжить (12:25)'), findsOneWidget);
    expect(find.text('С начала'), findsOneWidget);

    await tester.tap(find.text('Продолжить (12:25)'));
    expect(resumed, isTrue);

    await tester.tap(find.text('С начала'));
    expect(restarted, isTrue);
  });

  testWidgets('AnimeMediaInfoSection renders trailer and opening timecodes with auto-skip badge', (tester) async {
    bool trailerOpened = false;

    const titleWithMedia = AnimeTitle(
      id: 101,
      code: 'frieren',
      russianTitle: 'Фрирен',
      englishTitle: 'Sousou no Frieren',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      episodesTotal: 28,
      trailerUrl: 'https://youtube.com/watch?v=sample',
      genres: ['Фэнтези'],
      description: 'Описание',
      status: 'Завершен',
      episodes: [
        EpisodeItem(
          episode: 1,
          name: 'Эпизод 1',
          opening: TimecodeRange(start: 90, stop: 180),
          ending: TimecodeRange(start: 1300, stop: 1390),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: AnimeMediaInfoSection(
            title: titleWithMedia,
            onOpenTrailer: () => trailerOpened = true,
          ),
        ),
      ),
    );

    expect(find.text('Официальный трейлер'), findsOneWidget);
    expect(find.text('YouTube • HD 1080p'), findsOneWidget);
    expect(find.text('МУЗЫКА И ТАЙМКОДЫ'), findsOneWidget);
    expect(find.text('Opening (Опенинг)'), findsOneWidget);
    expect(find.textContaining('01:30 — 03:00'), findsOneWidget);
    expect(find.text('Авто-пропуск'), findsOneWidget);
    expect(find.text('Титры'), findsOneWidget);

    await tester.tap(find.text('Смотреть'));
    expect(trailerOpened, isTrue);
  });

  testWidgets('AnimeReviewsSection renders portal scores and community review cards', (tester) async {
    final reviews = AnimeReviewsProvider.getReviewsForTitle(testTitle);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimeReviewsSection(reviews: reviews),
          ),
        ),
      ),
    );

    expect(find.text('ОЦЕНКИ НА АНИМЕ-ПОРТАЛАХ'), findsOneWidget);
    expect(find.text('Shikimori'), findsNWidgets(2)); // В чипе портала и в отзыве
    expect(find.text('MyAnimeList'), findsNWidgets(2));
    expect(find.text('AniLibria'), findsNWidgets(2));
    expect(find.text('Отзывы сообщества'), findsOneWidget);
    expect(find.text('Sensei_Critic'), findsOneWidget);
    expect(find.text('AniLover99'), findsOneWidget);
  });

  test('UserProfile guest instantiation, copyWith and serialization', () {
    final guest = UserProfile.guest('user_123');
    expect(guest.id, 'user_123');
    expect(guest.isAnonymous, isTrue);
    expect(guest.username.startsWith('Сенпай'), isTrue);

    final updated = guest.copyWith(username: 'Хокаге', avatarUrl: '🦊');
    expect(updated.username, 'Хокаге');
    expect(updated.avatarUrl, '🦊');

    final json = updated.toJson();
    final restored = UserProfile.fromJson(json);
    expect(restored.username, 'Хокаге');
    expect(restored.avatarUrl, '🦊');
  });

  test('UserAnimeStats accurately computes watch time and episode totals', () {
    final entries = [
      UserAnimeEntry(
        id: '1',
        userId: 'u1',
        animeId: 101,
        titleRu: 'Фрирен',
        status: AnimeListStatus.completed,
        lastEpisode: 28,
        episodesTotal: 28,
        updatedAt: DateTime.now(),
      ),
      UserAnimeEntry(
        id: '2',
        userId: 'u1',
        animeId: 102,
        titleRu: 'Магическая битва',
        status: AnimeListStatus.watching,
        lastEpisode: 5,
        positionMs: 600000, // 10 минут
        episodesTotal: 24,
        updatedAt: DateTime.now(),
      ),
      UserAnimeEntry(
        id: '3',
        userId: 'u1',
        animeId: 103,
        titleRu: 'Блич',
        status: AnimeListStatus.planned,
        updatedAt: DateTime.now(),
      ),
    ];

    final stats = UserAnimeStats.compute(entries);
    expect(stats.totalTitles, 3);
    expect(stats.completedTitles, 1);
    expect(stats.watchingTitles, 1);
    expect(stats.plannedTitles, 1);
    expect(stats.totalEpisodesCompleted, 32); // 28 + (5 - 1)
    expect(stats.formattedTime.contains('ч.'), isTrue);
  });

  test('AnixartBackupParser extracts titles, categories and calculates metrics', () {
    const sampleBackup = '''
    [
      {
        "id": 1001,
        "title": "Атака титанов",
        "category": "completed",
        "watched_episodes": 25,
        "total_episodes": 25
      },
      {
        "id": 1002,
        "title": "Клинок рассекающий демонов",
        "category": "watching",
        "watched_episodes": 12,
        "total_episodes": 26
      },
      {
        "id": 1003,
        "title": "Человек-бензопила",
        "category": "planned"
      }
    ]
    ''';

    final result = AnixartBackupParser.parse(sampleBackup, userId: 'test_user');
    expect(result.totalParsed, 3);
    expect(result.entries[0].titleRu, 'Атака титанов');
    expect(result.entries[0].status, AnimeListStatus.completed);
    expect(result.entries[1].titleRu, 'Клинок рассекающий демонов');
    expect(result.entries[1].status, AnimeListStatus.watching);
    expect(result.entries[2].status, AnimeListStatus.planned);
  });

  test('AnixartCsvParser parses standard Anixart CSV export with comma delimiter', () {
    const csvContent = '''
Title,Status,Episodes,Score
Врата Штейна,Просмотрено,24,10
Магическая битва,Смотрю,18/24,9
Тетрадь смерти,Отложено,25,8
Человек-бензопила,В планах,0,
Токийский гуль,Брошено,6,4
''';

    final entries = AnixartCsvParser.parseCsv(csvContent, userId: 'u_csv');
    expect(entries.length, 5);
    expect(entries[0].titleRu, 'Врата Штейна');
    expect(entries[0].status, AnimeListStatus.completed);
    expect(entries[0].lastEpisode, 24);

    expect(entries[1].titleRu, 'Магическая битва');
    expect(entries[1].status, AnimeListStatus.watching);
    expect(entries[1].lastEpisode, 18);
    expect(entries[1].episodesTotal, 24);

    expect(entries[2].status, AnimeListStatus.planned);
    expect(entries[3].status, AnimeListStatus.planned);
    expect(entries[4].status, AnimeListStatus.dropped);
    expect(entries[4].lastEpisode, 6);
  });

  test('AnixartCsvParser parses semicolon delimiter and calculates statistics', () {
    const csvSemicolon = '''
Название;Статус;Серии;Оценка
Евангелион;completed;26/26;10
Блич;watching;120;9
''';

    final res = AnixartCsvParser.parseToResult(csvSemicolon, userId: 'u_semi');
    expect(res.totalParsed, 2);
    expect(res.totalEpisodes, greaterThanOrEqualTo(26));
    expect(res.entries[0].titleRu, 'Евангелион');
    expect(res.entries[0].status, AnimeListStatus.completed);
    expect(res.entries[1].titleRu, 'Блич');
    expect(res.entries[1].status, AnimeListStatus.watching);
  });

  test('AnixartBackupParser seamlessly handles CSV export without JSON tags', () {
    const csvContent = '''
Title,Status,Episodes
Наруто,Просмотрено,220
''';
    final res = AnixartBackupParser.parse(csvContent, userId: 'u_backup');
    expect(res.totalParsed, 1);
    expect(res.entries.first.titleRu, 'Наруто');
    expect(res.entries.first.status, AnimeListStatus.completed);
  });

  test('AnimeListRepositoryImpl stores and updates entries offline-first', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = AnimeListRepositoryImpl(prefs);

    final entry = UserAnimeEntry(
      id: 'test_1',
      userId: 'user_local',
      animeId: 555,
      titleRu: 'Врата Штейна',
      status: AnimeListStatus.completed,
      lastEpisode: 24,
      episodesTotal: 24,
      updatedAt: DateTime.now(),
    );

    await repo.upsertEntry(entry);

    final retrieved = await repo.getEntry(555);
    expect(retrieved, isNotNull);
    expect(retrieved!.titleRu, 'Врата Штейна');
    expect(retrieved.status, AnimeListStatus.completed);

    final all = await repo.getAllEntries();
    expect(all.length, 1);

    await repo.removeEntry(555);
    final empty = await repo.getAllEntries();
    expect(empty.isEmpty, isTrue);
  });

  test('AuthRepositoryImpl handles anonymous auth and profile persistence', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = AuthRepositoryImpl(prefs);

    final profile = await repo.getCurrentProfile();
    expect(profile.isAnonymous, isTrue);

    final updated = await repo.updateProfile(username: 'Тестовый Отаку', avatarUrl: '🐺');
    expect(updated.username, 'Тестовый Отаку');
    expect(updated.avatarUrl, '🐺');

    final cached = await repo.getCurrentProfile();
    expect(cached.username, 'Тестовый Отаку');
  });

  testWidgets('ProfileScreen renders stats block, categories and edit button', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AuthCubit>()),
          BlocProvider.value(value: getIt<AnimeListCubit>()),
        ],
        child: const MaterialApp(
          home: ProfileScreen(),
        ),
      ),
    );

    expect(find.text('Мой профиль'), findsOneWidget);
    expect(find.text('СТАТИСТИКА ПРОСМОТРА'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.textContaining('Смотрю'), findsOneWidget);
  });

  testWidgets('ProfileScreen with friend userId hides settings, auth banner and renders friend header', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AuthCubit>()),
          BlocProvider.value(value: getIt<AnimeListCubit>()),
        ],
        child: const MaterialApp(
          home: ProfileScreen(userId: 'friend_user_999'),
        ),
      ),
    );

    // Должна отображаться плашка "Профиль друга", а не "Мой профиль"
    expect(find.text('Профиль друга'), findsOneWidget);
    expect(find.text('Мой профиль'), findsNothing);

    // Шестеренка настроек скрыта для чужих профилей
    expect(find.byIcon(Icons.settings), findsNothing);

    // Плашка авторизации Google скрыта
    expect(find.text('Сохраните свой прогресс'), findsNothing);
  });

  test('ShikimoriRemoteDataSource BBCode parser and sanitizer', () {
    const raw = '[b]Шедевр![/b] [spoiler]Герой выжил[/spoiler] [character=123]Лелуш[/character] &quot;SyncPai&quot; &amp; anime.';
    final cleaned = ShikimoriRemoteDataSourceImpl.cleanBbCode(raw);
    expect(cleaned.contains('[b]'), isFalse);
    expect(cleaned.contains('[/b]'), isFalse);
    expect(cleaned.contains('[Спойлер: Герой выжил]'), isTrue);
    expect(cleaned.contains('Лелуш'), isTrue);
    expect(cleaned.contains('"SyncPai" & anime.'), isTrue);
  });

  test('ShikimoriRemoteDataSource returns ratings and fallback on unreachable host', () async {
    final ds = ShikimoriRemoteDataSourceImpl();
    final res = await ds.getReviewsAndRatings(testTitle);

    expect(res.portalScores, isNotEmpty);
    expect(res.portalScores.containsKey('Shikimori'), isTrue);
    expect(res.portalScores.containsKey('MyAnimeList'), isTrue);
    expect(res.portalScores.containsKey('AniLibria'), isTrue);
    expect(res.portalScores.containsKey('World Art'), isTrue);
    expect(res.reviews, isNotEmpty);
  });

  test('AnixartRemoteDataSource validates input and throws on empty query', () async {
    final ds = AnixartRemoteDataSourceImpl();
    expect(
      () => ds.fetchProfileBookmarks(loginOrId: '', userId: 'u1'),
      throwsA(isA<AnixartUserNotFoundException>()),
    );
  });

  testWidgets('SettingsScreen renders online import modal when tapping По ID', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AuthCubit>()),
          BlocProvider.value(value: getIt<AnimeListCubit>()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    expect(find.text('Импорт из Anixart по ID'), findsOneWidget);

    // Тапаем по кнопке «Импорт из Anixart по ID»
    await tester.ensureVisible(find.text('Импорт из Anixart по ID'));
    await tester.tap(find.text('Импорт из Anixart по ID'));
    await tester.pumpAndSettle();

    expect(find.text('Импорт профиля Anixart'), findsOneWidget);
    expect(find.text('Начать импорт'), findsOneWidget);
    expect(find.textContaining('Ваш профиль в Anixart должен быть открытым'), findsOneWidget);
  });

  testWidgets('LiquidGlassNavBar renders 4 navigation items and triggers onTap', (tester) async {
    int selectedIndex = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: LiquidGlassNavBar(
            currentIndex: selectedIndex,
            onTap: (idx) => selectedIndex = idx,
            items: const [
              LiquidGlassNavItem(icon: Icons.explore_outlined, selectedIcon: Icons.explore_rounded, label: 'Каталог'),
              LiquidGlassNavItem(icon: Icons.people_outline_rounded, selectedIcon: Icons.people_alt_rounded, label: 'Вместе'),
              LiquidGlassNavItem(icon: Icons.bookmark_outline_rounded, selectedIcon: Icons.bookmark_rounded, label: 'Списки'),
              LiquidGlassNavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Профиль'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Каталог'), findsOneWidget);
    expect(find.text('Вместе'), findsOneWidget);
    expect(find.text('Списки'), findsOneWidget);
    expect(find.text('Профиль'), findsOneWidget);

    await tester.tap(find.text('Вместе'));
    expect(selectedIndex, 1);

    await tester.tap(find.text('Списки'));
    expect(selectedIndex, 2);
  });

  testWidgets('WatchTogetherScreen renders PIN input, friend cards and add friend dialog', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WatchTogetherScreen(),
      ),
    );

    expect(find.text('Смотреть вместе'), findsOneWidget);
    expect(find.text('Присоединиться к комнате'), findsOneWidget);
    expect(find.text('Друзья онлайн'), findsOneWidget);
    expect(find.text('NekoChan_99'), findsOneWidget);

    // Открываем диалог добавления друга
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();

    expect(find.text('Добавить друга'), findsOneWidget);
  });

  testWidgets('SavedAnimeScreen renders category selector and search input', (tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AnimeListCubit>()),
          BlocProvider.value(value: getIt<WatchHistoryCubit>()),
        ],
        child: const MaterialApp(
          home: SavedAnimeScreen(),
        ),
      ),
    );

    expect(find.text('Мои списки'), findsOneWidget);
    expect(find.text('Поиск по сохраненным тайтлам...'), findsOneWidget);
    expect(find.text('Смотрю'), findsAtLeastNWidgets(1));
    expect(find.text('В планах'), findsOneWidget);
    expect(find.text('Просмотрено'), findsOneWidget);
  });

  testWidgets('SettingsScreen renders settings section and player options', (tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AuthCubit>()),
          BlocProvider.value(value: getIt<AnimeListCubit>()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('НАСТРОЙКИ ПЛЕЕРА И СИСТЕМЫ'), findsOneWidget);
    expect(find.text('Качество видео'), findsOneWidget);
    expect(find.text('Авто-пропуск опенингов'), findsOneWidget);
    expect(find.text('Очистить кэш плеера и историю'), findsOneWidget);
  });

  testWidgets('MainScreen integrates 4 tabs with LiquidGlassNavBar and switches between them', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AuthCubit>()),
          BlocProvider.value(value: getIt<AnimeListCubit>()),
          BlocProvider.value(value: getIt<WatchHistoryCubit>()),
          BlocProvider(
            create: (_) => CatalogCubit(
              getUpdates: getIt<GetUpdates>(),
              searchTitles: getIt<SearchTitles>(),
              prefs: getIt<SharedPreferences>(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: MainScreen(),
        ),
      ),
    );

    // Вкладка 0: Каталог активна
    expect(find.byType(LiquidGlassNavBar), findsOneWidget);
    expect(find.text('Каталог'), findsAtLeast(1));

    // Переключаемся на Вкладку 2: Вместе
    await tester.tap(find.text('Вместе'));
    await tester.pumpAndSettle();
    expect(find.text('Смотреть вместе'), findsOneWidget);

    // Переключаемся на Вкладку 3: Списки
    await tester.tap(find.text('Списки'));
    await tester.pumpAndSettle();
    expect(find.text('Мои списки'), findsOneWidget);

    // Переключаемся на Вкладку 4: Профиль
    await tester.tap(find.text('Профиль'));
    await tester.pumpAndSettle();
    expect(find.text('СТАТИСТИКА ПРОСМОТРА'), findsOneWidget);
  });

  testWidgets('TvFocusable triggers callback on tap and handles D-pad select key', (tester) async {
    bool tapped = false;
    final focusNode = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusable(
            focusNode: focusNode,
            onPressed: () => tapped = true,
            child: const Text('TV_BUTTON_ITEM'),
          ),
        ),
      ),
    );

    expect(find.text('TV_BUTTON_ITEM'), findsOneWidget);

    // 1. Проверка клика/тапа
    await tester.tap(find.text('TV_BUTTON_ITEM'));
    expect(tapped, isTrue);

    // 2. Фокусировка D-Pad и нажатие клавиши Select
    tapped = false;
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(tapped, isTrue);

    focusNode.dispose();
  });

  test('DownloadTask serialization, ID generator and formatted size', () {
    final task = DownloadTask(
      id: DownloadTask.generateId(101, 3),
      titleId: 101,
      titleName: 'Фрирен',
      posterUrl: 'https://example.com/poster.jpg',
      episode: 3,
      episodeName: 'Серия 3',
      quality: '1080p',
      sourceUrl: 'https://example.com/ep3.mp4',
      localPath: '/data/downloads/ep3.mp4',
      totalBytes: 1024 * 1024 * 550, // 550 МБ
      status: DownloadStatus.completed,
      createdAt: DateTime.parse('2026-11-05T12:00:00Z'),
    );

    expect(task.id, '101_3');
    expect(task.formattedSize, '550 МБ');

    final json = task.toJson();
    final restored = DownloadTask.fromJson(json);

    expect(restored.id, task.id);
    expect(restored.titleId, 101);
    expect(restored.episode, 3);
    expect(restored.status, DownloadStatus.completed);
    expect(restored.totalBytes, 1024 * 1024 * 550);
  });

  test('DownloadCubit and DownloadState manage offline collections', () {
    final task1 = DownloadTask(
      id: '101_1',
      titleId: 101,
      titleName: 'Фрирен',
      posterUrl: '',
      episode: 1,
      episodeName: 'Серия 1',
      quality: '1080p',
      sourceUrl: '',
      localPath: '/data/ep1.mp4',
      totalBytes: 1024 * 1024 * 500,
      status: DownloadStatus.completed,
      createdAt: DateTime.now(),
    );

    final task2 = DownloadTask(
      id: '101_2',
      titleId: 101,
      titleName: 'Фрирен',
      posterUrl: '',
      episode: 2,
      episodeName: 'Серия 2',
      quality: '1080p',
      sourceUrl: '',
      localPath: '/data/ep2.mp4',
      progress: 0.45,
      status: DownloadStatus.downloading,
      createdAt: DateTime.now(),
    );

    final state = DownloadState(
      tasks: {
        task1.id: task1,
        task2.id: task2,
      },
    );

    expect(state.isDownloaded(101, 1), isTrue);
    expect(state.isDownloaded(101, 2), isFalse);
    expect(state.completedTasks.length, 1);
    expect(state.activeTasks.length, 1);
    expect(state.formattedTotalBytesUsed, '500 МБ');
  });

  test('TorrentRelease models AniLibria and TorLook data correctly', () {
    final anilibriaJson = {
      'hash': '4b5a6c7d8e9f0a1b2c3d4e5f',
      'series': {'string': '1-12 [12]'},
      'quality': {'string': 'BDRip 1080p 10-bit'},
      'total_size': 14 * 1024 * 1024 * 1024,
      'seeders': 156,
      'leechers': 12,
    };

    final release1 = TorrentRelease.fromAniLibria(anilibriaJson, 'Клинок, рассекающий демонов');
    expect(release1.quality, 'BDRip 1080p 10-bit');
    expect(release1.series, '1-12 [12]');
    expect(release1.seeders, 156);
    expect(release1.sizeString, '14.0 ГБ');
    expect(release1.magnetUrl.contains('magnet:?xt=urn:btih:'), isTrue);

    final torlookJson = {
      'title': 'Frieren BD-Remux 1080p Dual Audio',
      'magnet': 'magnet:?xt=urn:btih:abcdef123456',
      'size': '28.5 GB',
      'seeds': 98,
      'leeches': 4,
    };

    final release2 = TorrentRelease.fromTorLook(torlookJson);
    expect(release2.title, 'Frieren BD-Remux 1080p Dual Audio');
    expect(release2.sizeString, '28.5 GB');
    expect(release2.seeders, 98);
    expect(release2.quality, 'BDRip 1080p');
  });

  testWidgets('TorrentReleasesSheet renders releases and triggers play', (tester) async {
    bool playTriggered = false;

    const mockRelease = TorrentRelease(
      title: 'Фрирен BDRip',
      magnetUrl: 'magnet:?xt=urn:btih:test12345',
      sizeString: '14.2 ГБ',
      seeders: 85,
      leechers: 5,
      quality: 'BDRip 1080p',
      series: '1-28 [28]',
      source: 'AniLibria BD',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TorrentReleasesSheet(
            releases: const [mockRelease],
            animeTitle: 'Фрирен',
            onPlayTorrent: (release, streamUrl) {
              playTriggered = true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Торренты & BDRip'), findsOneWidget);
    expect(find.text('BDRip 1080p'), findsOneWidget);
    expect(find.text('1-28 [28]'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
    expect(find.text('Размер: 14.2 ГБ'), findsOneWidget);
    expect(find.text('Смотреть стрим'), findsOneWidget);

    await tester.tap(find.text('Смотреть стрим'));
    expect(playTriggered, isTrue);
  });

  test('PipService reports support safely', () async {
    final isSupported = await PipService.instance.isSupported();
    expect(isSupported, isFalse); // Default false in flutter_test mock
    expect(PipService.instance.isInPip, isFalse);
  });

  test('CoopMatchCubit swipes cards and detects match on mutual like', () async {
    final titleA = testTitle;
    const titleB = AnimeTitle(
      id: 102,
      code: 'jjk',
      russianTitle: 'Магическая битва',
      englishTitle: 'Jujutsu Kaisen',
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      status: 'Онгоинг',
      description: 'Магическая битва',
      genres: ['Экшен'],
    );

    final repo = SyncRoomRepositoryImpl();
    final cubit = CoopMatchCubit(
      initialDeck: [titleA, titleB],
      roomCode: 'SP-1234',
      userName: 'Пользователь',
      syncRepository: repo,
    );

    expect(cubit.state.currentTitle?.id, 101);
    expect(cubit.state.remainingCount, 2);

    // Имитируем голос друга: он лайкнул titleA через комнату
    await repo.sendPacket(
      SyncPacket(
        action: SyncActionTypes.swipeVote,
        sender: 'Друг',
        roomCode: 'SP-1234',
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        payload: {'title_id': 101, 'liked': true},
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cubit.state.peerVotes[101], isTrue);

    // Пользователь тоже свайпает вправо (лайк)
    await cubit.voteCurrent(true);

    // Должен сработать Мэтч!
    expect(cubit.state.matchedTitle?.id, 101);
    expect(cubit.state.currentIndex, 1);
    expect(cubit.state.currentTitle?.id, 102);

    cubit.clearMatch();
    expect(cubit.state.matchedTitle, isNull);

    await cubit.close();
  });

  test('ReactionHeatmap computes SoundCloud-style normalized heights and records reactions', () {
    var heatmap = ReactionHeatmap.initial(titleId: 101, episode: 1, bucketCount: 40);
    expect(heatmap.buckets.length, 40);
    expect(heatmap.normalizedHeights.length, 40);

    // Добавляем реакцию на 14-й минуте (840 сек из 1440 сек)
    heatmap = heatmap.addReaction(
      timestampSec: 840,
      totalDurationSec: 1440,
      emoji: '🔥',
      sender: 'Друг',
    );

    expect(heatmap.reactions.length, 1);
    expect(heatmap.reactions.first.emoji, '🔥');
    expect(heatmap.reactions.first.timestampSec, 840.0);
    expect(heatmap.totalReactionsCount, greaterThan(40));

    // Проверяем нормализацию высот
    for (final h in heatmap.normalizedHeights) {
      expect(h, greaterThanOrEqualTo(0.15));
      expect(h, lessThanOrEqualTo(1.0));
    }
  });

  testWidgets('PlayerProgressBar renders SoundCloud-style reaction waveform', (tester) async {
    final heatmap = ReactionHeatmap.initial(titleId: 101, episode: 1, bucketCount: 30);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerProgressBar(
            position: const Duration(minutes: 5),
            duration: const Duration(minutes: 24),
            buffer: const Duration(minutes: 10),
            heatmap: heatmap,
            onSeek: (_) {},
          ),
        ),
      ),
    );

    // Проверяем, что прогресс-бар и волновые контейнеры отрисовались
    expect(find.byType(PlayerProgressBar), findsOneWidget);
    expect(find.byType(Stack), findsWidgets);
  });

  test('PlayerState manages Voice Chat, Push-to-Talk and Audio Ducking fields', () {
    const state = PlayerState(
      title: testTitle,
      episode: EpisodeItem(episode: 1),
      isVoiceMuted: true,
      isTalking: false,
      isPeerTalking: false,
    );

    expect(state.isVoiceMuted, isTrue);
    expect(state.isTalking, isFalse);
    expect(state.isPeerTalking, isFalse);

    // Включаем микрофон
    final unmutedState = state.copyWith(isVoiceMuted: false, isTalking: true);
    expect(unmutedState.isVoiceMuted, isFalse);
    expect(unmutedState.isTalking, isTrue);

    // Друг говорит (Audio Ducking)
    final duckingState = unmutedState.copyWith(isPeerTalking: true);
    expect(duckingState.isPeerTalking, isTrue);
    expect(SyncActionTypes.voiceTalking, 'VOICE_TALKING');
  });

  test('SmartMirrorInterceptor manages mirrors and anti-block toggle', () {
    expect(SmartMirrorInterceptor.isAntiBlockEnabled, isTrue);
    final initialMirror = SmartMirrorInterceptor.activeApiMirror;
    expect(initialMirror.contains('anilibria'), isTrue);

    // Ротация зеркала
    SmartMirrorInterceptor.rotateMirror();
    final nextMirror = SmartMirrorInterceptor.activeApiMirror;
    expect(nextMirror.isNotEmpty, isTrue);

    // Переключение тумблера анти-блокировки
    SmartMirrorInterceptor.isAntiBlockEnabled = false;
    expect(SmartMirrorInterceptor.isAntiBlockEnabled, isFalse);
    SmartMirrorInterceptor.isAntiBlockEnabled = true;
  });

  test('AppRouter contains valid routes for splash, main, catalog, details, profile, player', () {
    final routeNames = appRouter.configuration.routes
        .whereType<GoRoute>()
        .map((r) => r.name)
        .whereType<String>()
        .toSet();

    expect(routeNames.contains('splash'), isTrue);
    expect(routeNames.contains('main'), isTrue);
    expect(routeNames.contains('catalog'), isTrue);
    expect(routeNames.contains('details'), isTrue);
    expect(routeNames.contains('profile'), isTrue);
    expect(routeNames.contains('player'), isTrue);
    expect(routeNames.contains('shorts'), isTrue);
  });

  test('SteamProfileCustomization manages frames, backgrounds and custom titles', () {
    expect(SteamAvatarFrame.all.length, greaterThanOrEqualTo(5));
    final neon = SteamAvatarFrame.fromId('neon_cyber');
    expect(neon.name, 'Неон Киберпанк');
    expect(neon.colors.length, greaterThanOrEqualTo(2));

    expect(SteamBackgroundTheme.all.length, greaterThanOrEqualTo(5));
    final tokyo = SteamBackgroundTheme.fromId('tokyo_neon');
    expect(tokyo.name, 'Tokyo Neon Night');
    expect(tokyo.gradient.length, greaterThanOrEqualTo(2));

    expect(SteamCustomTitle.titles.contains('Архимаг Синхрона'), isTrue);
  });

  testWidgets('SteamAvatarFrameWidget renders child cleanly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SteamAvatarFrameWidget(
            frameId: 'none',
            size: 48,
            child: Text('AV'),
          ),
        ),
      ),
    );

    expect(find.text('AV'), findsOneWidget);
  });

  testWidgets('UserListsDistributionWidget renders status breakdown and counts', (tester) async {
    const stats = UserListsStats(
      watching: 66,
      planned: 234,
      onHold: 36,
      dropped: 41,
      completed: 1200,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserListsDistributionWidget(stats: stats),
        ),
      ),
    );

    expect(find.text('В списках у людей'), findsOneWidget);
    expect(find.text('Смотрю'), findsOneWidget);
    expect(find.text('66'), findsOneWidget);
    expect(find.text('В планах'), findsOneWidget);
    expect(find.text('234'), findsOneWidget);
    expect(find.text('Отложено'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    expect(find.text('Брошено'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
  });

  testWidgets('RelatedReleasesSection renders franchise seasons with "Вы здесь" and handles taps', (tester) async {
    RelatedAnimeRelease? tappedRelease;
    final releases = [
      const RelatedAnimeRelease(
        id: '1',
        title: 'Легенда о Белом Коте',
        year: '2020 год',
        rating: 4.3,
        kind: 'Сериал',
        posterUrl: '',
        relation: 'Основная история',
        isCurrent: false,
      ),
      const RelatedAnimeRelease(
        id: '2',
        title: 'Легенда о Белом Коте 2',
        year: '2022 год',
        rating: 4.3,
        kind: 'Сериал',
        posterUrl: '',
        relation: 'Продолжение',
        isCurrent: false,
      ),
      const RelatedAnimeRelease(
        id: '3',
        title: 'Легенда о Белом Коте 3',
        year: '2026 год',
        kind: 'Сериал',
        posterUrl: '',
        relation: 'Продолжение',
        isCurrent: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: RelatedReleasesSection(
            releases: releases,
            onReleaseSelected: (rel) => tappedRelease = rel,
          ),
        ),
      ),
    );

    expect(find.text('Связанные релизы'), findsOneWidget);
    expect(find.text('Легенда о Белом Коте'), findsOneWidget);
    expect(find.text('Легенда о Белом Коте 2'), findsOneWidget);
    expect(find.text('Легенда о Белом Коте 3'), findsOneWidget);
    expect(find.textContaining('Вы\nздесь'), findsOneWidget);

    // Tap Season 1
    await tester.tap(find.text('Легенда о Белом Коте'));
    expect(tappedRelease?.title, 'Легенда о Белом Коте');
  });

  testWidgets('AnimeVideosSection renders trailers carousel and list of videos', (tester) async {
    final videos = [
      const AnimeVideoItem(
        id: 'pv3',
        title: 'PV3',
        url: 'https://www.youtube.com/watch?v=sample3',
        imageUrl: '',
        publishedAt: '17 окт. в 12:00',
        source: 'YouTube',
      ),
      const AnimeVideoItem(
        id: 'pv1',
        title: 'PV1',
        url: 'https://www.youtube.com/watch?v=sample1',
        imageUrl: '',
        publishedAt: '17 окт. в 12:00',
        source: 'YouTube',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnimeVideosSection(
              videos: videos,
              animeTitle: 'Легенда о Белом Коте 3',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Видео'), findsOneWidget);
    expect(find.text('Легенда о Белом Коте 3'), findsWidgets);
    expect(find.text('Трейлеры'), findsOneWidget);
    expect(find.text('Последние видео'), findsOneWidget);
    expect(find.text('PV3'), findsWidgets);
    expect(find.text('PV1'), findsWidgets);
  });

  testWidgets('AnimeVideosScreen renders top banner, trailers carousel and video tiles', (tester) async {
    final testVideos = [
      const AnimeVideoItem(
        id: 'pv3',
        title: 'PV3',
        url: 'https://www.youtube.com/watch?v=sample3',
        imageUrl: '',
        publishedAt: '17 окт. в 12:00',
        source: 'Anixart',
      ),
      const AnimeVideoItem(
        id: 'pv1',
        title: 'PV1',
        url: 'https://www.youtube.com/watch?v=sample1',
        imageUrl: '',
        publishedAt: '17 окт. в 12:00',
        source: 'Anixart',
      ),
      const AnimeVideoItem(
        id: 'pv2',
        title: 'PV2',
        url: 'https://www.youtube.com/watch?v=sample2',
        imageUrl: '',
        publishedAt: '17 окт. в 12:00',
        source: 'Anixart',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: AnimeVideosScreen(
          animeTitle: 'Легенда о Белом Коте 3',
          videos: testVideos,
        ),
      ),
    );

    expect(find.text('Видео'), findsOneWidget);
    expect(find.text('Легенда о Белом Коте 3'), findsWidgets);
    expect(find.text('Трейлеры'), findsWidgets);
    expect(find.text('Последние видео'), findsOneWidget);
    expect(find.text('PV3'), findsWidgets);
    expect(find.text('PV1'), findsWidgets);
    expect(find.text('PV2'), findsWidgets);
    expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);
  });

  testWidgets('ScoreDistributionChart renders average, star breakdown and recommendation', (tester) async {
    final distribution = [
      const ScoreDistributionItem(score: 10, votes: 5000, percentage: 50.0),
      const ScoreDistributionItem(score: 9, votes: 3000, percentage: 30.0),
      const ScoreDistributionItem(score: 8, votes: 1500, percentage: 15.0),
      const ScoreDistributionItem(score: 7, votes: 500, percentage: 5.0),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: ScoreDistributionChart(
            distribution: distribution,
            averageScore: 9.1,
            totalVotes: 10000,
          ),
        ),
      ),
    );

    expect(find.text('Распределение оценок'), findsOneWidget);
    expect(find.text('9.1'), findsOneWidget);
    expect(find.textContaining('10.0k оценок'), findsOneWidget);
    expect(find.textContaining('советуют'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('FranchiseProgressionChart renders season bars and handles season tap', (tester) async {
    RelatedAnimeRelease? tapped;
    final releases = [
      const RelatedAnimeRelease(
        id: '1',
        title: 'Сезон 1',
        year: '2020 год',
        rating: 8.2,
        posterUrl: '',
        relation: 'Основная',
        isCurrent: false,
      ),
      const RelatedAnimeRelease(
        id: '2',
        title: 'Сезон 2',
        year: '2022 год',
        rating: 8.6,
        posterUrl: '',
        relation: 'Продолжение',
        isCurrent: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.cinemaDark,
        home: Scaffold(
          body: FranchiseProgressionChart(
            releases: releases,
            onReleaseSelected: (rel) => tapped = rel,
          ),
        ),
      ),
    );

    expect(find.text('Динамика сезонов'), findsOneWidget);
    expect(find.text('8.2'), findsOneWidget);
    expect(find.text('8.6'), findsOneWidget);
    expect(find.text('2020'), findsOneWidget);

    await tester.tap(find.text('8.2'));
    expect(tapped?.title, 'Сезон 1');
  });

  testWidgets('ProfileActivityChart renders weekly bars and genre chips', (tester) async {
    const stats = UserAnimeStats(
      totalTitles: 12,
      completedTitles: 8,
      watchingTitles: 3,
      plannedTitles: 5,
      droppedTitles: 1,
      totalEpisodesCompleted: 140,
      totalMinutesWatched: 3360,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileActivityChart(stats: stats),
          ),
        ),
      ),
    );

    expect(find.text('АКТИВНОСТЬ ПРОСМОТРА'), findsOneWidget);
    expect(find.text('РАСПРЕДЕЛЕНИЕ ПО ЖАНРАМ'), findsOneWidget);
    expect(find.text('Пн'), findsOneWidget);
    expect(find.text('Сб'), findsOneWidget);
    expect(find.text('Сёнэн'), findsOneWidget);
    expect(find.text('Экшен'), findsOneWidget);
  });

  test('UserProfile handles bio, badgeId and seamless serialization', () {
    final guest = UserProfile.guest('guest_999');
    expect(guest.badgeId, 'sync_master');
    expect(guest.bio, isNull);

    final customized = guest.copyWith(
      bio: 'Я стану Королем Пиратов!',
      badgeId: 'marathon_100',
      customTitle: 'Хокаге Деревни',
      frameId: 'void_arcana',
      backgroundId: 'solo_leveling',
    );

    expect(customized.bio, 'Я стану Королем Пиратов!');
    expect(customized.badgeId, 'marathon_100');
    expect(customized.frameId, 'void_arcana');
    expect(customized.backgroundId, 'solo_leveling');

    final json = customized.toJson();
    final restored = UserProfile.fromJson(json);
    expect(restored.bio, 'Я стану Королем Пиратов!');
    expect(restored.badgeId, 'marathon_100');
    expect(restored.frameId, 'void_arcana');
    expect(restored.backgroundId, 'solo_leveling');
  });

  test('AuthRepositoryImpl seamlessly preserves guest art, frame, nickname and status upon email auth', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = AuthRepositoryImpl(prefs);

    // 1. Пользователь в гостевом режиме кастомизирует профиль
    await repo.updateProfile(
      username: 'Shadow Lord',
      avatarUrl: 'https://images.unsplash.com/photo-test.jpg',
      frameId: 'glacial_frost',
      backgroundId: 'solo_leveling',
      customTitle: 'Король Пиратов',
      customStatus: 'В соло на 100 этаже',
      bio: 'Свет порождает тень',
      badgeId: 'marathon_100',
      accentColor: '#00E5FF',
    );

    final guestProfile = await repo.getCurrentProfile();
    expect(guestProfile.username, 'Shadow Lord');
    expect(guestProfile.frameId, 'glacial_frost');
    expect(guestProfile.backgroundId, 'solo_leveling');
    expect(guestProfile.bio, 'Свет порождает тень');
    expect(guestProfile.isAnonymous, isTrue);

    // 2. Пользователь регистрируется через Email/Password
    final authProfile = await repo.signUpWithEmail(
      email: 'shadow@example.com',
      password: 'password123',
      username: 'Shadow Monarch',
    );

    // 3. ПРОВЕРКА: Никакие кастомные данные НЕ сбросились!
    expect(authProfile.isAnonymous, isFalse);
    expect(authProfile.username, 'Shadow Monarch');
    expect(authProfile.frameId, 'glacial_frost');
    expect(authProfile.backgroundId, 'solo_leveling');
    expect(authProfile.customTitle, 'Король Пиратов');
    expect(authProfile.customStatus, 'В соло на 100 этаже');
    expect(authProfile.bio, 'Свет порождает тень');
    expect(authProfile.badgeId, 'marathon_100');
    expect(authProfile.accentColor, '#00E5FF');
    expect(authProfile.avatarUrl, 'https://images.unsplash.com/photo-test.jpg');
  });

  test('Steam customizer features: frames, backdrops, badges, custom URLs', () {
    expect(SteamAvatarFrame.all.length, greaterThanOrEqualTo(18));
    expect(SteamBackgroundTheme.all.length, greaterThanOrEqualTo(23));
    expect(SteamBadge.all.length, greaterThanOrEqualTo(8));

    // Проверка разрешения значков
    final badge = SteamBadge.fromId('pioneer');
    expect(badge.title, 'Первопроходец SyncPai');
    expect(badge.level, 99);

    // Проверка новых рамок
    expect(SteamAvatarFrame.all.any((f) => f.id == 'blood_moon'), isTrue);
    expect(SteamAvatarFrame.all.any((f) => f.id == 'terminal_matrix'), isTrue);
    expect(SteamAvatarFrame.all.any((f) => f.id == 'cyber_samurai'), isTrue);

    // Проверка кастомных ссылок и GIF
    const customGifUrl = 'https://media.tenor.com/anime_solo_leveling.gif';
    final customTheme = SteamBackgroundTheme.fromId(customGifUrl);
    expect(customTheme.assetOrUrl, customGifUrl);
    expect(customTheme.name, 'Пользовательский арт / GIF');
  });

  testWidgets('AuthModalSheet renders tabs, input fields and Google button', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final guest = UserProfile.guest('g_1');

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AuthCubit>()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AuthModalSheet(currentProfile: guest),
          ),
        ),
      ),
    );

    expect(find.text('Синхронизация профиля'), findsOneWidget);
    expect(find.textContaining('Ваш текущий кастомный арт'), findsOneWidget);
    expect(find.text('Вход'), findsOneWidget);
    expect(find.text('Регистрация'), findsOneWidget);
    expect(find.text('Продолжить через Google'), findsOneWidget);
    expect(find.text('Войти в аккаунт'), findsOneWidget);

    // Переключение на вкладку "Регистрация"
    await tester.tap(find.text('Регистрация'));
    await tester.pumpAndSettle();

    expect(find.text('Никнейм в приложении'), findsOneWidget);
    expect(find.text('Повторите пароль'), findsOneWidget);
    expect(find.text('Зарегистрироваться и перенести профиль'), findsOneWidget);
  });

  test('UserAnimeEntry name matching seamlessly maps Anixart entries to AniLibria catalog titles', () {
    const catalogTitles = [
      AnimeTitle(
        id: 10338,
        code: 'frieren',
        russianTitle: 'Фрирен, провожающая в последний путь',
        englishTitle: 'Sousou no Frieren',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Фэнтези'],
        description: '',
        status: 'Завершен',
      ),
      AnimeTitle(
        id: 8789,
        code: 'jujutsu-kaisen',
        russianTitle: 'Магическая битва',
        englishTitle: 'Jujutsu Kaisen',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        genres: ['Экшен'],
        description: '',
        status: 'Завершен',
      ),
    ];

    // Запись из Anixart с чужим Shikimori ID (например 5114 или 99999)
    final anixartEntry = UserAnimeEntry(
      id: 'anx_1',
      userId: 'u_1',
      animeId: 99999,
      titleRu: 'Магическая битва',
      status: AnimeListStatus.watching,
      lastEpisode: 12,
      updatedAt: DateTime.now(),
    );

    // Проверяем сопоставление по имени
    final matched = catalogTitles.firstWhere(
      (t) =>
          t.id == anixartEntry.animeId ||
          t.russianTitle.toLowerCase().trim() == anixartEntry.titleRu.toLowerCase().trim() ||
          (t.englishTitle.isNotEmpty &&
              t.englishTitle.toLowerCase().trim() == anixartEntry.titleRu.toLowerCase().trim()),
    );

    expect(matched.id, 8789);
    expect(matched.russianTitle, 'Магическая битва');
  });

  test('AnimeClip domain entity formatting and serialization', () {
    const clip = AnimeClip(
      id: 'clip_solo',
      animeId: 10344,
      animeTitle: 'Поднятие уровня в одиночку',
      englishTitle: 'Solo Leveling',
      posterUrl: 'https://example.com/poster.jpg',
      episodeNumber: 12,
      targetTimestampSeconds: 1115, // 18:35
      caption: '🔥 Восстань!',
      videoUrl: 'https://example.com/clip.mp4',
      likesCount: 28400,
      tags: ['#sololeveling', '#arise'],
    );

    expect(clip.formattedTimestamp, '18:35');
    expect(clip.timecodeLabel, 'Серия 12 • 18:35');

    // Проверяем 1 час+ таймкод
    final longClip = clip.copyWith(targetTimestampSeconds: 3725);
    expect(longClip.formattedTimestamp, '1:02:05');

    // Проверяем JSON сериализацию
    final json = clip.toJson();
    expect(json['id'], 'clip_solo');
    expect(json['animeId'], 10344);
    expect(json['episodeNumber'], 12);

    final fromJson = AnimeClip.fromJson(json);
    expect(fromJson.id, clip.id);
    expect(fromJson.animeTitle, clip.animeTitle);
    expect(fromJson.targetTimestampSeconds, 1115);
  });

  test('AnimeClipsDataSource & AnimeClipsRepository manage clips, likes and bookmarks', () async {
    final prefs = getIt<SharedPreferences>();
    final ds = AnimeClipsDataSourceImpl(prefs);
    final repo = AnimeClipsRepositoryImpl(ds);

    final clips = await repo.getClips();
    expect(clips.isNotEmpty, isTrue);
    expect(clips.any((c) => c.animeTitle.contains('Поднятие уровня')), isTrue);
    expect(clips.any((c) => c.animeTitle.contains('Магическая битва')), isTrue);
    expect(clips.any((c) => c.animeTitle.contains('Клинок, рассекающий демонов')), isTrue);

    // Тестируем лайк
    final firstClipId = clips.first.id;
    final liked = await repo.toggleLike(firstClipId);
    expect(liked, isTrue);
    final unliked = await repo.toggleLike(firstClipId);
    expect(unliked, isFalse);

    // Тестируем закладку
    final bookmarked = await repo.toggleBookmark(firstClipId);
    expect(bookmarked, isTrue);
    final unbookmarked = await repo.toggleBookmark(firstClipId);
    expect(unbookmarked, isFalse);
  });

  testWidgets('ClipBottomOverlay renders title, timestamp and triggers watch callback', (tester) async {
    const testClip = AnimeClip(
      id: 'test_clip',
      animeId: 10344,
      animeTitle: 'Поднятие уровня в одиночку',
      englishTitle: 'Solo Leveling',
      posterUrl: '',
      episodeNumber: 12,
      targetTimestampSeconds: 1115,
      caption: '🔥 Сон Джин-ву призывает Игриса',
      videoUrl: '',
    );

    bool watched = false;
    bool openedDetails = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClipBottomOverlay(
            clip: testClip,
            onWatchFromMoment: () => watched = true,
            onOpenDetails: () => openedDetails = true,
          ),
        ),
      ),
    );

    expect(find.text('Поднятие уровня в одиночку'), findsOneWidget);
    expect(find.text('Solo Leveling'), findsOneWidget);
    expect(find.text('Эп. 12'), findsOneWidget);
    expect(find.textContaining('Смотреть с этого момента (18:35)'), findsOneWidget);

    // Тап на кнопку просмотра с момента
    await tester.tap(find.textContaining('Смотреть с этого момента'));
    expect(watched, isTrue);

    // Тап на название тайтла для открытия страницы
    await tester.tap(find.text('Поднятие уровня в одиночку'));
    expect(openedDetails, isTrue);
  });

  testWidgets('ClipSideActions renders like, bookmark, open details and triggers callbacks', (tester) async {
    const testClip = AnimeClip(
      id: 'test_clip',
      animeId: 10344,
      animeTitle: 'Поднятие уровня в одиночку',
      englishTitle: 'Solo Leveling',
      posterUrl: '',
      episodeNumber: 12,
      targetTimestampSeconds: 1115,
      caption: '',
      videoUrl: '',
      likesCount: 15400,
    );

    bool liked = false;
    bool bookmarked = false;
    bool openedDetails = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClipSideActions(
            clip: testClip,
            onToggleLike: () => liked = true,
            onToggleBookmark: () => bookmarked = true,
            onOpenDetails: () => openedDetails = true,
          ),
        ),
      ),
    );

    expect(find.text('15.4k'), findsOneWidget);
    expect(find.text('В список'), findsOneWidget);
    expect(find.text('О тайтле'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    expect(liked, isTrue);

    await tester.tap(find.byIcon(Icons.bookmark_outline_rounded));
    expect(bookmarked, isTrue);

    await tester.tap(find.text('О тайтле'));
    expect(openedDetails, isTrue);
  });

  test('ThemePreset has 13 curated presets with unique IDs and valid colors', () {
    expect(ThemePreset.all.length, 13);
    final ids = ThemePreset.all.map((p) => p.id).toSet();
    expect(ids.length, 13);

    final sunset = ThemePreset.fromId('sunset_orange');
    expect(sunset.name, 'Мандарин Сенпай');
    expect(sunset.primaryColor, const Color(0xFFE06C53));

    final cyber = ThemePreset.fromId('cyber_cyan');
    expect(cyber.name, 'Кибер Неон');
    expect(cyber.primaryColor, const Color(0xFF00E5FF));

    final amoled = ThemePreset.fromId('amoled_black');
    expect(amoled.name, 'AMOLED Черный');
    expect(amoled.backgroundColor, const Color(0xFF000000));

    final sapphire = ThemePreset.fromId('sapphire_blue');
    expect(sapphire.name, 'Сапфировый Синий');
    expect(sapphire.primaryColor, const Color(0xFF2979FF));

    final midnight = ThemePreset.fromId('midnight_navy');
    expect(midnight.name, 'Полуночный Неви');

    final amethyst = ThemePreset.fromId('phantom_amethyst');
    expect(amethyst.name, 'Королевский Аметист');
  });

  test('ThemeCubit switches presets, persists to SharedPreferences and creates ThemeData', () async {
    final prefs = getIt<SharedPreferences>();
    final cubit = ThemeCubit(prefs);

    expect(cubit.state.currentPreset.id, 'sunset_orange');
    expect(cubit.state.themeData.primaryColor, const Color(0xFFE06C53));

    // Переключаем на Cyber Cyan
    final cyberPreset = ThemePreset.fromId('cyber_cyan');
    await cubit.setPreset(cyberPreset);

    expect(cubit.state.currentPreset.id, 'cyber_cyan');
    expect(cubit.state.themeData.primaryColor, const Color(0xFF00E5FF));
    expect(prefs.getString('syncpai_theme_preset_id'), 'cyber_cyan');

    // Возвращаем Sunset
    await cubit.setPreset(ThemePreset.all.first);
  });

  testWidgets('ThemeSelectorSheet renders 8 theme choices and allows picking', (tester) async {
    final cubit = getIt<ThemeCubit>();

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ThemeSelectorSheet(),
          ),
        ),
      ),
    );

    expect(find.text('Цветовая палитра'), findsOneWidget);
    expect(find.text('Мандарин Сенпай'), findsOneWidget);
    expect(find.text('Кибер Неон'), findsOneWidget);
    expect(find.text('Евангелион Фиолет'), findsOneWidget);
    expect(find.text('Розовая Сакура'), findsOneWidget);

    // Выбираем Кибер Неон
    await tester.tap(find.text('Кибер Неон'));
    await tester.pumpAndSettle();

    expect(cubit.state.currentPreset.id, 'cyber_cyan');

    // Возвращаем в исходное
    await cubit.setPreset(ThemePreset.all.first);
  });

  testWidgets('SplashScreen renders mascot logo, title, and interactive palette selector', (tester) async {
    final cubit = getIt<ThemeCubit>();

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cubit),
        ],
        child: const MaterialApp(
          home: SplashScreen(),
        ),
      ),
    );

    expect(find.byType(SyncPaiLogo), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('SyncPai')), findsOneWidget);
    expect(find.text('Смотри аниме синхронно с друзьями'), findsOneWidget);
    expect(find.text('Примерить тему оформления:'), findsOneWidget);
    expect(find.text('Все 13 тем ›'), findsOneWidget);
  });

  test('AuthRepository linkGoogleAccount safely preserves custom art, nickname and frame', () async {
    final prefs = getIt<SharedPreferences>();
    final repo = AuthRepositoryImpl(prefs);

    // Устанавливаем кастомный профиль пользователя с артом, рамкой и статусом
    await repo.updateProfile(
      username: 'СуперСенпай',
      avatarUrl: 'https://images.unsplash.com/custom_art.jpg',
      frameId: 'neon_cyber_ring',
      backgroundId: 'cyberpunk_alley',
      customTitle: 'Легенда Аниме',
      customStatus: 'Смотрю финал сезона',
    );

    // Связываем аккаунт с Google
    final linked = await repo.linkGoogleAccount(
      email: 'senpai.user@gmail.com',
      displayName: 'Google Default Name',
      photoUrl: 'https://lh3.googleusercontent.com/default_google.png',
    );

    // Проверяем, что кастомные данные НЕ сбросились, а email и провайдер привязались
    expect(linked.isAnonymous, isFalse);
    expect(linked.provider, 'google');
    expect(linked.email, 'senpai.user@gmail.com');
    expect(linked.username, 'СуперСенпай');
    expect(linked.avatarUrl, 'https://images.unsplash.com/custom_art.jpg');
    expect(linked.frameId, 'neon_cyber_ring');
    expect(linked.backgroundId, 'cyberpunk_alley');
    expect(linked.customTitle, 'Легенда Аниме');
    expect(linked.customStatus, 'Смотрю финал сезона');
  });

  testWidgets('SavedAnimeScreen supports switching between List, Grid and Card modes', (tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AnimeListCubit>()),
          BlocProvider.value(value: getIt<WatchHistoryCubit>()),
        ],
        child: const MaterialApp(
          home: SavedAnimeScreen(),
        ),
      ),
    );

    // Initial check: header and view mode switcher buttons
    expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.byIcon(Icons.view_agenda_rounded), findsOneWidget);

    // Tap Grid mode
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();

    // Verify column toggle button is shown in grid mode
    expect(find.byIcon(Icons.view_column_rounded), findsOneWidget);
    expect(find.text('3 к.'), findsOneWidget);

    // Toggle column count to 2
    await tester.tap(find.byIcon(Icons.view_column_rounded));
    await tester.pumpAndSettle();
    expect(find.text('2 к.'), findsOneWidget);

    // Tap History tab
    expect(find.text('История'), findsOneWidget);
    await tester.tap(find.text('История'));
    await tester.pumpAndSettle();

    // Tap Card mode
    await tester.tap(find.byIcon(Icons.view_agenda_rounded));
    await tester.pumpAndSettle();

    // Tap List mode
    await tester.tap(find.byIcon(Icons.view_list_rounded));
    await tester.pumpAndSettle();
  });

  testWidgets('WatchTogetherScreen opens room creation bottom sheet with options', (tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AuthCubit>()),
          BlocProvider(
            create: (_) => CatalogCubit(
              getUpdates: getIt<GetUpdates>(),
              searchTitles: getIt<SearchTitles>(),
              prefs: getIt<SharedPreferences>(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: WatchTogetherScreen(),
        ),
      ),
    );

    // Find and tap 'Создать свою комнату'
    final createBtn = find.text('Создать свою комнату');
    expect(createBtn, findsOneWidget);
    await tester.tap(createBtn);
    await tester.pumpAndSettle();

    // Check bottom sheet contents
    expect(find.text('Создание комнаты'), findsOneWidget);
    expect(find.text('Количество участников:'), findsOneWidget);
    expect(find.text('Текстовый Twitch-чат в углу'), findsOneWidget);
    expect(find.text('Быстрые ответы и реакции'), findsOneWidget);
    expect(find.text('Создать комнату и открыть лобби'), findsOneWidget);
  });

  testWidgets('SteamAvatarFrameWidget renders radiating aura and particles animation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SteamAvatarFrameWidget(
            frameId: 'fire_dragon_aura',
            size: 96,
            child: CircleAvatar(radius: 40, child: Text('SP')),
          ),
        ),
      ),
    );

    expect(find.byType(SteamAvatarFrameWidget), findsOneWidget);
    expect(find.text('SP'), findsOneWidget);

    // Advance frame for animation ticking
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('FranchiseProgressionChart renders dynamic bars with scores and 10.0 scale height', (tester) async {
    const r1 = RelatedAnimeRelease(
      id: '1',
      title: 'Сезон 1',
      rating: 8.5,
      isCurrent: true,
      relation: 'Основная история',
      posterUrl: 'https://cdn.example.com/poster.jpg',
    );
    const r2 = RelatedAnimeRelease(
      id: '2',
      title: 'Сезон 2',
      rating: 8.0,
      isCurrent: false,
      relation: 'Продолжение',
      posterUrl: 'https://cdn.example.com/poster.jpg',
    );
    const r3 = RelatedAnimeRelease(
      id: '3',
      title: 'Сезон 3',
      rating: 7.9,
      isCurrent: false,
      relation: 'Продолжение',
      posterUrl: 'https://cdn.example.com/poster.jpg',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FranchiseProgressionChart(
            releases: [r1, r2, r3],
          ),
        ),
      ),
    );

    expect(find.text('Динамика сезонов'), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
    expect(find.text('8.0'), findsOneWidget);
    expect(find.text('7.9'), findsOneWidget);
  });

  testWidgets('ClipBottomOverlay displays 2-line title and episode badge', (tester) async {
    const clip = AnimeClip(
      id: 'clip_frieren',
      animeId: 10450,
      animeTitle: 'Провожающая в последний путь Фрирен',
      englishTitle: 'Sousou no Frieren',
      posterUrl: 'https://example.com/frieren.jpg',
      episodeNumber: 8,
      targetTimestampSeconds: 1125,
      caption: 'Эпическая битва магии',
      videoUrl: 'https://example.com/frieren.mp4',
      likesCount: 1420,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClipBottomOverlay(
            clip: clip,
            onWatchFromMoment: () {},
            onOpenDetails: () {},
          ),
        ),
      ),
    );

    expect(find.text('Провожающая в последний путь Фрирен'), findsOneWidget);
    expect(find.text('Эп. 8'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && w.data != null && w.data!.contains('Смотреть с этого момента')), findsOneWidget);
  });

  testWidgets('SavedAnimeScreen opens sort sheet and switches sort order', (tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: getIt<AnimeListCubit>()),
          BlocProvider.value(value: getIt<WatchHistoryCubit>()),
        ],
        child: const MaterialApp(
          home: SavedAnimeScreen(),
        ),
      ),
    );

    final sortBtn = find.byIcon(Icons.sort_rounded);
    expect(sortBtn, findsOneWidget);
    await tester.tap(sortBtn);
    await tester.pumpAndSettle();

    expect(find.text('Сортировка списка'), findsOneWidget);
    expect(find.text('По дате обновления'), findsOneWidget);
    expect(find.text('По алфавиту (А–Я)'), findsOneWidget);
    expect(find.text('По прогрессу серий'), findsOneWidget);

    await tester.tap(find.text('По алфавиту (А–Я)'));
    await tester.pumpAndSettle();
  });

  test('DownloadCubit startSmartDownload queues next episode and onEpisodeFinished deletes watched', () async {
    final dlCubit = getIt<DownloadCubit>();
    expect(dlCubit.state.smartDownloadsEnabled, isTrue);

    const testTitle = AnimeTitle(
      id: 9999,
      code: 'smart-dl-anime',
      russianTitle: 'Умная Загрузка Аниме',
      englishTitle: 'Smart Download Anime',
      episodes: [
        EpisodeItem(episode: 1, name: 'Серия 1', fhdUrl: 'https://cdn.example.com/ep1.mp4'),
        EpisodeItem(episode: 2, name: 'Серия 2', fhdUrl: 'https://cdn.example.com/ep2.mp4'),
        EpisodeItem(episode: 3, name: 'Серия 3', fhdUrl: 'https://cdn.example.com/ep3.mp4'),
      ],
      genres: ['Приключения'],
      description: 'Тест умных загрузок',
      status: 'Выходит',
      posterSmall: 'https://cdn.example.com/poster.jpg',
      posterMedium: 'https://cdn.example.com/poster.jpg',
      posterOriginal: 'https://cdn.example.com/poster.jpg',
    );

    // 1. Запуск умной загрузки серии 1 -> ставит в очередь и серию 1, и серию 2
    await dlCubit.startSmartDownload(
      title: testTitle,
      episode: testTitle.episodes[0],
      quality: '1080p FHD',
    );

    final id1 = DownloadTask.generateId(testTitle.id, 1);
    final id2 = DownloadTask.generateId(testTitle.id, 2);
    final id3 = DownloadTask.generateId(testTitle.id, 3);

    expect(dlCubit.state.tasks.containsKey(id1), isTrue);
    expect(dlCubit.state.tasks.containsKey(id2), isTrue);

    // 2. Серия 1 досмотрена -> удаляет серию 1 и ставит серию 3
    await dlCubit.onEpisodeFinished(
      titleId: testTitle.id,
      finishedEpisode: 1,
      title: testTitle,
    );

    expect(dlCubit.state.tasks.containsKey(id1), isFalse);
    expect(dlCubit.state.tasks.containsKey(id3), isTrue);

    // Очистка
    await dlCubit.deleteDownload(id2);
    await dlCubit.deleteDownload(id3);
  });

  group('Kodik Voiceover & Video Stream Integration Tests', () {
    test('KodikTranslation entity correctly identifies AniLibria and Subtitles', () {
      final anilibria = KodikTranslation.anilibria();
      expect(anilibria.id, 0);
      expect(anilibria.isAniLibria, isTrue);
      expect(anilibria.displayIcon, '🎙️');

      const subs = KodikTranslation(
        id: 10,
        title: 'Субтитры (SRT)',
        type: 'subtitles',
        episodesCount: 12,
      );
      expect(subs.isAniLibria, isFalse);
      expect(subs.isSubtitles, isTrue);
      expect(subs.displayIcon, '💬');

      const studioBand = KodikTranslation(
        id: 609,
        title: 'StudioBand',
        type: 'voice',
        episodesCount: 24,
      );
      expect(studioBand.isAniLibria, isFalse);
      expect(studioBand.isSubtitles, isFalse);
      expect(studioBand.displayIcon, '🎙️');

      final json = studioBand.toJson();
      expect(json['title'], 'StudioBand');
      expect(json['episodes_count'], 24);
    });

    test('KodikStreamExtractor Caesar decryption works as expected', () {
      final decrypted = KodikStreamExtractor.caesarDecrypt('uryyb', shift: 13);
      expect(decrypted, 'hello');

      const text = 'KodikStream2024';
      final enc = KodikStreamExtractor.caesarDecrypt(text, shift: 13);
      final dec = KodikStreamExtractor.caesarDecrypt(enc, shift: 13);
      expect(dec, text);
    });

    test('KodikCubit loads translations and selects studio with preferences saved', () async {
      SharedPreferences.setMockInitialValues({'sync_pai_preferred_voiceover': 'StudioBand'});
      final prefs = await SharedPreferences.getInstance();

      final fakeDs = FakeKodikRemoteDataSource();
      final fakeExtractor = FakeKodikStreamExtractor();
      final cubit = KodikCubit(
        dataSource: fakeDs,
        extractor: fakeExtractor,
        prefs: prefs,
      );

      // 1. Initial state has AniLibria default
      expect(cubit.state.isAniLibriaActive, isTrue);

      // 2. Load voiceovers -> matches saved 'StudioBand'
      await cubit.loadVoiceovers(shikimoriId: 12345, title: 'Frieren');
      expect(cubit.state.translations.length, greaterThanOrEqualTo(3));
      expect(cubit.state.selectedTranslation.title, 'StudioBand');
      expect(cubit.state.isAniLibriaActive, isFalse);

      // 3. Resolve direct stream for episode 1
      final streamUrl = await cubit.getStreamForEpisode(1);
      expect(streamUrl, contains('.m3u8'));
      expect(cubit.state.resolvedStreamUrl, streamUrl);

      // 4. Switch back to AniLibria
      await cubit.selectVoiceover(KodikTranslation.anilibria());
      expect(cubit.state.isAniLibriaActive, isTrue);
      expect(prefs.getString('sync_pai_preferred_voiceover'), 'AniLibria');

      // 5. AniLibria stream resolution returns null (uses AniLibria HLS directly)
      final anilibriaStream = await cubit.getStreamForEpisode(1);
      expect(anilibriaStream, isNull);
    });

    testWidgets('VoiceoverSelectorSheet renders list and responds to selection', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final fakeDs = FakeKodikRemoteDataSource();
      final fakeExtractor = FakeKodikStreamExtractor();
      final cubit = KodikCubit(
        dataSource: fakeDs,
        extractor: fakeExtractor,
        prefs: prefs,
      );

      await cubit.loadVoiceovers(title: 'Frieren');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.cinemaDark,
          home: Scaffold(
            body: BlocProvider.value(
              value: cubit,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => VoiceoverSelectorSheet.show(context, episodeNumber: 1),
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Check title and translations are rendered
      expect(find.text('Озвучка и перевод'), findsOneWidget);
      expect(find.text('AniLibria'), findsOneWidget);
      expect(find.text('Рекомендуется'), findsOneWidget);
      expect(find.text('Dream Cast'), findsOneWidget);
      expect(find.text('StudioBand'), findsOneWidget);

      // Tap 'Dream Cast'
      await tester.tap(find.text('Dream Cast'));
      await tester.pumpAndSettle();

      // Sheet is closed and Dream Cast is selected in cubit
      expect(cubit.state.selectedTranslation.title, 'Dream Cast');
    });

    testWidgets('AnimeDetailsScreen renders voiceover selector chip', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final fakeDs = FakeKodikRemoteDataSource();
      final fakeExtractor = FakeKodikStreamExtractor();
      final cubit = KodikCubit(
        dataSource: fakeDs,
        extractor: fakeExtractor,
        prefs: prefs,
      );

      if (getIt.isRegistered<KodikCubit>()) {
        getIt.unregister<KodikCubit>();
      }
      getIt.registerSingleton<KodikCubit>(cubit);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.cinemaDark,
          home: AnimeDetailsScreen(
            title: testTitle,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Selector chip is visible in AnimeDetailsScreen
      expect(find.textContaining('Озвучка:'), findsWidgets);
      expect(find.text(cubit.state.activeVoiceoverTitle), findsWidgets);
    });
  });

  group('Anixart Title Cleaning & Batch Edit Tests', () {
    test('AnixartCsvParser.cleanTitle cleanly parses dirty CSV rows and quotes', () {
      const rawLine = '6 / "Аля иногда кокетничает со мной по-русски 2" / "Tokidoki..." / 1-12 / В планах / Не оценено';
      final cleaned = AnixartCsvParser.cleanTitle(rawLine);
      expect(cleaned, 'Аля иногда кокетничает со мной по-русски 2');

      const rawWithQuotes = '"Поднятие уровня в одиночку" / "Solo Leveling" / 1-12 / Смотрю / 10';
      expect(AnixartCsvParser.cleanTitle(rawWithQuotes), 'Поднятие уровня в одиночку');

      const plainTitle = 'Магическая битва 2';
      expect(AnixartCsvParser.cleanTitle(plainTitle), 'Магическая битва 2');
    });

    test('UserAnimeEntry.cleanTitleRu dynamically strips dirty prefixes', () {
      final entry = UserAnimeEntry(
        id: 'test_1',
        userId: 'u1',
        animeId: 4821,
        titleRu: '6 / "Аля иногда кокетничает со мной по-русски 2" / "Tokidoki..."',
        status: AnimeListStatus.planned,
        updatedAt: DateTime.now(),
      );
      expect(entry.cleanTitleRu, 'Аля иногда кокетничает со мной по-русски 2');
    });

    test('AnimeListCubit batchChangeStatus, updatePosterUrl and batchDelete work correctly', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = AnimeListRepositoryImpl(prefs);
      final cubit = AnimeListCubit(repository: repo);

      await cubit.setAnimeStatus(
        animeId: 101,
        titleRu: 'Тайтл 1',
        status: AnimeListStatus.planned,
      );
      await cubit.setAnimeStatus(
        animeId: 102,
        titleRu: 'Тайтл 2',
        status: AnimeListStatus.planned,
      );

      expect(cubit.state.entriesFor(AnimeListStatus.planned).length, 2);

      // Batch move to watching
      await cubit.batchChangeStatus([101, 102], AnimeListStatus.watching);
      expect(cubit.state.entriesFor(AnimeListStatus.watching).length, 2);
      expect(cubit.state.entriesFor(AnimeListStatus.planned).length, 0);

      // Update poster url
      await cubit.updatePosterUrl(101, 'https://example.com/poster101.jpg');
      expect(cubit.state.getEntryFor(101)?.posterUrl, 'https://example.com/poster101.jpg');

      // Batch delete
      await cubit.batchDelete([101, 102]);
      expect(cubit.state.entriesFor(AnimeListStatus.watching).length, 0);
    });

    testWidgets('SteamAvatarFrameWidget renders glacial_frost frame with crystal shards', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SteamAvatarFrameWidget(
                frameId: 'glacial_frost',
                size: 64,
                child: SizedBox(width: 64, height: 64),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SteamAvatarFrameWidget), findsOneWidget);
    });

    test('PlayerState manages 2X fast forward state properly', () {
      const state = PlayerState(
        title: testTitle,
        episode: EpisodeItem(episode: 1),
      );

      expect(state.is2xFastForwarding, false);
      final fastState = state.copyWith(is2xFastForwarding: true);
      expect(fastState.is2xFastForwarding, true);
      final normalState = fastState.copyWith(is2xFastForwarding: false);
      expect(normalState.is2xFastForwarding, false);
    });

    testWidgets('DoubleTapSeekOverlay triggers 2X speed on long press start and end', (tester) async {
      bool speedUpStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DoubleTapSeekOverlay(
              onTap: () {},
              onSeekRelative: (_) {},
              onLongPressStart: () => speedUpStarted = true,
              onLongPressEnd: () {},
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(GestureDetector).first);
      expect(speedUpStarted, isTrue);
    });

    test('SyncRoomRepositoryImpl joinRoom safely connects guest to room', () async {
      final repo = SyncRoomRepositoryImpl();
      final room = await repo.joinRoom(code: 'SP-4821', peerName: 'Тестовый Друг');

      expect(room.code, 'SP-4821');
      expect(room.status, SyncRoomStatus.connected);
      expect(room.peerName, 'Тестовый Друг');
      expect(room.episode.episode, greaterThanOrEqualTo(1));
    });

    test('SyncRoomRepositoryImpl joinRoom rejects non-existent ghost room', () async {
      final repo = SyncRoomRepositoryImpl();
      expect(
        () => repo.joinRoom(code: 'SP-9999', peerName: 'Ghost'),
        throwsA(isA<Exception>()),
      );
    });

    test('PlayerNavigationGuard blocks rapid double-tap parallel opens', () {
      expect(PlayerNavigationGuard.canOpen(), isTrue);
      // Immediately second call must be blocked
      expect(PlayerNavigationGuard.canOpen(), isFalse);
    });

    group('Supabase Catalog & Player BFF Tests', () {
      test('AnimeCatalogModel serialization and toDomain mapping', () {
        final json = {
          'id': 'uuid-12345',
          'shikimori_id': 51009,
          'title_ru': 'Магическая битва 2',
          'title_en': 'Jujutsu Kaisen 2nd Season',
          'poster_url': 'https://shikimori.me/poster.jpg',
          'kind': 'tv',
          'status': 'ongoing',
          'score': 8.8,
          'episodes_total': 23,
          'updated_at': '2026-11-08T12:00:00.000Z',
        };

        final model = AnimeCatalogModel.fromJson(json);
        expect(model.id, 'uuid-12345');
        expect(model.shikimoriId, 51009);
        expect(model.titleRu, 'Магическая битва 2');
        expect(model.score, 8.8);
        expect(model.status, 'ongoing');

        final domain = model.toDomain();
        expect(domain, isA<AnimeEntity>());
        expect(domain.displayTitle, 'Магическая битва 2');

        final animeTitle = domain.toAnimeTitle();
        expect(animeTitle.id, 51009);
        expect(animeTitle.russianTitle, 'Магическая битва 2');
        expect(animeTitle.status, 'Онгоинг');

        final serialized = model.toJson();
        expect(serialized['shikimori_id'], 51009);
        expect(serialized['score'], 8.8);
      });

      test('AnimePlayerDataModel, TranslationModel and EpisodeModel parsing', () {
        final bffJson = {
          'shikimori_id': 12345,
          'translations': [
            {
              'studio_name': 'AniLibria',
              'translation_type': 'dub',
              'is_direct_stream': true,
              'episodes': [
                {'episode': 1, 'link': 'https://cache.libria.fun/ep1.m3u8'},
                {'episode': 2, 'link': 'https://cache.libria.fun/ep2.m3u8'}
              ]
            },
            {
              'studio_name': 'StudioBand',
              'translation_type': 'dub',
              'is_direct_stream': false,
              'iframe_url': 'https://kodik.info/video/sb123'
            }
          ]
        };

        final playerData = AnimePlayerDataModel.fromJson(bffJson);
        expect(playerData.shikimoriId, 12345);
        expect(playerData.translations.length, 2);

        final direct = playerData.translations.first.toDomain();
        expect(direct.studioName, 'AniLibria');
        expect(direct.isDirectStream, isTrue);
        expect(direct.getStreamForEpisode(2), 'https://cache.libria.fun/ep2.m3u8');

        final iframe = playerData.translations.last.toDomain();
        expect(iframe.studioName, 'StudioBand');
        expect(iframe.isDirectStream, isFalse);
        expect(iframe.iframeUrl, 'https://kodik.info/video/sb123');
      });

      test('GetCatalogUseCase and GetPlayerLinksUseCase interact with repository', () async {
        final mockRepo = _MockAnimeCatalogRepository();
        final getCatalog = GetCatalogUseCase(mockRepo);
        final getLinks = GetPlayerLinksUseCase(mockRepo);

        final catalog = await getCatalog(page: 1, limit: 10);
        expect(catalog.length, 1);
        expect(catalog.first.titleRu, 'Тестовое Аниме');

        final links = await getLinks(99999);
        expect(links.length, 1);
        expect(links.first.studioName, 'AniLibria');
        expect(links.first.isDirectStream, isTrue);
      });

      test('AnimeCatalogModel maps PostgreSQL anime_catalog fields accurately', () {
        final json = {
          'id': 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
          'shikimori_id': 57584,
          'title_ru': 'Восхождение в тени! Реверберация',
          'title_en': 'Kage no Jitsuryokusha ni Naritakute! Movie: Zankoku-hen',
          'poster_url': 'https://desu.shikimori.me/original/57584.jpg',
          'score': 8.74,
          'episodes_total': 1,
          'kind': 'movie',
          'status': 'released',
        };

        final model = AnimeCatalogModel.fromJson(json);
        expect(model.id, 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d');
        expect(model.shikimoriId, 57584);
        expect(model.titleRu, 'Восхождение в тени! Реверберация');
        expect(model.posterUrl, 'https://desu.shikimori.me/original/57584.jpg');
        expect(model.score, 8.74);
        expect(model.episodesTotal, 1);

        final entity = model.toDomain();
        expect(entity.shikimoriId, 57584);

        final animeTitle = entity.toAnimeTitle();
        expect(animeTitle.id, 57584);
        expect(animeTitle.russianTitle, 'Восхождение в тени! Реверберация');
        expect(animeTitle.posterOriginal, 'https://desu.shikimori.me/original/57584.jpg');
      });

      test('AnimeCatalogModel.fromShikimori parses Shikimori API structure correctly', () {
        final shikimoriJson = {
          'id': 57584,
          'name': 'Kage no Jitsuryokusha ni Naritakute! Movie: Zankoku-hen',
          'russian': 'Восхождение в тени! Реверберация',
          'image': {
            'original': '/system/animes/original/57584.jpg',
            'preview': '/system/animes/preview/57584.jpg',
          },
          'score': '8.74',
          'episodes': 1,
          'kind': 'movie',
          'status': 'released',
        };

        final model = AnimeCatalogModel.fromShikimori(shikimoriJson);
        expect(model.id, '57584');
        expect(model.shikimoriId, 57584);
        expect(model.titleRu, 'Восхождение в тени! Реверберация');
        expect(model.titleEn, 'Kage no Jitsuryokusha ni Naritakute! Movie: Zankoku-hen');
        expect(model.posterUrl, 'https://shikimori.io/system/animes/original/57584.jpg');
        expect(model.score, 8.74);
        expect(model.episodesTotal, 1);
      });

      test('SearchCatalogUseCase queries anime_catalog in PostgreSQL', () async {
        final mockRepo = _MockAnimeCatalogRepository();
        final searchUseCase = SearchCatalogUseCase(mockRepo);
        final results = await searchUseCase('Тест', limit: 20);
        expect(results.length, 1);
        expect(results.first.titleRu, 'Тестовое Аниме');
        expect(results.first.shikimoriId, 99999);
      });

      test('Screen Lock state and DoubleTapSeekOverlay gesture protection', () {
        const initialState = PlayerState(
          title: testTitle,
          episode: EpisodeItem(episode: 1),
        );
        expect(initialState.isScreenLocked, isFalse);

        final lockedState = initialState.copyWith(isScreenLocked: true);
        expect(lockedState.isScreenLocked, isTrue);

        final unlockedState = lockedState.copyWith(isScreenLocked: false);
        expect(unlockedState.isScreenLocked, isFalse);
      });
    });

    group('Anixart CSV Bookmark & Room Validation & Auth Tests', () {
      test('AnixartCsvParser parses Anixart_Bookmarks.csv format with index and title columns', () {
        const rawCsv = '''#,Русское название
1,"100 девушек, которые очень-очень-очень-очень-очень сильно тебя любят"
2,"Адский рай"
3,"Адский рай 2"
4,"Аллель Кидзуны"
5,"Аля иногда кокетничает со мной по-русски"
''';
        final rawTitles = AnixartCsvParser.extractRawTitles(rawCsv, defaultStatus: AnimeListStatus.completed);
        expect(rawTitles.length, 5);
        expect(rawTitles[0].title, '100 девушек, которые очень-очень-очень-очень-очень сильно тебя любят');
        expect(rawTitles[0].status, AnimeListStatus.completed);
        expect(rawTitles[1].title, 'Адский рай');
        expect(rawTitles[2].title, 'Адский рай 2');

        final entries = AnixartCsvParser.parseCsv(rawCsv, userId: 'u_user', defaultStatus: AnimeListStatus.planned);
        expect(entries.length, 5);
        expect(entries[0].titleRu, '100 девушек, которые очень-очень-очень-очень-очень сильно тебя любят');
        expect(entries[0].status, AnimeListStatus.planned);
      });

      test('SyncRoomRepository validateRoomExists returns false on invalid random room', () async {
        final repo = getIt<SyncRoomRepository>();
        final exists = await repo.validateRoomExists('RANDOM_NON_EXISTENT_9999');
        expect(exists, isFalse);
      });

      test('SyncRoomRepository validateRoomExists returns true for standard room SP4821', () async {
        final repo = getIt<SyncRoomRepository>();
        final exists = await repo.validateRoomExists('SP4821');
        expect(exists, isTrue);
      });

      testWidgets('WatchTogetherScreen blocks ghost room and shows SnackBar', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: WatchTogetherScreen(),
          ),
        );

        final pinInput = find.byType(TextField);
        expect(pinInput, findsOneWidget);

        await tester.enterText(pinInput, 'GHOST_ROOM_XYZ');
        await tester.pump();

        final joinBtn = find.widgetWithText(ElevatedButton, 'Войти');
        expect(joinBtn, findsOneWidget);
        await tester.tap(joinBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Комната не найдена или сессия завершена'), findsAtLeast(1));
      });

      testWidgets('ImportStatusSelectorDialog renders options and switches category', (tester) async {
        ImportStatusSelection? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    selected = await ImportStatusSelectorDialog.show(
                      context,
                      totalTitlesDetected: 301,
                      fileName: 'Anixart_Bookmarks.csv',
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.text('Импорт закладок Anixart'), findsOneWidget);
        expect(find.textContaining('301 тайтлов в "Anixart_Bookmarks.csv"'), findsOneWidget);
        expect(find.text('Просмотрено'), findsOneWidget);
        expect(find.text('В планах'), findsOneWidget);

        // Тапаем по категории «Просмотрено»
        await tester.tap(find.text('Просмотрено'));
        await tester.pumpAndSettle();

        // Подтверждаем
        await tester.tap(find.text('Начать импорт'));
        await tester.pumpAndSettle();

        expect(selected, isNotNull);
        expect(selected!.defaultStatus, AnimeListStatus.completed);
        expect(selected!.useShikimoriSearch, isTrue);
      });

      testWidgets('ImportProgressDialog updates progress and current title smoothly', (tester) async {
        final progressNotifier = ValueNotifier<ImportProgressData>(
          const ImportProgressData(
            current: 45,
            total: 301,
            currentTitle: '100 девушек...',
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ImportProgressDialog(progressNotifier: progressNotifier),
            ),
          ),
        );

        expect(find.text('Импорт аниме: 45 / 301 (Находим Shikimori ID...)'), findsOneWidget);
        expect(find.textContaining('100 девушек...'), findsOneWidget);
        expect(find.text('14%'), findsOneWidget);

        progressNotifier.value = const ImportProgressData(
          current: 150,
          total: 301,
          currentTitle: 'Адский рай',
        );
        await tester.pump();

        expect(find.text('Импорт аниме: 150 / 301 (Находим Shikimori ID...)'), findsOneWidget);
        expect(find.textContaining('Адский рай'), findsOneWidget);
      });

      testWidgets('AuthScreen renders anime aesthetics, logo, form and Google Sign-In button', (tester) async {
        await tester.pumpWidget(
          BlocProvider.value(
            value: getIt<AuthCubit>(),
            child: const MaterialApp(
              home: AuthScreen(),
            ),
          ),
        );

        expect(find.text('SyncPai'), findsOneWidget);
        expect(find.text('Смотрите аниме синхронно с друзьями'), findsOneWidget);
        expect(find.text('Войти через Google'), findsOneWidget);
        expect(find.text('Продолжить как гость'), findsOneWidget);
        expect(find.text('Email'), findsOneWidget);
        expect(find.text('Пароль'), findsOneWidget);
      });

      test('AnixartCsvParser automatically distributes slash-delimited titles into separate categories', () {
        const slashSample = '''
1 / "100 девушек" / "100 Girlfriends" / Не указаны / Не добавлено в избранное / В планах
2 / "Адский рай" / "Jigokuraku" / Не указаны / Не добавлено в избранное / Просмотрено
4 / "Аллель Кидзуны" / "Kizuna no Allele" / Не указаны / Не добавлено в избранное / Брошено
5 / "Аля кокетничает" / "Alya-san" / Не указаны / В избранном / Смотрю
''';
        final entries = AnixartCsvParser.parseCsv(slashSample);
        expect(entries.length, 4);
        expect(entries[0].titleRu, '100 девушек');
        expect(entries[0].status, AnimeListStatus.planned);
        expect(entries[1].titleRu, 'Адский рай');
        expect(entries[1].status, AnimeListStatus.completed);
        expect(entries[2].titleRu, 'Аллель Кидзуны');
        expect(entries[2].status, AnimeListStatus.dropped);
        expect(entries[3].titleRu, 'Аля кокетничает');
        expect(entries[3].status, AnimeListStatus.watching);
      });

      testWidgets('WatchTogetherScreen shows exact error message when friend is not found', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: const WatchTogetherScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Открываем диалог добавления друга
        final openDialogButton = find.text('Добавить').first;
        expect(openDialogButton, findsOneWidget);
        await tester.tap(openDialogButton);
        await tester.pumpAndSettle();

        // Вводим несуществующего друга
        final input = find.byType(TextField).last;
        await tester.enterText(input, 'NonExistentUserXYZ999');
        await tester.pumpAndSettle();

        // Нажимаем добавить
        final submitButton = find.widgetWithText(ElevatedButton, 'Добавить');
        await tester.tap(submitButton);
        await tester.pump();

        expect(find.text('Такого друга не существует'), findsOneWidget);
      });

      test('CatalogCubit caches category lists in-memory and switches instantaneously without re-fetching', () async {
        int getCatalogCalls = 0;
        final mockRepo = _CountingMockAnimeCatalogRepository(
          onGetCatalog: () => getCatalogCalls++,
        );
        final cubit = CatalogCubit(
          getUpdates: getIt<GetUpdates>(),
          searchTitles: getIt<SearchTitles>(),
          getCatalogUseCase: GetCatalogUseCase(mockRepo),
        );

        // 1. Первая загрузка «Сёнэн» (нет в кэше)
        cubit.onCategoryChanged('Сёнэн');
        await Future.delayed(const Duration(milliseconds: 50));
        expect(cubit.state, isA<CatalogLoaded>());
        expect(getCatalogCalls, 1);
        expect((cubit.state as CatalogLoaded).titles.first.russianTitle, contains('Сёнэн'));

        // 2. Первая загрузка «Экшен» (нет в кэше)
        cubit.onCategoryChanged('Экшен');
        await Future.delayed(const Duration(milliseconds: 50));
        expect(cubit.state, isA<CatalogLoaded>());
        expect(getCatalogCalls, 2);
        expect((cubit.state as CatalogLoaded).titles.first.russianTitle, contains('Экшен'));

        // 3. Возврат на «Сёнэн» — отдается мгновенно из In-Memory кэша, счетчик вызовов не растет!
        cubit.onCategoryChanged('Сёнэн');
        expect(cubit.state, isA<CatalogLoaded>());
        expect(getCatalogCalls, 2); // Снова 2! Никакого сетевого запроса!
        expect((cubit.state as CatalogLoaded).titles.first.russianTitle, contains('Сёнэн'));

        // 4. Пагинация loadMore() прибавляет элементы
        await cubit.loadMore();
        expect(getCatalogCalls, 3);
        expect((cubit.state as CatalogLoaded).currentPage, 2);
      });
    });

    group('Anime Moments & Shorts 3-Player Pool Buffering Tests', () {
      test('AnimeMomentModel fromJson, toJson and toDomain mapping', () {
        final json = {
          'id': 'moment_solo_leveling_arise',
          'anime_id': '10344',
          'title': 'Поднятие уровня в одиночку',
          'description': 'Кульминация сезона! Сон Джин-ву произносит заветное «Восстань»',
          'episode': 12,
          'start_timestamp': 1115,
          'video_url': 'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
          'youtube_id': '9g0H2gKqQ5Y',
          'likes_count': 28420,
        };

        final model = AnimeMomentModel.fromJson(json);
        expect(model.id, 'moment_solo_leveling_arise');
        expect(model.animeId, '10344');
        expect(model.title, 'Поднятие уровня в одиночку');
        expect(model.episode, 12);
        expect(model.startTimestamp, 1115);
        expect(model.youtubeId, '9g0H2gKqQ5Y');
        expect(model.likesCount, 28420);

        final mappedJson = model.toJson();
        expect(mappedJson['id'], 'moment_solo_leveling_arise');
        expect(mappedJson['youtube_id'], '9g0H2gKqQ5Y');

        final domain = model.toDomain(posterUrl: 'https://custom-poster.jpg');
        expect(domain.id, 'moment_solo_leveling_arise');
        expect(domain.animeId, 10344);
        expect(domain.animeTitle, 'Поднятие уровня в одиночку');
        expect(domain.episodeNumber, 12);
        expect(domain.targetTimestampSeconds, 1115);
        expect(domain.posterUrl, 'https://custom-poster.jpg');
        expect(domain.youtubeId, '9g0H2gKqQ5Y');
        expect(domain.youtubeUrl, 'https://www.youtube.com/watch?v=9g0H2gKqQ5Y');
      });

      test('MomentsPlayerPool state and mute control', () {
        final pool = MomentsPlayerPool();
        expect(pool.currentIndex, 0);
        expect(pool.isMuted, isFalse);

        pool.toggleMute();
        expect(pool.isMuted, isTrue);

        pool.toggleMute();
        expect(pool.isMuted, isFalse);

        pool.dispose();
      });

      testWidgets('ShortVideoPlayerItem renders YouTube Shorts card when videoUrl is empty', (tester) async {
        VisibilityDetectorController.instance.updateInterval = Duration.zero;
        const testClip = AnimeClip(
          id: 'moment_yt_only',
          animeId: 10344,
          animeTitle: 'Поднятие уровня в одиночку',
          englishTitle: 'Solo Leveling',
          posterUrl: 'https://desu.shikimori.one/system/animes/original/10344.jpg',
          episodeNumber: 12,
          targetTimestampSeconds: 1115,
          caption: 'Кульминация сезона! Сон Джин-ву произносит заветное «Восстань»',
          videoUrl: '', // Прямого потока нет
          youtubeId: '9g0H2gKqQ5Y',
        );

        bool ytOpened = false;
        bool liked = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ShortVideoPlayerItem(
                clip: testClip,
                isActive: true,
                onOpenYouTube: () => ytOpened = true,
                onDoubleTapLike: () => liked = true,
              ),
            ),
          ),
        );

        expect(find.text('YouTube Shorts'), findsOneWidget);
        expect(find.text('Смотреть в YouTube Shorts'), findsOneWidget);
        expect(find.text('Нативный запуск без лагов WebView'), findsOneWidget);

        // Клик открывает YouTube (выжидаем таймер double-tap в 350 мс)
        await tester.tap(find.text('Смотреть в YouTube Shorts'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(ytOpened, isTrue);

        // Двойной тап вызывает лайк
        await tester.tap(find.byType(ShortVideoPlayerItem));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byType(ShortVideoPlayerItem));
        await tester.pumpAndSettle();
        expect(liked, isTrue);
      });

      testWidgets('MomentsPageView renders PageView with VisibilityDetector items', (tester) async {
        VisibilityDetectorController.instance.updateInterval = Duration.zero;
        final pool = MomentsPlayerPool();
        final controller = PageController();
        const testClips = [
          AnimeClip(
            id: 'clip_1',
            animeId: 10344,
            animeTitle: 'Solo Leveling',
            englishTitle: 'Solo Leveling',
            posterUrl: '',
            episodeNumber: 1,
            targetTimestampSeconds: 100,
            caption: 'Epic moment',
            videoUrl: '',
            youtubeId: 'test_yt_id',
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MomentsPageView(
                clips: testClips,
                pool: pool,
                pageController: controller,
              ),
            ),
          ),
        );

        expect(find.byType(MomentsPageView), findsOneWidget);
        expect(find.byType(PageView), findsOneWidget);
        expect(find.text('Solo Leveling'), findsAtLeastNWidgets(1));

        pool.dispose();
        controller.dispose();
      });
    });
  });
}

class _CountingMockAnimeCatalogRepository implements AnimeCatalogRepository {
  final VoidCallback? onGetCatalog;

  _CountingMockAnimeCatalogRepository({this.onGetCatalog});

  @override
  Future<List<AnimeEntity>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
  }) async {
    onGetCatalog?.call();
    final genreName = genres ?? 'Все';
    return List.generate(
      20,
      (i) => AnimeEntity(
        id: '${genreName}_p${page}_$i',
        shikimoriId: page * 1000 + i,
        titleRu: 'Тайтл $genreName (Стр. $page - $i)',
        titleEn: 'Title $genreName Page $page $i',
        status: 'ongoing',
        score: 9.0,
        episodesTotal: 12,
        genres: [genreName],
      ),
    );
  }

  @override
  Future<List<AnimeEntity>> searchCatalog(String query, {int limit = 30}) async => [];

  @override
  Future<List<TranslationEntity>> getPlayerLinks(int releaseId, {String? title}) async => [];
}

class _MockAnimeCatalogRepository implements AnimeCatalogRepository {
  @override
  Future<List<AnimeEntity>> getCatalog({
    int page = 1,
    int limit = 40,
    String? genres,
    String? year,
  }) async {
    return [
      const AnimeEntity(
        id: 'test-uuid',
        shikimoriId: 99999,
        titleRu: 'Тестовое Аниме',
        titleEn: 'Test Anime',
        status: 'ongoing',
        score: 9.0,
        episodesTotal: 12,
      ),
    ];
  }

  @override
  Future<List<AnimeEntity>> searchCatalog(String query, {int limit = 30}) async {
    return [
      const AnimeEntity(
        id: 'test-uuid',
        shikimoriId: 99999,
        titleRu: 'Тестовое Аниме',
        titleEn: 'Test Anime',
        status: 'ongoing',
        score: 9.0,
        episodesTotal: 12,
      ),
    ];
  }

  @override
  Future<List<TranslationEntity>> getPlayerLinks(int releaseId, {String? title}) async {
    return [
      const TranslationEntity(
        studioName: 'AniLibria',
        translationType: 'dub',
        isDirectStream: true,
        episodes: [
          EpisodeEntity(episode: 1, link: 'https://test.m3u8'),
        ],
      ),
    ];
  }
}
