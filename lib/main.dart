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
import 'features/catalog/presentation/cubit/catalog_cubit.dart';
import 'features/downloads/presentation/cubit/download_cubit.dart';
import 'features/kodik/presentation/cubit/kodik_cubit.dart';
import 'features/player/services/global_mini_player_service.dart';
import 'features/watch_history/presentation/cubit/watch_history_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Игнорируем известный баг Flutter Engine на Windows при нажатии Alt (Alt Left assertion в raw_keyboard.dart)
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.exceptionAsString();
    if (msg.contains('raw_keyboard.dart') || msg.contains('keysPressed.isNotEmpty')) {
      return;
    }
    if (defaultOnError != null) {
      defaultOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  MediaKit.ensureInitialized();

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

  runApp(const SyncPaiApp());
}

class SyncPaiApp extends StatelessWidget {
  const SyncPaiApp({super.key});

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
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp.router(
            title: 'SyncPai',
            debugShowCheckedModeBanner: false,
            theme: themeState.themeData,
            routerConfig: appRouter,
            builder: (context, child) {
              return GestureDetector(
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
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
