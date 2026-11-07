import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/player_navigation_guard.dart';
import '../../features/anime_details/domain/entities/anime_video_item.dart';
import '../../features/anime_details/presentation/screens/anime_details_screen.dart';
import '../../features/anime_details/presentation/screens/anime_videos_screen.dart';
import '../../features/catalog/domain/entities/anime_title.dart';
import '../../features/catalog/domain/entities/episode_item.dart';
import '../../features/main/presentation/screens/main_screen.dart';
import '../../features/player/domain/entities/player_quality.dart';
import '../../features/player/presentation/screens/player_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/shorts/presentation/screens/anime_shorts_screen.dart';
import '../../features/splash/presentation/screens/splash_screen.dart';
import '../../features/sync_room/presentation/screens/join_room_screen.dart';
import '../../features/sync_room/presentation/widgets/sync_room_lobby_sheet.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      name: 'splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/',
      name: 'main',
      builder: (context, state) => MainScreen(
        onTitleSelected: (title) {
          context.pushNamed('details', extra: title);
        },
      ),
    ),
    GoRoute(
      path: '/catalog',
      name: 'catalog',
      redirect: (context, state) => '/',
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
          onPlayEpisode: (t, ep, quality) {
            PlayerNavigationGuard.openPlayer(context, extra: {
              'title': t,
              'episode': ep,
              'quality': quality,
            });
          },
          onResumeEpisode: (t, ep, quality, position) {
            PlayerNavigationGuard.openPlayer(context, extra: {
              'title': t,
              'episode': ep,
              'quality': quality,
              'initialPosition': position,
            });
          },
          onStartSyncRoom: (t, ep) {
            SyncRoomLobbySheet.show(
              context,
              title: t,
              episode: ep,
              initialQuality: PlayerQuality.hd,
              onStartPlayback: (room, isHost) {
                PlayerNavigationGuard.openPlayer(context, extra: {
                  'title': room.title,
                  'episode': room.episode,
                  'quality': room.quality,
                  'roomCode': room.code,
                  'isHost': isHost,
                });
              },
            );
          },
        );
      },
    ),
    GoRoute(
      path: '/profile',
      name: 'profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/shorts',
      name: 'shorts',
      builder: (context, state) => AnimeShortsScreen(
        showBackButton: true,
        onTitleSelected: (title) {
          context.pushNamed('details', extra: title);
        },
      ),
    ),
    GoRoute(
      path: '/anime-videos',
      name: 'anime-videos',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final title = extra?['title'] as String? ?? 'Тайтл';
        final backdrop = extra?['backdrop'] as String? ?? '';
        final videos = extra?['videos'] as List<AnimeVideoItem>? ?? [];
        return AnimeVideosScreen(
          animeTitle: title,
          backdropUrl: backdrop,
          videos: videos,
        );
      },
    ),
    GoRoute(
      path: '/room/:code',
      name: 'join_room',
      builder: (context, state) {
        final code = state.pathParameters['code'] ?? '';
        return JoinRoomScreen(code: code);
      },
    ),
    GoRoute(
      path: '/player',
      name: 'player',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final title = extra?['title'] as AnimeTitle?;
        final episode = extra?['episode'] as EpisodeItem?;
        final quality = extra?['quality'] as PlayerQuality? ?? PlayerQuality.fhd;
        final roomCode = extra?['roomCode'] as String?;
        final isHost = extra?['isHost'] as bool? ?? false;
        final initialPosition = extra?['initialPosition'] as Duration?;

        if (title == null || episode == null) {
          return const Scaffold(
            body: Center(child: Text('Видеопоток не найден')),
          );
        }

        return PlayerScreen(
          title: title,
          initialEpisode: episode,
          initialQuality: quality,
          roomCode: roomCode,
          isHost: isHost,
          initialPosition: initialPosition,
        );
      },
    ),
  ],
);
