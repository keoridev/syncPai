import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/app_avatar.dart';

/// Пресеты парных диптих-витрин (Левая / Правая часть единой панорамы).
class DuoDiptychPreset {
  final String id;
  final String title;
  final String sideLabel;
  final List<Color> gradient;
  final Color accent;
  final bool isPremium;

  const DuoDiptychPreset({
    required this.id,
    required this.title,
    required this.sideLabel,
    required this.gradient,
    required this.accent,
    this.isPremium = false,
  });

  static const List<DuoDiptychPreset> all = [
    DuoDiptychPreset(
      id: 'duo_sunset_left',
      title: 'Закатный мост',
      sideLabel: 'Левая часть',
      gradient: [Color(0xFF1B1035), Color(0xFF6B1D5C), Color(0xFFFF7A59)],
      accent: Color(0xFFFF7A59),
    ),
    DuoDiptychPreset(
      id: 'duo_sunset_right',
      title: 'Закатный мост',
      sideLabel: 'Правая часть',
      gradient: [Color(0xFFFF7A59), Color(0xFF6B1D5C), Color(0xFF1B1035)],
      accent: Color(0xFF38BDF8),
    ),
    DuoDiptychPreset(
      id: 'duo_neon_left',
      title: 'Кибер-неон',
      sideLabel: 'Левая часть',
      gradient: [Color(0xFF071324), Color(0xFF0F2B47), Color(0xFF00E5FF)],
      accent: Color(0xFF00E5FF),
    ),
    DuoDiptychPreset(
      id: 'duo_neon_right',
      title: 'Кибер-неон',
      sideLabel: 'Правая часть',
      gradient: [Color(0xFF00E5FF), Color(0xFF28164A), Color(0xFF0A0F1D)],
      accent: Color(0xFFFF4D94),
    ),
    DuoDiptychPreset(
      id: 'duo_cosmic_left',
      title: 'Космический импульс',
      sideLabel: 'Левая часть',
      gradient: [Color(0xFF0A0A23), Color(0xFF311B92), Color(0xFF7C4DFF)],
      accent: Color(0xFF7C4DFF),
      isPremium: true,
    ),
    DuoDiptychPreset(
      id: 'duo_cosmic_right',
      title: 'Космический импульс',
      sideLabel: 'Правая часть',
      gradient: [Color(0xFF7C4DFF), Color(0xFF880E4F), Color(0xFF0A0A23)],
      accent: Color(0xFFFF4081),
      isPremium: true,
    ),
  ];

  static DuoDiptychPreset fromId(String id) {
    return all.firstWhere(
      (p) => p.id == id,
      orElse: () => all.first,
    );
  }
}

/// Парная диптих-витрина для профиля («Закатный мост», «Кибер-неон», «Космический импульс»).
class DuoDiptychBanner extends StatelessWidget {
  final String themeId;
  final double width;
  final double height;

