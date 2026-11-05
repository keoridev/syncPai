import 'dart:convert';
import 'package:dio/dio.dart';

/// Экстрактор прямых HLS (.m3u8) и MP4 видеопотоков из iframe плеера Kodik/Aniqit.
/// Обходит обфускацию, декодирует urlParams и извлекает прямые ссылки для media_kit.
class KodikStreamExtractor {
  final Dio _dio;

  KodikStreamExtractor({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Accept': '*/*',
                  'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
                },
              ),
            );

  /// Декодирование шифра Цезаря / ROT со сдвигом (часто используемого Kodik)
  static String caesarDecrypt(String text, {int shift = 13}) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i);
      // a-z
      if (code >= 97 && code <= 122) {
        code = ((code - 97 - shift) % 26) + 97;
        if (code < 97) code += 26;
      }
      // A-Z
      else if (code >= 65 && code <= 90) {
        code = ((code - 65 - shift) % 26) + 65;
        if (code < 65) code += 26;
      }
      buffer.write(String.fromCharCode(code));
    }
    return buffer.toString();
  }

  /// Извлечение прямой ссылки m3u8 или mp4 по ссылке iframe плеера
  Future<String?> extractDirectStream(String embedUrl, {String quality = '720p'}) async {
    try {
      final safeUrl = embedUrl.startsWith('//') ? 'https:$embedUrl' : embedUrl;
      final uri = Uri.parse(safeUrl);
      final domain = '${uri.scheme}://${uri.host}';

      final response = await _dio.get<String>(
        safeUrl,
        options: Options(
          headers: {
            'Referer': domain,
          },
        ),
      );

      final html = response.data ?? '';
      if (html.isEmpty) return null;

      // 1. Попытка найти прямую m3u8 ссылку в скриптах страницы
      final m3u8Match = RegExp(r'''['"](https?:\\?/\\?/[^'"]+?\.m3u8[^'"]*?)['"]''', caseSensitive: false)
          .firstMatch(html);
      if (m3u8Match != null) {
        final rawLink = m3u8Match.group(1)!.replaceAll(r'\/', '/');
        return rawLink;
      }

      // 2. Попытка извлечь urlParams для обращения к шлюзу потоков
      final urlParamsMatch = RegExp(r'''var\s+urlParams\s*=\s*['"](\{.+?\})['"]''').firstMatch(html);
      Map<String, dynamic>? urlParams;
      if (urlParamsMatch != null) {
        final rawJson = urlParamsMatch.group(1)!;
        try {
          urlParams = jsonDecode(rawJson) as Map<String, dynamic>;
        } catch (_) {
          try {
            final decoded = Uri.decodeComponent(rawJson);
            urlParams = jsonDecode(decoded) as Map<String, dynamic>;
          } catch (_) {}
        }
      }

      // 3. Извлечение видео-хэшей и домена
      final videoInfoMatch = RegExp(r'''videoInfo\s*=\s*(\{.+?\});''').firstMatch(html);
      if (videoInfoMatch != null && urlParams != null) {
        try {
          final postUri = Uri.parse('$domain/gvi');
          final postRes = await _dio.post(
            postUri.toString(),
            data: FormData.fromMap(urlParams),
            options: Options(
              headers: {
                'Referer': safeUrl,
                'X-Requested-With': 'XMLHttpRequest',
              },
            ),
          );

          if (postRes.data is Map) {
            final data = postRes.data as Map;
            final links = data['links'] as Map<String, dynamic>?;
            if (links != null) {
              // Ищем ссылку под выбранное качество (720, 1080, 480, 360)
              for (final q in ['1080', '720', '480', '360']) {
                final list = links[q] as List?;
                if (list != null && list.isNotEmpty) {
                  final linkObj = list.first;
                  final src = linkObj is Map ? (linkObj['src'] as String?) : null;
                  if (src != null) {
                    final cleanSrc = src.startsWith('//') ? 'https:$src' : src;
                    return cleanSrc;
                  }
                }
              }
            }
          }
        } catch (_) {}
      }

      // Fallback: возвращаем iframe ссылку для внешнего воспроизведения или вебвью
      return safeUrl;
    } catch (_) {
      return null;
    }
  }
}

