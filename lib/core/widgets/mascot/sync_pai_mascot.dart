import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimensions.dart';
import '../../theme/app_typography.dart';
import 'mascot_state.dart';

/// Варианты размеров маскота
enum MascotSizePreset {
  small(130.0, 130.0),
  medium(190.0, 190.0),
  large(260.0, 260.0);

  final double width;
  final double height;

  const MascotSizePreset(this.width, this.height);
}

class MascotSize {
  final double width;
  final double height;

  const MascotSize._(this.width, this.height);

  static const MascotSize small = MascotSize._(130.0, 130.0);
  static const MascotSize medium = MascotSize._(190.0, 190.0);
  static const MascotSize large = MascotSize._(260.0, 260.0);

  const MascotSize.custom(double width, double height) : this._(width, height);
}

/// Универсальный переиспользуемый компонент маскота SyncPai
///
/// Поддерживает:
/// - Все 29 состояний (enum [MascotState])
/// - Адаптивные размеры под мобильные и десктоп экраны
/// - Плавную «дышащую» левитацию (с поддержкой reduced motion)
/// - Доступность (semanticLabel alt-text)
/// - Кастомные сообщения, описания и интерактивные кнопки действий
class SyncPaiMascot extends StatefulWidget {
  final MascotState state;
  final MascotSize size;
  final String? message;
  final String? description;
  final Widget? action;
  final bool animated;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const SyncPaiMascot({
    super.key,
    required this.state,
    this.size = MascotSize.medium,
    this.message,
    this.description,
    this.action,
    this.animated = true,
    this.onTap,
    this.padding = const EdgeInsets.all(AppDimensions.spacingMd),
  });

  /// Быстрый фабричный конструктор для пустых состояний
  factory SyncPaiMascot.empty({
    Key? key,
    required MascotState state,
    String? message,
    String? description,
    Widget? action,
    MascotSize size = MascotSize.medium,
  }) {
    return SyncPaiMascot(
      key: key,
      state: state,
      size: size,
      message: message,
      description: description,
      action: action,
    );
  }

  /// Быстрый фабричный конструктор для экранов ошибок
  factory SyncPaiMascot.error({
    Key? key,
    MascotState state = MascotState.networkError,
    String? message,
    String? description,
    VoidCallback? onRetry,
    String retryLabel = 'Повторить попытку',
    MascotSize size = MascotSize.medium,
  }) {
    return SyncPaiMascot(
      key: key,
      state: state,
      size: size,
      message: message,
      description: description,
      action: onRetry != null
          ? ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(retryLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: const Color(0xFF0F1117),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          : null,
    );
  }

  @override
  State<SyncPaiMascot> createState() => _SyncPaiMascotState();
}

class _SyncPaiMascotState extends State<SyncPaiMascot>
    with SingleTickerProviderStateMixin {
  AnimationController? _floatController;
  Animation<double>? _floatAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimation();
  }

  void _initAnimation() {
    if (widget.animated) {
      _floatController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);

      _floatAnimation = Tween<double>(begin: -4.0, end: 4.0).animate(
        CurvedAnimation(
          parent: _floatController!,
          curve: Curves.easeInOutSine,
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant SyncPaiMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animated != widget.animated) {
      if (widget.animated) {
        _initAnimation();
      } else {
        _floatController?.dispose();
        _floatController = null;
        _floatAnimation = null;
      }
    }
  }

  @override
  void dispose() {
    _floatController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Поддержка системной настройки доступности Reduced Motion
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    // Адаптивное масштабирование
    final targetWidth = isDesktop ? widget.size.width * 1.05 : widget.size.width;
    final targetHeight = isDesktop ? widget.size.height * 1.05 : widget.size.height;

    final displayMessage = widget.message ?? widget.state.defaultMessage;
    final displayDesc = widget.description ?? widget.state.defaultDescription;

    Widget imageContent = Semantics(
      label: '${widget.state.title}: ${widget.state.description}',
      image: true,
      child: Image.asset(
        widget.state.assetPath,
        width: targetWidth,
        height: targetHeight,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) {
          // Изящный fallback в случае отсутствия ассета
          return Container(
            width: targetWidth,
            height: targetHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: Icon(
              Icons.face_rounded,
              size: 48,
              color: AppColors.primary,
            ),
          );
        },
      ),
    );

    // Плавная левитация маскота
    if (widget.animated && !disableAnimations && _floatAnimation != null) {
      imageContent = AnimatedBuilder(
        animation: _floatAnimation!,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, _floatAnimation!.value),
            child: child,
          );
        },
        child: imageContent,
      );
    }

    if (widget.onTap != null) {
      imageContent = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: imageContent,
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isDesktop ? 480 : 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              imageContent,
              if (displayMessage.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  displayMessage,
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: isDesktop ? 17 : 15.5,
                  ),
                ),
              ],
              if (displayDesc.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  displayDesc,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                    fontSize: isDesktop ? 13.5 : 12.5,
                  ),
                ),
              ],
              if (widget.action != null) ...[
                const SizedBox(height: 18),
                widget.action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
