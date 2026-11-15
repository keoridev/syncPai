import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import '../../features/profile/services/friends_service.dart';

typedef InviteDetectedCallback = void Function(String inviteCode);

/// Глобальный сервис обработки входящих глубоких ссылок и инвайтов:
/// - `syncpai://invite/friend/{code}`
/// - `https://syncpai.app/f/{code}`
/// - `syncpai://room/{code}`
/// - `https://syncpai.app/room/{code}`
class DeepLinkService {
  static final DeepLinkService instance = DeepLinkService._();
  DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  InviteDetectedCallback? onFriendInviteDetected;
  void Function(String roomCode)? onRoomInviteDetected;

  String? _pendingInviteCode;
  String? get pendingInviteCode => _pendingInviteCode;

  void clearPendingInvite() => _pendingInviteCode = null;

  Future<void> init() async {
    // 1. Обработка cold start (запуск приложения по клику на ссылку)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }
    } catch (e) {
      debugPrint('DeepLinkService getInitialLink error: $e');
    }

    // 2. Обработка ссылки во время работы приложения (warm/hot state)
    _linkSubscription?.cancel();
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingUri,
      onError: (err) {
        debugPrint('DeepLinkService stream error: $err');
      },
    );
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  void _handleIncomingUri(Uri uri) {
    debugPrint('DeepLinkService received uri: $uri');
    final uriStr = uri.toString();

    // 1. Дружеский инвайт: /f/{code} или /invite/friend/{code}
    if (uriStr.contains('/f/') || uriStr.contains('/invite/friend/')) {
      final code = FriendsService.extractInviteCode(uriStr);
      if (code.isNotEmpty) {
        _pendingInviteCode = code;
        onFriendInviteDetected?.call(code);
      }
      return;
    }

    // 2. Комната совместного просмотра: /room/{code}
    if (uriStr.contains('/room/')) {
      final parts = uriStr.split('/room/');
      if (parts.length > 1) {
        final code = parts.last.split('?').first.split('/').first;
        if (code.isNotEmpty) {
          onRoomInviteDetected?.call(code);
        }
      }
    }
  }

  /// Проверить строку (например, из буфера обмена) на наличие кода инвайта
  static String? detectInviteInText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.contains('syncpai.app/f/') || trimmed.contains('syncpai://invite/friend/')) {
      final code = FriendsService.extractInviteCode(trimmed);
      return code.isNotEmpty ? code : null;
    }

    // Если скопирован просто Friend Code (например, SP-8F3K9A)
    if (RegExp(r'^SP-[A-Z0-9]{5,8}$', caseSensitive: false).hasMatch(trimmed)) {
      return trimmed.toUpperCase();
    }

    return null;
  }
}
