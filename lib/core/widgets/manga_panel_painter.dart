import 'package:flutter/material.dart';

/// Проверяет, активна ли печатная тема «Манга» (бумага #F5F4F0 + тушь #111111).
bool isMangaPrintTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.light &&
      theme.scaffoldBackgroundColor == const Color(0xFFF5F4F0);
}

/// Декоративный слой печатной манга-панели:
/// - полутоновый Ben-Day скринтон (`Color(0x14111111)`),
/// - диагональные линии скорости (speedlines) в правом верхнем углу,
/// - чёткие тушевые уголки-акценты (`Color(0xFF111111)`).
class MangaPanelPainter extends CustomPainter {
  const MangaPanelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Полутоновый Ben-Day скринтон
    final dotPaint = Paint()..color = const Color(0x14111111);
    const step = 9.0;
    for (double y = 4.5; y < size.height; y += step) {
      final shiftX = ((y ~/ step).isOdd) ? step * 0.5 : 0.0;
      for (double x = 4.5 + shiftX; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.05, dotPaint);
      }
    }

    // 2. Диагональные манга-линии скорости в правом верхнем углу
    final speedPaint = Paint()
      ..color = const Color(0x12111111)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 6; i++) {
      final offset = i * 14.0;
      canvas.drawLine(
        Offset(size.width - 110 + offset, 0),
        Offset(size.width, 90 - offset * 0.65),
        speedPaint,
      );
    }

    // 3. Тушевые уголки-акценты (corner ink accents)
    final cornerPaint = Paint()
      ..color = const Color(0xFF111111)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    const len = 12.0;
    // Левый верхний
    canvas.drawLine(const Offset(4, 4), const Offset(4 + len, 4), cornerPaint);
    canvas.drawLine(const Offset(4, 4), const Offset(4, 4 + len), cornerPaint);
    // Правый нижний
    canvas.drawLine(
      Offset(size.width - 4, size.height - 4),
      Offset(size.width - 4 - len, size.height - 4),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(size.width - 4, size.height - 4),
      Offset(size.width - 4, size.height - 4 - len),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

