import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liquid_glass_nav_bar.dart';
import '../../../../core/widgets/sync_pai_logo.dart';
import '../../../anime_lists/presentation/screens/saved_anime_screen.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/presentation/screens/catalog_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../shorts/presentation/screens/anime_shorts_screen.dart';
import '../../../sync_room/presentation/screens/watch_together_screen.dart';

/// Главный экран приложения со связкой 5 разделов:
/// 1. Каталог (Релизы, поиск, просмотр аниме)
/// 2. Моменты (Лента вертикальных клипов / шортсов)
/// 3. Вместе (Совместный просмотр, друзья, комнаты)
/// 4. Списки (Закладки, «В планах», «Смотрю»)
/// 5. Профиль & Настройки (Кастомизация, статистика, импорт, плеер)
/// На широких экранах (планшеты, десктоп, альбомная ориентация) отображается боковой сайдбар слева,
/// а на мобильных устройствах — парящая панель Liquid Glass внизу.
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
    final themePrimary = Theme.of(context).colorScheme.primary;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 720;

    final bodyContent = IndexedStack(
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
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: isWide
          ? Row(
              children: [
                _buildLeftSidebar(context, themePrimary),
                Expanded(child: bodyContent),
              ],
            )
          : bodyContent,
      bottomNavigationBar: isWide
          ? null
          : LiquidGlassNavBar(
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

  Widget _buildLeftSidebar(BuildContext context, Color themePrimary) {
    final navItems = [
      (Icons.explore_outlined, Icons.explore_rounded, 'Каталог'),
      (Icons.movie_filter_outlined, Icons.movie_filter_rounded, 'Моменты'),
      (Icons.people_outline_rounded, Icons.people_alt_rounded, 'Вместе'),
      (Icons.bookmark_outline_rounded, Icons.bookmark_rounded, 'Списки'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Профиль'),
    ];

    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(color: AppColors.strokeMedium, width: 1.0),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Логотип приложения в сайдбаре
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  SyncPaiLogo(size: 34, accentColor: themePrimary),
                  const SizedBox(width: 10),
                  RichText(
                    text: TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Sync',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        TextSpan(
                          text: 'Pai',
                          style: TextStyle(
                            color: themePrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Divider(color: AppColors.stroke, height: 1),
            const SizedBox(height: 14),

            // Элементы навигации сайдбара
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: navItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = navItems[index];
                  final isSelected = _currentIndex == index;

                  return InkWell(
                    onTap: () => switchTab(index),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? themePrimary.withValues(alpha: 0.16) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? themePrimary.withValues(alpha: 0.4) : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? item.$2 : item.$1,
                            size: 22,
                            color: isSelected ? themePrimary : Colors.white70,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item.$3,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Нижний статус
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'SyncPai Nordic Dark v1.0',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
