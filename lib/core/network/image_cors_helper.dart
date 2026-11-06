import 'package:flutter/foundation.dart';

/// Вспомогательная утилита для безопасной загрузки картинок на всех платформах.
/// Во Flutter Web (Chrome / браузеры) сторонние серверы без заголовка
/// Access-Control-Allow-Origin блокируются политикой CORS браузера.
/// Для Web используется глобальный CDN-прокси с CORS-заголовками (images.weserv.nl),
/// а на Android, iOS, Windows, macOS картинка загружается напрямую.
String wrapCorsSafeUrl(String url) {
  if (url.isEmpty) return '';
  if (!kIsWeb) return url;

  final trimmed = url.trim();
  // Если ссылка уже локальная или уже проходит через прокси — возвращаем как есть
  if (trimmed.startsWith('blob:') ||
      trimmed.startsWith('data:') ||
      trimmed.contains('images.weserv.nl')) {
    return trimmed;
  }

  // Удаляем протокол для передачи в сервис weserv
  final cleanUrl = trimmed.replaceFirst(RegExp(r'^https?:\/\/'), '').replaceFirst(RegExp(r'^\/\/'), '');
  return 'https://images.weserv.nl/?url=${Uri.encodeComponent(cleanUrl)}';
}

