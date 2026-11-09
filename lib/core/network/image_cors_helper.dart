import 'package:flutter/foundation.dart';

/// Вспомогательная утилита для безопасной загрузки картинок на всех платформах.
/// - На Web: обходит ограничения CORS браузера через глобальный CDN-прокси images.weserv.nl.
/// - На Android / iOS / Desktop: проксирует домены Shikimori (shikimori.one, shikimori.me, shikimori.io),
///   так как прямые запросы к ним блокируются мобильными провайдерами (РКН) или защитой DDoS-Guard.
/// - Остальные изображения на нативных платформах грузятся напрямую.
String wrapCorsSafeUrl(String url) {
  if (url.isEmpty) return '';

  var trimmed = url.trim();
  // Если ссылка уже локальная или уже проходит через прокси — возвращаем как есть
  if (trimmed.startsWith('blob:') ||
      trimmed.startsWith('data:') ||
      trimmed.contains('images.weserv.nl')) {
    return trimmed;
  }

  // Заменяем недействительные/устаревшие зеркала Shikimori на рабочий домен shikimori.io
  trimmed = trimmed
      .replaceFirst('https://desu.shikimori.one', 'https://shikimori.io')
      .replaceFirst('http://desu.shikimori.one', 'https://shikimori.io')
      .replaceFirst('//desu.shikimori.one', '//shikimori.io')
      .replaceFirst('https://shikimori.me', 'https://shikimori.io')
      .replaceFirst('http://shikimori.me', 'https://shikimori.io')
      .replaceFirst('//shikimori.me', '//shikimori.io')
      .replaceFirst('https://shikimori.one', 'https://shikimori.io')
      .replaceFirst('http://shikimori.one', 'https://shikimori.io')
      .replaceFirst('//shikimori.one', '//shikimori.io');

  final isShikimori = trimmed.contains('shikimori.io') ||
      trimmed.contains('shikimori.one') ||
      trimmed.contains('shikimori.me');

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

