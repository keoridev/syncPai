import 'dart:convert';

/// Тип распознанного QR-кода или ссылки SyncPai
enum QrPayloadType {
  room,
  friendInvite,
  unknown,
}

/// Результат классификации QR-кода / ссылки / кода
class ParsedQrPayload {
  final QrPayloadType type;
  final String cleanCode;
  final String rawValue;

  const ParsedQrPayload({
    required this.type,
    required this.cleanCode,
    required this.rawValue,
  });

  bool get isRoom => type == QrPayloadType.room && cleanCode.isNotEmpty;
  bool get isFriendInvite =>
      type == QrPayloadType.friendInvite && cleanCode.isNotEmpty;
  bool get isValid => isRoom || isFriendInvite;
}

/// Парсер и нормализатор кодов комнат SyncPai.
/// Извлекает чистый 6-значный (или 4-значный демо) ID комнаты без авто-дефисов и префиксов.
class RoomCodeParser {
  RoomCodeParser._();

  /// Очищает сырую строку (код, URL `syncpai://room/639245`, `https://syncpai.app/room/639245`,
  /// JSON `{"type":"room","id":"639245"}`, `SP-639245`, `639-245`) и возвращает чистый ID комнаты (`"639245"`).
  static String extractCleanRoomId(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    // 1. Проверяем JSON формат: {"type":"room","id":"639245"}
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final idVal =
              decoded['id'] ?? decoded['room_id'] ?? decoded['code'] ?? '';
          if (idVal.toString().isNotEmpty) {
            return extractCleanRoomId(idVal.toString());
          }
        }
      } catch (_) {}
    }

    String working = trimmed;

    // 2. Извлекаем из URL или Deep Link:
    // syncpai://room/639245, https://syncpai.app/room/639245, ?room=639245
    final roomPathMatch = RegExp(
      r'(?:syncpai:\/\/room\/|https?:\/\/[^\/\s]+\/room\/|[?&]room=)([A-Za-z0-9\-_]+)',
      caseSensitive: false,
    ).firstMatch(working);

    if (roomPathMatch != null && roomPathMatch.group(1) != null) {
      working = roomPathMatch.group(1)!;
    } else if (working.contains('/')) {
      final uri = Uri.tryParse(working);
      if (uri != null) {
        if (uri.queryParameters['room'] != null &&
            uri.queryParameters['room']!.isNotEmpty) {
          working = uri.queryParameters['room']!;
        } else if (uri.pathSegments.isNotEmpty) {
          working = uri.pathSegments.last;
        }
      }
    }

    // 3. Убираем префикс SP- или SP (если за ним идет код комнаты)
    working = working.trim();
    if (RegExp(r'^sp[\-\s_]*', caseSensitive: false).hasMatch(working)) {
      final withoutSp = working.replaceFirst(
        RegExp(r'^sp[\-\s_]*', caseSensitive: false),
        '',
      );
      if (withoutSp.isNotEmpty) {
        working = withoutSp;
      }
    }

    // 4. Удаляем все дефисы, пробелы и не-алфавитно-цифровые символы
    final clean = working
        .replaceAll(RegExp(r'[^0-9A-Za-z]'), '')
        .toUpperCase();

    return clean;
  }
}

/// Единый маршрутизатор QR-кодов и инвайт-ссылок SyncPai (Room QR vs Friend Invite QR).
class QrPayloadRouter {
  QrPayloadRouter._();

