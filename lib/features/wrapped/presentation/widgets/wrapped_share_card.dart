import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/mascot/sync_pai_mascot.dart';
import '../../../../core/widgets/sync_pai_logo.dart';
import '../../domain/entities/wrapped_data.dart';

/// Элегантная карточка годовых итогов «SyncPai Wrapped 2026», готовая для сохранения и шеринга в соцсетях.
class WrappedShareCard extends StatelessWidget {
  final WrappedData data;

  const WrappedShareCard({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final personality = data.personality;

    return Container(
      width: 360,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0C101A),
            personality.color.withValues(alpha: 0.16),
            const Color(0xFF141926),
          ],
        ),
        border: Border.all(
          color: personality.color.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: personality.color.withValues(alpha: 0.2),
            blurRadius: 40,
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Декоративные фоновые круги
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: personality.color.withValues(alpha: 0.12),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentTurquoise.withValues(alpha: 0.08),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Верхний колонтитул: Бренд SyncPai + 2026 Wrapped
                  Row(
                    children: [
                      const SyncPaiLogo(size: 26),
                      const SizedBox(width: 8),
                      Text(
                        'SyncPai',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: personality.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: personality.color.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'WRAPPED 2026',
                          style: TextStyle(
                            color: personality.color,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 2. Блок пользователя
                  Row(
                    children: [
                      AppAvatar(
                        avatarUrl: data.avatarUrl,
                        username: data.username,
                        size: 44,
                        borderWidth: 1.5,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Моё аниме-путешествие 2026',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 3. Главный тайтл года (Hero Anime)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      children: [
                        if (data.topAnimePoster.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              data.topAnimePoster,
                              width: 52,
                              height: 74,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildPosterFallback(),
                            ),
                          )
                        else
                          _buildPosterFallback(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ГЛАВНОЕ АНИМЕ ГОДА',
                                style: TextStyle(
                                  color: personality.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                data.topAnimeTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${data.topAnimeEpisodes} серий просмотрено',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4. Метрики в 2 колонки: Время и Серии
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricBox(
                          icon: Icons.schedule_rounded,
                          label: 'ВРЕМЯ В АНИМЕ',
                          value: data.formattedWatchTime,
                          accentColor: AppColors.accentTurquoise,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricBox(
                          icon: Icons.movie_outlined,
                          label: 'СЕРИЙ ПРОСМОТРЕНО',
                          value: '${data.totalEpisodesWatched}',
                          accentColor: AppColors.accentCoral,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Жанр и Совместный просмотр
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricBox(
                          icon: Icons.category_rounded,
                          label: 'ЛЮБИМЫЙ ЖАНР',
                          value: data.favoriteGenre,
                          accentColor: const Color(0xFFFFB300),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricBox(
                          icon: Icons.groups_rounded,
                          label: 'С ДРУЗЬЯМИ',
                          value: '${data.totalWatchParties} комнат',
                          accentColor: personality.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 5. Карточка типажа зрителя (Personality)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: personality.color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: personality.color.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: personality.color.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(personality.icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ВАШ ТИПАЖ ЗРИТЕЛЯ',
                                style: TextStyle(
                                  color: personality.color,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                ),
                              ),
                              Text(
                                personality.titleRu,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: SyncPaiMascot(
                            state: personality.mascotState,
                            animated: false,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Футер карточки
                  Center(
                    child: Text(
                      'syncpai.app • Смотри аниме синхронно с друзьями',
                      style: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.7),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
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

  Widget _buildPosterFallback() {
    return Container(
      width: 52,
      height: 74,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.movie_rounded, color: AppColors.textMuted, size: 24),
    );
  }

  Widget _buildMetricBox({
    required IconData icon,
    required String label,
    required String value,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accentColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
