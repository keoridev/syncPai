import 'package:flutter/material.dart';
import '../presentation/widgets/friend_invite_dialog.dart';
import 'friends_service.dart';

/// Хранилище отложенных социальных действий (инвайт-код из QR / Deep Link или заявка в друзья)
/// для гостевых пользователей на время прохождения авторизации через Pai-chan Auth Gate.
class PendingInviteStorage {
  PendingInviteStorage._();

  static String? _pendingInviteCode;
  static Map<String, dynamic>? _pendingFriendUser;

  /// Текущий сохраненный код приглашения (если есть)
  static String? get pendingInviteCode => _pendingInviteCode;

  /// Текущий сохраненный профиль друга для добавления (если есть)
  static Map<String, dynamic>? get pendingFriendUser => _pendingFriendUser;

  /// Есть ли ожидающее действие после входа
  static bool get hasPendingAction =>
      (_pendingInviteCode != null && _pendingInviteCode!.isNotEmpty) ||
      _pendingFriendUser != null;

  /// Сохранить код приглашения из QR-кода или Deep Link перед показом Pai-chan Auth Gate
  static void savePendingInvite(String inviteCode) {
    final clean = FriendsService.extractInviteCode(inviteCode);
    if (clean.isNotEmpty) {
      _pendingInviteCode = clean;
    }
  }

  /// Извлечь и очистить отложенный инвайт-код
  static String? consumePendingInvite() {
    final code = _pendingInviteCode;
    _pendingInviteCode = null;
    return code;
  }

  /// Сохранить пользователя, которого гость хотел добавить в друзья (из комнаты, поиска или профиля)
  static void savePendingFriendUser(Map<String, dynamic> user) {
    _pendingFriendUser = Map<String, dynamic>.from(user);
  }

  /// Извлечь и очистить отложенного пользователя
  static Map<String, dynamic>? consumePendingFriendUser() {
    final user = _pendingFriendUser;
    _pendingFriendUser = null;
    return user;
  }

  /// Сбросить все отложенные инвайты
  static void clear() {
    _pendingInviteCode = null;
    _pendingFriendUser = null;
  }

  /// Автоматически выполнить отложенное добавление друга или открыть диалог подтверждения инвайта
  /// сразу после успешного входа / регистрации.
  static Future<void> resolvePendingActionsAfterAuth(
    BuildContext context, {
    Color? accentColor,
    VoidCallback? onFriendsChanged,
  }) async {
    final code = consumePendingInvite();
    if (code != null && code.isNotEmpty) {
      if (!context.mounted) return;
      await FriendInviteConfirmationDialog.show(
        context,
        inviteCode: code,
        accentColor: accentColor,
        onAccepted: onFriendsChanged,
      );
      return;
    }

    final friendUser = consumePendingFriendUser();
    if (friendUser != null) {
      final added = await FriendsService.addFriend(friendUser);
      onFriendsChanged?.call();
      if (!context.mounted) return;
      final name = friendUser['name'] ?? friendUser['username'] ?? 'Друг';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added
                ? '✨ «$name» добавлен в список друзей!'
                : '«$name» уже в вашем списке друзей',
          ),
          backgroundColor: added
              ? const Color(0xFF00E676).withValues(alpha: 0.9)
              : Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

