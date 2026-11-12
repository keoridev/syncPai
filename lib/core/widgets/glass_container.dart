import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';

/// Элегантный компонент в стиле Frosted Glass (матовое стекло)
/// для дизайн-системы Cinema Dark / Nordic Dark.
///
/// Использует [BackdropFilter] с размытием и тонкой полупрозрачной рамкой.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final double blurSigma;
  final double backgroundOpacity;
  final double borderOpacity;
  final Color tintColor;
  final VoidCallback? onTap;
  final Border? customBorder;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.blurSigma = 8.0,
    this.backgroundOpacity = 0.08,
    this.borderOpacity = 0.12,
    this.tintColor = Colors.white,
    this.onTap,
    this.customBorder,
  });

  const GlassContainer.circle({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.blurSigma = 8.0,
    this.backgroundOpacity = 0.08,
    this.borderOpacity = 0.12,
    this.tintColor = Colors.white,
    this.onTap,
    this.customBorder,
  })  : shape = BoxShape.circle,
        borderRadius = null;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = shape == BoxShape.circle
        ? null
        : (borderRadius ?? AppDimensions.borderRadiusMedium);

    final border = customBorder ??
        Border.all(
          color: tintColor.withValues(alpha: borderOpacity),
          width: 1.0,
        );

    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: backgroundOpacity),
        shape: shape,
        borderRadius: effectiveRadius,
        border: border,
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        shape: shape == BoxShape.circle
            ? const CircleBorder()
            : RoundedRectangleBorder(borderRadius: effectiveRadius ?? BorderRadius.zero),
        child: InkWell(
          onTap: onTap,
          customBorder: shape == BoxShape.circle
              ? const CircleBorder()
              : RoundedRectangleBorder(borderRadius: effectiveRadius ?? BorderRadius.zero),
          splashColor: tintColor.withValues(alpha: 0.12),
          highlightColor: tintColor.withValues(alpha: 0.06),
          child: content,
        ),
      );
    }

    final effectiveSigma = blurSigma.clamp(0.0, 8.0);

    Widget glass = RepaintBoundary(
      child: ClipRRect(
        borderRadius: effectiveRadius ?? BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: effectiveSigma, sigmaY: effectiveSigma),
          child: content,
        ),
      ),
    );

    if (shape == BoxShape.circle) {
      glass = RepaintBoundary(
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: effectiveSigma, sigmaY: effectiveSigma),
            child: content,
          ),
        ),
      );
    }

    if (margin != null) {
      return Padding(
        padding: margin!,
        child: glass,
      );
    }

    return glass;
  }
}

/// Компактная круглая или скругленная стеклянная кнопка с иконкой
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color iconColor;
  final String? tooltip;
  final double blurSigma;
  final double backgroundOpacity;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 44.0,
    this.iconSize = 20.0,
    this.iconColor = AppColors.textPrimary,
    this.tooltip,
    this.blurSigma = 8.0,
    this.backgroundOpacity = 0.10,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = GlassContainer.circle(
      width: size,
      height: size,
      blurSigma: blurSigma,
      backgroundOpacity: backgroundOpacity,
      onTap: onTap,
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor,
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

