import 'dart:io' show Platform, File;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import '../../../auth/presentation/widgets/auth_modal_sheet.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../watch_history/domain/entities/watch_history_item.dart';
import '../../../watch_history/domain/repositories/watch_history_repository.dart';
import '../../domain/entities/steam_profile_customization.dart';
import '../cubit/profile_cubit.dart';
import '../cubit/profile_state.dart';
import '../widgets/live_backgrounds/live_background_widget.dart';
import '../widgets/profile_activity_chart.dart';
import '../widgets/steam_profile_customizer_sheet.dart';

/// Экран профиля пользователя (UserProfileScreen) SyncPai:
/// Концепция: Гибрид Steam Showcase и Discord Nitro.
/// Стиль: Темный киберпанк / глассморфизм (Liquid Glass) с динамической темой
/// под выбранный фон (Матрица / Сакура / Киберпанк / Discord).
class ProfileScreen extends StatefulWidget {
  final String? userId; // Если null — мой профиль. Если передано — профиль друга.
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
  List<WatchHistoryItem> _watchHistory = [];

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
    _loadWatchHistory();

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

  Future<void> _loadWatchHistory() async {
    if (getIt.isRegistered<WatchHistoryRepository>()) {
      try {
        final items = await getIt<WatchHistoryRepository>().getAllHistory();
        if (mounted) {
          setState(() => _watchHistory = items);
        }
      } catch (_) {}
    }
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
      _loadWatchHistory();
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

  /// Динамический Accent Color (Киберпанк / Матрица / Сакура / Discord)
  Color _resolveDynamicAccent(UserProfile profile, Color themePrimary) {
    final bg = (profile.backgroundId ?? '').toLowerCase();
    if (bg.contains('matrix')) {
      return const Color(0xFF00FF66); // Зеленый неон Матрицы
    }
    if (bg.contains('sakura')) {
      return const Color(0xFFFF2A6D); // Неоново-розовая Сакура
    }
    if (bg.contains('cyberpunk') || bg.contains('neon')) {
      return const Color(0xFF00F0FF); // Циан Cyberpunk
    }
    if (profile.accentColor != null &&
        profile.accentColor!.isNotEmpty &&
        profile.accentColor != '#E06C53' &&
        profile.accentColor != '#8A2BE2') {
      return SteamProfileThemeAccent.fromHex(profile.accentColor!).color;
    }
    // По умолчанию: Discord Blurple
    return const Color(0xFF5865F2);
  }

  String _extractDiscordTag(String id) {
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 4) {
      return digits.substring(digits.length - 4);
    }
    return '5627';
  }

