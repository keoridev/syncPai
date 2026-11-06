import 'dart:convert';
import 'package:dio/dio.dart';

/// Экстрактор прямых HLS (.m3u8) видеопотоков из iframe плеера Kodik (kodikplayer.com / kodik.info / aniqit).
/// Поддерживает прямое обращение к API /ftor Kodik с расшифровкой ROT18 + base64.
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

  /// Декодирование шифра Цезаря / ROT со сдвигом (для обратной совместимости)
  static String caesarDecrypt(String text, {int shift = 13}) {
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      int code = text.codeUnitAt(i);
      if (code >= 97 && code <= 122) {
        code = ((code - 97 - shift) % 26) + 97;
        if (code < 97) code += 26;
      } else if (code >= 65 && code <= 90) {
        code = ((code - 65 - shift) % 26) + 65;
        if (code < 65) code += 26;
      }
      buffer.write(String.fromCharCode(code));
    }
    return buffer.toString();
  }

  /// Декодирование шифра Kodik (ROT18 + Base64)
  static String decodeKodikLink(String encoded) {
    try {
      final buffer = StringBuffer();
      for (int i = 0; i < encoded.length; i++) {
        final char = encoded[i];
        final code = encoded.codeUnitAt(i);
        // Заглавные A-Z
        if (code >= 65 && code <= 90) {
          final shifted = code + 18;
          buffer.writeCharCode(shifted <= 90 ? shifted : shifted - 26);
        }
        // Строчные a-z
        else if (code >= 97 && code <= 122) {
          final shifted = code + 18;
          buffer.writeCharCode(shifted <= 122 ? shifted : shifted - 26);
        } else {
          buffer.write(char);
        }
      }
      final rotString = buffer.toString();
      final decoded = utf8.decode(base64.decode(rotString));
      return decoded.startsWith('//') ? 'https:$decoded' : decoded;
    } catch (_) {
      return encoded;
    }
  }

  /// Извлечение прямой ссылки m3u8 по ссылке iframe плеера Kodik
  Future<String?> extractDirectStream(String embedUrl, {String quality = '720p'}) async {
    try {
      final safeUrl = embedUrl.startsWith('//') ? 'https:$embedUrl' : embedUrl;
      final uri = Uri.parse(safeUrl);
      final domain = '${uri.scheme}://${uri.host}';

      final response = await _dio.get<String>(
        safeUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Referer': domain,
          },
        ),
      );

      final html = response.data ?? '';
      if (html.isEmpty) return null;

      // 1. Попытка найти уже готовую m3u8 ссылку в скриптах страницы
      final m3u8Match = RegExp(
        r'''['"](https?:\\?/\\?/[^'"]+?\.m3u8[^'"]*?)['"]''',
        caseSensitive: false,
      ).firstMatch(html);
      if (m3u8Match != null) {
        final rawLink = m3u8Match.group(1)!.replaceAll(r'\/', '/');
        return rawLink;
      }

      // 2. Извлекаем параметры для запроса к /ftor шлюзу Kodik
      final domainMatch = RegExp(r'var\s+domain\s*=\s*"([^"]+)";').firstMatch(html);
      final dSignMatch = RegExp(r'var\s+d_sign\s*=\s*"([^"]+)";').firstMatch(html);
      final pdMatch = RegExp(r'var\s+pd\s*=\s*"([^"]+)";').firstMatch(html);
      final pdSignMatch = RegExp(r'var\s+pd_sign\s*=\s*"([^"]+)";').firstMatch(html);
      final refSignMatch = RegExp(r'var\s+ref_sign\s*=\s*"([^"]+)";').firstMatch(html);

      final vTypeMatch = RegExp(r"vInfo\.type\s*=\s*'([^']+)';").firstMatch(html);
      final vHashMatch = RegExp(r"vInfo\.hash\s*=\s*'([^']+)';").firstMatch(html);
      final vIdMatch = RegExp(r"vInfo\.id\s*=\s*'([^']+)';").firstMatch(html);

      if (vHashMatch != null && vIdMatch != null) {
        final postData = {
          'd': domainMatch?.group(1) ?? uri.host,
          'd_sign': dSignMatch?.group(1) ?? '',
          'pd': pdMatch?.group(1) ?? uri.host,
          'pd_sign': pdSignMatch?.group(1) ?? '',
          'ref': '',
          'ref_sign': refSignMatch?.group(1) ?? '',
          'bad_user': 'false',
          'cdn_is_working': 'true',
          'type': vTypeMatch?.group(1) ?? 'seria',
          'hash': vHashMatch.group(1)!,
          'id': vIdMatch.group(1)!,
        };

        final ftorRes = await _dio.post(
          '$domain/ftor',
          data: postData,
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            headers: {
              'Referer': safeUrl,
              'X-Requested-With': 'XMLHttpRequest',
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            },
          ),
        );

        if (ftorRes.statusCode == 200) {
          Map? data;
          if (ftorRes.data is Map) {
            data = ftorRes.data as Map;
          } else if (ftorRes.data is String) {
            try {
              data = jsonDecode(ftorRes.data as String) as Map?;
            } catch (_) {}
          }
          final links = data != null ? data['links'] as Map<String, dynamic>? : null;

          if (links != null) {
            // Приоритеты качества видео
            final targetQuality = quality.replaceAll('p', '');
            final qualityOrder = [targetQuality, '720', '1080', '480', '360'];

            for (final q in qualityOrder) {
              final list = links[q] as List?;
              if (list != null && list.isNotEmpty) {
                final linkObj = list.first;
                final src = linkObj is Map ? (linkObj['src'] as String?) : null;
                if (src != null && src.isNotEmpty) {
                  final decoded = decodeKodikLink(src);
                  if (decoded.contains('.m3u8') || decoded.contains('.mp4')) {
                    final cleanDecoded = decoded.trim();
                    return cleanDecoded.startsWith('//') ? 'https:$cleanDecoded' : cleanDecoded;
                  }
                }
              }
            }
          }
        }
      }

      // Не возвращаем HTML страницу iframe плееру media_kit, так как libmpv не может играть HTML
      return null;
    } catch (_) {
      return null;
    }
  }
}
