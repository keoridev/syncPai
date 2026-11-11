import 'package:flutter/foundation.dart';

/// Вспомогательная утилита для безопасной загрузки картинок на всех платформах.
/// - На Web: обходит ограничения CORS браузера через глобальный CDN-прокси images.weserv.nl.
/// - На Android / iOS / Desktop: нативные платформы не имеют ограничений CORS браузера,
///   поэтому грузят изображения напрямую с серверов (anilibria.top, shikimori.io).
/// - Заменяет устаревшие/заблокированные зеркала Shikimori на рабочий домен shikimori.io.
String wrapCorsSafeUrl(String url) {
  if (url.isEmpty) return '';

  var trimmed = url.trim();
  // Если ссылка уже локальная (blob/data/file) — возвращаем как есть
  if (trimmed.startsWith('blob:') ||
      trimmed.startsWith('data:') ||
      trimmed.startsWith('file:') ||
      trimmed.startsWith('/')) {
    return trimmed;
  }

  // Заменяем недействительные/устаревшие зеркала Shikimori на рабочий домен shikimori.io
  trimmed = trimmed
      .replaceFirst('https://desu.shikimori.one', 'https://shikimori.io')
      .replaceFirst('http://desu.shikimori.one', 'https://shikimori.io')
      .replaceFirst('//desu.shikimori.one', 'https://shikimori.io')
      .replaceFirst('https://shikimori.me', 'https://shikimori.io')
      .replaceFirst('http://shikimori.me', 'https://shikimori.io')
      .replaceFirst('//shikimori.me', 'https://shikimori.io')
      .replaceFirst('https://shikimori.one', 'https://shikimori.io')
      .replaceFirst('http://shikimori.one', 'https://shikimori.io')
      .replaceFirst('//shikimori.one', 'https://shikimori.io');

  if (trimmed.startsWith('//')) {
    trimmed = 'https:$trimmed';
  }

  // На нативных платформах (Android, iOS, Desktop) ограничения CORS браузера отсутствуют:
  // грузим изображения напрямую без сторонних прокси, которые могут блокироваться провайдерами
  if (!kIsWeb) {
    return trimmed;
  }

  // Для Web: если ссылка уже проходит через weserv — не дублируем
  if (trimmed.contains('images.weserv.nl')) {
    return trimmed;
  }

  // Удаляем протокол для передачи в сервис weserv на Web
  final cleanUrl = trimmed
      .replaceFirst(RegExp(r'^https?:\/\/'), '')
      .replaceFirst(RegExp(r'^\/\/'), '');
  return 'https://images.weserv.nl/?url=${Uri.encodeComponent(cleanUrl)}';
}


