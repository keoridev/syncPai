import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../widgets/badge_details_sheet.dart';
import '../widgets/friends_management_sheet.dart';
import '../widgets/live_backgrounds/live_background_widget.dart';
import '../widgets/profile_activity_chart.dart';
import '../widgets/steam_profile_customizer_sheet.dart';
import '../widgets/steam_style_profile_header.dart';
import '../../services/friends_service.dart';

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
  bool _showActivityCharts = true;
  bool _guestBannerDismissed = false;
  bool _isBgPaused = false;
  int _selectedMobileTab = 0; // 0: Обзор, 1: Статистика, 2: Стена
  late final ScrollController _scrollController;
  late final ProfileCubit _profileCubit;
  final TextEditingController _commentController = TextEditingController();
  List<WatchHistoryItem> _watchHistory = [];
  List<Map<String, dynamic>> _onlineFriends = [];
  List<Map<String, String>> _wallComments = [
    {
      'author': 'Senpai_Kun',
      'text': '+rep за витрину и киберпанк тему 🔥',
      'time': '2 ч. назад',
      'avatar': 'https://api.dicebear.com/7.x/bottts/png?seed=Senpai',
    },
    {
      'author': 'NekoChan',
      'text': 'Когда совместный просмотр второго сезона? Жду в лобби!',
      'time': 'Вчера',
      'avatar': 'https://api.dicebear.com/7.x/bottts/png?seed=Neko',
    },
    {
      'author': 'OtakuMaster',
      'text': 'Топ 1 по времени за эту неделю 👏',
      'time': '3 дн. назад',
      'avatar': 'https://api.dicebear.com/7.x/bottts/png?seed=Otaku',
    },
  ];

  static const List<String> _avatarPresets = [
    'cat', 'fox', 'panda', 'wolf', 'bolt', 'flower', 'shield', 'fire', 'gamer', 'star', 'bot'
  ];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    _loadBannerDismissed();
    _loadWatchHistory();
    _loadRealFriends();
    _loadWallComments();

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

  Future<void> _loadRealFriends() async {
    final loaded = await FriendsService.getFriends();
    if (mounted) {
      setState(() => _onlineFriends = loaded);
    }
  }

  void _loadWallComments() {
    if (getIt.isRegistered<SharedPreferences>()) {
      try {
        final key = 'profile_wall_comments_${widget.userId ?? "me"}';
        final raw = getIt<SharedPreferences>().getString(key);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as List<dynamic>;
          final parsed = decoded
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
              .toList();
          if (parsed.isNotEmpty) {
            _wallComments = parsed;
          }
        }
      } catch (_) {}
    }
  }

  void _submitWallComment(UserProfile currentProfile) {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();

    setState(() {
      _wallComments.insert(0, {
        'author': currentProfile.username,
        'text': text,
        'time': 'Только что',
        'avatar': currentProfile.avatarUrl ?? 'cat',
      });
      _commentController.clear();
    });

    if (getIt.isRegistered<SharedPreferences>()) {
      try {
        final key = 'profile_wall_comments_${widget.userId ?? "me"}';
        getIt<SharedPreferences>().setString(key, jsonEncode(_wallComments));
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
      _loadRealFriends();
      _loadWallComments();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _commentController.dispose();
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

          // Вычисляем суммарное реальное время просмотра из истории
          int historyMinutes = 0;
          for (final item in _watchHistory) {
            if (item.positionMs > 0) {
              historyMinutes += (item.positionMs / 60000).round();
            }
          }

          final effectiveMinutes = stats.totalMinutesWatched > 0
              ? stats.totalMinutesWatched
              : (historyMinutes > 0 ? historyMinutes : 276); // 276 мин = 4.6 ч., точно как на графике активности

          final effectiveTitles = stats.totalTitles > 0
              ? stats.totalTitles
              : (_watchHistory.isNotEmpty ? _watchHistory.map((e) => e.titleId).toSet().length : 4);
          final effectiveEpisodes = stats.totalEpisodesCompleted > 0
              ? stats.totalEpisodesCompleted
              : (_watchHistory.isNotEmpty ? _watchHistory.length : 13);

          stats = UserAnimeStats(
            totalTitles: effectiveTitles,
            completedTitles: stats.completedTitles > 0 ? stats.completedTitles : 2,
            watchingTitles: stats.watchingTitles > 0 ? stats.watchingTitles : 1,
            plannedTitles: stats.plannedTitles > 0 ? stats.plannedTitles : 1,
            droppedTitles: stats.droppedTitles,
            totalEpisodesCompleted: effectiveEpisodes,
            totalMinutesWatched: effectiveMinutes,
          );

          final bgTheme = SteamBackgroundTheme.fromId(profile.backgroundId);
          final currentAccentColor = _resolveDynamicAccent(profile, themePrimary);
          final bool isDesktopOS = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

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

              // СЛОЙ 3: Безопасный верхний отступ + Двухколоночный десктопный или облегченный мобильный Layout
              SafeArea(
                bottom: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isDesktopOS ? 1280 : 860),
                    child: isDesktopOS
                        ? CustomScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              const SliverToBoxAdapter(child: SizedBox(height: 16)),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // ЛЕВАЯ КОЛОНКА (flex: 60)
                                      Expanded(
                                        flex: 60,
                                        child: Padding(
                                          padding: const EdgeInsets.only(bottom: 48),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              SteamStyleProfileHeader(
                                                profile: profile,
                                                isCurrentUser: isCurrentUser,
                                                showBackButton: widget.showBackButton,
                                                onBackTap: widget.onBack,
                                                onEditProfileTap: () => _showEditProfileSheet(context, profile),
                                                onCustomizerTap: () => SteamProfileCustomizerSheet.show(context, profile),
                                                onSettingsTap: () => context.push('/settings'),
                                              ),
                                              if (isCurrentUser && isGuest && !_guestBannerDismissed) ...[
                                                const SizedBox(height: 8),
                                                _buildGuestSyncBanner(context, profile, themePrimary, currentAccentColor),
                                              ],
                                              const SizedBox(height: 8),
                                              _buildFavoriteAnimeShowcase(context, profile, currentAccentColor),
                                              const SizedBox(height: 8),
                                              _RecentHistoryCarousel(
                                                items: _watchHistory,
                                                currentAccentColor: currentAccentColor,
                                                onItemTap: (item) => _openDetailsForHistory(context, item),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      // ПРАВАЯ КОЛОНКА (flex: 40)
                                      Expanded(
                                        flex: 40,
                                        child: Padding(
                                          padding: const EdgeInsets.only(bottom: 48),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              _StatsCard(
                                                stats: stats,
                                                currentAccentColor: currentAccentColor,
                                                showActivityCharts: _showActivityCharts,
                                                onToggleCharts: () => setState(() => _showActivityCharts = !_showActivityCharts),
                                              ),
                                              const SizedBox(height: 14),
                                              _buildBadgesShowcaseCard(context, currentAccentColor),
                                              const SizedBox(height: 14),
                                              _buildOnlineFriendsCard(context, currentAccentColor),
                                              const SizedBox(height: 14),
                                              _buildCommentsWallCard(context, profile, currentAccentColor),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SliverToBoxAdapter(child: SizedBox(height: 100)),
                            ],
                          )
                        : CustomScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              SliverToBoxAdapter(
                                child: SteamStyleProfileHeader(
                                  profile: profile,
                                  isCurrentUser: isCurrentUser,
                                  showBackButton: widget.showBackButton,
                                  onBackTap: widget.onBack,
                                  onEditProfileTap: () => _showEditProfileSheet(context, profile),
                                  onCustomizerTap: () => SteamProfileCustomizerSheet.show(context, profile),
                                  onSettingsTap: () => context.push('/settings'),
                                ),
                              ),
                              if (isCurrentUser && isGuest && !_guestBannerDismissed)
                                SliverToBoxAdapter(
                                  child: _buildGuestSyncBanner(context, profile, themePrimary, currentAccentColor),
                                ),
                              // Segmented Tabs на телефоне: «Обзор» | «Статистика» | «Стена»
                              SliverToBoxAdapter(
                                child: _buildMobileSegmentedTabs(currentAccentColor),
                              ),
                              if (_selectedMobileTab == 0) ...[
                                SliverToBoxAdapter(
                                  child: _buildFavoriteAnimeShowcase(context, profile, currentAccentColor),
                                ),
                                SliverToBoxAdapter(
                                  child: _RecentHistoryCarousel(
                                    items: _watchHistory,
                                    currentAccentColor: currentAccentColor,
                                    onItemTap: (item) => _openDetailsForHistory(context, item),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: _buildMobileFriendsBanner(context, currentAccentColor),
                                ),
                              ] else if (_selectedMobileTab == 1) ...[
                                SliverToBoxAdapter(
                                  child: _StatsCard(
                                    stats: stats,
                                    currentAccentColor: currentAccentColor,
                                    showActivityCharts: _showActivityCharts,
                                    onToggleCharts: () => setState(() => _showActivityCharts = !_showActivityCharts),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: _buildBadgesShowcaseCard(context, currentAccentColor),
                                ),
                              ] else ...[
                                SliverToBoxAdapter(
                                  child: _buildCommentsWallCard(context, profile, currentAccentColor),
                                ),
                              ],
                              const SliverToBoxAdapter(child: SizedBox(height: 110)),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMobileSegmentedTabs(Color accent) {
    final tabs = [
      (0, 'Обзор', Icons.auto_awesome_mosaic_rounded),
      (1, 'Статистика', Icons.bar_chart_rounded),
      (2, 'Стена', Icons.comment_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(alpha: 0.25),
                width: 1.1,
              ),
            ),
            child: Row(
              children: tabs.map((tab) {
                final index = tab.$1;
                final label = tab.$2;
                final icon = tab.$3;
                final isSelected = _selectedMobileTab == index;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedMobileTab = index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent.withValues(alpha: 0.22)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? accent.withValues(alpha: 0.55)
                              : Colors.transparent,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 14,
                            color: isSelected ? accent : Colors.white60,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? Colors.white : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileFriendsBanner(BuildContext context, Color accent) {
    final onlineCount = _onlineFriends.where((f) => f['isOnline'] == true).length;
    final subtitle = _onlineFriends.isEmpty
        ? 'Нажмите, чтобы перейти во вкладку «Вместе» и добавить друзей'
        : '$onlineCount в сети • Нажмите для совместного просмотра';

    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onTap: () => showFriendsManagementSheet(
        context,
        accentColor: accent,
        onFriendsChanged: _loadRealFriends,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.people_alt_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Друзья в сети →',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: accent, size: 22),
        ],
      ),
    );
  }

  Widget _buildFavoriteAnimeShowcase(BuildContext context, UserProfile profile, Color accent) {
    final title = (profile.favoriteAnimeTitle != null && profile.favoriteAnimeTitle!.isNotEmpty)
        ? profile.favoriteAnimeTitle!
        : 'Клинок, рассекающий демонов';
    final poster = (profile.favoriteAnimePoster != null && profile.favoriteAnimePoster!.isNotEmpty)
        ? profile.favoriteAnimePoster!
        : 'https://desu.shikimori.one/system/animes/original/38000.jpg';

    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'ЛЮБИМЫЙ ТАЙТЛ // ИЗБРАННОЕ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '★ 10/10',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 80,
                  child: CachedNetworkImage(
                    imageUrl: wrapCorsSafeUrl(poster),
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.surface,
                      child: const Icon(Icons.movie_rounded, color: Colors.white38),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Все сезоны просмотрены в SyncPai',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.favorite_rounded, size: 13, color: accent),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Главная рекомендация профиля',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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
        ],
      ),
    );
  }

  Widget _buildBadgesShowcaseCard(BuildContext context, Color accent) {
    final badges = SteamBadge.all.take(8).toList();

    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.military_tech_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'РЕДКИЕ ЗНАЧКИ И ДОСТИЖЕНИЯ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${badges.length} шт.',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: badges.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (context, index) {
              final b = badges[index];
              return Tooltip(
                message: '${b.title} (Ур. ${b.level})\n${b.description}',
                child: InkWell(
                  onTap: () => BadgeDetailsSheet.show(context, badge: b),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: b.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: b.color.withValues(alpha: 0.4), width: 1.0),
                      boxShadow: [
                        BoxShadow(
                          color: b.color.withValues(alpha: 0.15),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(b.icon, color: b.color, size: 24),
                          const SizedBox(height: 4),
                          Text(
                            'Ур. ${b.level}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: b.color,
                            ),
                          ),
                          const SizedBox(height: 2),
                          SizedBox(
                            width: 64,
                            child: Text(
                              b.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineFriendsCard(BuildContext context, Color accent) {
    final friends = _onlineFriends;
    final onlineCount = friends.where((f) => f['isOnline'] == true).length;

    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'ДРУЗЬЯ ОНЛАЙН',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.person_add_rounded, size: 16, color: accent),
                tooltip: 'Управление друзьями',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: () => showFriendsManagementSheet(
                  context,
                  accentColor: accent,
                  onFriendsChanged: _loadRealFriends,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF66).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00FF66).withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$onlineCount в сети',
                  style: const TextStyle(
                    color: Color(0xFF00FF66),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (friends.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                children: [
                  Icon(Icons.people_outline_rounded, size: 28, color: accent.withValues(alpha: 0.65)),
                  const SizedBox(height: 6),
                  const Text(
                    'Пока нет друзей онлайн',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Добавьте друзей, чтобы видеть их статус и смотреть аниме синхронно',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => showFriendsManagementSheet(
                      context,
                      accentColor: accent,
                      onFriendsChanged: _loadRealFriends,
                    ),
                    icon: Icon(Icons.person_add_alt_1_rounded, size: 15, color: accent),
                    label: const Text('Найти друзей', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: accent.withValues(alpha: 0.5)),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            )
          else
            ...friends.map((f) {
              final room = f['room'] as String?;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          AppAvatar(
                            avatarUrl: f['avatar'] as String?,
                            username: f['name'] as String?,
                            size: 34,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: f['isOnline'] == true ? const Color(0xFF57CBDE) : Colors.white38,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF14161F), width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              f['name'] as String,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              f['status'] as String,
                              style: TextStyle(
                                color: room != null ? accent : Colors.white60,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (room != null && room.isNotEmpty)
                        ElevatedButton(
                          onPressed: () => context.push('/room/$room'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: AppColors.onColor(accent),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          child: const Text('Войти', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildCommentsWallCard(BuildContext context, UserProfile profile, Color accent) {
    final comments = _wallComments;

    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.comment_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              const Flexible(
                child: Text(
                  'СТЕНА КОММЕНТАРИЕВ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${comments.length} записи',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white60,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Поле ввода комментария
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    onSubmitted: (_) => _submitWallComment(profile),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Оставить комментарий в профиле...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 11.5,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _submitWallComment(profile),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.send_rounded, size: 17, color: accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...comments.map((c) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                    avatarUrl: c['avatar'],
                    username: c['author'],
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c['author'] ?? 'Отаку',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              c['time'] ?? '',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c['text'] ?? '',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
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
    final watchTimeStr = (stats.formattedTime.isNotEmpty && stats.formattedTime != '0 мин.')
        ? stats.formattedTime
        : '4 ч. 36 мин.';
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
              const Expanded(
                child: Text(
                  'СТАТИСТИКА ПРОСМОТРА',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 6),
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
    final rawItems = items.isNotEmpty ? items : _fallbackSampleItems;
    // Дедупликация по titleId, чтобы серии одного аниме не дублировались карточками
    final seenIds = <int>{};
    final displayItems = rawItems.where((i) => seenIds.add(i.titleId)).toList();

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
              Flexible(
                child: Text(
                  'НЕДАВНО ПРОСМОТРЕНО',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: currentAccentColor,
                  ),
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

    return RepaintBoundary(
      child: Padding(
        padding: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
            child: onTap != null
                ? InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(20),
                    child: cardContent,
                  )
                : cardContent,
          ),
        ),
      ),
    );
  }
}


