import 'package:flutter/material.dart';

/// Проверяет, активна ли тёмная графитовая тема «Манга» (#0D0F12 + #F1F5F9).
bool isMangaPrintTheme(BuildContext context) {
  final theme = Theme.of(context);
  return theme.scaffoldBackgroundColor == const Color(0xFF0D0F12) &&
      theme.colorScheme.primary == const Color(0xFFF1F5F9);
}

/// Декоративный слой манга-панели на тёмном графите:
/// - тонкий полутоновый скринтон (`Color(0x08F8FAFC)` — 3% белой прозрачности),
/// - диагональные линии скорости (speedlines) в правом верхнем углу,
/// - чёткие меловые уголки-акценты (`Color(0x4DF8FAFC)`).
class MangaPanelPainter extends CustomPainter {
  const MangaPanelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Полутоновый скринтон (3% белой прозрачности)
    final dotPaint = Paint()..color = const Color(0x08F8FAFC);
    const step = 9.0;
    for (double y = 4.5; y < size.height; y += step) {
      final shiftX = ((y ~/ step).isOdd) ? step * 0.5 : 0.0;
      for (double x = 4.5 + shiftX; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }

    // 2. Диагональные манга-линии скорости в правом верхнем углу
    final speedPaint = Paint()
      ..color = const Color(0x0AF8FAFC)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 6; i++) {
      final offset = i * 14.0;
      canvas.drawLine(
        Offset(size.width - 110 + offset, 0),
        Offset(size.width, 90 - offset * 0.65),
        speedPaint,
      );
    }

    // 3. Меловые уголки-акценты
    final cornerPaint = Paint()
      ..color = const Color(0x4DF8FAFC)
      ..strokeWidth = 1.8
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

