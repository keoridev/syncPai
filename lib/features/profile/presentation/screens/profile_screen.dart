import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/steam_avatar_frame.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/domain/repositories/anime_list_repository.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../domain/entities/steam_profile_customization.dart';
import '../cubit/profile_cubit.dart';
import '../cubit/profile_state.dart';
import '../widgets/badge_details_sheet.dart';
import '../widgets/live_backgrounds/live_background_widget.dart';
import '../widgets/profile_activity_chart.dart';
import '../widgets/steam_profile_customizer_sheet.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId; // Если null — это мой профиль. Если передано — профиль друга.
  final VoidCallback? onBack;
  final bool showBackButton;

  const ProfileScreen({
    super.key,
    this.userId,
    this.onBack,
    this.showBackButton = true,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _showActivityCharts = false;
  bool _guestBannerDismissed = false;
  bool _isBgPaused = false;
  late final ScrollController _scrollController;
  late final ProfileCubit _profileCubit;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  static const List<String> _avatarPresets = [
    'cat', 'fox', 'panda', 'wolf', 'bolt', 'flower', 'shield', 'fire', 'gamer', 'star', 'bot'
  ];

  bool get _isTestEnv {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (!_isTestEnv) {
      _pulseController.repeat(reverse: true);
    }
    _pulseAnimation = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);
    _loadBannerDismissed();
    _profileCubit = getIt.isRegistered<ProfileCubit>()
        ? getIt<ProfileCubit>()
        : ProfileCubit(
            authRepository: getIt.isRegistered<AuthRepository>() ? getIt<AuthRepository>() : null,
            animeListRepository: getIt.isRegistered<AnimeListRepository>() ? getIt<AnimeListRepository>() : null,
          );
    _profileCubit.loadProfile(targetUserId: widget.userId);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldPause = _scrollController.offset > 320;
    if (shouldPause != _isBgPaused) {
      setState(() => _isBgPaused = shouldPause);
    }
  }

  void _cycleShowcaseType(UserProfile profile) {
    const modes = ['favorite_anime', 'stats_badges', 'custom_text'];
    final currentIndex = modes.indexOf(profile.showcaseType);
    final nextIndex = (currentIndex == -1 || currentIndex == modes.length - 1) ? 0 : currentIndex + 1;
    final nextMode = modes[nextIndex];
    context.read<AuthCubit>().updateProfile(
      username: profile.username,
      showcaseType: nextMode,
    );
  }

  void _loadBannerDismissed() {
    if (getIt.isRegistered<SharedPreferences>()) {
      final prefs = getIt<SharedPreferences>();
      _guestBannerDismissed = prefs.getBool('guest_sync_banner_dismissed') ?? false;
    }
  }

  void _dismissGuestBanner() {
    setState(() => _guestBannerDismissed = true);
    if (getIt.isRegistered<SharedPreferences>()) {
      getIt<SharedPreferences>().setBool('guest_sync_banner_dismissed', true);
    }
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _profileCubit.loadProfile(targetUserId: widget.userId);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _profileCubit.close();
    super.dispose();
  }

  void _showEditProfileSheet(BuildContext context, UserProfile profile) {
    final controller = TextEditingController(text: profile.username);
    String selectedAvatar = profile.avatarUrl ?? 'cat';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.spacingXl,
            AppDimensions.spacingLg,
            AppDimensions.spacingXl,
            MediaQuery.of(context).viewInsets.bottom + AppDimensions.spacingXl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.strokeMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Редактировать профиль',
                  style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 16),
                Text(
                  'Выберите аватар профиля',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _avatarPresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final preset = _avatarPresets[index];
                      final isSelected = selectedAvatar == preset;
                      return GestureDetector(
                        onTap: () => setSheetState(() => selectedAvatar = preset),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: AppAvatar(avatarUrl: preset, size: 50),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: controller,
                  maxLength: 24,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Имя профиля',
                    labelStyle: const TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surface,
                    counterStyle: const TextStyle(color: AppColors.textMuted),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.strokeMedium),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      final newName = controller.text.trim();
                      if (newName.isNotEmpty) {
                        context.read<AuthCubit>().updateProfile(
                          username: newName,
                          avatarUrl: selectedAvatar,
                        );
                        _profileCubit.loadProfile(targetUserId: widget.userId);
                        Navigator.pop(sheetContext);
                      }
                    },
                    child: const Text('Сохранить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFavoriteAnimeDetails(BuildContext context, UserProfile profile) async {
    final favTitle = profile.favoriteAnimeTitle;
    if (favTitle == null || favTitle.isEmpty) return;

    AnimeTitle? matched;
    try {
      final catalogState = getIt.isRegistered<CatalogCubit>()
          ? getIt<CatalogCubit>().state
          : (context.mounted ? context.read<CatalogCubit>().state : null);
      if (catalogState is CatalogLoaded) {
        matched = catalogState.titles.firstWhere(
          (t) =>
              (profile.favoriteAnimeId != null && t.id.toString() == profile.favoriteAnimeId) ||
              t.russianTitle.toLowerCase().trim() == favTitle.toLowerCase().trim() ||
              (t.englishTitle.isNotEmpty && t.englishTitle.toLowerCase().trim() == favTitle.toLowerCase().trim()),
          orElse: () => catalogState.titles.firstWhere(
            (t) =>
                t.russianTitle.toLowerCase().contains(favTitle.toLowerCase().trim()) ||
                favTitle.toLowerCase().trim().contains(t.russianTitle.toLowerCase()),
            orElse: () => const AnimeTitle(
              id: 0,
              code: '',
              russianTitle: '',
              englishTitle: '',
              posterSmall: '',
              posterMedium: '',
              posterOriginal: '',
              genres: [],
              description: '',
              status: '',
            ),
          ),
        );
      }
    } catch (_) {}

    if (matched == null || matched.id == 0) {
      try {
        final listState = context.read<AnimeListCubit>().state;
        final entry = listState.allEntries.firstWhere(
          (e) =>
              (profile.favoriteAnimeId != null && e.animeId.toString() == profile.favoriteAnimeId) ||
              e.cleanTitleRu.toLowerCase().trim() == favTitle.toLowerCase().trim() ||
              e.titleRu.toLowerCase().trim() == favTitle.toLowerCase().trim(),
          orElse: () => listState.allEntries.firstWhere(
            (e) =>
                e.cleanTitleRu.toLowerCase().contains(favTitle.toLowerCase().trim()) ||
                favTitle.toLowerCase().trim().contains(e.cleanTitleRu.toLowerCase()),
            orElse: () => listState.allEntries.first,
          ),
        );
        matched = AnimeTitle(
          id: entry.animeId,
          code: 'shikimori_${entry.animeId}',
          russianTitle: entry.cleanTitleRu,
          englishTitle: entry.titleRu,
          posterSmall: entry.posterUrl ?? '',
          posterMedium: entry.posterUrl ?? '',
          posterOriginal: entry.posterUrl ?? '',
          genres: const [],
          description: '',
          status: 'В списках',
        );
      } catch (_) {}
    }

    if (matched == null || matched.id == 0) {
      matched = AnimeTitle(
        id: int.tryParse(profile.favoriteAnimeId ?? '0') ?? 0,
        code: favTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
        russianTitle: favTitle,
        englishTitle: favTitle,
        posterSmall: profile.favoriteAnimePoster ?? '',
        posterMedium: profile.favoriteAnimePoster ?? '',
        posterOriginal: profile.favoriteAnimePoster ?? '',
        fallbackPosterUrl: profile.favoriteAnimePoster ?? '',
        genres: const [],
        description: '',
        status: 'Любимый тайтл',
      );
    }

    if (context.mounted) {
      context.pushNamed('details', extra: matched);
    }
  }

  Widget _buildFallbackShowcaseBackground(Color accent) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.35),
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_filter_rounded,
          color: Colors.white.withValues(alpha: 0.3),
          size: 48,
        ),
      ),
    );
  }

  Widget _buildRoundHeaderAction({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    Color iconColor = Colors.white,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black38,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
            ),
            child: IconButton(
              icon: Icon(icon, color: iconColor, size: 18),
              tooltip: tooltip,
              onPressed: onTap,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    VoidCallback? onTap,
  }) {
    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
      ),
      child: child,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: content,
      );
    }

    return RepaintBoundary(child: content);
  }

  /// Монолитная витрина профиля в стиле Steam Community
  Widget _buildMonolithicShowcase(
    BuildContext context,
    UserProfile profile,
    UserAnimeStats stats,
    Color accent,
    bool isCurrentUser,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF13161F).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Шапка витрины Steam с иконкой, заголовком, кнопкой быстрой смены и кнопкой настроить
            _buildShowcaseHeader(context, profile, accent, isCurrentUser),
            const SizedBox(height: 14),

            // Содержимое одного из 3 режимов витрины
            if (profile.showcaseType == 'stats_badges')
              _buildStatsBadgesShowcaseContent(context, profile, stats, accent, isCurrentUser)
            else if (profile.showcaseType == 'custom_text')
              _buildCustomTextShowcaseContent(context, profile, accent, isCurrentUser)
            else
              _buildFavoriteAnimeShowcaseContent(context, profile, accent, isCurrentUser),
          ],
        ),
      ),
    );
  }

  Widget _buildShowcaseHeader(
    BuildContext context,
    UserProfile profile,
    Color accent,
    bool isCurrentUser,
  ) {
    IconData headerIcon;
    String headerTitle;

    switch (profile.showcaseType) {
      case 'stats_badges':
        headerIcon = Icons.military_tech_rounded;
        headerTitle = 'ВИТРИНА ПРОФИЛЯ • ЗНАЧКИ И СТАТИСТИКА';
        break;
      case 'custom_text':
        headerIcon = Icons.article_rounded;
        headerTitle = 'ВИТРИНА ПРОФИЛЯ • ИНФО-БОКС';
        break;
      case 'favorite_anime':
      default:
        headerIcon = Icons.movie_filter_rounded;
        headerTitle = 'ВИТРИНА ПРОФИЛЯ • ЛЮБИМЫЙ ТАЙТЛ';
        break;
    }

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(headerIcon, color: accent, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headerTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    letterSpacing: 1.1,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isCurrentUser) ...[
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => _cycleShowcaseType(profile),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        'Сменить',
                        style: TextStyle(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => SteamProfileCustomizerSheet.show(context, profile, initialTabIndex: 4),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Настроить',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFavoriteAnimeShowcaseContent(
    BuildContext context,
    UserProfile profile,
    Color accent,
    bool isCurrentUser,
  ) {
    final favTitle = profile.favoriteAnimeTitle;
    String? showcasePoster = profile.favoriteAnimePoster;
    String? showcaseFallback = profile.favoriteAnimePoster;

    if (favTitle != null && favTitle.isNotEmpty) {
      try {
        final catalogState = getIt.isRegistered<CatalogCubit>()
            ? getIt<CatalogCubit>().state
            : (context.mounted ? context.read<CatalogCubit>().state : null);
        if (catalogState is CatalogLoaded) {
          final m = catalogState.titles.firstWhere(
            (t) =>
                (profile.favoriteAnimeId != null && t.id.toString() == profile.favoriteAnimeId) ||
                t.russianTitle.toLowerCase().trim() == favTitle.toLowerCase().trim() ||
                (t.englishTitle.isNotEmpty && t.englishTitle.toLowerCase().trim() == favTitle.toLowerCase().trim()),
          );
          showcasePoster ??= m.posterUrl;
          showcaseFallback = m.effectiveFallbackPoster;
        }
      } catch (_) {}

      if (showcasePoster == null || showcasePoster.isEmpty) {
        try {
          final listState = context.read<AnimeListCubit>().state;
          final m = listState.allEntries.firstWhere(
            (e) =>
                (profile.favoriteAnimeId != null && e.animeId.toString() == profile.favoriteAnimeId) ||
                e.cleanTitleRu.toLowerCase().trim() == favTitle.toLowerCase().trim(),
          );
          showcasePoster = m.posterUrl;
          showcaseFallback = m.posterUrl;
        } catch (_) {}
      }

      if ((showcasePoster == null || showcasePoster.isEmpty) && profile.favoriteAnimeId != null) {
        showcasePoster = 'https://desu.shikimori.one/system/animes/original/${profile.favoriteAnimeId}.jpg';
        showcaseFallback = 'https://shikimori.one/system/animes/original/${profile.favoriteAnimeId}.jpg';
      }

      if (showcaseFallback == null || showcaseFallback.isEmpty) {
        if (profile.favoriteAnimePoster != null &&
            profile.favoriteAnimePoster!.isNotEmpty &&
            profile.favoriteAnimePoster != showcasePoster) {
          showcaseFallback = profile.favoriteAnimePoster;
        } else if (profile.favoriteAnimeId != null) {
          showcaseFallback = 'https://shikimori.one/system/animes/original/${profile.favoriteAnimeId}.jpg';
        }
      }

      if (showcasePoster != null && showcasePoster.startsWith('/')) {
        showcasePoster = 'https://anilibria.top$showcasePoster';
      }
      if (showcaseFallback != null && showcaseFallback.startsWith('/')) {
        showcaseFallback = 'https://anilibria.top$showcaseFallback';
      }
    }

    if (favTitle != null && favTitle.isNotEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Широкий кинематографичный арт на фоне карточки
              CachedNetworkImage(
                imageUrl: wrapCorsSafeUrl(showcasePoster ?? ''),
                fit: BoxFit.cover,
                memCacheWidth: 600,
                errorWidget: (context, url, error) {
                  if (showcaseFallback != null && showcaseFallback.isNotEmpty) {
                    return CachedNetworkImage(
                      imageUrl: wrapCorsSafeUrl(showcaseFallback),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _buildFallbackShowcaseBackground(accent),
                    );
                  }
                  return _buildFallbackShowcaseBackground(accent);
                },
              ),

              // 2. Затемняющий кинематографичный градиент
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      const Color(0xFF0C0E14).withValues(alpha: 0.94),
                      const Color(0xFF0C0E14).withValues(alpha: 0.85),
                      const Color(0xFF0C0E14).withValues(alpha: 0.40),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),

              // 3. Контент витрины
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Слева: Вертикальный постер аниме (формат 2:3, размер 64x96, BorderRadius.circular(8))
                    Container(
                      width: 64,
                      height: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(showcasePoster ?? ''),
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          errorWidget: (_, __, ___) => _buildFallbackShowcaseBackground(accent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // По центру: Золотистый бейдж ★ ИЗБРАННЫЙ ТАЙТЛ, крупное название, просмотренные серии
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded, size: 12, color: Colors.black),
                                SizedBox(width: 4),
                                Text(
                                  '★ ИЗБРАННЫЙ ТАЙТЛ',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            favTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(Icons.play_circle_fill_rounded, size: 13, color: accent),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  (profile.bio != null && profile.bio!.isNotEmpty)
                                      ? '«${profile.bio!}»'
                                      : 'Нажмите для перехода к серии',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Справа внизу/по центру: Круглая аккуратная кнопка Play с эффектом стекла
                    GestureDetector(
                      onTap: () => _openFavoriteAnimeDetails(context, profile),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (isCurrentUser) {
      return CustomPaint(
        painter: _DashedBorderPainter(
          color: accent.withValues(alpha: 0.45),
          strokeWidth: 1.5,
          dashWidth: 6.0,
          dashSpace: 4.0,
          radius: 14.0,
        ),
        child: InkWell(
          onTap: () => SteamProfileCustomizerSheet.show(context, profile, initialTabIndex: 4),
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 100,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
                  ),
                  child: Icon(Icons.add_rounded, color: accent, size: 20),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Добавить витрину',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Закрепите тайтл на витрине вашего профиля в стиле Steam',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Пользователь еще не настроил витрину профиля',
          style: AppTypography.caption.copyWith(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBadgesShowcaseContent(
    BuildContext context,
    UserProfile profile,
    UserAnimeStats stats,
    Color accent,
    bool isCurrentUser,
  ) {
    final badge = SteamBadge.fromId(profile.badgeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Карточка значка Steam
        InkWell(
          onTap: () => BadgeDetailsSheet.show(context, badge: badge),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: badge.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: badge.color.withValues(alpha: 0.35), width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [badge.color.withValues(alpha: 0.4), badge.color.withValues(alpha: 0.15)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: badge.color.withValues(alpha: 0.7), width: 1.5),
                  ),
                  child: Icon(badge.icon, color: badge.color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              badge.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badge.color.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: badge.color, width: 0.8),
                            ),
                            child: Text(
                              'LVL ${badge.level}',
                              style: TextStyle(
                                color: badge.color,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${badge.perkTitle} • ${badge.description}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.4), size: 20),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Мини-статистика
        Row(
          children: [
            Expanded(
              child: _buildShowcaseMiniStat(
                icon: Icons.schedule_rounded,
                color: const Color(0xFF00E5FF),
                value: stats.formattedTime,
                label: 'Время',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildShowcaseMiniStat(
                icon: Icons.movie_filter_rounded,
                color: const Color(0xFFB388FF),
                value: '${stats.totalTitles}',
                label: 'Тайтлов',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildShowcaseMiniStat(
                icon: Icons.play_circle_filled_rounded,
                color: const Color(0xFFFF5252),
                value: '${stats.totalEpisodesCompleted}',
                label: 'Серий',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShowcaseMiniStat({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTextShowcaseContent(
    BuildContext context,
    UserProfile profile,
    Color accent,
    bool isCurrentUser,
  ) {
    final title = (profile.customTitle != null && profile.customTitle!.isNotEmpty)
        ? profile.customTitle!
        : 'Информация о профиле';
    final hasBio = profile.bio != null && profile.bio!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_quote_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    profile.customStatus ?? 'Смотрю аниме...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasBio)
            Text(
              '«${profile.bio!}»',
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Colors.white,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (isCurrentUser)
            InkWell(
              onTap: () => SteamProfileCustomizerSheet.show(context, profile, initialTabIndex: 4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.edit_note_rounded, size: 18, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Инфо-бокс пуст. Нажмите «Настроить», чтобы написать о себе или добавить цитату.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              'Пользователь не заполнил инфо-бокс.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  /// Блок статистики просмотра: слитная монолитная витрина с тремя метриками
  Widget _buildStatsSection(
    BuildContext context,
    UserAnimeStats stats,
    Color accent,
    Color themePrimary,
    Color themePrimaryLight,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _buildGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.insights_rounded,
                      size: 16,
                      color: themePrimaryLight,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'СТАТИСТИКА ПРОСМОТРА',
                      style: AppTypography.caption.copyWith(
                        letterSpacing: 1.2,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () => setState(() => _showActivityCharts = !_showActivityCharts),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: themePrimary.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: themePrimary.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showActivityCharts ? Icons.keyboard_arrow_up_rounded : Icons.bar_chart_rounded,
                          size: 14,
                          color: themePrimaryLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showActivityCharts ? 'Скрыть график' : 'Графики',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: themePrimaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Единая монолитная полоса статистики без 3 отдельных черных квадратов
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF141721).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMonolithicStatCol(
                      icon: Icons.schedule_rounded,
                      iconColor: const Color(0xFF00E5FF),
                      value: stats.formattedTime,
                      label: 'Время в аниме',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                  Expanded(
                    child: _buildMonolithicStatCol(
                      icon: Icons.movie_filter_rounded,
                      iconColor: const Color(0xFFB388FF),
                      value: '${stats.totalTitles}',
                      label: 'Тайтлы',
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 36,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                  Expanded(
                    child: _buildMonolithicStatCol(
                      icon: Icons.play_circle_filled_rounded,
                      iconColor: const Color(0xFFFF5252),
                      value: '${stats.totalEpisodesCompleted}',
                      label: 'Серии',
                    ),
                  ),
                ],
              ),
            ),

            if (_showActivityCharts) ...[
              const SizedBox(height: 14),
              ProfileActivityChart(stats: stats),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonolithicStatCol({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.60),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// БЛОК 1: STEAM MINI-PROFILE (Единая монолитная карточка шапки)
  Widget _buildSteamMiniProfileCard(
    BuildContext context,
    UserProfile profile,
    Color accent,
    bool isCurrentUser,
  ) {
    final badge = SteamBadge.fromId(profile.badgeId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141721).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.50),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Левая часть — Аватар в стиле Steam (80x80, радиус 14 dp, Pulse Glow, рамка)
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Фоновая анимация дыхания (Pulse Glow) мягкого акцентного цвета за аватаром
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, _) {
                        final pulse = _pulseAnimation.value;
                        return Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.25 + 0.25 * pulse),
                                blurRadius: 14 + 8 * pulse,
                                spreadRadius: 1 + 2 * pulse,
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Квадратный аватар со скруглением 14 dp
                    AppAvatar(
                      avatarUrl: profile.avatarUrl,
                      username: profile.username,
                      size: 80,
                      borderRadius: BorderRadius.circular(14),
                      borderColor: Colors.white.withValues(alpha: 0.25),
                      borderWidth: 1.5,
                    ),

                    // Рамка поверх аватара
                    if (profile.frameId != null && profile.frameId != 'none')
                      Positioned(
                        left: -12,
                        top: -12,
                        right: -12,
                        bottom: -12,
                        child: IgnorePointer(
                          child: SteamAvatarFrameWidget(
                            frameId: profile.frameId,
                            size: 80,
                            child: const SizedBox(width: 80, height: 80),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // 2. Правая часть — Инфо и Steam Badge (Expanded Column)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Верхняя строка: Никнейм (20 sp, w700) + Steam Level Badge
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SteamLevelBadge(
                          badge: badge,
                          accent: accent,
                          onTap: () => _showSteamBadgeModal(context, badge, accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),

                    // Средняя строка: Кастомный статус курсивом
                    Text(
                      '«${profile.customStatus ?? 'Смотрю аниме...'}»',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Нижняя строка: Тонкий прогресс-бар уровня Steam (450/500 XP до следующего уровня)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Уровень ${badge.level}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.50),
                              ),
                            ),
                            Text(
                              '450 / 500 XP (80%)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(
                              value: 0.8,
                              backgroundColor: Colors.white.withValues(alpha: 0.10),
                              valueColor: AlwaysStoppedAnimation<Color>(accent),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSteamBadgeModal(BuildContext context, SteamBadge badge, Color accent) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF141721),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.70),
                blurRadius: 30,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.7), const Color(0xFF2E1A47)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white38, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 16),
                  ],
                ),
                child: Icon(badge.icon, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 14),
              Text(
                'Уровень профиля: ${badge.level}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Значок: ${badge.title}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Прогресс до ${badge.level + 1} уровня:',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          '80% (450/500 XP)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 6,
                        child: LinearProgressIndicator(
                          value: 0.8,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    BadgeDetailsSheet.show(context, badge: badge);
                  },
                  child: const Text(
                    'Открыть коллекцию значков',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGuestSyncBanner(BuildContext context, Color themePrimary, Color themePrimaryLight) {
    return _buildGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.read<AuthCubit>().signInWithGoogle(),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themePrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.cloud_sync_rounded,
                color: themePrimaryLight,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: GestureDetector(
              onTap: () => context.read<AuthCubit>().signInWithGoogle(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Сохраните свой прогресс',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Войти через Google для синхронизации истории и списков',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: AppColors.textSecondary,
              size: 18,
            ),
            onPressed: _dismissGuestBanner,
            tooltip: 'Скрыть',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLight = HSLColor.fromColor(themePrimary)
        .withLightness((HSLColor.fromColor(themePrimary).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: BlocBuilder<ProfileCubit, ProfileState>(
        bloc: _profileCubit,
        builder: (context, profileState) {
          // Проверяем текущего пользователя
          User? currentUser;
          try {
            currentUser = Supabase.instance.client.auth.currentUser;
          } catch (_) {}

          UserProfile rawProfile = profileState.profile;
          String? currentUserId = currentUser?.id;

          try {
            final authState = context.watch<AuthCubit>().state;
            if (authState is Authenticated) {
              currentUserId ??= authState.profile.id;
              if (widget.userId == null || widget.userId == currentUserId) {
                rawProfile = authState.profile;
              }
            }
          } catch (_) {}

          final bool isCurrentUser = widget.userId == null ||
              widget.userId!.trim().isEmpty ||
              widget.userId == currentUserId ||
              (rawProfile.id.isNotEmpty && widget.userId == rawProfile.id);

          final isUserAnonymous = currentUser == null || currentUser.isAnonymous;
          final isGuest = rawProfile.isAnonymous || isUserAnonymous;

          final metadata = currentUser?.userMetadata;
          final googleName = (metadata?['full_name'] ?? metadata?['name']) as String?;
          final googleAvatar = (metadata?['avatar_url'] ?? metadata?['picture']) as String?;

          final profile = (isCurrentUser && !isGuest && googleName != null && (rawProfile.username.startsWith('Сенпай') || rawProfile.username == 'Гость'))
              ? rawProfile.copyWith(
                  username: googleName,
                  avatarUrl: (rawProfile.avatarUrl == null || rawProfile.avatarUrl == 'cat' || rawProfile.avatarUrl == 'none')
                      ? googleAvatar
                      : rawProfile.avatarUrl,
                )
              : rawProfile;

          UserAnimeStats stats = profileState.stats;
          if (isCurrentUser) {
            try {
              final listState = context.watch<AnimeListCubit>().state;
              stats = listState.stats;
            } catch (_) {}
          }

          final bgTheme = SteamBackgroundTheme.fromId(profile.backgroundId);
          final accent = (profile.accentColor != null && profile.accentColor != '#E06C53')
              ? SteamProfileThemeAccent.fromHex(profile.accentColor).color
              : themePrimary;

          // Фоновый арт: обои профиля или постер любимого аниме с витрины
          final headerBgUrl = (bgTheme.assetOrUrl != null && bgTheme.assetOrUrl!.isNotEmpty)
              ? bgTheme.assetOrUrl!
              : (profile.favoriteAnimePoster ?? '');

          return Stack(
            children: [
              // 1. Процедурный живой фон и частицы растянуты НА ВСЮ СТРАНИЦУ
              Positioned.fill(
                child: RepaintBoundary(
                  child: Opacity(
                    opacity: 0.70,
                    child: LiveBackgroundWidget(
                      backgroundId: profile.backgroundId,
                      assetOrUrl: bgTheme.assetOrUrl ?? profile.backgroundId,
                      fallbackGradient: bgTheme.gradient,
                      isPaused: _isBgPaused,
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E0E12).withValues(alpha: 0.45),
                  ),
                ),
              ),

              // 2. Основной CustomScrollView со SliverAppBar в стиле Steam (высота 340.0)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // ИММЕРСИВНЫЙ SLIVER APP BAR (expandedHeight: 290.0, pinned: true)
                      SliverAppBar(
                        expandedHeight: 290.0,
                        pinned: true,
                        stretch: true,
                        backgroundColor: const Color(0xFF0E0E12),
                        elevation: 0,
                        leading: widget.showBackButton
                            ? Center(
                                child: _buildRoundHeaderAction(
                                   icon: Icons.arrow_back_ios_new_rounded,
                                   tooltip: 'Назад',
                                   onTap: widget.onBack ?? () => Navigator.of(context).maybePop(),
                                ),
                              )
                            : null,
                        title: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            isCurrentUser ? 'Мой профиль' : 'Профиль друга',
                            style: AppTypography.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        actions: [
                          if (isCurrentUser) ...[
                            _buildRoundHeaderAction(
                              icon: Icons.edit_outlined,
                              tooltip: 'Редактировать профиль',
                              onTap: () => _showEditProfileSheet(context, profile),
                            ),
                            _buildRoundHeaderAction(
                              icon: Icons.palette_outlined,
                              tooltip: 'Палитра оформления',
                              iconColor: accent,
                              onTap: () => SteamProfileCustomizerSheet.show(context, profile),
                            ),
                            _buildRoundHeaderAction(
                              icon: Icons.settings,
                              tooltip: 'Настройки',
                              onTap: () => context.push('/settings'),
                            ),
                          ],
                          const SizedBox(width: 8),
                        ],
                        flexibleSpace: FlexibleSpaceBar(
                          collapseMode: CollapseMode.parallax,
                          background: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Фоновый арт профиля / живое видео / процедурный шейдер
                              LiveBackgroundWidget(
                                backgroundId: profile.backgroundId,
                                assetOrUrl: headerBgUrl.isNotEmpty
                                    ? headerBgUrl
                                    : (bgTheme.assetOrUrl ?? profile.backgroundId),
                                fallbackGradient: bgTheme.gradient,
                                isPaused: _isBgPaused,
                              ),

                              // Вертикальный градиент: Colors.transparent сверху -> 0xFF0E0E12 снизу
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.35),
                                      const Color(0xFF0E0E12).withValues(alpha: 0.85),
                                      const Color(0xFF0E0E12),
                                    ],
                                    stops: const [0.0, 0.35, 0.75, 1.0],
                                  ),
                                ),
                              ),

                              // БЛОК 1: STEAM MINI-PROFILE (Единая монолитная карточка шапки внизу)
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 10,
                                child: RepaintBoundary(
                                  child: _buildSteamMiniProfileCard(context, profile, accent, isCurrentUser),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ПЛАШКА СИНХРОНИЗАЦИИ ПРОФИЛЯ (Показывается только если свой профиль и гость)
                      if (isCurrentUser && isGuest && !_guestBannerDismissed) ...[
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: _buildGuestSyncBanner(context, themePrimary, themePrimaryLight),
                          ),
                        ),
                      ],

                      // 1. ВИТРИНА ПРОФИЛЯ В СТИЛЕ STEAM (Hero Showcase)
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      SliverToBoxAdapter(
                        child: _buildMonolithicShowcase(context, profile, stats, accent, isCurrentUser),
                      ),

                      // 2. БЛОК СТАТИСТИКИ (Слитная монолитная полоса)
                      const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      SliverToBoxAdapter(
                        child: _buildStatsSection(context, stats, accent, themePrimary, themePrimaryLight),
                      ),

                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Художник пунктирной рамки в стиле Steam (Dashed Border)
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.5,
    this.dashWidth = 6.0,
    this.dashSpace = 4.0,
    this.radius = 16.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);

    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = dashWidth.clamp(0.0, metric.length - distance);
        dashPath.addPath(
          metric.extractPath(distance, distance + length),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashSpace != dashSpace ||
      oldDelegate.radius != radius;
}

/// Анимированный значок уровня Steam с переливающейся анимацией блеска (Shimmer sweep)
class _SteamLevelBadge extends StatefulWidget {
  final SteamBadge badge;
  final Color accent;
  final VoidCallback onTap;

  const _SteamLevelBadge({
    required this.badge,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_SteamLevelBadge> createState() => _SteamLevelBadgeState();
}

class _SteamLevelBadgeState extends State<_SteamLevelBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    try {
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        _shimmerController.repeat();
      }
    } catch (_) {
      _shimmerController.repeat();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, _) {
          final t = _shimmerController.value;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.accent,
                  widget.accent.withValues(alpha: 0.75),
                  const Color(0xFF1E1430),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.30),
                  Colors.white.withValues(alpha: 0.85),
                  (math.sin(t * 2 * math.pi) + 1.0) / 2.0,
                )!,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: 0.40),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.badge.icon, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  '${widget.badge.level} LVL',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
