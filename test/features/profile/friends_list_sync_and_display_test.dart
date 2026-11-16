import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/profile/domain/entities/friend_models.dart';
import 'package:sync_pai/features/profile/services/friends_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FriendsService.friendsNotifier.value = const [];
    final prefs = await SharedPreferences.getInstance();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<SharedPreferences>()) {
      await getIt.unregister<SharedPreferences>();
    }
    getIt.registerSingleton<SharedPreferences>(prefs);
  });

  group('FriendsService — otherUserId resolution & FriendProfile mapping', () {
    test('resolveOtherUserIds picks opposite side regardless of requester/recipient', () {
      const currentUid = 'user-me-111';
      final rows = [
        {'user_id': 'user-me-111', 'friend_id': 'user-alice-222', 'status': 'accepted'},
        {'user_id': 'user-bob-333', 'friend_id': 'user-me-111', 'status': 'accepted'},
        {'user_id': 'user-me-111', 'friend_id': 'user-me-111', 'status': 'accepted'},
      ];

      final resolved = FriendsService.resolveOtherUserIds(rows, currentUid);
      expect(resolved, ['user-alice-222', 'user-bob-333']);
    });

    test('FriendProfile.fromMap maps real username, normalizes tag, never falls back to Друг', () {
      final profile = FriendProfile.fromMap({
        'id': 'u2',
        'username': 'keori',
        'tag': '5727',
        'friend_code': 'SP-3B34E7',
        'avatar_url': 'https://cdn.example/keori.png',
        'supporter_tier': 'vip',
      });

      expect(profile.username, 'keori');
      expect(profile.tag, '#5727');
      expect(profile.fullHandle, 'keori#5727');
      expect(profile.friendCode, 'SP-3B34E7');
      expect(profile.avatarUrl, 'https://cdn.example/keori.png');
      expect(profile.supporterTier, 'vip');

      final emptyName = FriendProfile.fromMap({
        'id': 'u3',
        'username': '   ',
        'tag': '#0421',
      });
      expect(emptyName.username, 'Пользователь');
      expect(emptyName.tag, '#0421');
    });
  });

  group('FriendsService — instant 0ms optimistic add & remove', () {
    test('addFriend & removeFriend update friendsNotifier immediately and persist', () async {
      final added = await FriendsService.addFriend({
        'id': 'friend-uuid-1',
        'username': 'Mikasa',
        'tag': '1042',
        'friend_code': 'SP-1042AA',
        'avatar_url': 'https://cdn.example/mikasa.png',
      });

      expect(added, isTrue);
      expect(FriendsService.friendsNotifier.value.length, 1);
      final first = FriendsService.friendsNotifier.value.first;
      expect(first['username'], 'Mikasa');
      expect(first['tag'], '#1042');
      expect(first['friend_code'], 'SP-1042AA');
      expect(first['avatar_url'], 'https://cdn.example/mikasa.png');

      // Duplicate ID is rejected
      final dup = await FriendsService.addFriend({
        'id': 'friend-uuid-1',
        'username': 'Mikasa',
        'tag': '1042',
      });
      expect(dup, isFalse);
      expect(FriendsService.friendsNotifier.value.length, 1);

      // Different ID with same display name is allowed
      final sameNameDiffId = await FriendsService.addFriend({
        'id': 'friend-uuid-2',
        'username': 'Mikasa',
        'tag': '9999',
      });
      expect(sameNameDiffId, isTrue);
      expect(FriendsService.friendsNotifier.value.length, 2);

      // Instant optimistic remove
      final removed = await FriendsService.removeFriend('friend-uuid-1');
      expect(removed, isTrue);
      expect(FriendsService.friendsNotifier.value.length, 1);
      expect(FriendsService.friendsNotifier.value.first['id'], 'friend-uuid-2');

      // Persisted across reloads
      final reloaded = await FriendsService.getFriends();
      expect(reloaded.length, 1);
      expect(reloaded.first['id'], 'friend-uuid-2');
    });
  });
}

