import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../data/repositories/anime_reviews_repository_impl.dart';
import '../../domain/entities/anime_review.dart';
import '../../domain/repositories/anime_reviews_repository.dart';

class WriteReviewSheet extends StatefulWidget {
  final AnimeTitle title;
  final ValueChanged<AnimeReview>? onReviewSubmitted;

  const WriteReviewSheet({
    super.key,
    required this.title,
    this.onReviewSubmitted,
  });

  static Future<AnimeReview?> show(
    BuildContext context, {
    required AnimeTitle title,
    ValueChanged<AnimeReview>? onReviewSubmitted,
  }) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 700;
    if (isDesktop) {
      return showDialog<AnimeReview>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: WriteReviewSheet(
                    title: title,
                    onReviewSubmitted: onReviewSubmitted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<AnimeReview>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated.withValues(alpha: 0.94),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: AppColors.strokeMedium),
              ),
              child: WriteReviewSheet(
                title: title,
                onReviewSubmitted: onReviewSubmitted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends State<WriteReviewSheet> {
  final _textController = TextEditingController();
  double _score = 9.0;
  bool _containsSpoiler = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String _getScoreLabel(double score) {
    if (score >= 10.0) return 'Шедевр!';
    if (score >= 9.0) return 'Великолепно';
    if (score >= 8.0) return 'Очень хорошо';
    if (score >= 7.0) return 'Хорошо';
    if (score >= 6.0) return 'Нормально';
    if (score >= 5.0) return 'Средне';
    if (score >= 4.0) return 'Ниже среднего';
    if (score >= 3.0) return 'Плохо';
    if (score >= 2.0) return 'Ужасно';
    return 'Худшее что я видел';
  }

  Color _getScoreColor(double score) {
    if (score >= 8.0) return const Color(0xFF4CAF50);
    if (score >= 6.0) return const Color(0xFFFFB74D);
    return const Color(0xFFEF5350);
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.length < 10) {
      setState(() {
        _errorMessage = 'Отзыв должен содержать минимум 10 символов';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final authState = context.read<AuthCubit>().state;
    final userId = authState is Authenticated ? authState.profile.id : 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final userName = authState is Authenticated ? authState.profile.username : 'Гость SyncPai';
    final userAvatar = authState is Authenticated ? authState.profile.avatarUrl : null;

    try {
      final reviewsRepo = getIt.isRegistered<AnimeReviewsRepository>()
          ? getIt<AnimeReviewsRepository>()
          : AnimeReviewsRepositoryImpl();

      final review = await reviewsRepo.submitReview(
        title: widget.title,
        userId: userId,
        userName: userName,
        userAvatar: userAvatar,
        score: _score,
        content: text,
        containsSpoiler: _containsSpoiler,
      );

      if (mounted) {
        widget.onReviewSubmitted?.call(review);
        Navigator.of(context).pop(review);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surfaceElevated,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ваш отзыв успешно опубликован в сообществе!',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Ошибка публикации отзыва: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final username = authState is Authenticated ? authState.profile.username : 'Гость SyncPai';
    final avatarUrl = authState is Authenticated ? authState.profile.avatarUrl : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Полоска перетаскивания (Drag handle)
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.strokeMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Заголовок и карточка тайтла
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.title.posterUrl,
                  width: 44,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 44,
                    height: 60,
                    color: AppColors.surfaceElevated,
                    child: const Icon(Icons.movie_rounded, color: AppColors.textMuted, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ОСТАВИТЬ ОТЗЫВ',
                      style: AppTypography.caption.copyWith(
                        letterSpacing: 1.2,
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.title.displayTitle,
                      style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        AppAvatar(
                          avatarUrl: avatarUrl,
                          username: username,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          username,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Выбор оценки (1 - 10)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.strokeMedium),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ваша оценка:',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, color: _getScoreColor(_score), size: 20),
                        const SizedBox(width: 4),
                        Text(
                          '${_score.toInt()} / 10',
                          style: AppTypography.titleMedium.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${_getScoreLabel(_score)})',
                          style: AppTypography.caption.copyWith(
                            color: _getScoreColor(_score),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Интерактивный ряд звезд от 1 до 10
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - (9 * 4)) / 10;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(10, (index) {
                        final val = (index + 1).toDouble();
                        final isSelected = val <= _score;
                        return InkWell(
                          onTap: () => setState(() => _score = val),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: itemWidth.clamp(24.0, 42.0),
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _getScoreColor(_score).withValues(alpha: 0.2)
                                  : AppColors.surfaceElevated.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? _getScoreColor(_score).withValues(alpha: 0.8)
                                    : AppColors.strokeMedium,
                              ),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: AppTypography.caption.copyWith(
                                color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Поле ввода текста отзыва
          TextField(
            controller: _textController,
            maxLines: 5,
            minLines: 3,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Поделитесь впечатлениями о сюжете, рисовке, саундтреке или персонажах...',
              hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface.withValues(alpha: 0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Переключатель спойлеров
          InkWell(
            onTap: () => setState(() => _containsSpoiler = !_containsSpoiler),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Checkbox(
                    value: _containsSpoiler,
                    onChanged: (v) => setState(() => _containsSpoiler = v ?? false),
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Содержит спойлеры',
                      style: AppTypography.bodySmall.copyWith(
                        color: _containsSpoiler ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: _containsSpoiler ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF5350).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF5350).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFEF5350), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTypography.caption.copyWith(color: const Color(0xFFEF5350)),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Кнопка публикации
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Опубликовать отзыв',
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
