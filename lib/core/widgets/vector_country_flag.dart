import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

/// Четкий векторный виджет флага страны (`20x14px`, `borderRadius: 3`) на базе `country_flags`,
/// который одинаково ярко и без искажений рендерится на Windows Desktop
/// (где региональные эмодзи `🇰🇬` падают в серые буквы `KG`) и на Android/iOS.
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
    // Если передан валидный 2-буквенный ISO-код страны
    if (RegExp(r'^[A-Z]{2}$').hasMatch(f)) {
      return f;
    }
    return 'KG';
  }

  @override
  Widget build(BuildContext context) {
    final countryCode = resolveCountryCode(countryFlag, countryName);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 0.7,
        ),
      ),
      child: CountryFlag.fromCountryCode(
        countryCode,
        width: width,
        height: height,
        shape: RoundedRectangle(borderRadius),
      ),
    );
  }
}
