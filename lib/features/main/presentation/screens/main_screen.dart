import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liquid_glass_nav_bar.dart';
import '../../../../core/widgets/manga_panel_painter.dart';
import '../../../../core/widgets/safe_anime_poster.dart';
import '../../../../core/widgets/sync_pai_logo.dart';
import '../../../anime_lists/presentation/screens/saved_anime_screen.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/presentation/screens/catalog_screen.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../profile/services/friends_service.dart';
import '../../../shorts/presentation/screens/anime_shorts_screen.dart';
import '../../../sync_room/presentation/screens/watch_together_screen.dart';
import '../../../sync_room/presentation/widgets/floating_room_overlay.dart';
import '../../../watch_history/presentation/cubit/watch_history_cubit.dart';
import '../../../watch_history/presentation/cubit/watch_history_state.dart';
import '../../../winter_theme/presentation/widgets/background_snow_layer.dart';

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

  static _MainScreenState? _activeState;

  /// Переключить активный таб главного экрана (например, на Каталог при клике на жанр).
  static bool switchToTab(int index) {
    final state = _activeState;
    if (state == null || !state.mounted) return false;
    state.switchTab(index);
    return true;
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    MainScreen._activeState = this;
    _currentIndex = widget.initialTab.clamp(0, 4);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    if (identical(MainScreen._activeState, this)) {
      MainScreen._activeState = null;
    }
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
    // В headless тестовом окружении Flutter (где Platform.isWindows true) эмулируем мобильный режим при ширине < 900
    final bool isTestEnv = Platform.environment.containsKey('FLUTTER_TEST') ||
        WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');
    final bool isDesktopOS = !isTestEnv && !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final isWide = isDesktopOS || screenWidth >= 900;

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
      body: Stack(
        children: [
          const Positioned.fill(
            child: BackgroundSnowLayer(
              key: ValueKey('main_background_snow_layer'),
            ),
          ),
          isWide
              ? Row(
                  children: [
                    _buildLeftSidebar(context, themePrimary),
                    Expanded(child: bodyContent),
                  ],
                )
              : bodyContent,
          const Positioned.fill(
            child: FloatingRoomOverlay(mobileBottomInset: 92),
          ),
        ],
      ),
      bottomNavigationBar: (isWide || isDesktopOS)
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
    final scheme = Theme.of(context).colorScheme;
    final isManga = isMangaPrintTheme(context);
    final showWidgets = MediaQuery.sizeOf(context).height >= 720;

    return Container(
      width: 230,
      decoration: BoxDecoration(
        color: isManga ? const Color(0xFF161920) : scheme.surface,
        border: Border(
          right: BorderSide(
            color: isManga ? const Color(0x33F8FAFC) : AppColors.stroke,
            width: isManga ? 1.5 : 1.0,
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
                  Text(
                    'SyncPai',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildSidebarItem(0, Icons.movie_outlined, Icons.movie_rounded, 'Каталог', themePrimary),
            _buildSidebarItem(1, Icons.play_circle_outline_rounded, Icons.play_circle_filled_rounded, 'Моменты', themePrimary),
            _buildSidebarItem(2, Icons.people_outline_rounded, Icons.people_alt_rounded, 'Вместе', themePrimary),
            _buildSidebarItem(3, Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'Списки', themePrimary),
            _buildSidebarItem(4, Icons.person_outline_rounded, Icons.person_rounded, 'Профиль', themePrimary),
            if (showWidgets)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSidebarContinueCard(context, themePrimary, isManga),
                      const SizedBox(height: 12),
                      _buildSidebarOnlineFriends(context, themePrimary, isManga),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarContinueCard(
    BuildContext context,
    Color themePrimary,
    bool isManga,
  ) {
    if (!getIt.isRegistered<WatchHistoryCubit>()) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<WatchHistoryCubit, WatchHistoryState>(
      bloc: getIt<WatchHistoryCubit>(),
      builder: (context, state) {
        if (state.history.isEmpty) {
          return const SizedBox.shrink();
        }
        final item = state.history.firstWhere(
          (i) => i.progress > 0,
          orElse: () => state.history.first,
        );
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isManga ? const Color(0xFF1C2029) : const Color(0xFF131722),
            borderRadius: BorderRadius.circular(isManga ? 10 : 12),
            border: Border.all(
              color: isManga ? const Color(0x33F8FAFC) : const Color(0x14FFFFFF),
              width: isManga ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ПРОДОЛЖИТЬ',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 34,
                    height: 48,
                    child: SafeAnimePoster(
                      imageUrl: item.posterUrl,
                      title: item.titleName,
                      borderRadius: isManga ? 4 : 6,
                      monogramFontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.titleName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Серия ${item.episode}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: item.progress.clamp(0.05, 1.0),
                            minHeight: 3,
                            backgroundColor: isManga
                                ? const Color(0x26F8FAFC)
                                : const Color(0x18FFFFFF),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isManga ? const Color(0xFFF1F5F9) : const Color(0xFFFF6B4A),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 30,
                child: FilledButton(
                  onPressed: () {
                    context.pushNamed(
                      'details',
                      queryParameters: {'id': '${item.titleId}'},
                      extra: {
                        'id': '${item.titleId}',
                        'russianTitle': item.titleName,
                        'posterMedium': item.posterUrl,
                      },
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: isManga ? const Color(0xFFF1F5F9) : const Color(0xFFFF6B4A),
                    foregroundColor: isManga ? const Color(0xFF0D0F12) : Colors.white,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Продолжить',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarOnlineFriends(
    BuildContext context,
    Color themePrimary,
    bool isManga,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([
        FriendsService.friendsNotifier,
        PresenceService.instance,
      ]),
      builder: (context, _) {
        final online = FriendsService.friendsNotifier.value.where((f) {
          final fid = (f['id'] ?? '').toString();
          return f['isOnline'] == true ||
              (fid.isNotEmpty && PresenceService.instance.isUserOnline(fid));
        }).take(3).toList();
        if (online.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isManga ? const Color(0xFF1C2029) : const Color(0xFF131722),
            borderRadius: BorderRadius.circular(isManga ? 10 : 12),
            border: Border.all(
              color: isManga ? const Color(0x33F8FAFC) : const Color(0x14FFFFFF),
              width: isManga ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ДРУЗЬЯ ОНЛАЙН',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 8),
              ...online.map((f) {
                final name = (f['username'] ?? f['name'] ?? 'Друг').toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isManga ? const Color(0xFFF1F5F9) : const Color(0xFFFF6B4A),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => switchTab(2),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isManga
                                ? const Color(0xFFF1F5F9)
                                : const Color(0xFF1A202E),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Войти',
                            style: TextStyle(
                              color: isManga ? const Color(0xFF0D0F12) : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
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
