import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'tv_focusable.dart';

class LiquidGlassNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const LiquidGlassNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Парящая нижняя панель навигации в премиальном стиле Liquid Glass (Жидкое стекло)
/// с аппаратным размытием BackdropFilter, полупрозрачным бликом и капсульными индикаторами.
class LiquidGlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<LiquidGlassNavItem> items;

  const LiquidGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLight = HSLColor.fromColor(themePrimary)
        .withLightness((HSLColor.fromColor(themePrimary).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();

    return SafeArea(
      bottom: true,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              // Глубокая объемная тень под стеклом
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.50),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
              // Легкое янтарно-акцентное свечение
              BoxShadow(
                color: themePrimary.withValues(alpha: 0.12),
                blurRadius: 18,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  // Полупрозрачный фон графита жидкого стекла
                  color: AppColors.surfaceElevated.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(32),
                  // Тонкая полупрозрачная окантовка с верхним бликом
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 1.0,
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.14),
                      Colors.white.withValues(alpha: 0.02),
                      Colors.black.withValues(alpha: 0.25),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final isSelected = index == currentIndex;

                    return Expanded(
                      child: TvFocusable(
                        borderRadius: BorderRadius.circular(22),
                        scaleFactor: 1.05,
                        glowColor: themePrimary,
                        onPressed: () {
                          if (!isSelected) {
                            HapticFeedback.lightImpact();
                            onTap(index);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            // Жидкая акцентная капсула активной вкладки
                            color: isSelected
                                ? themePrimary.withValues(alpha: 0.20)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                            border: isSelected
                                ? Border.all(
                                    color: themePrimary.withValues(alpha: 0.50),
                                    width: 1.0,
                                  )
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isSelected ? item.selectedIcon : item.icon,
                                size: 20,
                                color: isSelected
                                    ? themePrimaryLight
                                    : AppColors.textSecondary,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  fontSize: 10.5,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}
