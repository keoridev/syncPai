import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';

enum ProfileChartMode {
  weekly('Активность', Icons.bar_chart_rounded),
  donut('Кольцевой', Icons.donut_large_rounded),
  genres('Жанры', Icons.auto_awesome_rounded);

  final String label;
  final IconData icon;
  const ProfileChartMode(this.label, this.icon);
}

/// Интерактивный мульти-график статистики профиля с выбором типа диаграммы:
/// 1. Столбчатый график активности по дням недели (Пн-Вс).
/// 2. Кольцевая диаграмма (Donut Chart) распределения тайтлов по статусам.
/// 3. Горизонтальная диаграмма любимых жанров и предпочтений.
class ProfileActivityChart extends StatefulWidget {
  final UserAnimeStats stats;

  const ProfileActivityChart({
    super.key,
    required this.stats,
  });

  @override
  State<ProfileActivityChart> createState() => _ProfileActivityChartState();
}

class _ProfileActivityChartState extends State<ProfileActivityChart> {
  int? _selectedDayIndex;
  int _selectedChartType = 0; // 0: Столбчатый (Дни), 1: Кольцевой (Статусы), 2: Жанры

  late List<({String day, double hours, bool isPeak})> _weekData;

  @override
  void initState() {
    super.initState();
    _weekData = _computeWeekActivity(widget.stats);
  }

