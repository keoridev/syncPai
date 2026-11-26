import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Четкий векторный виджет флага страны (`20x14px`, `borderRadius: 3`) без внешних `.si`-ассетов.
/// Одинаково чисто рендерится на Windows Desktop и Android/iOS через `CustomPainter`.
class VectorCountryFlag extends StatelessWidget {
  final String? countryFlag;
  final String? countryName;
  final double width;
  final double height;
  final double borderRadius;

  const VectorCountryFlag({
    super.key,
    this.countryFlag,
    this.countryName,
    this.width = 20,
    this.height = 14,
    this.borderRadius = 3,
  });

  static const Set<String> _painterSupportedCodes = {
    'KG',
    'RU',
    'KZ',
    'UZ',
    'JP',
    'KR',
    'US',
    'DE',
    'GB',
    'FR',
  };

  static String resolveCountryCode(String? flag, String? name) {
    final f = (flag ?? '').trim().toUpperCase();
    final n = (name ?? '').trim().toLowerCase();

    if (f.contains('🇰🇬') || f == 'KG' || n.contains('kyrgyz') || n.contains('кыргыз')) {
      return 'KG';
    }
    if (f.contains('🇷🇺') || f == 'RU' || n.contains('russia') || n.contains('росси')) {
      return 'RU';
    }
    if (f.contains('🇯🇵') || f == 'JP' || n.contains('japan') || n.contains('япон')) {
      return 'JP';
    }
    if (f.contains('🇰🇿') || f == 'KZ' || n.contains('kazakh') || n.contains('казах')) {
      return 'KZ';
    }
    if (f.contains('🇺🇸') || f == 'US' || n.contains('usa') || n.contains('united states') || n.contains('сша')) {
      return 'US';
    }
    if (f.contains('🇺🇦') || f == 'UA' || n.contains('ukrain') || n.contains('украин')) {
      return 'UA';
    }
    if (f.contains('🇧🇾') || f == 'BY' || n.contains('belarus') || n.contains('беларус')) {
      return 'BY';
    }
    if (f.contains('🇺🇿') || f == 'UZ' || n.contains('uzbek') || n.contains('узбек')) {
      return 'UZ';
    }
    if (f.contains('🇰🇷') || f == 'KR' || n.contains('korea') || n.contains('коре')) {
      return 'KR';
    }
    if (f.contains('🇩🇪') || f == 'DE' || n.contains('german') || n.contains('герман')) {
      return 'DE';
    }
    if (f.contains('🇬🇧') || f == 'GB' || f == 'UK' || n.contains('united kingdom') || n.contains('великобрит')) {
      return 'GB';
    }
    if (f.contains('🇫🇷') || f == 'FR' || n.contains('france') || n.contains('франц')) {
      return 'FR';
    }
    if (RegExp(r'^[A-Z]{2}$').hasMatch(f)) {
      return f;
    }
    return 'KG';
  }

  @override
  Widget build(BuildContext context) {
    final countryCode = resolveCountryCode(countryFlag, countryName);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF1A202E),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 0.7,
          ),
        ),
        child: _painterSupportedCodes.contains(countryCode)
            ? CustomPaint(
                size: Size(width, height),
                painter: _VectorFlagPainter(countryCode),
              )
            : Center(
                child: Text(
                  countryCode,
                  style: TextStyle(
                    color: const Color(0xFFE2E8F0),
                    fontSize: math.max(8, height * 0.56),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    height: 1,
                  ),
                ),
              ),
      ),
    );
  }
}

class _VectorFlagPainter extends CustomPainter {
  final String code;

  const _VectorFlagPainter(this.code);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()..style = PaintingStyle.fill;

