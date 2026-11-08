import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/di/injection.dart';
import 'app/router/app_router.dart';
import 'core/network/api_constants.dart';
import 'core/theme/cubit/theme_cubit.dart';
import 'features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/catalog/presentation/cubit/catalog_cubit.dart';
import 'features/downloads/presentation/cubit/download_cubit.dart';
import 'features/kodik/presentation/cubit/kodik_cubit.dart';
import 'features/watch_history/presentation/cubit/watch_history_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  MediaKit.ensureInitialized();

  if (ApiConstants.supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: ApiConstants.supabaseUrl,
        publishableKey: ApiConstants.supabaseAnonKey,
      );
    } catch (e) {
      debugPrint('Supabase init error: $e');
    }
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
                child: child ?? const SizedBox.shrink(),
              );
            },
          );
        },
      ),
    );
  }
}
