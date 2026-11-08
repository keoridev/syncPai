import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../domain/entities/steam_profile_customization.dart';

/// Интерактивная карточка значка профиля (Interactive Badge Details & Perks)
/// Отображает функциональный перк в SyncPai, редкость, критерии получения и настройки свечения.
class BadgeDetailsSheet extends StatefulWidget {
  final SteamBadge badge;
  final ValueChanged<Color>? onColorChanged;
  final ValueChanged<BadgeGlowStyle>? onGlowStyleChanged;

  final VoidCallback? onSelectBadge;

  const BadgeDetailsSheet({
    super.key,
    required this.badge,
    this.onColorChanged,
    this.onGlowStyleChanged,
    this.onSelectBadge,
  });

  static void show(
    BuildContext context, {
    required SteamBadge badge,
    ValueChanged<Color>? onColorChanged,
    ValueChanged<BadgeGlowStyle>? onGlowStyleChanged,
    VoidCallback? onSelectBadge,
  }) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BadgeDetailsSheet(
        badge: badge,
        onColorChanged: onColorChanged,
        onGlowStyleChanged: onGlowStyleChanged,
        onSelectBadge: onSelectBadge,
      ),
    );
  }

  @override
  State<BadgeDetailsSheet> createState() => _BadgeDetailsSheetState();
}

class _BadgeDetailsSheetState extends State<BadgeDetailsSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late Color _currentColor;
  BadgeGlowStyle _currentGlowStyle = BadgeGlowStyle.pulse;

  static const List<Color> _neonPalette = [
    Color(0xFF00E5FF),
    Color(0xFFFF2A68),
    Color(0xFFFFD700),
    Color(0xFF00FF87),
    Color(0xFFB388FF),
    Color(0xFFFF6B4A),
    Color(0xFFFF76AC),
    Color(0xFFE040FB),
  ];

  @override
  void initState() {
    super.initState();
    _currentColor = widget.badge.color;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _getRarityColor(BadgeRarity rarity) {
    switch (rarity) {
      case BadgeRarity.legendary:
        return const Color(0xFFFFD700);
      case BadgeRarity.epic:
        return const Color(0xFFB388FF);
      case BadgeRarity.rare:
        return const Color(0xFF00E5FF);
      case BadgeRarity.common:
        return const Color(0xFF90A4AE);
    }
  }

  String _getRarityLabel(BadgeRarity rarity) {
    switch (rarity) {
      case BadgeRarity.legendary:
        return 'LEGENDARY';
      case BadgeRarity.epic:
        return 'EPIC';
      case BadgeRarity.rare:
        return 'RARE';
      case BadgeRarity.common:
        return 'COMMON';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rarityColor = _getRarityColor(widget.badge.rarity);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Хэндл бар
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
          const SizedBox(height: 18),

          // Анимированная иконка значка с кастомным свечением
          AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              final t = _animController.value;
              final pulse = (math.sin(t * math.pi * 2) + 1.0) / 2.0;

              double blur = 16;
              double spread = 2;
              if (_currentGlowStyle == BadgeGlowStyle.pulse) {
                blur = 12 + pulse * 14;
                spread = 2 + pulse * 4;
              } else if (_currentGlowStyle == BadgeGlowStyle.flame) {
                blur = 20 + math.sin(t * 12).abs() * 8;
                spread = 3 + math.cos(t * 12).abs() * 3;
              }

              return Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF16181F),
                  border: Border.all(color: _currentColor, width: 2.0),
                  boxShadow: [
                    BoxShadow(
                      color: _currentColor.withValues(alpha: 0.55),
                      blurRadius: blur,
                      spreadRadius: spread,
                    ),
                  ],
                ),
                child: Icon(
                  widget.badge.icon,
                  size: 44,
                  color: _currentColor,
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // Тег редкости
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: rarityColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: rarityColor, width: 1.0),
            ),
            child: Text(
              _getRarityLabel(widget.badge.rarity),
              style: TextStyle(
                color: rarityColor,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Название значка и уровень
          Text(
            widget.badge.title,
            style: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Уровень ${widget.badge.level} • ${widget.badge.description}',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Карточка функционального перка (Внутриигровой бонус в SyncPai)
          GlassContainer(
            borderRadius: BorderRadius.circular(16),
            blurSigma: 12,
            backgroundOpacity: 0.14,
            customBorder: Border.all(color: _currentColor.withValues(alpha: 0.4), width: 1.2),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _currentColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.stars_rounded, color: _currentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'БОНУС В ПРИЛОЖЕНИИ:',
                        style: TextStyle(
                          color: _currentColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.badge.perkTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.badge.perkDescription,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Критерий получения
          Row(
            children: [
              const Icon(Icons.military_tech_outlined, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Получение: ${widget.badge.unlockCriteria}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Настройка акцентного цвета значка
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Цвет неона значка:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Wrap(
                spacing: 6,
                children: _neonPalette.map((c) {
                  final isSelected = _currentColor == c;
                  return InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _currentColor = c);
                      widget.onColorChanged?.call(c);
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Стиль свечения значка
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Стиль свечения:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              SegmentedButton<BadgeGlowStyle>(
                segments: const [
                  ButtonSegment(value: BadgeGlowStyle.pulse, label: Text('Пульс', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: BadgeGlowStyle.flame, label: Text('Пламя', style: TextStyle(fontSize: 11))),
                ],
                selected: {_currentGlowStyle},
                onSelectionChanged: (set) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentGlowStyle = set.first);
                  widget.onGlowStyleChanged?.call(set.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? _currentColor.withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Кнопки действий
          Row(
            children: [
              if (widget.onSelectBadge != null) ...[
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _currentColor),
                        foregroundColor: _currentColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        widget.onSelectBadge?.call();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Выбрать значок', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Закрыть', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

