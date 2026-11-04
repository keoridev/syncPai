import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'app/di/injection.dart';
import 'app/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация libmpv для media_kit
  MediaKit.ensureInitialized();

  // Регистрация сервисов и зависимостей Clean Architecture
  await configureDependencies();

  runApp(const SyncPaiApp());
}

class SyncPaiApp extends StatelessWidget {
  const SyncPaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SyncPai',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.cinemaDark,
      routerConfig: appRouter,
    );
  }
}
