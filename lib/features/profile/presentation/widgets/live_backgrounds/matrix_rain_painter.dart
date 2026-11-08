import 'package:flutter/material.dart';

/// Высокопроизводительный процедурный холст эффекта «Матрица» (Matrix Digital Rain).
/// Падающие неоновые столбцы японской катаканы и бинарного кода
/// с разной скоростью, плотностью и затуханием шлейфа (fade trail).
class MatrixRainPainter extends CustomPainter {
  final double animationValue;
  final Color primaryColor;
  final int columnCount;

  static const List<String> _glyphs = [
    'ｱ', 'ｲ', 'ｳ', 'ｴ', 'ｵ', 'ｶ', 'ｷ', 'ｸ', 'ｹ', 'ｺ',
    'ｻ', 'ｼ', 'ｽ', 'ｾ', 'ｿ', 'ﾀ', 'ﾁ', 'ﾂ', 'ﾃ', 'ﾄ',
    'ﾅ', 'ﾆ', 'ﾇ', 'ﾈ', 'ﾉ', 'ﾊ', 'ﾋ', 'ﾌ', 'ﾍ', 'ﾎ',
    '0', '1', 'X', 'Y', 'Z', '9', '7', '4', '2',
  ];

  MatrixRainPainter({
    required this.animationValue,
    this.primaryColor = const Color(0xFF00FF66),
    this.columnCount = 28,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final columnWidth = size.width / columnCount;
    final rowHeight = 16.0;
    final maxRows = (size.height / rowHeight).ceil() + 4;

    for (int col = 0; col < columnCount; col++) {
      // Псевдослучайное смещение для каждого столбца
      final seed = (col * 17 + 31) % 100;
      final speedFactor = 0.6 + ((seed % 10) * 0.08);
      final colOffset = (seed / 100.0);

      // Текущая ведущая позиция капли (drop head)
      final dropHeadY = ((animationValue * speedFactor + colOffset) % 1.0) * (size.height + 120) - 40;
      final leadRow = (dropHeadY / rowHeight).floor();
      final trailLength = 8 + (seed % 10);

      final colX = col * columnWidth + (columnWidth / 2);

      for (int t = 0; t < trailLength; t++) {
        final currentRow = leadRow - t;
        if (currentRow < 0 || currentRow > maxRows) continue;

        final y = currentRow * rowHeight;
        if (y < -10 || y > size.height + 10) continue;

        final glyphIndex = (col * 7 + currentRow * 13 + (animationValue * 10).floor()) % _glyphs.length;
        final char = _glyphs[glyphIndex];

        // Голова капли — ярко-белая/сверхсветлая, шлейф плавно затухает в темный неон
        final isHead = t == 0;
        final alpha = isHead
            ? 0.95
            : (1.0 - (t / trailLength)).clamp(0.05, 0.85);

        final color = isHead
            ? Colors.white
            : primaryColor.withValues(alpha: alpha);

        final textPainter = TextPainter(
          text: TextSpan(
            text: char,
            style: TextStyle(
              color: color,
              fontSize: isHead ? 13 : 11.5,
              fontWeight: isHead ? FontWeight.w900 : FontWeight.w600,
              fontFamily: 'monospace',
              shadows: isHead
                  ? [
                      Shadow(
                        color: primaryColor,
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        textPainter.paint(
          canvas,
          Offset(colX - textPainter.width / 2, y),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant MatrixRainPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.primaryColor != primaryColor;
  }
}
