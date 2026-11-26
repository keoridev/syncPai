import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../watch_history/domain/entities/watch_history_item.dart';

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
  final List<WatchHistoryItem> watchHistory;
  final bool isMangaTab;
  final int mangaChaptersRead;
  final Color? accentColor;

  const ProfileActivityChart({
    super.key,
    required this.stats,
    this.watchHistory = const [],
    this.isMangaTab = false,
    this.mangaChaptersRead = 0,
    this.accentColor,
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
    _weekData = _computeWeekActivity(widget.watchHistory);
  }

  @override
  void didUpdateWidget(covariant ProfileActivityChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats ||
        oldWidget.watchHistory != widget.watchHistory) {
      _weekData = _computeWeekActivity(widget.watchHistory);
    }
  }

  static List<({String day, double hours, bool isPeak})> _computeWeekActivity(
    List<WatchHistoryItem> history,
  ) {
    const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 6));

    final hoursByDay = List<double>.filled(7, 0.0);
    for (final item in history) {
      final localDt = item.updatedAt.toLocal();
      if (localDt.isBefore(cutoff)) continue;
      final weekdayIdx = (localDt.weekday - 1).clamp(0, 6);
      final watchedMs = item.positionMs > 0 ? item.positionMs : item.durationMs;
      if (watchedMs > 0) {
        hoursByDay[weekdayIdx] += watchedMs / 3600000.0;
      }
    }

    final roundedHours = hoursByDay
        .map((h) => double.parse(h.toStringAsFixed(1)))
        .toList();

    double maxH = 0;
    for (final h in roundedHours) {
      if (h > maxH) maxH = h;
    }

    return List.generate(7, (i) {
      return (
        day: days[i],
        hours: roundedHours[i],
        isPeak: maxH > 0 && roundedHours[i] == maxH,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentColor ?? scheme.primary;

    final maxHours = _weekData.map((e) => e.hours).reduce((a, b) => a > b ? a : b);
    final totalWeekHours = _weekData.fold<double>(0, (sum, item) => sum + item.hours).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingLg),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF191F2B)
            : scheme.surfaceContainerLowest.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Переключатель вида графика (Дни / Списки / Жанры)
          Row(
            children: [
              _buildChartTypeTab(0, 'Дни', Icons.bar_chart_rounded, accent, scheme, isDark),
              const SizedBox(width: 6),
              _buildChartTypeTab(1, 'Списки', Icons.donut_large_rounded, accent, scheme, isDark),
              const SizedBox(width: 6),
              _buildChartTypeTab(2, 'Жанры', Icons.radar_rounded, accent, scheme, isDark),
            ],
          ),
          const SizedBox(height: 16),

          if (_selectedChartType == 0)
            _buildWeeklyBarChart(maxHours, totalWeekHours, accent, scheme)
          else if (_selectedChartType == 1)
            _buildDonutStatusChart(accent, scheme)
          else
            _buildGenresRadarChart(accent, scheme),

          const SizedBox(height: 16),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.35)),
          const SizedBox(height: 12),
          Text(
            'РАСПРЕДЕЛЕНИЕ ПО ЖАНРАМ',
            style: AppTypography.caption.copyWith(
              letterSpacing: 1.0,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.isMangaTab
                ? [
                    _GenreStatChip(label: 'Сёнэн', pct: '42%', color: accent),
                    _GenreStatChip(label: 'Экшен', pct: '28%', color: accent.withValues(alpha: 0.80)),
                    _GenreStatChip(label: 'Романтика', pct: '18%', color: accent.withValues(alpha: 0.65)),
                    _GenreStatChip(label: 'Драма', pct: '12%', color: accent.withValues(alpha: 0.50)),
                  ]
                : [
                    _GenreStatChip(label: 'Сёнэн', pct: '38%', color: accent),
                    _GenreStatChip(label: 'Экшен', pct: '26%', color: accent.withValues(alpha: 0.80)),
                    _GenreStatChip(label: 'Фэнтези', pct: '18%', color: accent.withValues(alpha: 0.65)),
                    _GenreStatChip(label: 'Романтика', pct: '12%', color: accent.withValues(alpha: 0.50)),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartTypeTab(int index, String label, IconData icon, Color accent, ColorScheme scheme, bool isDark) {
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
                ? (isDark ? const Color(0xFF252C3B) : accent.withValues(alpha: 0.18))
                : (isDark ? Colors.white.withValues(alpha: 0.04) : scheme.surfaceContainerHigh.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: isSelected ? accent : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyBarChart(double maxHours, String totalWeekHours, Color accent, ColorScheme scheme) {
    final totalBadgeText = widget.isMangaTab
        ? '${widget.mangaChaptersRead} гл.'
        : '$totalWeekHours ч.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'АКТИВНОСТЬ ЗА 7 ДНЕЙ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  letterSpacing: 1.0,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                totalBadgeText,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: accent,
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
                          color: (item.isPeak || isSelected)
                              ? accent
                              : scheme.onSurfaceVariant,
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
                                    ? [accent.withValues(alpha: 0.65), accent]
                                    : (isSelected
                                        ? [accent.withValues(alpha: 0.85), accent]
                                        : [
                                            accent.withValues(alpha: 0.20),
                                            accent.withValues(alpha: 0.50),
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
                              ? scheme.onSurface
                              : (isSelected ? accent : scheme.onSurfaceVariant),
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

  Widget _buildDonutStatusChart(Color accent, ColorScheme scheme) {
    final s = widget.stats;
    final watching = s.watchingTitles > 0 ? s.watchingTitles : 2;
    final completed = s.completedTitles > 0 ? s.completedTitles : 8;
    final planned = s.plannedTitles > 0 ? s.plannedTitles : 5;
    final dropped = s.droppedTitles;
    final total = watching + completed + planned + dropped;

    final segments = [
      (label: 'Просмотрено', count: completed, color: accent),
      (label: 'Смотрю', count: watching, color: accent.withValues(alpha: 0.75)),
      (label: 'В планах', count: planned, color: accent.withValues(alpha: 0.50)),
      if (dropped > 0) (label: 'Брошено', count: dropped, color: scheme.onSurfaceVariant.withValues(alpha: 0.40)),
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
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'тайтлов',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
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
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${seg.count} ($pct%)',
                      style: TextStyle(
                        color: scheme.onSurface,
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

  Widget _buildGenresRadarChart(Color accent, ColorScheme scheme) {
    final genres = widget.isMangaTab
        ? [
            (name: 'Сёнэн / Боевик', pct: 0.42, label: '42%', color: accent),
            (name: 'Экшен / Спорт', pct: 0.28, label: '28%', color: accent.withValues(alpha: 0.80)),
            (name: 'Романтика / Повседневность', pct: 0.18, label: '18%', color: accent.withValues(alpha: 0.65)),
            (name: 'Драма / Психология', pct: 0.12, label: '12%', color: accent.withValues(alpha: 0.50)),
          ]
        : [
            (name: 'Сёнэн / Экшен', pct: 0.38, label: '38%', color: accent),
            (name: 'Фэнтези / Исекай', pct: 0.26, label: '26%', color: accent.withValues(alpha: 0.80)),
            (name: 'Сэйнэн / Триллер', pct: 0.18, label: '18%', color: accent.withValues(alpha: 0.65)),
            (name: 'Романтика / Драма', pct: 0.12, label: '12%', color: accent.withValues(alpha: 0.50)),
            (name: 'Киберпанк / Sci-Fi', pct: 0.06, label: '6%', color: accent.withValues(alpha: 0.35)),
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
                      style: TextStyle(
                        color: scheme.onSurface,
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
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
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
            style: TextStyle(
              color: scheme.onSurface,
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
