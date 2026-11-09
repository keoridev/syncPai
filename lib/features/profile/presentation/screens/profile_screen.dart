import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  bool _showActivityCharts = false;
  late final AnimationController _neonPulseController;
  late final Animation<double> _neonPulseAnim;
  late final ProfileCubit _profileCubit;

  static const List<String> _avatarPresets = [
    'cat', 'fox', 'panda', 'wolf', 'bolt', 'flower', 'shield', 'fire', 'gamer', 'star', 'bot'
  ];

  @override
  void initState() {
    super.initState();
    _neonPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    final isInTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    if (!isInTest) {
      _neonPulseController.repeat(reverse: true);
    }
    _neonPulseAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _neonPulseController, curve: Curves.easeInOut),
    );

    _profileCubit = getIt.isRegistered<ProfileCubit>()
        ? getIt<ProfileCubit>()
        : ProfileCubit(
            authRepository: getIt.isRegistered<AuthRepository>() ? getIt<AuthRepository>() : null,
            animeListRepository: getIt.isRegistered<AnimeListRepository>() ? getIt<AnimeListRepository>() : null,
          );
    _profileCubit.loadProfile(targetUserId: widget.userId);
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
    _neonPulseController.dispose();
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

  /// Витрина любимого тайтла в стиле Steam (горизонтальный баннер 140-160 dp)
  Widget _buildFavoriteAnimeShowcase(
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: accent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'ВИТРИНА ПРОФИЛЯ • ЛЮБИМЫЙ ТАЙТЛ',
                    style: AppTypography.caption.copyWith(
                      letterSpacing: 1.1,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              if (isCurrentUser)
                InkWell(
                  onTap: () => SteamProfileCustomizerSheet.show(context, profile, initialTabIndex: 4),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      favTitle != null ? 'Изменить' : 'Настроить',
                      style: TextStyle(
                        fontSize: 11,
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (favTitle != null && favTitle.isNotEmpty)
            _buildGlassCard(
              padding: const EdgeInsets.all(12),
              onTap: () => _openFavoriteAnimeDetails(context, profile),
              child: SizedBox(
                height: 130,
                child: Row(
                  children: [
                    // Превью постера слева
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 95,
                        height: 130,
                        child: CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(showcasePoster ?? ''),
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          errorWidget: (context, url, error) {
                            if (showcaseFallback != null && showcaseFallback.isNotEmpty) {
                              return CachedNetworkImage(
                                imageUrl: wrapCorsSafeUrl(showcaseFallback),
                                fit: BoxFit.cover,
                                memCacheWidth: 400,
                                errorWidget: (_, __, ___) => _buildFallbackShowcaseBackground(accent),
                              );
                            }
                            return _buildFallbackShowcaseBackground(accent);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Информация и кнопка воспроизведения справа
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: accent.withValues(alpha: 0.6), width: 0.8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star_rounded, size: 12, color: accent),
                                const SizedBox(width: 4),
                                const Text(
                                  'Любимое аниме',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            favTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            (profile.bio != null && profile.bio!.isNotEmpty)
                                ? '«${profile.bio!}»'
                                : 'Закреплено на витрине профиля',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.7),
                              fontStyle: (profile.bio != null && profile.bio!.isNotEmpty)
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 32,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              onPressed: () => _openFavoriteAnimeDetails(context, profile),
                              icon: const Icon(Icons.play_arrow_rounded, size: 16),
                              label: const Text('Смотреть', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (isCurrentUser)
            CustomPaint(
              painter: _DashedBorderPainter(
                color: accent.withValues(alpha: 0.45),
                strokeWidth: 1.5,
                dashWidth: 6.0,
                dashSpace: 4.0,
                radius: 20.0,
              ),
              child: _buildGlassCard(
                onTap: () => SteamProfileCustomizerSheet.show(context, profile, initialTabIndex: 4),
                child: SizedBox(
                  height: 110,
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
            )
          else
            _buildGlassCard(
              child: Center(
                child: Text(
                  'Пользователь еще не настроил витрину профиля',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Блок статистики просмотра (3 симметричные колонки без перегородок)
  Widget _buildStatsSection(
    BuildContext context,
    UserAnimeStats stats,
    Color accent,
    Color themePrimary,
    Color themePrimaryLight,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: _buildGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'СТАТИСТИКА ПРОСМОТРА',
                  style: AppTypography.caption.copyWith(
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showActivityCharts = !_showActivityCharts),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: themePrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showActivityCharts ? Icons.keyboard_arrow_up_rounded : Icons.bar_chart_rounded,
                          size: 13,
                          color: themePrimaryLight,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showActivityCharts ? 'Скрыть график' : 'Графики',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: themePrimaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 3 симметричные колонки, разделенные воздухом
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        stats.formattedTime,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Время потрачено',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${stats.totalTitles}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Тайтлы в списках',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${stats.totalEpisodesCompleted}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Серии просмотрено',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_showActivityCharts) ...[
              const SizedBox(height: 16),
              ProfileActivityChart(stats: stats),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderUserInfo(
    BuildContext context,
    UserProfile profile,
    Color accent,
    bool isCurrentUser,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Аватар 96x96 в анимированном неоновом кольце с дышащим BoxShadow
        AnimatedBuilder(
          animation: _neonPulseAnim,
          builder: (context, child) {
            final shadowFactor = _neonPulseAnim.value;
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: (0.65 * shadowFactor).clamp(0.0, 1.0)),
                    blurRadius: 20 * shadowFactor,
                    spreadRadius: 2 * shadowFactor,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: SteamAvatarFrameWidget(
            frameId: profile.frameId,
            size: 96,
            child: AppAvatar(
              avatarUrl: profile.avatarUrl,
              username: profile.username,
              size: 96,
              borderColor: accent,
              borderWidth: 2.5,
            ),
          ),
        ),
        const SizedBox(width: 16),

        // Никнейм, статус, значок и титул
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                  ),
                  if (profile.badgeId != null) ...[
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final badge = SteamBadge.fromId(profile.badgeId);
                        return InkWell(
                          onTap: () => BadgeDetailsSheet.show(context, badge: badge),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  badge.color.withValues(alpha: 0.35),
                                  badge.color.withValues(alpha: 0.15),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: badge.color.withValues(alpha: 0.8), width: 1.0),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(badge.icon, size: 12, color: badge.color),
                                const SizedBox(width: 4),
                                Text(
                                  '${badge.level}',
                                  style: TextStyle(
                                    color: badge.color,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '«${profile.customStatus ?? 'Смотрю аниме...'}»',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.85),
                  shadows: const [
                    Shadow(color: Colors.black, blurRadius: 4),
                  ],
                ),
              ),
              if (profile.customTitle != null && profile.customTitle!.isNotEmpty) ...[
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.6),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    profile.customTitle!,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
                    opacity: 0.40,
                    child: LiveBackgroundWidget(
                      backgroundId: profile.backgroundId,
                      assetOrUrl: bgTheme.assetOrUrl ?? profile.backgroundId,
                      fallbackGradient: bgTheme.gradient,
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E0E12).withValues(alpha: 0.78),
                  ),
                ),
              ),

              // 2. Основной CustomScrollView со SliverAppBar в стиле Steam (высота 340.0)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // ИММЕРСИВНЫЙ SLIVER APP BAR (expandedHeight: 340.0, pinned: true)
                      SliverAppBar(
                        expandedHeight: 340.0,
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
                              // Фоновый арт профиля во всю ширину и высоту шапки
                              if (headerBgUrl.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: wrapCorsSafeUrl(headerBgUrl),
                                  fit: BoxFit.cover,
                                  memCacheWidth: 600,
                                  errorWidget: (_, __, ___) => _buildFallbackShowcaseBackground(accent),
                                )
                              else
                                _buildFallbackShowcaseBackground(accent),

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

                              // Поверх фона (в нижней части FlexibleSpaceBar): Аватар в неоновом кольце, Имя, Бейдж
                              Positioned(
                                left: 20,
                                right: 20,
                                bottom: 16,
                                child: RepaintBoundary(
                                  child: _buildHeaderUserInfo(context, profile, accent, isCurrentUser),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // ПЛАШКА СИНХРОНИЗАЦИИ ПРОФИЛЯ (Показывается только если свой профиль и гость)
                      if (isCurrentUser && isGuest)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                            child: _buildGlassCard(
                              onTap: () => context.read<AuthCubit>().signInWithGoogle(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  Container(
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
                                  const SizedBox(width: 14),
                                  Expanded(
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
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: AppColors.textSecondary,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // 1. ВИТРИНА ПРОФИЛЯ В СТИЛЕ STEAM (Горизонтальный баннер 140-160 dp)
                      SliverToBoxAdapter(
                        child: _buildFavoriteAnimeShowcase(context, profile, accent, isCurrentUser),
                      ),

                      // 2. БЛОК СТАТИСТИКИ (3 симметричные колонки без перегородок)
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
