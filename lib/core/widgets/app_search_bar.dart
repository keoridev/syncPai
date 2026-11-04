import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';

/// Строка поиска в стиле Nordic Dark.
class AppSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final String hintText;
  final bool autofocus;

  const AppSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.onClear,
    this.hintText = 'Поиск аниме, жанров, студий…',
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDimensions.searchBarHeight,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppDimensions.borderRadiusMedium,
        border: Border.all(
          color: AppColors.stroke,
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          filled: false,
          hintText: hintText,
          hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          prefixIconConstraints: const BoxConstraints(
            minWidth: AppDimensions.iconSizeMedium + 8,
            minHeight: AppDimensions.iconSizeMedium,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(right: AppDimensions.spacingSm),
            child: Icon(
              Icons.search_rounded,
              color: AppColors.textSecondary,
              size: AppDimensions.iconSizeMedium,
            ),
          ),
          suffixIcon: controller != null && controller!.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    controller?.clear();
                    onClear?.call();
                    onChanged?.call('');
                  },
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppColors.textMuted,
                    size: AppDimensions.iconSizeSmall + 2,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