  const DuoDiptychBanner({
    super.key,
    required this.themeId,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final preset = DuoDiptychPreset.fromId(themeId);
    final isLeft = preset.id.endsWith('_left');

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: preset.gradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _DiptychHorizonPainter(
              isLeft: isLeft,
              accent: preset.accent,
            ),
          ),
          Positioned(
            left: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: preset.accent.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_rounded, size: 11, color: preset.accent),
                  const SizedBox(width: 5),
                  Text(
                    '${preset.title} • ${preset.sideLabel}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
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

class _DiptychHorizonPainter extends CustomPainter {
  final bool isLeft;
  final Color accent;

  const _DiptychHorizonPainter({
    required this.isLeft,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sunCenter = Offset(
      isLeft ? size.width : 0,
      size.height * 0.45,
    );
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.85),
          accent.withValues(alpha: 0.45),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: size.height * 0.65));
    canvas.drawCircle(sunCenter, size.height * 0.65, sunPaint);

    // Линия горизонта / моста, соединяющаяся на стыке двух профилей
    final horizonY = size.height * 0.68;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset(0, horizonY), Offset(size.width, horizonY), linePaint);

    final archPath = Path()
      ..moveTo(isLeft ? size.width * 0.1 : 0, horizonY)
      ..quadraticBezierTo(
        isLeft ? size.width * 0.55 : size.width * 0.45,
        horizonY - size.height * 0.24,
        isLeft ? size.width : size.width * 0.9,
        horizonY,
      );
    canvas.drawPath(
      archPath,
      Paint()
        ..color = accent.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(covariant _DiptychHorizonPainter oldDelegate) =>
      oldDelegate.isLeft != isLeft || oldDelegate.accent != accent;
}

/// Компактная плашка «В паре с ... • N дн.» в шапке профиля.
class DuoBadgePill extends StatelessWidget {
  final String partnerName;
  final int daysTogether;
  final int sharedEpisodes;
  final double sharedHours;
  final VoidCallback? onTap;

  const DuoBadgePill({
    super.key,
    required this.partnerName,
    required this.daysTogether,
    this.sharedEpisodes = 0,
    this.sharedHours = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('profile_duo_badge_pill'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFF4D94).withValues(alpha: 0.22),
              const Color(0xFF38BDF8).withValues(alpha: 0.16),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFF4D94).withValues(alpha: 0.55),
          ),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  size: 13,
                  color: Color(0xFFFF4D94),
                ),
                const SizedBox(width: 5),
                Text(
                  'В паре с $partnerName • $daysTogether дн.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (sharedEpisodes > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.live_tv_rounded,
                      size: 11,
                      color: Color(0xFF38BDF8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Смотрят вместе: $sharedEpisodes сер. (${sharedHours.toStringAsFixed(1)} ч)',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
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
}

/// Модальная карточка «Наша совместимость» для шеринга в Telegram / Stories.
Future<void> showDuoCompatibilityCardSheet(
  BuildContext context, {
  required String myName,
  required String? myAvatarUrl,
  required String partnerName,
  required String? partnerAvatarUrl,
  required int daysTogether,
  required int matchPercent,
  required int sharedEpisodes,
  required double sharedHours,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0E1426),
                  Color(0xFF1F1135),
                  Color(0xFF132238),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFFFF4D94).withValues(alpha: 0.45),
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite_rounded, color: Color(0xFFFF4D94), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'НАША СОВМЕСТИМОСТЬ • SYNCPAI DUO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _DuoRingAvatar(name: myName, avatarUrl: myAvatarUrl, ringColor: const Color(0xFF22D3EE)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Column(
                        children: [
                          Text(
                            '$matchPercent%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Text(
                            'совпадение вкусов',
                            style: TextStyle(color: Colors.white60, fontSize: 10.5),
                          ),
                        ],
                      ),
                    ),
                    _DuoRingAvatar(
                      name: partnerName,
                      avatarUrl: partnerAvatarUrl,
                      ringColor: const Color(0xFFFF4D94),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _DuoMetricTile(
                        icon: Icons.calendar_today_rounded,
                        label: 'Вместе',
                        value: '$daysTogether дн.',
                        color: const Color(0xFFFF4D94),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DuoMetricTile(
                        icon: Icons.live_tv_rounded,
                        label: 'Смотрят вместе',
                        value: '$sharedEpisodes сер. • ${sharedHours.toStringAsFixed(1)} ч',
                        color: const Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    key: const ValueKey('duo_share_card_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4D94),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text(
                      'Поделиться парной карточкой',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () async {
                      final summary =
                          'SyncPai Duo: $myName + $partnerName — $matchPercent% совместимости по жанрам, $daysTogether дн. вместе ($sharedEpisodes сер. / ${sharedHours.toStringAsFixed(1)} ч)';
                      await Clipboard.setData(ClipboardData(text: summary));
                      if (ctx.mounted) {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Парная карточка скопирована для Telegram / Stories'),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _DuoRingAvatar extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final Color ringColor;

  const _DuoRingAvatar({
    required this.name,
    required this.avatarUrl,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [ringColor, Colors.white, ringColor],
            ),
            boxShadow: [
              BoxShadow(
                color: ringColor.withValues(alpha: 0.4),
                blurRadius: 12,
              ),
            ],
          ),
          child: AppAvatar(
            avatarUrl: avatarUrl,
            username: name,
            size: 56,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 80,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DuoMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DuoMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(color: Colors.white60, fontSize: 10.5),
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
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Расчёт процента совместимости по жанрам без внешних зависимостей.
int computeDuoGenreMatchPercent(List<String> myGenres, List<String> partnerGenres) {
  if (myGenres.isEmpty || partnerGenres.isEmpty) {
    return math.max(72, 84);
  }
  final a = myGenres.map((g) => g.trim().toLowerCase()).toSet();
  final b = partnerGenres.map((g) => g.trim().toLowerCase()).toSet();
  final union = a.union(b).length;
  if (union == 0) return 80;
  final inter = a.intersection(b).length;
  return ((inter / union) * 100).round().clamp(45, 99);
}

