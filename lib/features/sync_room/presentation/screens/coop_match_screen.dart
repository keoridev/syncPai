import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/widgets/tv_focusable.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../cubit/coop_match_cubit.dart';
import '../cubit/coop_match_state.dart';
import '../widgets/match_confetti_blast_widget.dart';

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

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: widget.cubit,
      child: BlocConsumer<CoopMatchCubit, CoopMatchState>(
        listener: (context, state) {
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
          return Scaffold(
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
              child: Column(
                children: [
                  // Подзаголовок режима
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                    child: Text(
                      state.peerName != null
                          ? 'Свайпайте вдвоем с ${state.peerName}. При совпадении серия запустится!'
                          : 'Свайпайте вправо — хочу смотреть, влево — скип',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Центральная колода карточек
                  Expanded(
                    child: state.hasFinishedDeck
                        ? _buildEmptyDeckView(context)
                        : _buildCardStack(context, state),
                  ),

                  // Панель кнопок (Скип, Лайк)
                  if (!state.hasFinishedDeck)
                    _buildActionButtons(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardStack(BuildContext context, CoopMatchState state) {
    final title = state.currentTitle!;
    final rotation = (_dragOffset.dx / 300) * 0.25;

    return Center(
      child: GestureDetector(
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
                    child: title.posterOriginal.isNotEmpty || title.posterMedium.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: title.posterOriginal.isNotEmpty
                                ? title.posterOriginal
                                : title.posterMedium,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
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
                      'Вы оба хотите смотреть:',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),

                    // Картинка совпавшего аниме
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: 140,
                        height: 200,
                        child: CachedNetworkImage(
                          imageUrl: matched.posterMedium.isNotEmpty
                              ? matched.posterMedium
                              : matched.posterSmall,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: AppColors.surfaceElevated),
                        ),
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
                        label: const Text(
                          'Смотреть 1-ю серию вместе',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onPressed: () async {
                          await widget.cubit.startWatchingMatch();
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (context.mounted && Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                          widget.onStartWatching?.call(matched);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),

                    TextButton(
                      onPressed: () {
                        widget.cubit.clearMatch();
                        Navigator.of(ctx).pop();
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
      ),
    );
  }
}

