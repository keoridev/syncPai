import 'dart:io';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_container.dart';

/// Результат кадрирования и трансформации медиа
class MediaCropResult {
  final double scale;
  final double rotationDegrees;
  final Offset offset;

  const MediaCropResult({
    required this.scale,
    required this.rotationDegrees,
    required this.offset,
  });
}

enum CropShape { circle, banner }

/// Интерактивный редактор позиционирования (Crop, Zoom, Rotate)
/// в стиле Discord Nitro / Steam Profile Customizer.
class MediaCropEditorModal extends StatefulWidget {
  final String imagePathOrUrl;
  final CropShape shape;
  final double initialScale;
  final double initialRotation;

  const MediaCropEditorModal({
    super.key,
    required this.imagePathOrUrl,
    this.shape = CropShape.circle,
    this.initialScale = 1.0,
    this.initialRotation = 0.0,
  });

  static Future<MediaCropResult?> show(
    BuildContext context, {
    required String imagePathOrUrl,
    CropShape shape = CropShape.circle,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<MediaCropResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MediaCropEditorModal(
        imagePathOrUrl: imagePathOrUrl,
        shape: shape,
      ),
    );
  }

  @override
  State<MediaCropEditorModal> createState() => _MediaCropEditorModalState();
}

class _MediaCropEditorModalState extends State<MediaCropEditorModal> {
  late final TransformationController _transformController;
  double _rotationDegrees = 0.0;
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _rotationDegrees = widget.initialRotation;
    _currentScale = widget.initialScale;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _rotateBy90() {
    HapticFeedback.selectionClick();
    setState(() {
      _rotationDegrees = (_rotationDegrees + 90.0) % 360.0;
    });
  }

  void _resetTransform() {
    HapticFeedback.mediumImpact();
    setState(() {
      _rotationDegrees = 0.0;
      _currentScale = 1.0;
      _transformController.value = Matrix4.identity();
    });
  }

  void _applyCrop() {
    HapticFeedback.heavyImpact();
    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = Offset(matrix.storage[12], matrix.storage[13]);

    Navigator.of(context).pop(
      MediaCropResult(
        scale: scale,
        rotationDegrees: _rotationDegrees,
        offset: translation,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isCircle = widget.shape == CropShape.circle;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.88,
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Хэндл бар
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.strokeMedium,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Заголовок
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.crop_rotate_rounded, color: accent, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isCircle ? 'Кадрирование аватарки' : 'Настройка баннера',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                  tooltip: 'Сбросить',
                  onPressed: _resetTransform,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Центральная область кадрирования с интерактивной сеткой
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AspectRatio(
                  aspectRatio: isCircle ? 1.0 : (16 / 9),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isCircle ? 999 : 20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Интерактивный трансформатор с зумом и сдвигом
                        InteractiveViewer(
                          transformationController: _transformController,
                          minScale: 0.5,
                          maxScale: 4.5,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          onInteractionUpdate: (details) {
                            final s = _transformController.value.getMaxScaleOnAxis();
                            if ((s - _currentScale).abs() > 0.05) {
                              setState(() => _currentScale = s);
                            }
                          },
                          child: Center(
                            child: Transform.rotate(
                              angle: (_rotationDegrees * math.pi) / 180.0,
                              child: _buildImageSource(),
                            ),
                          ),
                        ),

                        // Полупрозрачная видоискательная сетка кадрирования (Rule of Thirds)
                        IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                              border: Border.all(color: accent, width: 2.0),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                            child: isCircle
                                ? null
                                : CustomPaint(
                                    painter: _RuleOfThirdsPainter(color: accent.withValues(alpha: 0.45)),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Панель управления (Вращение + Зум слайдер)
          GlassContainer(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            blurSigma: 16,
            backgroundOpacity: 0.12,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ползунок точного угла поворота
                Row(
                  children: [
                    const Icon(Icons.rotate_right_rounded, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Угол: ${_rotationDegrees.round()}°',
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    Expanded(
                      child: Slider(
                        value: _rotationDegrees,
                        min: 0,
                        max: 360,
                        divisions: 72,
                        activeColor: accent,
                        inactiveColor: AppColors.strokeMedium,
                        onChanged: (val) {
                          setState(() => _rotationDegrees = val);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.rotate_90_degrees_cw_rounded, color: AppColors.textPrimary, size: 22),
                      tooltip: 'Повернуть на 90°',
                      onPressed: _rotateBy90,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Кнопка применить
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    onPressed: _applyCrop,
                    child: const Text(
                      'Применить ракурс',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSource() {
    final path = widget.imagePathOrUrl.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: wrapCorsSafeUrl(path),
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 64, color: AppColors.textMuted),
      );
    }
    final clean = path.replaceFirst('file://', '');
    return Image.file(
      File(clean),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, size: 64, color: AppColors.textMuted),
    );
  }
}

/// Сетка золотого сечения (правило третей)
class _RuleOfThirdsPainter extends CustomPainter {
  final Color color;

  _RuleOfThirdsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final x1 = size.width / 3;
    final x2 = size.width * 2 / 3;
    final y1 = size.height / 3;
    final y2 = size.height * 2 / 3;

    canvas.drawLine(Offset(x1, 0), Offset(x1, size.height), paint);
    canvas.drawLine(Offset(x2, 0), Offset(x2, size.height), paint);
    canvas.drawLine(Offset(0, y1), Offset(size.width, y1), paint);
    canvas.drawLine(Offset(0, y2), Offset(size.width, y2), paint);
  }

  @override
  bool shouldRepaint(covariant _RuleOfThirdsPainter oldDelegate) => oldDelegate.color != color;
}

