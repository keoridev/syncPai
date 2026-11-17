import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../cubit/coop_match_cubit.dart';
import '../cubit/coop_match_state.dart';
import '../widgets/match_confetti_blast_widget.dart';

/// Псевдоним для экрана свайпов аниме-матчинга
typedef AnimeMatchScreen = CoopMatchScreen;

class CoopMatchScreen extends StatefulWidget {
  final CoopMatchCubit cubit;
  final Function(AnimeTitle matched)? onStartWatching;

  const CoopMatchScreen({
    super.key,
    required this.cubit,
    this.onStartWatching,
  });

  static Future<void> open(
    BuildContext context, {
    required List<AnimeTitle> deck,
    String? roomCode,
    String userName = 'Я',
    dynamic syncRepository,
    Function(AnimeTitle matched)? onStartWatching,
  }) {
    final cubit = CoopMatchCubit(
      initialDeck: deck,
      roomCode: roomCode,
      userName: userName,
      syncRepository: syncRepository,
    );

    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CoopMatchScreen(
          cubit: cubit,
          onStartWatching: onStartWatching,
        ),
      ),
    );
  }

  @override
  State<CoopMatchScreen> createState() => _CoopMatchScreenState();
}

class _CoopMatchScreenState extends State<CoopMatchScreen>
    with SingleTickerProviderStateMixin {
  Offset _dragOffset = Offset.zero;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    widget.cubit.close();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Легкая тактильная отдача при активном движении карточки
    if (_dragOffset.dx.abs() > 40 && (_dragOffset.dx - details.delta.dx).abs() <= 40) {
      HapticFeedback.selectionClick();
    }
    setState(() {
      _dragOffset += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    const threshold = 55.0;
    final velocityX = details.velocity.pixelsPerSecond.dx;
    if (_dragOffset.dx > threshold || velocityX > 300) {
      // Свайп вправо: Лайк
      HapticFeedback.mediumImpact();
      widget.cubit.voteCurrent(true);
    } else if (_dragOffset.dx < -threshold || velocityX < -300) {
      // Свайп влево: Скип
      HapticFeedback.lightImpact();
      widget.cubit.voteCurrent(false);
    }
    setState(() {
      _dragOffset = Offset.zero;
    });
  }

  void _openAnimeDetails(BuildContext context, AnimeTitle anime) {
    context.push('/anime/${anime.id}', extra: anime);
  }

  void _openCurrentCardDetails(BuildContext context) {
    final activeAnime = widget.cubit.state.currentTitle;
    if (activeAnime == null) return;
    _openAnimeDetails(context, activeAnime);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: widget.cubit,
      child: BlocConsumer<CoopMatchCubit, CoopMatchState>(
        listener: (context, state) {
          if (state.isSuspenseReveal) {
            HapticFeedback.mediumImpact();
          }
          if (state.isStartingPlayback && state.matchedTitle != null) {
            HapticFeedback.vibrate();
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            widget.onStartWatching?.call(state.matchedTitle!);
            return;
          }
          if (state.matchedTitle != null && !state.isStartingPlayback) {
            HapticFeedback.vibrate();
            _showMatchDialog(context, state.matchedTitle!);
          }
        },
        builder: (context, state) {
          return Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent || state.hasFinishedDeck) {
                return KeyEventResult.ignored;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                widget.cubit.voteCurrent(false);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                widget.cubit.voteCurrent(true);
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                _openCurrentCardDetails(context);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Anime Match', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      '${state.currentIndex + 1}/${state.deck.length}',
                      style: AppTypography.badge.copyWith(color: AppColors.primaryLight, fontSize: 11),
                    ),
                  ),
                ],
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: SafeArea(
              child: Builder(
                builder: (context) {
                  final isDesktop = MediaQuery.of(context).size.width >= 900;
                  return Stack(
                    children: [
                      Column(
                        children: [
                          // Подзаголовок режима
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                            child: Text(
                              state.peerName != null
                                  ? 'Свайпайте вдвоем с ${state.peerName}. При совпадении серия запустится!'
                                  : (isDesktop
                                      ? 'Выбирайте интересные тайтлы клавишами ← (Скип) и → (В планы)'
                                      : 'Свайпайте вправо — хочу смотреть, влево — скип'),
                              textAlign: TextAlign.center,
                              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Центральная колода карточек (Сплит-карточка на Desktop, свайп-колода на Mobile)
                          Expanded(
                            child: state.hasFinishedDeck
                                ? _buildEmptyDeckView(context)
                                : (isDesktop
                                    ? _buildDesktopSplitCard(context, state)
                                    : _buildCardStack(context, state)),
                          ),

                          // Панель кнопок (Скип, Лайк) — только для мобильного режима
                          if (!state.hasFinishedDeck && !isDesktop) ...[
                            _buildActionButtons(context),
                            const SizedBox(height: 24),
                          ] else
                            const SizedBox(height: 20),
                        ],
                      ),

                  // Эффект интриги игрового автомата (Variable Reward Suspense)
                  if (state.isSuspenseReveal)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.82),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFF2A68).withValues(alpha: 0.2),
                                border: Border.all(color: const Color(0xFFFF2A68), width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF2A68).withValues(alpha: 0.5),
                                    blurRadius: 28,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.favorite_rounded, color: Color(0xFFFF2A68), size: 48),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'ПРОВЕРКА СОВПАДЕНИЯ...',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Кажется, ваши вкусы сошлись!',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  ),
);
}

  Widget _buildDesktopSplitCard(BuildContext context, CoopMatchState state) {
    final title = state.currentTitle!;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 540),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12161F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left: 360px vertical poster (2:3) with badges
            SizedBox(
              width: 360,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (title.posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: wrapCorsSafeUrl(title.posterUrl),
                      alignment: Alignment.topCenter,
                      fit: BoxFit.cover,
                      httpHeaders: const {
                        'User-Agent': 'SyncPai-App/1.0',
                        'Referer': 'https://shikimori.io/',
                      },
                      placeholder: (_, __) => const ColoredBox(color: Color(0xFF181D27)),
                      errorWidget: (_, __, ___) => title.effectiveFallbackPoster.isNotEmpty &&
                              title.effectiveFallbackPoster != title.posterUrl
                          ? CachedNetworkImage(
                              imageUrl: wrapCorsSafeUrl(title.effectiveFallbackPoster),
                              alignment: Alignment.topCenter,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: const Color(0xFF181D27),
                              child: const Icon(Icons.broken_image_rounded, color: Colors.white24, size: 48),
                            ),
                    )
                  else
                    Container(
                      color: const Color(0xFF181D27),
                      child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 48),
                    ),
                  // Gradient overlay on bottom of poster
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                          stops: const [0.7, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Badges top
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (title.episodesBadgeText.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Text(
                              title.episodesBadgeText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        if (title.year != null && title.year! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Text(
                              '${title.year}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Right: Info and Action Buttons
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    if (title.englishTitle.isNotEmpty && title.englishTitle != title.displayTitle) ...[
                      const SizedBox(height: 4),
                      Text(
                        title.englishTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // Genre chips
                    if (title.genres.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: title.genres.take(5).map((genre) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Text(
                              genre,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),
                    // Synopsis (scrollable)
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          title.description.isNotEmpty
                              ? title.description
                              : 'Описание отсутствует.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 3 Action buttons
                    Row(
                      children: [
                        // Skip button
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white60,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => widget.cubit.voteCurrent(false),
                            icon: const Icon(Icons.close_rounded, size: 20),
                            label: const Text('Пропустить', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Details button
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryLight,
                              side: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.3)),
                              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => _openCurrentCardDetails(context),
                            icon: const Icon(Icons.info_outline_rounded, size: 20),
                            label: const Text('Подробнее', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Like / Add button
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => widget.cubit.voteCurrent(true),
                            icon: const Icon(Icons.bookmark_add_rounded, size: 20),
                            label: const Text('В планы', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardStack(BuildContext context, CoopMatchState state) {
    final title = state.currentTitle!;
    final rotation = (_dragOffset.dx / 300) * 0.25;

    return Center(
      child: GestureDetector(
        key: ValueKey('coop_match_active_card_${title.id}'),
        onTap: () => _openCurrentCardDetails(context),
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Transform.translate(
          offset: _dragOffset,
          child: Transform.rotate(
            angle: rotation,
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.88,
              height: MediaQuery.of(context).size.height * 0.58,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Постер аниме с закруглениями
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: title.posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: wrapCorsSafeUrl(title.posterUrl),
                            memCacheWidth: 600,
                            fit: BoxFit.cover,
                            httpHeaders: const {
                              'User-Agent': 'SyncPai-App/1.0',
                              'Referer': 'https://shikimori.io/',
                            },
                            placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                            errorWidget: (_, __, ___) => title.effectiveFallbackPoster.isNotEmpty &&
                                    title.effectiveFallbackPoster != title.posterUrl
                                ? CachedNetworkImage(
                                    imageUrl: wrapCorsSafeUrl(title.effectiveFallbackPoster),
                                    memCacheWidth: 600,
                                    fit: BoxFit.cover,
                                    placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                                    errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                                  )
                                : Container(color: AppColors.surfaceElevated),
                          )
                        : Container(color: AppColors.surfaceElevated),
                  ),

                  // Затемнение нижней части с описанием
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.1),
                            Colors.black.withValues(alpha: 0.85),
                            Colors.black.withValues(alpha: 0.98),
                          ],
                          stops: const [0.0, 0.45, 0.78, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Информация о тайтле внизу
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (title.genres.isNotEmpty)
                          Text(
                            title.genres.take(3).join(' • '),
                            style: AppTypography.caption.copyWith(
                              color: AppColors.primaryLight,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        const SizedBox(height: 6),
                        Text(
                          title.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                        if (title.description.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            title.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Штамп "ХОЧУ СМОТРЕТЬ" при свайпе вправо
                  if (_dragOffset.dx > 20)
                    Positioned(
                      top: 30,
                      left: 30,
                      child: Transform.rotate(
                        angle: -0.2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.syncActive, width: 3),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.favorite_rounded, color: AppColors.syncActive, size: 22),
                              SizedBox(width: 8),
                              Text(
                                'ХОЧУ',
                                style: TextStyle(
                                  color: AppColors.syncActive,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Штамп "СКИП" при свайпе влево
                  if (_dragOffset.dx < -20)
                    Positioned(
                      top: 30,
                      right: 30,
                      child: Transform.rotate(
                        angle: 0.2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.syncError, width: 3),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close_rounded, color: AppColors.syncError, size: 24),
                              SizedBox(width: 6),
                              Text(
                                'СКИП',
                                style: TextStyle(
                                  color: AppColors.syncError,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Кнопка Скип (Красная)
          TvFocusable(
            borderRadius: BorderRadius.circular(35),
            scaleFactor: 1.1,
            glowColor: AppColors.syncError,
            onPressed: () {
              HapticFeedback.lightImpact();
              widget.cubit.voteCurrent(false);
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: AppColors.syncError.withValues(alpha: 0.4), width: 1.5),
              ),
              child: const Icon(Icons.close_rounded, color: AppColors.syncError, size: 34),
            ),
          ),

          // Кнопка Подробнее (открывает именно текущую активную карточку)
          TvFocusable(
            borderRadius: BorderRadius.circular(28),
            scaleFactor: 1.08,
            glowColor: AppColors.primary,
            onPressed: () => _openCurrentCardDetails(context),
            child: Container(
              key: const ValueKey('coop_match_open_details_btn'),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.45), width: 1.5),
              ),
              child: Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 24),
            ),
          ),

          // Кнопка Лайк (Зеленая)
          TvFocusable(
            borderRadius: BorderRadius.circular(35),
            scaleFactor: 1.1,
            glowColor: AppColors.syncActive,
            onPressed: () {
              HapticFeedback.mediumImpact();
              widget.cubit.voteCurrent(true);
            },
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.syncActive.withValues(alpha: 0.15),
                border: Border.all(color: AppColors.syncActive, width: 2),
              ),
              child: const Icon(Icons.favorite_rounded, color: AppColors.syncActive, size: 34),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDeckView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_awesome_rounded, size: 56, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Колода тайтлов закончилась!',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Вы просмотрели все предложенные варианты. Попробуйте еще раз или выберите аниме из каталога.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Вернуться назад'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMatchDialog(BuildContext context, AnimeTitle matched) {
    int countdown = 3;
    Timer? countdownTimer;

    Future<void> launchPlayback(BuildContext dialogCtx) async {
      countdownTimer?.cancel();
      await widget.cubit.startWatchingMatch();
      if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      widget.onStartWatching?.call(matched);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (!dialogCtx.mounted) {
              t.cancel();
              return;
            }
            if (countdown > 1) {
              setDialogState(() => countdown--);
            } else {
              t.cancel();
              launchPlayback(dialogCtx);
            }
          });

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Dialog(
              backgroundColor: Colors.transparent,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GlassContainer(
                    borderRadius: BorderRadius.circular(28),
                    blurSigma: 24,
                    backgroundOpacity: 0.18,
                    customBorder: Border.all(color: AppColors.syncActive.withValues(alpha: 0.6), width: 1.5),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.auto_awesome, color: AppColors.syncActive, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'ЭТО МЭТЧ!',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.5,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.auto_awesome, color: AppColors.syncActive, size: 22),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Вы оба выбрали этот тайтл! Включаем серию...',
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),

                        // Картинка совпавшего аниме
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 140,
                            height: 200,
                            child: matched.posterUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: wrapCorsSafeUrl(matched.posterUrl),
                                    memCacheWidth: 450,
                                    fit: BoxFit.cover,
                                    httpHeaders: const {
                                      'User-Agent': 'SyncPai-App/1.0',
                                      'Referer': 'https://shikimori.io/',
                                    },
                                    placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                                    errorWidget: (_, __, ___) => matched.effectiveFallbackPoster.isNotEmpty &&
                                            matched.effectiveFallbackPoster != matched.posterUrl
                                        ? CachedNetworkImage(
                                            imageUrl: wrapCorsSafeUrl(matched.effectiveFallbackPoster),
                                            memCacheWidth: 450,
                                            fit: BoxFit.cover,
                                            placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                                          )
                                        : Container(color: AppColors.surfaceElevated),
                                  )
                                : Container(color: AppColors.surfaceElevated),
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text(
                          matched.displayTitle,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Кнопка запуска серии
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.syncActive,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                              shadowColor: AppColors.syncActive.withValues(alpha: 0.4),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              'Смотреть вместе ($countdown с.) ▶',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            onPressed: () => launchPlayback(dialogCtx),
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextButton(
                          onPressed: () {
                            countdownTimer?.cancel();
                            widget.cubit.clearMatch();
                            Navigator.of(dialogCtx).pop();
                          },
                          child: const Text('Продолжить поиск', style: TextStyle(color: AppColors.textMuted)),
                        ),
                      ],
                    ),
                  ),

                  // Праздничный салют конфетти поверх модального окна
                  const Positioned.fill(
                    child: MatchConfettiBlastWidget(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

