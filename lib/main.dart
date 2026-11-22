import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'app/di/injection.dart';
import 'app/router/app_router.dart';
import 'core/network/api_constants.dart';
import 'core/theme/cubit/theme_cubit.dart';
import 'core/widgets/desktop_title_bar.dart';
import 'features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/catalog/data/services/catalog_persistent_store.dart';
import 'features/catalog/presentation/cubit/catalog_cubit.dart';
import 'features/settings/presentation/cubit/settings_cubit.dart';
import 'features/downloads/presentation/cubit/download_cubit.dart';
import 'features/kodik/presentation/cubit/kodik_cubit.dart';
import 'features/player/services/global_mini_player_service.dart';
import 'features/support/presentation/widgets/support_prompt_overlay.dart';
import 'features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'core/services/app_updater_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/device_performance_service.dart';
import 'core/services/discord_rpc_service.dart';
import 'core/services/mascot_companion_service.dart';
import 'core/widgets/achievement_toast_overlay.dart';
import 'core/widgets/mascot/pai_companion_toast.dart';
import 'features/profile/domain/services/achievement_service.dart';
import 'features/profile/presentation/widgets/friend_invite_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (msg.contains('raw_keyboard.dart') ||
        msg.contains('keysPressed.isNotEmpty')) {
      return;
    }
    if (defaultOnError != null) {
      defaultOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  MediaKit.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 300;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 * 1024 * 1024;

  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1280, 760),
        minimumSize: Size(800, 560),
        center: true,
        backgroundColor: Color(0xFF090910),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
        title: 'SyncPai',
      );
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
        await windowManager.setBackgroundColor(const Color(0xFF090910));
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (e) {
      debugPrint('WindowManager init error: $e');
    }
  }

  try {
    await Supabase.initialize(
      url: ApiConstants.supabaseUrl,
      publishableKey: ApiConstants.supabaseAnonKey,
    );
  } catch (e) {
    debugPrint('Supabase init error: $e');
  }

  await configureDependencies();

  await Future.wait([
    DevicePerformanceService.instance.init(),
    CatalogPersistentStore.instance.init(),
    MascotCompanionService.instance.init(),
  ]);

  runApp(const SyncPaiApp());
}

class SyncPaiApp extends StatefulWidget {
  const SyncPaiApp({super.key});

  @override
  State<SyncPaiApp> createState() => _SyncPaiAppState();
}

class _SyncPaiAppState extends State<SyncPaiApp> {
  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdaterService.instance.checkForUpdates();
      if (!kIsWeb && Platform.isWindows) {
        DiscordRpcService.instance.init();
      }
      AchievementService.instance.init();
    });
  }

  void _initDeepLinks() {
    DeepLinkService.instance.onFriendInviteDetected = (code) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null) {
        FriendInviteConfirmationDialog.show(
          navContext,
          inviteCode: code,
        );
      }
    };

    DeepLinkService.instance.onRoomInviteDetected = (roomCode) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null) {
        appRouter.push('/room/$roomCode');
      }
    };

    DeepLinkService.instance.onAnimeEpisodeDetected = (animeId, epNum) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null) {
        appRouter.push('/details?id=$animeId&ep=$epNum');
      }
    };

    DeepLinkService.instance.init();
  }

  @override
  void dispose() {
    DeepLinkService.instance.dispose();
    DiscordRpcService.instance.disposeService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: getIt<ThemeCubit>()),
        BlocProvider.value(value: getIt<AuthCubit>()),
        BlocProvider.value(value: getIt<AnimeListCubit>()),
        BlocProvider.value(value: getIt<WatchHistoryCubit>()),
        BlocProvider.value(value: getIt<DownloadCubit>()),
        BlocProvider.value(value: getIt<KodikCubit>()),
        BlocProvider.value(value: getIt<CatalogCubit>()),
        BlocProvider.value(value: getIt<SettingsCubit>()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp.router(
            title: 'SyncPai',
            debugShowCheckedModeBanner: false,
            theme: themeState.themeData,
            routerConfig: appRouter,
            builder: (context, child) {
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) =>
                    MascotCompanionService.instance.reportUserActivity(),
                onPointerHover: (_) =>
                    MascotCompanionService.instance.reportUserActivity(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: Column(
                    children: [
                      const DesktopTitleBar(),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            child ?? const SizedBox.shrink(),
                            const GlobalMiniPlayerOverlay(),
                            const SupportPromptOverlay(),
                            const AchievementToastOverlay(),
                            const PaiCompanionToast(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
