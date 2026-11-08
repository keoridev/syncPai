import 'package:flutter/foundation.dart';

/// Вспомогательная утилита для безопасной загрузки картинок на всех платформах.
/// - На Web: обходит ограничения CORS браузера через глобальный CDN-прокси images.weserv.nl.
/// - На Android / iOS / Desktop: проксирует домены Shikimori (shikimori.one, shikimori.me, shikimori.io),
///   так как прямые запросы к ним блокируются мобильными провайдерами (РКН) или защитой DDoS-Guard.
/// - Остальные изображения на нативных платформах грузятся напрямую.
String wrapCorsSafeUrl(String url) {
  if (url.isEmpty) return '';

  final trimmed = url.trim();
  // Если ссылка уже локальная или уже проходит через прокси — возвращаем как есть
  if (trimmed.startsWith('blob:') ||
      trimmed.startsWith('data:') ||
      trimmed.contains('images.weserv.nl')) {
    return trimmed;
  }

  final isShikimori = trimmed.contains('shikimori.one') ||
      trimmed.contains('shikimori.me') ||
      trimmed.contains('shikimori.io');

  // Если это не Web и не домен Shikimori, используем прямой URL
  if (!kIsWeb && !isShikimori) {
    return trimmed;
  }

  // Удаляем протокол для передачи в сервис weserv
  final cleanUrl = trimmed
      .replaceFirst(RegExp(r'^https?:\/\/'), '')
      .replaceFirst(RegExp(r'^\/\/'), '');
  return 'https://images.weserv.nl/?url=${Uri.encodeComponent(cleanUrl)}';
}

