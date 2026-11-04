import 'package:get_it/get_it.dart';
import '../../core/network/dio_client.dart';
import '../../features/catalog/data/datasources/anilibria_remote_datasource.dart';
import '../../features/catalog/data/repositories/catalog_repository_impl.dart';
import '../../features/catalog/domain/repositories/catalog_repository.dart';
import '../../features/catalog/domain/usecases/get_title_details.dart';
import '../../features/catalog/domain/usecases/get_updates.dart';
import '../../features/catalog/domain/usecases/search_titles.dart';
import '../../features/catalog/presentation/cubit/catalog_cubit.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
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
  getIt.registerFactory<CatalogCubit>(
    () => CatalogCubit(
      getUpdates: getIt<GetUpdates>(),
      searchTitles: getIt<SearchTitles>(),
    ),
  );
}

