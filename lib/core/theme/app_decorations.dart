import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_dimensions.dart';

/// Декорации, градиенты и визуальные стили элементов SyncPai.
abstract final class AppDecorations {
  // Тонкая полупрозрачная граница (5% белого)
  static BoxBorder get subtleBorder => Border.all(
    color: AppColors.stroke,
    width: 1.0,
  );

  // Средняя полупрозрачная граница (10% белого) для интерактивных элементов
  static BoxBorder get mediumBorder => Border.all(
    color: AppColors.strokeMedium,
    width: 1.0,
  );

  // Контейнер карточки тайтла
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: AppColors.surface,
    borderRadius: AppDimensions.borderRadiusCard,
    border: subtleBorder,
  );

  // Приподнятый контейнер (диалоги, выпадающие шторки, панели управления)
  static BoxDecoration get elevatedContainerDecoration => BoxDecoration(
    color: AppColors.surfaceElevated,
    borderRadius: AppDimensions.borderRadiusLarge,
    border: subtleBorder,
  );

  // Градиент затемнения постера снизу (плавный переход от прозрачного к фону карточки)
  static const LinearGradient posterBottomGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.45, 1.0],
    colors: [
      Colors.transparent,
      Color(0x66121316),
      AppColors.background,
    ],
  );

  // Градиент затемнения карточки в сетке каталога
  static const LinearGradient cardPosterGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.35, 0.75, 1.0],
    colors: [
      Colors.transparent,
      Color(0x801A1C22),
      AppColors.surface,
    ],
  );

  // Фон вторичной полупрозрачной кнопки ("Смотреть с другом" / Frosted Glass)
  static BoxDecoration get frostedGlassDecoration => BoxDecoration(
    color: AppColors.frostedWhite,
    borderRadius: AppDimensions.borderRadiusMedium,
    border: Border.all(
      color: const Color(0x1FFFFFFF), // rgba(255, 255, 255, 0.12)
      width: 1.0,
    ),
  );

  // Чипс / плашка неактивного фильтра
  static BoxDecoration get chipInactiveDecoration => BoxDecoration(
    color: AppColors.surfaceElevated,
    borderRadius: AppDimensions.borderRadiusSmall,
    border: subtleBorder,
  );

  // Чипс активного фильтра
  static BoxDecoration get chipActiveDecoration => BoxDecoration(
    color: AppColors.primary,
    borderRadius: AppDimensions.borderRadiusSmall,
  );

  // Цвета для скелетонной анимации загрузки (Shimmer)
  static const Color shimmerBase = AppColors.surface;
  static const Color shimmerHighlight = AppColors.surfaceElevated;
}

