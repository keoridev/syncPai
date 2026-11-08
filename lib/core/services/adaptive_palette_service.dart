import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Сервис извлечения доминирующей палитры из постера или арта аниме (Adaptive Theming).
/// Обеспечивает кэширование и плавную трансформацию акцентных оттенков интерфейса.
class AdaptivePaletteService {
  AdaptivePaletteService._();
  static final AdaptivePaletteService instance = AdaptivePaletteService._();

  final Map<String, Color> _paletteCache = {};

  /// Извлечь доминирующий яркий цвет из сетевого изображения с безопасным фолбэком.
  Future<Color> extractDominantColor(String imageUrl, {Color fallbackColor = const Color(0xFFE06C53)}) async {
    if (imageUrl.isEmpty) return fallbackColor;
    if (_paletteCache.containsKey(imageUrl)) {
      return _paletteCache[imageUrl]!;
    }

    try {
      final imageProvider = NetworkImage(imageUrl);
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 16,
      ).timeout(const Duration(seconds: 2));

      Color? chosen = palette.vibrantColor?.color ??
          palette.dominantColor?.color ??
          palette.lightVibrantColor?.color ??
          palette.mutedColor?.color;

      if (chosen != null) {
        // Убедимся, что цвет не слишком темный для неонового свечения
        final hsl = HSLColor.fromColor(chosen);
        if (hsl.lightness < 0.35) {
          chosen = hsl.withLightness(0.52).withSaturation((hsl.saturation * 1.2).clamp(0.0, 1.0)).toColor();
        } else if (hsl.lightness > 0.85) {
          chosen = hsl.withLightness(0.65).toColor();
        }
        _paletteCache[imageUrl] = chosen;
        return chosen;
      }
    } catch (_) {
      // Игнорируем сетевые сбои или ошибки декодирования
    }

    return fallbackColor;
  }

  /// Очистка кэша
  void clearCache() => _paletteCache.clear();
}
