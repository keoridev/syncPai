import 'package:flutter/material.dart';

/// Константы отступов, радиусов и размеров SyncPai.
/// Пропорции: умеренные радиусы (12-16px карточки, 8-10px чипсы/кнопки) и воздух (16-20px).
abstract final class AppDimensions {
  // Радиусы скругления
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 10.0;
  static const double radiusCard = 14.0;
  static const double radiusLarge = 16.0;
  static const double radiusExtraLarge = 24.0;

  static const BorderRadius borderRadiusSmall = BorderRadius.all(Radius.circular(radiusSmall));
  static const BorderRadius borderRadiusMedium = BorderRadius.all(Radius.circular(radiusMedium));
  static const BorderRadius borderRadiusCard = BorderRadius.all(Radius.circular(radiusCard));
  static const BorderRadius borderRadiusLarge = BorderRadius.all(Radius.circular(radiusLarge));
  static const BorderRadius borderRadiusExtraLarge = BorderRadius.all(Radius.circular(radiusExtraLarge));

  // Отступы (Spacing & Padding)
  static const double spacing2xs = 2.0;
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 20.0;
  static const double spacing2xl = 24.0;
  static const double spacing3xl = 32.0;

  // Размеры интерактивных элементов
  static const double buttonHeight = 48.0;
  static const double buttonHeightSmall = 36.0;
  static const double searchBarHeight = 46.0;
  static const double chipHeight = 32.0;
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 20.0;
  static const double iconSizeLarge = 24.0;

  // Соотношение сторон постеров тайтлов (3:4.3)
  static const double posterAspectRatio = 0.70;
}

