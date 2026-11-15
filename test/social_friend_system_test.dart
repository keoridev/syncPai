import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/services/deep_link_service.dart';
import 'package:sync_pai/features/profile/domain/entities/friend_models.dart';
import 'package:sync_pai/features/profile/services/friends_service.dart';

void main() {
  group('Social Friend System - Invite Code & Deep Link Extraction', () {
    test('extractInviteCode parses universal link https://syncpai.app/f/SP-8F3K9A', () {
      const url = 'https://syncpai.app/f/SP-8F3K9A';
      final code = FriendsService.extractInviteCode(url);
      expect(code, 'SP-8F3K9A');
    });

    test('extractInviteCode parses custom scheme syncpai://invite/friend/abc123xyz', () {
      const url = 'syncpai://invite/friend/abc123xyz';
      final code = FriendsService.extractInviteCode(url);
      expect(code, 'abc123xyz');
    });

    test('extractInviteCode extracts raw code surrounded by text', () {
      const rawText = 'Привет! Добавляйся в SyncPai https://syncpai.app/f/SP-XYZ789';
      final code = FriendsService.extractInviteCode(rawText);
      expect(code, 'SP-XYZ789');
    });

    test('detectInviteInText detects direct friend code format', () {
      const text = 'SP-48A9CD';
      final detected = DeepLinkService.detectInviteInText(text);
      expect(detected, 'SP-48A9CD');
    });

    test('FriendProfile models parse properly', () {
      final map = {
        'id': 'user-123',
        'username': 'Keori',
        'tag': '#0421',
        'friend_code': 'SP-0421AA',
        'avatar_url': 'https://example.com/avatar.jpg',
        'custom_status': 'Смотрю Frieren',
        'last_seen_at': DateTime.now().toIso8601String(),
        'roomCode': 'SP-139173',
      };

      final profile = FriendProfile.fromMap(map);
      expect(profile.id, 'user-123');
      expect(profile.username, 'Keori');
      expect(profile.tag, '#0421');
      expect(profile.fullHandle, 'Keori#0421');
      expect(profile.friendCode, 'SP-0421AA');
      expect(profile.isOnline, true);
      expect(profile.currentRoomCode, 'SP-139173');
    });

    test('FriendInvite checks validity and expiration', () {
      final inviteValid = FriendInvite(
        code: 'SP-ABC1234',
        inviterId: 'user-1',
        maxUses: 5,
        usesCount: 2,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        createdAt: DateTime.now(),
      );
      expect(inviteValid.isValid, true);

      final inviteExpired = FriendInvite(
        code: 'SP-ABC1234',
        inviterId: 'user-1',
        maxUses: 5,
        usesCount: 2,
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        createdAt: DateTime.now(),
      );
      expect(inviteExpired.isExpired, true);
      expect(inviteExpired.isValid, false);

      final inviteLimitReached = FriendInvite(
        code: 'SP-ABC1234',
        inviterId: 'user-1',
        maxUses: 3,
        usesCount: 3,
        createdAt: DateTime.now(),
      );
      expect(inviteLimitReached.isLimitReached, true);
      expect(inviteLimitReached.isValid, false);
    });
  });
}