  void _openDetailsForHistory(BuildContext context, WatchHistoryItem item) {
    try {
      final entry = context.read<AnimeListCubit>().state.getEntryFor(item.titleId);
      if (entry != null) {
        final title = AnimeTitle(
          id: entry.animeId,
          code: 'title-${entry.animeId}',
          russianTitle: entry.cleanTitleRu,
          englishTitle: '',
          posterSmall: entry.posterUrl ?? '',
          posterMedium: entry.posterUrl ?? '',
          posterOriginal: entry.posterUrl ?? '',
          genres: const [],
          description: '',
          status: '',
        );
        context.pushNamed('details', extra: title);
        return;
      }
    } catch (_) {}

    final fallback = AnimeTitle(
      id: item.titleId,
      code: 'history-${item.titleId}',
      russianTitle: item.titleName,
      englishTitle: '',
      posterSmall: item.posterUrl,
      posterMedium: item.posterUrl,
      posterOriginal: item.posterUrl,
      genres: const [],
      description: '',
      status: '',
    );
    context.pushNamed('details', extra: fallback);
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.25),
                      accent.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(color: accent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.40),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Icon(badge.icon, size: 44, color: accent),
              ),
              const SizedBox(height: 14),
              Text(
                '★ Уровень профиля: ${badge.level}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 6),
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
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Прогресс до ${badge.level + 1} уровня',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        Text(
                          '450 / 500 XP (80%)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: 0.8,
                        minHeight: 6,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Понятно', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditProfileSheet(BuildContext context, UserProfile profile) {
    final controller = TextEditingController(text: profile.username);
    final avatarUrlController = TextEditingController(
      text: (profile.avatarUrl?.startsWith('http') == true) ? profile.avatarUrl : '',
    );
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
                Row(
                  children: [
                    Text(
                      'Редактировать профиль',
                      style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.palette_outlined, color: AppColors.textSecondary, size: 20),
                      tooltip: 'Полная кастомизация Steam',
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        SteamProfileCustomizerSheet.show(context, profile);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Превью аватара
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: AppAvatar(
                      avatarUrl: selectedAvatar,
                      username: controller.text.isNotEmpty ? controller.text : profile.username,
                      size: 72,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Кнопка загрузки из галереи
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                    label: const Text('Загрузить фото из галереи'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6), width: 1.2),
                      backgroundColor: AppColors.surface,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      try {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          withData: true,
                        );
                        if (result != null && result.files.isNotEmpty) {
                          final file = result.files.first;
                          final appDir = await getApplicationDocumentsDirectory();
                          final ext = file.extension ?? 'jpg';
                          final targetPath = '${appDir.path}/custom_avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
                          final targetFile = File(targetPath);
                          if (file.bytes != null) {
                            await targetFile.writeAsBytes(file.bytes!);
                          } else if (file.path != null) {
                            await File(file.path!).copy(targetPath);
                          }
                          setSheetState(() {
                            selectedAvatar = targetPath;
                            avatarUrlController.text = targetPath;
                          });
                        }
                      } catch (e) {
                        debugPrint('Error picking avatar file: $e');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                Text('Имя пользователя', style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Введите имя',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.strokeMedium),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text('URL ссылки на аватар', style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                TextField(
                  controller: avatarUrlController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://.../avatar.png',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.strokeMedium),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.trim().isNotEmpty) {
                      setSheetState(() => selectedAvatar = val.trim());
                    }
                  },
                ),
                const SizedBox(height: 16),

                Text('Или выберите силуэт:', style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _avatarPresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final preset = _avatarPresets[index];
                      final isSelected = selectedAvatar == preset;
                      return GestureDetector(
                        onTap: () => setSheetState(() {
                          selectedAvatar = preset;
                          avatarUrlController.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: AppAvatar(avatarUrl: preset, size: 48),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final newName = controller.text.trim();
                      final finalAvatar = avatarUrlController.text.trim().isNotEmpty
                          ? avatarUrlController.text.trim()
                          : selectedAvatar;

                      if (newName.isNotEmpty) {
                        context.read<AuthCubit>().updateProfile(
                              username: newName,
                              avatarUrl: finalAvatar,
                            );
                        Navigator.pop(sheetContext);
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Сохранить'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestSyncBanner(BuildContext context, UserProfile profile, Color themePrimary, Color accent) {
    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => AuthModalSheet.show(context, profile),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.account_circle_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Войти или создать аккаунт',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Вход по Email / Google для сохранения истории и списков',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
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

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: BlocBuilder<ProfileCubit, ProfileState>(
        bloc: _profileCubit,
        builder: (context, state) {
          final isFriend = widget.userId != null && widget.userId!.isNotEmpty;
          UserProfile profile;

          if (isFriend) {
            profile = state.profile;
          } else {
            final authState = context.watch<AuthCubit>().state;
            if (authState is Authenticated) {
              profile = authState.profile;
            } else {
              profile = state.profile;
            }
          }

          final isCurrentUser = !isFriend;
          final isGuest = profile.isAnonymous;

          UserAnimeStats stats = state.stats;
          if (isCurrentUser) {
            try {
              final listState = context.watch<AnimeListCubit>().state;
              stats = listState.stats;
            } catch (_) {}
          }

          final bgTheme = SteamBackgroundTheme.fromId(profile.backgroundId);
          final currentAccentColor = _resolveDynamicAccent(profile, themePrimary);

          final headerBgUrl = (bgTheme.assetOrUrl != null && bgTheme.assetOrUrl!.isNotEmpty)
              ? bgTheme.assetOrUrl!
              : (profile.favoriteAnimePoster ?? '');

          return Stack(
            children: [
              // СЛОЙ 1: Анимированный / Живой / Видео фон на весь экран
              if (profile.backgroundId != 'none')
                Positioned.fill(
                  child: RepaintBoundary(
                    child: Opacity(
                      opacity: 0.75,
                      child: LiveBackgroundWidget(
                        backgroundId: profile.backgroundId,
                        assetOrUrl: bgTheme.assetOrUrl ?? profile.backgroundId,
                        fallbackGradient: bgTheme.gradient,
                        isPaused: _isBgPaused,
                      ),
                    ),
                  ),
                ),

              // СЛОЙ 2: Киберпанк-виньетка для глубокого контраста и читаемости текста
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.25),
                          Colors.transparent,
                          const Color(0xFF0E0E12).withValues(alpha: 0.70),
                          const Color(0xFF0E0E12).withValues(alpha: 0.96),
                        ],
                        stops: const [0.0, 0.20, 0.65, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // СЛОЙ 3: CustomScrollView со всеми глассморфными карточками
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // 1. HEADER (Баннер 150dp + Наплыв круглого аватара 84dp на стык)
                      SliverToBoxAdapter(
                        child: _ProfileHeader(
                          profile: profile,
                          headerBgUrl: headerBgUrl,
                          bgTheme: bgTheme,
                          currentAccentColor: currentAccentColor,
                          pulseAnimation: _pulseAnimation,
                          isCurrentUser: isCurrentUser,
                          showBackButton: widget.showBackButton,
                          onBack: widget.onBack,
                          onEditAvatar: () => _showEditProfileSheet(context, profile),
                          onOpenCustomizer: () => SteamProfileCustomizerSheet.show(context, profile),
                          onOpenSettings: () => context.push('/settings'),
                        ),
                      ),

                      // 2. БЛОК ЛИЧНОСТИ (User Info Card)
                      SliverToBoxAdapter(
                        child: _UserInfoCard(
                          profile: profile,
                          discordTag: _extractDiscordTag(profile.id),
                          currentAccentColor: currentAccentColor,
                          onBadgeTap: (badge) => _showSteamBadgeModal(context, badge, currentAccentColor),
                        ),
                      ),

                      // ПЛАШКА СИНХРОНИЗАЦИИ (Только для гостя в своем профиле)
                      if (isCurrentUser && isGuest && !_guestBannerDismissed)
                        SliverToBoxAdapter(
                          child: _buildGuestSyncBanner(context, profile, themePrimary, currentAccentColor),
                        ),

                      // 3. ВИТРИНА STEAM: «ЛЮБИМЫЙ ТАЙТЛ» (Favorite Anime Showcase)
                      SliverToBoxAdapter(
                        child: _FavoriteAnimeShowcase(
                          profile: profile,
                          currentAccentColor: currentAccentColor,
                          isCurrentUser: isCurrentUser,
                          onSelectAnime: () => SteamProfileCustomizerSheet.show(context, profile, initialTabIndex: 4),
                        ),
                      ),

                      // 4. БЛОК «СТАТИСТИКА ПРОСМОТРА» (Watch Stats Card)
                      SliverToBoxAdapter(
                        child: _StatsCard(
                          stats: stats,
                          currentAccentColor: currentAccentColor,
                          showActivityCharts: _showActivityCharts,
                          onToggleCharts: () => setState(() => _showActivityCharts = !_showActivityCharts),
                        ),
                      ),

                      // 5. ВИТРИНА «НЕДАВНО ПРОСМОТРЕННЫЕ СЕРИИ» (Recent Watch History)
                      SliverToBoxAdapter(
                        child: _RecentHistoryCarousel(
                          items: _watchHistory,
                          currentAccentColor: currentAccentColor,
                          onItemTap: (item) => _openDetailsForHistory(context, item),
                        ),
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

// ============================================================================
// 1. HEADER (Баннер 150dp + Кнопки управления + Круглый аватар 84dp на стыке)
// ============================================================================
class _ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final String headerBgUrl;
  final SteamBackgroundTheme bgTheme;
  final Color currentAccentColor;
  final Animation<double> pulseAnimation;
  final bool isCurrentUser;
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback onEditAvatar;
  final VoidCallback onOpenCustomizer;
  final VoidCallback onOpenSettings;

  const _ProfileHeader({
    required this.profile,
    required this.headerBgUrl,
    required this.bgTheme,
    required this.currentAccentColor,
    required this.pulseAnimation,
    required this.isCurrentUser,
    required this.showBackButton,
    this.onBack,
    required this.onEditAvatar,
    required this.onOpenCustomizer,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    const bannerHeight = 150.0;
    const avatarRadius = 42.0; // Диаметр 84 dp

    return SizedBox(
      height: bannerHeight + avatarRadius, // 192 dp
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1.1 Баннер (Steam Cover) высотой 150dp
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: bannerHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Фоновое изображение или арт баннера
                if (headerBgUrl.isNotEmpty && (headerBgUrl.startsWith('http') || headerBgUrl.startsWith('file:') || headerBgUrl.contains('/')))
                  CachedNetworkImage(
                    imageUrl: wrapCorsSafeUrl(headerBgUrl),
                    fit: BoxFit.cover,
                    memCacheWidth: 800,
                    errorWidget: (_, __, ___) => _buildFallbackBanner(),
                  )
                else
                  _buildFallbackBanner(),

                // Полупрозрачный градиент снизу вверх (от прозрачного к Colors.black.withOpacity(0.8))
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.80),
                      ],
                      stops: const [0.0, 0.35, 1.0],
                    ),
                  ),
                ),

                // Верхняя панель: Кнопка "Назад", Плашка "Мой профиль", Кнопки действий
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        if (showBackButton)
                          _buildGlassIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            tooltip: 'Назад',
                            onTap: onBack ?? () => Navigator.of(context).maybePop(),
                          ),
                        const SizedBox(width: 8),
                        Container(
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
                        const Spacer(),
                        if (isCurrentUser) ...[
                          _buildGlassIconButton(
                            icon: Icons.palette_outlined,
                            tooltip: 'Оформление профиля',
                            iconColor: currentAccentColor,
                            onTap: onOpenCustomizer,
                          ),
                          const SizedBox(width: 8),
                          _buildGlassIconButton(
                            icon: Icons.settings,
                            tooltip: 'Настройки',
                            onTap: onOpenSettings,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 1.2 Круглый аватар 84dp на стыке баннера (bottom: 0 от SizedBox = bottom: -42 от баннера)
          Positioned(
            left: 20,
            bottom: 0,
            child: GestureDetector(
              onTap: isCurrentUser ? onEditAvatar : null,
              child: SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Неоновое свечение вокруг аватара с мягким дыханием pulse glow
                    AnimatedBuilder(
                      animation: pulseAnimation,
                      builder: (context, _) {
                        final pulse = pulseAnimation.value;
                        return Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: currentAccentColor.withValues(alpha: 0.28 + 0.22 * pulse),
                                blurRadius: 18 + 8 * pulse,
                                spreadRadius: 2 + 2 * pulse,
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Аватар диаметром 84dp
                    AppAvatar(
                      avatarUrl: profile.avatarUrl,
                      username: profile.username,
                      size: 84,
                      borderColor: currentAccentColor,
                      borderWidth: 2.2,
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
                            size: 84,
                            child: const SizedBox(width: 84, height: 84),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassIconButton({
    required IconData icon,
    required String tooltip,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.black.withValues(alpha: 0.40),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Icon(icon, size: 18, color: iconColor ?? Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            currentAccentColor.withValues(alpha: 0.35),
            const Color(0xFF141721),
            Colors.black,
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. БЛОК ЛИЧНОСТИ (User Info Card)
// ============================================================================
class _UserInfoCard extends StatelessWidget {
  final UserProfile profile;
  final String discordTag;
  final Color currentAccentColor;
  final void Function(SteamBadge) onBadgeTap;

  const _UserInfoCard({
    required this.profile,
    required this.discordTag,
    required this.currentAccentColor,
    required this.onBadgeTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = SteamBadge.fromId(profile.badgeId);

    return _GlassCard(
      accentColor: currentAccentColor,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Верхняя строка: Имя пользователя + Дискорд-тег + Steam Level Badge
          Row(
            children: [
              Flexible(
                child: Text(
                  profile.username.isNotEmpty ? profile.username : 'Сенпай',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              Text(
                ' #$discordTag',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),

              // Steam Level Badge: Компактный капсульный бейдж
              InkWell(
                onTap: () => onBadgeTap(badge),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: currentAccentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: currentAccentColor, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: currentAccentColor.withValues(alpha: 0.20),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '★ ${badge.level} LVL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: currentAccentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Кастомный статус курсивом
          Text(
            '«${profile.customStatus ?? 'Смотрю аниме...'}»',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Colors.white70,
            ),
          ),

          if (profile.customTitle != null && profile.customTitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile.customTitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: currentAccentColor.withValues(alpha: 0.90),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // XP Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                value: 0.80,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation<Color>(currentAccentColor),
              ),
            ),
          ),
          const SizedBox(height: 5),

          // Подпись под прогресс-баром
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Уровень ${badge.level}',
                style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
              ),
              Text(
                '450 / 500 XP (80%)',
                style: TextStyle(fontSize: 11, color: currentAccentColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 3. ВИТРИНА STEAM: «ЛЮБИМЫЙ ТАЙТЛ» (Favorite Anime Showcase)
// ============================================================================
class _FavoriteAnimeShowcase extends StatelessWidget {
  final UserProfile profile;
  final Color currentAccentColor;
  final bool isCurrentUser;
  final VoidCallback onSelectAnime;

  const _FavoriteAnimeShowcase({
    required this.profile,
    required this.currentAccentColor,
    required this.isCurrentUser,
    required this.onSelectAnime,
  });

  @override
  Widget build(BuildContext context) {
    final hasFavorite = profile.favoriteAnimeTitle != null && profile.favoriteAnimeTitle!.trim().isNotEmpty;

    return _GlassCard(
      accentColor: currentAccentColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок витрины: Иконка + Текст + Кнопка Изменить
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, size: 14, color: currentAccentColor),
              const SizedBox(width: 6),
              Text(
                'ВИТРИНА: ЛЮБИМОЕ АНИМЕ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: currentAccentColor,
                ),
              ),
              const Spacer(),
              if (isCurrentUser)
                InkWell(
                  onTap: onSelectAnime,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded, size: 12, color: currentAccentColor),
                        const SizedBox(width: 4),
                        Text(
                          'Изменить',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: currentAccentColor),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Содержимое карточки витрины
          if (hasFavorite) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Постер 2:3 (75x110) со скруглением 12dp и тенью
                Container(
                  width: 75,
                  height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: currentAccentColor.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: (profile.favoriteAnimePoster != null && profile.favoriteAnimePoster!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: wrapCorsSafeUrl(profile.favoriteAnimePoster!),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _buildFallbackPoster(),
                          )
                        : _buildFallbackPoster(),
                  ),
                ),
                const SizedBox(width: 14),

                // Справа: Название, Метаданные, Цитата, Статус
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Название тайтла: жирный шрифт, 2 строки max, ellipsis
                      Text(
                        profile.favoriteAnimeTitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Метаданные: Рейтинг + Жанры
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB800).withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFFB800), width: 0.8),
                            ),
                            child: const Text(
                              '★ 9.4',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFFB800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Flexible(
                            child: Text(
                              'Экшен • Киберпанк',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: Colors.white60),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Любимая цитата пользователя о тайтле в кавычках
                      Text(
                        '«${(profile.bio != null && profile.bio!.isNotEmpty) ? profile.bio : 'Шедевр анимации, изменивший всё.'}»',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Индикатор: Просмотрено целиком
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded, size: 13, color: currentAccentColor),
                          const SizedBox(width: 5),
                          Text(
                            'Просмотрено целиком (24/24 эп.)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: currentAccentColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            // Empty State: Пунктирный полупрозрачный контейнер с кнопкой
            CustomPaint(
              painter: _DashedBorderPainter(
                color: currentAccentColor.withValues(alpha: 0.35),
                strokeWidth: 1.2,
                dashWidth: 6,
                dashSpace: 4,
                radius: 14,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Center(
                  child: InkWell(
                    onTap: onSelectAnime,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline_rounded, size: 18, color: currentAccentColor),
                          const SizedBox(width: 8),
                          Text(
                            '+ Выбрать любимый тайтл из каталога',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: currentAccentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFallbackPoster() {
    return Container(
      color: Colors.white10,
      child: Center(
        child: Icon(Icons.movie_rounded, size: 30, color: currentAccentColor.withValues(alpha: 0.5)),
      ),
    );
  }
}

// ============================================================================
// 4. БЛОК «СТАТИСТИКА ПРОСМОТРА» (Watch Stats Card)
// ============================================================================
class _StatsCard extends StatelessWidget {
  final UserAnimeStats stats;
  final Color currentAccentColor;
  final bool showActivityCharts;
  final VoidCallback onToggleCharts;

  const _StatsCard({
    required this.stats,
    required this.currentAccentColor,
    required this.showActivityCharts,
    required this.onToggleCharts,
  });

  @override
  Widget build(BuildContext context) {
    final watchTimeStr = stats.formattedTime.isNotEmpty
        ? stats.formattedTime
        : '5 ч. 14 мин.';
    final totalTitles = stats.totalTitles > 0 ? stats.totalTitles : 4;
    final totalEpisodes = stats.totalEpisodesCompleted > 0 ? stats.totalEpisodesCompleted : 13;

    return _GlassCard(
      accentColor: currentAccentColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок: иконка графика + СТАТИСТИКА ПРОСМОТРА + кнопка Графика / Детали
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 15, color: currentAccentColor),
              const SizedBox(width: 6),
              const Text(
                'СТАТИСТИКА ПРОСМОТРА',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onToggleCharts,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        showActivityCharts ? Icons.keyboard_arrow_up_rounded : Icons.insights_rounded,
                        size: 13,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        showActivityCharts ? 'Скрыть детали' : 'Графика / Детали',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Горизонтальный ряд из 3 равных колонок с разделителями
          Row(
            children: [
              // 1. Время в аниме
              Expanded(
                child: _buildStatCol(
                  icon: Icons.access_time_rounded,
                  value: watchTimeStr,
                  label: 'Общее время',
                ),
              ),
              Container(width: 1, height: 38, color: Colors.white.withValues(alpha: 0.12)),

              // 2. Тайтлы
              Expanded(
                child: _buildStatCol(
                  icon: Icons.video_library_rounded,
                  value: '$totalTitles',
                  label: 'В коллекции',
                ),
              ),
              Container(width: 1, height: 38, color: Colors.white.withValues(alpha: 0.12)),

              // 3. Серии
              Expanded(
                child: _buildStatCol(
                  icon: Icons.play_circle_outline_rounded,
                  value: '$totalEpisodes',
                  label: 'Эпизодов',
                ),
              ),
            ],
          ),

          // Дополнительные статусные метки коллекции (Смотрю, Просмотрено, В планах)
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildCategoryPill(
                label: 'В процессе: ${stats.watchingTitles > 0 ? stats.watchingTitles : 1}',
                color: currentAccentColor,
              ),
              _buildCategoryPill(
                label: 'Просмотрено: ${stats.completedTitles > 0 ? stats.completedTitles : 2}',
                color: const Color(0xFF00FF66),
              ),
              _buildCategoryPill(
                label: 'В планах: ${stats.plannedTitles > 0 ? stats.plannedTitles : 1}',
                color: Colors.white54,
              ),
            ],
          ),

          // Развернутая детальная аналитика и график активности
          if (showActivityCharts) ...[
            const SizedBox(height: 14),
            ProfileActivityChart(stats: stats),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCol({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: currentAccentColor),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white60,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================================
// 5. ВИТРИНА «НЕДАВНО ПРОСМОТРЕННЫЕ СЕРИИ» (Recent Watch History)
// ============================================================================
class _RecentHistoryCarousel extends StatelessWidget {
  final List<WatchHistoryItem> items;
  final Color currentAccentColor;
  final void Function(WatchHistoryItem) onItemTap;

  const _RecentHistoryCarousel({
    required this.items,
    required this.currentAccentColor,
    required this.onItemTap,
  });

  static final List<WatchHistoryItem> _fallbackSampleItems = [
    WatchHistoryItem(
      titleId: 40748,
      titleName: 'Магическая битва',
      posterUrl: 'https://desu.shikimori.one/system/animes/original/40748.jpg',
      episode: 5,
      episodeName: 'Расставание',
      positionMs: 445000, // 07:25
      durationMs: 1440000, // 24:00
      updatedAt: DateTime.now(),
    ),
    WatchHistoryItem(
      titleId: 16498,
      titleName: 'Атака титанов',
      posterUrl: 'https://desu.shikimori.one/system/animes/original/16498.jpg',
      episode: 12,
      episodeName: 'Рана',
      positionMs: 1120000, // 18:40
      durationMs: 1435000, // 23:55
      updatedAt: DateTime.now(),
    ),
    WatchHistoryItem(
      titleId: 52991,
      titleName: 'Провожающая в последний путь Фрирен',
      posterUrl: 'https://desu.shikimori.one/system/animes/original/52991.jpg',
      episode: 4,
      episodeName: 'По следам героя',
      positionMs: 745000, // 12:25
      durationMs: 1440000, // 24:00
      updatedAt: DateTime.now(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final displayItems = items.isNotEmpty ? items : _fallbackSampleItems;

    return _GlassCard(
      accentColor: currentAccentColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок витрины
          Row(
            children: [
              Icon(Icons.history_rounded, size: 15, color: currentAccentColor),
              const SizedBox(width: 6),
              Text(
                'НЕДАВНО ПРОСМОТРЕНО',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: currentAccentColor,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  if (displayItems.isNotEmpty) {
                    onItemTap(displayItems.first);
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Вся история >',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: currentAccentColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Горизонтальный скролл эпизодов (16:9)
          SizedBox(
            height: 135,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: displayItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = displayItems[index];
                return _buildRecentCard(context, item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentCard(BuildContext context, WatchHistoryItem item) {
    const cardWidth = 140.0;
    const previewHeight = 78.0; // 16:9

    return InkWell(
      onTap: () => onItemTap(item),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Превью 16:9 с прогресс-баром и кнопкой Play
            Container(
              width: cardWidth,
              height: previewHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 0.8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.posterUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: wrapCorsSafeUrl(item.posterUrl),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildFallbackPreview(),
                      )
                    else
                      _buildFallbackPreview(),

                    // Черная полупрозрачная маска
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                    ),

                    // Иконка Play по центру
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.55),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.8),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                      ),
                    ),

                    // Полоска прогресса и таймкод внизу превью
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '${item.formattedPosition} / ${item.formattedDuration}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                            child: LinearProgressIndicator(
                              value: item.progress > 0 ? item.progress : 0.45,
                              minHeight: 3,
                              backgroundColor: Colors.white.withValues(alpha: 0.20),
                              valueColor: AlwaysStoppedAnimation<Color>(currentAccentColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Название тайтла (1 строка, ellipsis)
            Text(
              item.titleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),

            // Номер серии (например: Серия 2 • Расставание)
            Text(
              'Серия ${item.episode}${item.episodeName != null && item.episodeName!.isNotEmpty ? ' • ${item.episodeName}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackPreview() {
    return Container(
      color: const Color(0xFF1B1E2B),
      child: Center(
        child: Icon(Icons.movie_filter_rounded, size: 24, color: currentAccentColor.withValues(alpha: 0.45)),
      ),
    );
  }
}

// ============================================================================
// БАЗОВАЯ КАРТОЧКА ГЛАССМОРФИЗМА (Liquid Glass)
// ============================================================================
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  const _GlassCard({
    required this.child,
    required this.accentColor,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: onTap != null
              ? InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(20),
                  child: cardContent,
                )
              : cardContent,
        ),
      ),
    );
  }
}

// ============================================================================
// ХУДОЖНИК ПУНКТИРНОЙ РАМКИ STEAM (Dashed Border)
// ============================================================================
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 1.2,
    this.dashWidth = 6.0,
    this.dashSpace = 4.0,
    this.radius = 14.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final len = (distance + dashWidth < metric.length) ? dashWidth : metric.length - distance;
        canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashWidth != dashWidth ||
      oldDelegate.dashSpace != dashSpace ||
      oldDelegate.radius != radius;
}