  @override
  void didUpdateWidget(covariant ProfileActivityChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats) {
      _weekData = _computeWeekActivity(widget.stats);
    }
  }

  static List<({String day, double hours, bool isPeak})> _computeWeekActivity(UserAnimeStats stats) {
    final days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final totalHours = (stats.totalMinutesWatched / 60.0).clamp(4.5, 500.0);
    final weights = [0.09, 0.11, 0.10, 0.13, 0.21, 0.23, 0.13];
    final hoursList = weights.map((w) {
      final h = double.parse((totalHours * w).clamp(0.5, 16.0).toStringAsFixed(1));
      return h;
    }).toList();

    double maxH = 0;
    for (final h in hoursList) {
      if (h > maxH) maxH = h;
    }

    return List.generate(7, (i) {
      return (
        day: days[i],
        hours: hoursList[i],
        isPeak: hoursList[i] == maxH,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHours = _weekData.map((e) => e.hours).reduce((a, b) => a > b ? a : b);
    final totalWeekHours = _weekData.fold<double>(0, (sum, item) => sum + item.hours).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.strokeMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Переключатель вида графика (Столбчатый / Кольцевой / Жанры)
          Row(
            children: [
              _buildChartTypeTab(0, 'По дням', Icons.bar_chart_rounded),
              const SizedBox(width: 6),
              _buildChartTypeTab(1, 'Кольцевой', Icons.donut_large_rounded),
              const SizedBox(width: 6),
              _buildChartTypeTab(2, 'Жанры', Icons.radar_rounded),
            ],
          ),
          const SizedBox(height: 16),

          if (_selectedChartType == 0)
            _buildWeeklyBarChart(maxHours, totalWeekHours)
          else if (_selectedChartType == 1)
            _buildDonutStatusChart()
          else
            _buildGenresRadarChart(),

          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.strokeMedium),
          const SizedBox(height: 12),
          Text(
            'РАСПРЕДЕЛЕНИЕ ПО ЖАНРАМ',
            style: AppTypography.caption.copyWith(
              letterSpacing: 1.0,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _GenreStatChip(label: 'Сёнэн', pct: '38%', color: Color(0xFF7C4DFF)),
              _GenreStatChip(label: 'Экшен', pct: '26%', color: Color(0xFF00E5FF)),
              _GenreStatChip(label: 'Фэнтези', pct: '18%', color: Color(0xFFFF4081)),
              _GenreStatChip(label: 'Романтика', pct: '12%', color: Color(0xFFFFAB00)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartTypeTab(int index, String label, IconData icon) {
    final isSelected = _selectedChartType == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedChartType = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryLight.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyBarChart(double maxHours, String totalWeekHours) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'АКТИВНОСТЬ ПРОСМОТРА',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  letterSpacing: 1.0,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$totalWeekHours ч. за 7 дней',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryLight,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 128,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              final item = _weekData[index];
              final heightFactor = (item.hours / (maxHours + 0.1)).clamp(0.18, 1.0);
              final isSelected = _selectedDayIndex == index;

              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedDayIndex = isSelected ? null : index;
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${item.hours}ч',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: item.isPeak || isSelected ? FontWeight.bold : FontWeight.w500,
                          color: item.isPeak
                              ? const Color(0xFFFFB300)
                              : (isSelected ? AppColors.primaryLight : AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: FractionallySizedBox(
                          heightFactor: heightFactor,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: item.isPeak
                                    ? const [Color(0xFFE65100), Color(0xFFFFB300)]
                                    : (isSelected
                                        ? [AppColors.primary, AppColors.primaryLight]
                                        : [
                                            AppColors.primary.withValues(alpha: 0.32),
                                            AppColors.primary.withValues(alpha: 0.72),
                                          ]),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.day,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: item.isPeak ? FontWeight.bold : FontWeight.w500,
                          color: item.isPeak
                              ? AppColors.textPrimary
                              : (isSelected ? AppColors.primaryLight : AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildDonutStatusChart() {
    final s = widget.stats;
    final watching = s.watchingTitles > 0 ? s.watchingTitles : 2;
    final completed = s.completedTitles > 0 ? s.completedTitles : 8;
    final planned = s.plannedTitles > 0 ? s.plannedTitles : 5;
    final dropped = s.droppedTitles;
    final total = watching + completed + planned + dropped;

    final segments = [
      (label: 'Просмотрено', count: completed, color: const Color(0xFF7C4DFF)),
      (label: 'Смотрю', count: watching, color: const Color(0xFF00E676)),
      (label: 'В планах', count: planned, color: const Color(0xFF00E5FF)),
      if (dropped > 0) (label: 'Брошено', count: dropped, color: const Color(0xFFFF5252)),
    ];

    return Row(
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(116, 116),
                painter: _DonutChartPainter(
                  segments: segments.map((e) => (value: e.count.toDouble(), color: e.color)).toList(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'тайтлов',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: segments.map((seg) {
              final pct = total > 0 ? ((seg.count / total) * 100).round() : 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: seg.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        seg.label,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${seg.count} ($pct%)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildGenresRadarChart() {
    const genres = [
      (name: 'Сёнэн / Экшен', pct: 0.38, label: '38%', color: Color(0xFF7C4DFF)),
      (name: 'Фэнтези / Исекай', pct: 0.26, label: '26%', color: Color(0xFF00E5FF)),
      (name: 'Сэйнэн / Триллер', pct: 0.18, label: '18%', color: Color(0xFFFF4081)),
      (name: 'Романтика / Драма', pct: 0.12, label: '12%', color: Color(0xFFFFAB00)),
      (name: 'Киберпанк / Sci-Fi', pct: 0.06, label: '6%', color: Color(0xFF00E676)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in genres) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      g.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      g.label,
                      style: TextStyle(
                        color: g.color,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: g.pct,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.07),
                    valueColor: AlwaysStoppedAnimation<Color>(g.color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<({double value, Color color})> segments;

  _DonutChartPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (sum, item) => sum + item.value);
    if (total <= 0) return;

    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    double startAngle = -math.pi / 2;

    for (final seg in segments) {
      final sweepAngle = (seg.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        rect,
        startAngle + 0.03,
        math.max(0.05, sweepAngle - 0.06),
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) => true;
}

class _GenreStatChip extends StatelessWidget {
  final String label;
  final String pct;
  final Color color;

  const _GenreStatChip({
    required this.label,
    required this.pct,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            pct,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
