import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liquid_glass_nav_bar.dart';
import '../../../anime_lists/presentation/screens/saved_anime_screen.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/presentation/screens/catalog_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../shorts/presentation/screens/anime_shorts_screen.dart';
import '../../../sync_room/presentation/screens/watch_together_screen.dart';

/// Главный экран приложения со связкой 5 разделов и парящей панелью Liquid Glass:
/// 1. Каталог (Релизы, поиск, просмотр аниме)
/// 2. Моменты (Лента вертикальных клипов / шортсов с мгновенным прыжком в таймкод)
/// 3. Вместе (Совместный просмотр, друзья, комнаты)
/// 4. Списки (Закладки, «В планах», «Смотрю», продолжение просмотра)
/// 5. Профиль & Настройки (Кастомизация, статистика, импорт, плеер)
class MainScreen extends StatefulWidget {
  final int initialTab;
  final ValueChanged<AnimeTitle>? onTitleSelected;

  const MainScreen({
    super.key,
    this.initialTab = 0,
    this.onTitleSelected,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, 4);
  }

  void switchTab(int index) {
    if (index >= 0 && index < 5 && index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // extendBody позволяет фону и скроллу плавно уходить под размытое стекло нижней панели
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Вкладка 1: Каталог
          CatalogScreen(
            onTitleSelected: widget.onTitleSelected,
          ),

          // Вкладка 2: Лента Моментов (Shorts / Reels)
          AnimeShortsScreen(
            showBackButton: false,
            isActive: _currentIndex == 1,
            onTitleSelected: widget.onTitleSelected,
          ),

          // Вкладка 3: Смотреть вместе & Добавить друга
          WatchTogetherScreen(
            onCreateRoomTap: () => switchTab(0),
          ),

          // Вкладка 4: Мои списки & Закладки (В планах / Смотрю)
          SavedAnimeScreen(
            onTitleSelected: widget.onTitleSelected,
            onGoToCatalog: () => switchTab(0),
          ),

          // Вкладка 5: Профиль & Кастомизация
          const ProfileScreen(
            showBackButton: false,
          ),
        ],
      ),
      bottomNavigationBar: LiquidGlassNavBar(
        currentIndex: _currentIndex,
        onTap: switchTab,
        items: const [
          LiquidGlassNavItem(
            icon: Icons.explore_outlined,
            selectedIcon: Icons.explore_rounded,
            label: 'Каталог',
          ),
          LiquidGlassNavItem(
            icon: Icons.movie_filter_outlined,
            selectedIcon: Icons.movie_filter_rounded,
            label: 'Моменты',
          ),
          LiquidGlassNavItem(
            icon: Icons.people_outline_rounded,
            selectedIcon: Icons.people_alt_rounded,
            label: 'Вместе',
          ),
          LiquidGlassNavItem(
            icon: Icons.bookmark_outline_rounded,
            selectedIcon: Icons.bookmark_rounded,
            label: 'Списки',
          ),
          LiquidGlassNavItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}