    switch (code) {
      case 'KG':
        paint.color = const Color(0xFFE8112D);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        paint.color = const Color(0xFFFFD100);
        final cx = w / 2;
        final cy = h / 2;
        final r = math.min(w, h) * 0.27;
        canvas.drawCircle(Offset(cx, cy), r, paint);
        paint.color = const Color(0xFFE8112D);
        canvas.drawCircle(Offset(cx, cy), r * 0.58, paint);
        paint
          ..color = const Color(0xFFFFD100)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.42),
          0,
          math.pi,
          false,
          paint,
        );
        break;

      case 'RU':
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), paint);
        paint.color = const Color(0xFF0039A6);
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), paint);
        paint.color = const Color(0xFFD52B1E);
        canvas.drawRect(Rect.fromLTWH(0, 2 * h / 3, w, h / 3), paint);
        break;

      case 'KZ':
        paint.color = const Color(0xFF00AFCA);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        paint.color = const Color(0xFFFEC50C);
        canvas.drawCircle(Offset(w * 0.52, h * 0.48), math.min(w, h) * 0.22, paint);
        canvas.drawRect(Rect.fromLTWH(w * 0.08, 0, w * 0.08, h), paint);
        break;

      case 'UZ':
        paint.color = const Color(0xFF0099B5);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.32), paint);
        paint.color = const Color(0xFFCE1126);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.32, w, h * 0.04), paint);
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, h * 0.36, w, h * 0.28), paint);
        paint.color = const Color(0xFFCE1126);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.64, w, h * 0.04), paint);
        paint.color = const Color(0xFF1EB53A);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.68, w, h * 0.32), paint);
        paint.color = Colors.white;
        canvas.drawCircle(Offset(w * 0.18, h * 0.16), h * 0.09, paint);
        break;

      case 'JP':
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        paint.color = const Color(0xFFBC002D);
        canvas.drawCircle(Offset(w / 2, h / 2), math.min(w, h) * 0.30, paint);
        break;

      case 'KR':
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        final center = Offset(w / 2, h / 2);
        final r = math.min(w, h) * 0.26;
        paint.color = const Color(0xFFCD2E3A);
        canvas.drawArc(Rect.fromCircle(center: center, radius: r), math.pi, math.pi, true, paint);
        paint.color = const Color(0xFF0047A0);
        canvas.drawArc(Rect.fromCircle(center: center, radius: r), 0, math.pi, true, paint);
        paint.color = const Color(0xFF111827);
        canvas.drawRect(Rect.fromLTWH(w * 0.12, h * 0.18, w * 0.14, h * 0.09), paint);
        canvas.drawRect(Rect.fromLTWH(w * 0.74, h * 0.73, w * 0.14, h * 0.09), paint);
        break;

      case 'US':
        for (int i = 0; i < 7; i++) {
          paint.color = i.isEven ? const Color(0xFFB22234) : Colors.white;
          canvas.drawRect(Rect.fromLTWH(0, i * (h / 7), w, h / 7 + 0.5), paint);
        }
        paint.color = const Color(0xFF3C3B6E);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.44, h * (4 / 7)), paint);
        break;

      case 'DE':
        paint.color = const Color(0xFF111111);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3), paint);
        paint.color = const Color(0xFFDD0000);
        canvas.drawRect(Rect.fromLTWH(0, h / 3, w, h / 3), paint);
        paint.color = const Color(0xFFFFCE00);
        canvas.drawRect(Rect.fromLTWH(0, 2 * h / 3, w, h / 3), paint);
        break;

      case 'GB':
        paint.color = const Color(0xFF012169);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
        paint
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.6, h * 0.18);
        canvas.drawLine(Offset.zero, Offset(w, h), paint);
        canvas.drawLine(Offset(w, 0), Offset(0, h), paint);
        paint.strokeWidth = math.max(2.4, h * 0.26);
        canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), paint);
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), paint);
        paint
          ..color = const Color(0xFFC8102E)
          ..strokeWidth = math.max(1.3, h * 0.14);
        canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), paint);
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), paint);
        break;

      case 'FR':
        paint.color = const Color(0xFF0055A4);
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 3, h), paint);
        paint.color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(w / 3, 0, w / 3, h), paint);
        paint.color = const Color(0xFFEF4135);
        canvas.drawRect(Rect.fromLTWH(2 * w / 3, 0, w / 3, h), paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _VectorFlagPainter oldDelegate) =>
      oldDelegate.code != code;
}
