import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/dio_client.dart';
import '../../features/anime_details/data/datasources/shikimori_remote_datasource.dart';
import '../../features/anime_lists/data/datasources/anixart_remote_datasource.dart';
import '../../features/anime_lists/data/repositories/anime_list_repository_impl.dart';
import '../../features/anime_lists/domain/repositories/anime_list_repository.dart';
import '../../features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../features/auth/data/repositories/auth_repository_impl.dart';
import '../../features/auth/domain/repositories/auth_repository.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/catalog/data/datasources/anilibria_remote_datasource.dart';
import '../../features/catalog/data/repositories/catalog_repository_impl.dart';
import '../../features/catalog/domain/repositories/catalog_repository.dart';
import '../../features/catalog/domain/usecases/get_title_details.dart';
import '../../features/catalog/domain/usecases/get_updates.dart';
import '../../features/catalog/domain/usecases/search_titles.dart';
import '../../features/catalog/presentation/cubit/catalog_cubit.dart';
import '../../features/sync_room/data/repositories/sync_room_repository_impl.dart';
import '../../features/sync_room/domain/repositories/sync_room_repository.dart';
import '../../features/watch_history/data/repositories/watch_history_repository_impl.dart';
import '../../features/watch_history/domain/repositories/watch_history_repository.dart';
import '../../features/watch_history/presentation/cubit/watch_history_cubit.dart';
import '../../features/downloads/data/repositories/download_repository_impl.dart';
import '../../features/downloads/domain/repositories/download_repository.dart';
import '../../features/downloads/presentation/cubit/download_cubit.dart';
import '../../features/torrents/data/repositories/torrent_repository_impl.dart';
import '../../features/torrents/domain/repositories/torrent_repository.dart';
import '../../features/shorts/data/datasources/anime_clips_datasource.dart';
import '../../features/shorts/data/repositories/anime_clips_repository_impl.dart';
import '../../features/shorts/domain/repositories/anime_clips_repository.dart';
import '../../features/kodik/data/datasources/kodik_remote_datasource.dart';
import '../../features/kodik/data/datasources/kodik_stream_extractor.dart';
import '../../features/kodik/presentation/cubit/kodik_cubit.dart';
import '../../core/theme/cubit/theme_cubit.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // Storage: SharedPreferences для настроек и кэша
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  // Theme & Appearance (Динамические цветовые палитры)
  getIt.registerLazySingleton<ThemeCubit>(
    () => ThemeCubit(getIt<SharedPreferences>()),
  );

  // Auth: Безболезненный Anonymous + Google Auth
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<AuthCubit>(
    () => AuthCubit(repository: getIt<AuthRepository>()),
  );

  // Anime Lists & Anixart Import
  getIt.registerLazySingleton<AnixartRemoteDataSource>(
    () => AnixartRemoteDataSourceImpl(),
  );
  getIt.registerLazySingleton<ShikimoriRemoteDataSource>(
    () => ShikimoriRemoteDataSourceImpl(),
  );
  getIt.registerLazySingleton<AnimeListRepository>(
    () => AnimeListRepositoryImpl(
      getIt<SharedPreferences>(),
      anixartRemoteDataSource: getIt<AnixartRemoteDataSource>(),
    ),
  );
  getIt.registerLazySingleton<AnimeListCubit>(
    () => AnimeListCubit(repository: getIt<AnimeListRepository>()),
  );

  // Watch History (История просмотров и позиций серий)
  getIt.registerLazySingleton<WatchHistoryRepository>(
    () => WatchHistoryRepositoryImpl(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<WatchHistoryCubit>(
    () => WatchHistoryCubit(repository: getIt<WatchHistoryRepository>()),
  );

  // Downloads (Менеджер фоновой загрузки серий и офлайн-просмотра)
  getIt.registerLazySingleton<DownloadRepository>(
    () => DownloadRepositoryImpl(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<DownloadCubit>(
    () => DownloadCubit(getIt<DownloadRepository>()),
  );

  // Torrents & TorLook (Торрент-раздачи максимального битрейта)
  getIt.registerLazySingleton<TorrentRepository>(
    () => TorrentRepositoryImpl(),
  );

  // Anime Shorts / Reels (Лента моментов с мгновенным прыжком в таймкод)
  getIt.registerLazySingleton<AnimeClipsDataSource>(
    () => AnimeClipsDataSourceImpl(getIt<SharedPreferences>()),
  );
  getIt.registerLazySingleton<AnimeClipsRepository>(
    () => AnimeClipsRepositoryImpl(getIt<AnimeClipsDataSource>()),
  );

  // Kodik (База альтернативных озвучек: Dream Cast, StudioBand, AniDUB...)
  getIt.registerLazySingleton<KodikRemoteDataSource>(
    () => KodikRemoteDataSourceImpl(),
  );
  getIt.registerLazySingleton<KodikStreamExtractor>(
    () => KodikStreamExtractor(),
  );
  getIt.registerLazySingleton<KodikCubit>(
    () => KodikCubit(
      dataSource: getIt<KodikRemoteDataSource>(),
      extractor: getIt<KodikStreamExtractor>(),
      prefs: getIt<SharedPreferences>(),
    ),
  );

  // Sync Room Repository
  getIt.registerLazySingleton<SyncRoomRepository>(() => SyncRoomRepositoryImpl());

  // Core: Network
  getIt.registerLazySingleton<DioClient>(() => DioClient());

  // Features: Catalog - Data
  getIt.registerLazySingleton<AnilibriaRemoteDataSource>(
    () => AnilibriaRemoteDataSourceImpl(getIt<DioClient>()),
  );
  getIt.registerLazySingleton<CatalogRepository>(
    () => CatalogRepositoryImpl(getIt<AnilibriaRemoteDataSource>()),
  );

  // Features: Catalog - Domain Use Cases
  getIt.registerLazySingleton<GetUpdates>(
    () => GetUpdates(getIt<CatalogRepository>()),
  );
  getIt.registerLazySingleton<SearchTitles>(
    () => SearchTitles(getIt<CatalogRepository>()),
  );
  getIt.registerLazySingleton<GetTitleDetails>(
    () => GetTitleDetails(getIt<CatalogRepository>()),
  );

  // Features: Catalog - Presentation Cubit
  getIt.registerLazySingleton<CatalogCubit>(
    () => CatalogCubit(
      getUpdates: getIt<GetUpdates>(),
      searchTitles: getIt<SearchTitles>(),
      prefs: getIt<SharedPreferences>(),
    ),
  );
}
