import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_colors.dart';
import '../theme/app_decorations.dart';
import '../theme/app_dimensions.dart';

/// Элегантный скелетон (Shimmer) в палитре Nordic Dark.
class ShimmerPlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final bool enabled;

  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.enabled = true,
  });

  const ShimmerPlaceholder.card({
    super.key,
    this.width = double.infinity,
    this.height = double.infinity,
    this.enabled = true,
  }) : borderRadius = AppDimensions.borderRadiusCard;

  const ShimmerPlaceholder.line({
    super.key,
    required this.width,
    this.height = 14.0,
    this.enabled = true,
  }) : borderRadius = AppDimensions.borderRadiusSmall;

  static bool get _isInTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Widget build(BuildContext context) {
    if (!enabled || _isInTest) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: borderRadius ?? AppDimensions.borderRadiusMedium,
        ),
      );
    }

    return Shimmer.fromColors(
      baseColor: AppDecorations.shimmerBase,
      highlightColor: AppDecorations.shimmerHighlight,
      period: const Duration(milliseconds: 1500),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: borderRadius ?? AppDimensions.borderRadiusMedium,
        ),
      ),
    );
  }
}
