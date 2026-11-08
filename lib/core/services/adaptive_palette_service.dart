import 'package:flutter/material.dart';

/// Сервис извлечения доминирующей палитры из постера или арта аниме (Adaptive Theming).
/// Использует нативную ультра-быструю функцию ColorScheme.fromImageProvider (Flutter 3.22+)
/// без зависания основного изолята и с красивой адаптивной темной палитрой Material You.
class AdaptivePaletteService {
  AdaptivePaletteService._();
  static final AdaptivePaletteService instance = AdaptivePaletteService._();

  final Map<String, Color> _paletteCache = {};

  /// Извлечь доминирующий гармоничный цвет из сетевого изображения с безопасным фолбэком.
  Future<Color> extractDominantColor(String imageUrl, {Color fallbackColor = const Color(0xFFE06C53)}) async {
    if (imageUrl.isEmpty) return fallbackColor;
    if (_paletteCache.containsKey(imageUrl)) {
      return _paletteCache[imageUrl]!;
    }

    try {
      final imageProvider = NetworkImage(imageUrl);
      final scheme = await ColorScheme.fromImageProvider(
        provider: imageProvider,
        brightness: Brightness.dark,
      ).timeout(const Duration(seconds: 2));

      Color chosen = scheme.primary;
      // Добавим сочности для неоновых акцентов
      final hsl = HSLColor.fromColor(chosen);
      if (hsl.lightness < 0.40) {
        chosen = hsl.withLightness(0.55).withSaturation((hsl.saturation * 1.25).clamp(0.0, 1.0)).toColor();
      } else if (hsl.lightness > 0.80) {
        chosen = hsl.withLightness(0.65).toColor();
      }

      _paletteCache[imageUrl] = chosen;
      return chosen;
    } catch (_) {
      // Игнорируем сетевые сбои или ошибки декодирования
    }

    return fallbackColor;
  }

  /// Очистка кэша
  void clearCache() => _paletteCache.clear();
}

