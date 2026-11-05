import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';

/// Элегантная поисковая строка в стиле Frosted Glass / Nordic Dark.
/// Тонкая, полупрозрачная, с деликатным размытием вместо массивного глухого блока.
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 42.0,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingMd),
          alignment: Alignment.center,
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            onChanged: onChanged,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
            cursorColor: Theme.of(context).colorScheme.primary,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              filled: false,
              hintText: hintText,
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
                fontSize: 13.5,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              prefixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 20,
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.search_rounded,
                  color: AppColors.textSecondary,
                  size: 19,
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
                        size: 18,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
