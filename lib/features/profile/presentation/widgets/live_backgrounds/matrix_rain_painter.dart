import 'package:flutter/material.dart';

/// Высокопроизводительный процедурный холст эффекта «Матрица / Hacker Code» (Matrix Digital Rain).
/// Быстро падающие неоновые столбцы японской катаканы, шестнадцатеричного и бинарного кода
/// с яркими мерцающими белыми головами потоков, затухающим шлейфом и киберпанк-свечением.
class MatrixRainPainter extends CustomPainter {
  final double animationValue;
  final Color primaryColor;
  final int columnCount;

  static const List<String> _glyphs = [
    'ｱ', 'ｲ', 'ｳ', 'ｴ', 'ｵ', 'ｶ', 'ｷ', 'ｸ', 'ｹ', 'ｺ',
    'ｻ', 'ｼ', 'ｽ', 'ｾ', 'ｿ', 'ﾀ', 'ﾁ', 'ﾂ', 'ﾃ', 'ﾄ',
    'ﾅ', 'ﾆ', 'ﾇ', 'ﾈ', 'ﾉ', 'ﾊ', 'ﾋ', 'ﾌ', 'ﾍ', 'ﾎ',
    '0', '1', 'A', 'F', 'X', 'Y', 'Z', '9', '7', '4', '2', '8',
    'λ', 'π', 'Ω', '§', '%', '#', '&',
  ];

  MatrixRainPainter({
    required this.animationValue,
    this.primaryColor = const Color(0xFF00FF66),
    this.columnCount = 26,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final columnWidth = size.width / columnCount;
    const rowHeight = 15.0;
    final maxRows = (size.height / rowHeight).ceil() + 3;

    for (int col = 0; col < columnCount; col++) {
      final seed = (col * 19 + 43) % 100;
      // Высокая скорость для эффекта реального хакерского терминала
      final speedFactor = 1.2 + ((seed % 10) * 0.16);
      final colOffset = (seed / 100.0);

      // Ведущая позиция капли (drop head)
      final dropHeadY = ((animationValue * speedFactor + colOffset) % 1.0) * (size.height + 140) - 30;
      final leadRow = (dropHeadY / rowHeight).floor();
      final trailLength = 7 + (seed % 9);

      final colX = col * columnWidth + (columnWidth / 2);

      for (int t = 0; t < trailLength; t++) {
        final currentRow = leadRow - t;
        if (currentRow < 0 || currentRow > maxRows) continue;

        final y = currentRow * rowHeight;
        if (y < -12 || y > size.height + 12) continue;

        final glyphIndex = (col * 11 + currentRow * 17 + (animationValue * 22).floor()) % _glyphs.length;
        final char = _glyphs[glyphIndex];

        final isHead = t == 0;
        final alpha = isHead
            ? 1.0
            : (1.0 - (t / trailLength)).clamp(0.08, 0.85);

        final textColor = isHead
            ? Colors.white
            : primaryColor.withValues(alpha: alpha);

        final textPainter = TextPainter(
          text: TextSpan(
            text: char,
            style: TextStyle(
              color: textColor,
              fontSize: isHead ? 13.5 : 11.0,
              fontWeight: isHead ? FontWeight.w900 : FontWeight.w600,
              fontFamily: 'monospace',
              shadows: isHead
                  ? [
                      Shadow(
                        color: primaryColor,
                        blurRadius: 9,
                      ),
                      const Shadow(
                        color: Colors.white,
                        blurRadius: 4,
                      ),
                    ]
                  : (t < 3
                      ? [
                          Shadow(
                            color: primaryColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ]
                      : null),
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
