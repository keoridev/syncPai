import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';

/// Элегантная поисковая строка в стиле Frosted Glass / Nordic Dark.
/// Тонкая, полупрозрачная, с деликатным размытием и кнопкой очистки `✕` внутри `suffixIcon`.
class AppSearchBar extends StatefulWidget {
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
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  late TextEditingController _effectiveController;
  bool _ownsController = false;
  final FocusNode _focusNode = FocusNode();
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _effectiveController = widget.controller!;
    } else {
      _effectiveController = TextEditingController();
      _ownsController = true;
    }
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_hasFocus != _focusNode.hasFocus) {
      setState(() => _hasFocus = _focusNode.hasFocus);
    }
  }

  @override
  void didUpdateWidget(covariant AppSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) {
        _effectiveController.dispose();
        _ownsController = false;
      }
      if (widget.controller != null) {
        _effectiveController = widget.controller!;
      } else {
        _effectiveController = TextEditingController();
        _ownsController = true;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    if (_ownsController) {
      _effectiveController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 46.0,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hasFocus ? 0.08 : 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hasFocus
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.3),
              width: _hasFocus ? 1.4 : 1.0,
            ),
            boxShadow: _hasFocus
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.14),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.only(left: AppDimensions.spacingMd, right: 6),
          alignment: Alignment.center,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _effectiveController,
            builder: (context, value, _) {
              final hasText = value.text.isNotEmpty;
              return TextField(
                controller: _effectiveController,
                focusNode: _focusNode,
                autofocus: widget.autofocus,
                onChanged: widget.onChanged,
                textAlignVertical: TextAlignVertical.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                cursorColor: scheme.primary,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  filled: false,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  hintText: widget.hintText,
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textMuted,
                    fontSize: 13.5,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 20,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.search_rounded,
                      color: _hasFocus ? scheme.primary : AppColors.textSecondary,
                      size: 19,
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  suffixIcon: hasText
                      ? IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                          tooltip: 'Очистить поиск',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            _effectiveController.clear();
                            widget.onClear?.call();
                            widget.onChanged?.call('');
                          },
                        )
                      : null,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
