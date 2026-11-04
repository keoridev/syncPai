import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../di/injection.dart';
import '../../features/anime_details/presentation/screens/anime_details_screen.dart';
import '../../features/catalog/domain/entities/anime_title.dart';
import '../../features/catalog/presentation/cubit/catalog_cubit.dart';
import '../../features/catalog/presentation/screens/catalog_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'catalog',
      builder: (context, state) => BlocProvider(
        create: (context) => getIt<CatalogCubit>(),
        child: CatalogScreen(
          onTitleSelected: (title) {
            context.pushNamed('details', extra: title);
          },
        ),
      ),
    ),
    GoRoute(
      path: '/details',
      name: 'details',
      builder: (context, state) {
        final title = state.extra as AnimeTitle?;
        if (title == null) {
          return const Scaffold(
            body: Center(child: Text('Тайтл не найден')),
          );
        }
        return AnimeDetailsScreen(
          title: title,
          onPlayEpisode: (t, ep) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Запуск: ${t.displayTitle} — Серия ${ep.episode}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          onStartSyncRoom: (t, ep) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Создание комнаты совместного просмотра: Серия ${ep.episode}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        );
      },
    ),
  ],
);