  static ParsedQrPayload parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return ParsedQrPayload(
        type: QrPayloadType.unknown,
        cleanCode: '',
        rawValue: raw,
      );
    }

    // 1. JSON payload
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final typeStr = (decoded['type'] ?? '').toString().toLowerCase();
          if (typeStr == 'room') {
            final cleanId = RoomCodeParser.extractCleanRoomId(
              (decoded['id'] ?? decoded['room_id'] ?? decoded['code'] ?? '')
                  .toString(),
            );
            if (cleanId.isNotEmpty) {
              return ParsedQrPayload(
                type: QrPayloadType.room,
                cleanCode: cleanId,
                rawValue: raw,
              );
            }
          } else if (typeStr == 'friend' || typeStr == 'friend_invite') {
            final code = _normalizeFriendCode(
              (decoded['code'] ?? decoded['id'] ?? '').toString(),
            );
            if (code.isNotEmpty) {
              return ParsedQrPayload(
                type: QrPayloadType.friendInvite,
                cleanCode: code,
                rawValue: raw,
              );
            }
          }
        }
      } catch (_) {}
    }

    // 2. Явные ссылки приглашения в друзья:
    // syncpai://invite/friend/{code}, syncpai://friend/{code}, https://syncpai.app/f/{code}
    final friendUrlMatch = RegExp(
      r'(?:syncpai:\/\/(?:invite\/)?friend\/|https?:\/\/[^\/\s]+\/(?:f|friend|invite\/friend)\/)([A-Za-z0-9\-_]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (friendUrlMatch != null && friendUrlMatch.group(1) != null) {
      final code = _normalizeFriendCode(friendUrlMatch.group(1)!);
      if (code.isNotEmpty) {
        return ParsedQrPayload(
          type: QrPayloadType.friendInvite,
          cleanCode: code,
          rawValue: raw,
        );
      }
    }

    // 3. Явные ссылки на комнату совместного просмотра:
    // syncpai://room/{id}, https://syncpai.app/room/{id}, ?room={id}
    final roomUrlMatch = RegExp(
      r'(?:syncpai:\/\/room\/|https?:\/\/[^\/\s]+\/room\/|[?&]room=)([A-Za-z0-9\-_]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (roomUrlMatch != null && roomUrlMatch.group(1) != null) {
      final cleanId = RoomCodeParser.extractCleanRoomId(roomUrlMatch.group(1)!);
      if (cleanId.isNotEmpty) {
        return ParsedQrPayload(
          type: QrPayloadType.room,
          cleanCode: cleanId,
          rawValue: raw,
        );
      }
    }

    // 4. Прямые коды без URL:
    // 4a. Чистый 6-значный цифровой код комнаты ("639245") или с дефисом ("639-245") или 4-значный демо ("4821")
    if (RegExp(r'^\d{6}$').hasMatch(trimmed) ||
        RegExp(r'^\d{3}-\d{3}$').hasMatch(trimmed) ||
        RegExp(r'^\d{4}$').hasMatch(trimmed)) {
      final cleanId = RoomCodeParser.extractCleanRoomId(trimmed);
      return ParsedQrPayload(
        type: QrPayloadType.room,
        cleanCode: cleanId,
        rawValue: raw,
      );
    }

    // 4b. Код с префиксом SP-...
    final spMatch = RegExp(
      r'^SP[\-\s_]?([A-Za-z0-9]{4,8})$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (spMatch != null && spMatch.group(1) != null) {
      final body = spMatch.group(1)!.toUpperCase();
      // Если внутри только цифры (например SP-639245 или SP-4821) — это код комнаты
      if (RegExp(r'^\d{4,6}$').hasMatch(body)) {
        return ParsedQrPayload(
          type: QrPayloadType.room,
          cleanCode: body,
          rawValue: raw,
        );
      }
      // Если содержит буквы (например SP-8F3K9A) — это инвайт-код друга
      if (body.length == 6 && RegExp(r'[A-Z]').hasMatch(body)) {
        return ParsedQrPayload(
          type: QrPayloadType.friendInvite,
          cleanCode: 'SP-$body',
          rawValue: raw,
        );
      }
    }

    return ParsedQrPayload(
      type: QrPayloadType.unknown,
      cleanCode: '',
      rawValue: raw,
    );
  }

  static String _normalizeFriendCode(String raw) {
    var clean = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9\-]'), '');
    if (clean.isEmpty) return '';
    if (clean.startsWith('SP-')) return clean;
    if (clean.startsWith('SP') && clean.length == 8) {
      return 'SP-${clean.substring(2)}';
    }
    if (clean.length == 6) {
      return 'SP-$clean';
    }
    return clean;
  }
}

