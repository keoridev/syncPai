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
/// Поддерживает плавный горизонтальный свайп между экранами (PageView) с сохранением состояния.
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
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, 4);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void switchTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    if (index >= 0 && index < 5) {
      if (_currentIndex != index) {
        setState(() => _currentIndex = index);
      }
      if (_pageController.hasClients && _pageController.page?.round() != index) {
        _pageController.jumpToPage(index);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 900;

    final bodyContent = PageView(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (index) {
        FocusManager.instance.primaryFocus?.unfocus();
        FocusScope.of(context).unfocus();
        if (_currentIndex != index) {
          setState(() => _currentIndex = index);
        }
      },
      children: [
        // Вкладка 1: Каталог
        _KeepAlivePage(
          child: CatalogScreen(
            onTitleSelected: widget.onTitleSelected,
          ),
        ),

        // Вкладка 2: Лента Моментов (Shorts / Reels)
        _KeepAlivePage(
          child: AnimeShortsScreen(
            showBackButton: false,
            isActive: _currentIndex == 1,
            onTitleSelected: widget.onTitleSelected,
          ),
        ),

        // Вкладка 3: Смотреть вместе & Добавить друга
        _KeepAlivePage(
          child: WatchTogetherScreen(
            onCreateRoomTap: () => switchTab(0),
          ),
        ),

        // Вкладка 4: Мои списки & Закладки (В планах / Смотрю)
        _KeepAlivePage(
          child: SavedAnimeScreen(
            onTitleSelected: widget.onTitleSelected,
            onGoToCatalog: () => switchTab(0),
          ),
        ),

        // Вкладка 5: Профиль & Кастомизация
        const _KeepAlivePage(
          child: ProfileScreen(
            showBackButton: false,
          ),
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
                  icon: Icons.movie_outlined,
                  selectedIcon: Icons.movie_rounded,
                  label: 'Каталог',
                ),
                LiquidGlassNavItem(
                  icon: Icons.play_circle_outline_rounded,
                  selectedIcon: Icons.play_circle_filled_rounded,
                  label: 'Моменты',
                ),
                LiquidGlassNavItem(
                  icon: Icons.people_outline_rounded,
                  selectedIcon: Icons.people_alt_rounded,
                  label: 'Вместе',
                ),
                LiquidGlassNavItem(
                  icon: Icons.bookmark_border_rounded,
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

  /// Боковой сайдбар на широких экранах (планшеты, десктоп)
  Widget _buildLeftSidebar(BuildContext context, Color themePrimary) {
    return Container(
      width: 230,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          right: BorderSide(
            color: AppColors.stroke,
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Логотип приложения с правильными отступами
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SyncPaiLogo(
                    size: 32,
                    accentColor: themePrimary,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'SyncPai',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            _buildSidebarItem(0, Icons.movie_outlined, Icons.movie_rounded, 'Каталог', themePrimary),
            _buildSidebarItem(1, Icons.play_circle_outline_rounded, Icons.play_circle_filled_rounded, 'Моменты', themePrimary),
            _buildSidebarItem(2, Icons.people_outline_rounded, Icons.people_alt_rounded, 'Вместе', themePrimary),
            _buildSidebarItem(3, Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'Списки', themePrimary),
            _buildSidebarItem(4, Icons.person_outline_rounded, Icons.person_rounded, 'Профиль', themePrimary),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    int index,
    IconData icon,
    IconData selectedIcon,
    String label,
    Color themePrimary,
  ) {
    final isSelected = _currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: InkWell(
        onTap: () => switchTab(index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? themePrimary.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? selectedIcon : icon,
                color: isSelected ? themePrimary : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Вспомогательный виджет для сохранения состояния страницы при свайпах
class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
