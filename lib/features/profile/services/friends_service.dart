import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/di/injection.dart';
import '../../auth/presentation/cubit/auth_cubit.dart';
import '../../auth/presentation/cubit/auth_state.dart';
import '../domain/entities/friend_models.dart';

class FriendsService {
  static const String _storageKey = 'saved_friends_list_v2';
  static final ValueNotifier<List<Map<String, dynamic>>> friendsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>(const []);
  static RealtimeChannel? _realtimeChannel;
  static String? _subscribedUid;

  static const String _profileSelectColumns =
      'id, username, tag, friend_code, avatar_url, custom_status, last_seen_at, supporter_tier';

  static SupabaseClient? get _supabaseClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Проверяет, авторизован ли пользователь в постоянном (не гостевом/анонимном) аккаунте
  static bool get isCurrentUserPermanent {
    try {
      if (getIt.isRegistered<AuthCubit>()) {
        final state = getIt<AuthCubit>().state;
        if (state is Authenticated) {
          return !state.profile.isAnonymous;
        }
      }
    } catch (_) {}
    final user = _supabaseClient?.auth.currentUser;
    if (user == null || user.isAnonymous) {
      return false;
    }
    return true;
  }

  /// Получить или сгенерировать персональный код инвайта для текущего пользователя
  static Future<FriendInvite?> getOrCreatePersonalInvite({String? customCode}) async {
    if (!isCurrentUserPermanent) return null;
    final client = _supabaseClient;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) return null;

    try {
      // 1. Проверяем, есть ли уже постоянный инвайт (max_uses is null)
      final existing = await client
          .from('friend_invites')
          .select()
          .eq('inviter_id', currentUid)
          .isFilter('max_uses', null)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null && existing.isNotEmpty) {
        return FriendInvite.fromMap(existing);
      }

      // 2. Генерируем новый 8-значный URL-safe токен
      final code = customCode ?? _generateInviteToken();
      final insertData = {
        'code': code,
        'inviter_id': currentUid,
        'max_uses': null,
        'uses_count': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final created = await client.from('friend_invites').insert(insertData).select().single();
      return FriendInvite.fromMap(created);
    } catch (e) {
      debugPrint('FriendsService getOrCreatePersonalInvite error: $e');
      return null;
    }
  }

  /// Создать одноразовый временный инвайт (на 24 часа)
  static Future<FriendInvite?> createOneTimeInvite() async {
    if (!isCurrentUserPermanent) return null;
    final client = _supabaseClient;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) return null;

    try {
      final code = _generateInviteToken();
      final insertData = {
        'code': code,
        'inviter_id': currentUid,
        'max_uses': 1,
        'uses_count': 0,
        'expires_at': DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final created = await client.from('friend_invites').insert(insertData).select().single();
      return FriendInvite.fromMap(created);
    } catch (e) {
      debugPrint('FriendsService createOneTimeInvite error: $e');
      return null;
    }
  }

  /// Разрешить инвайт-код (получить информацию о пользователе перед подтверждением)
  static Future<Map<String, dynamic>?> resolveInvite(String rawCodeOrUrl) async {
    final cleanCode = extractInviteCode(rawCodeOrUrl);
    if (cleanCode.isEmpty) return null;

    final client = _supabaseClient;
    if (client == null) return null;

    try {
      final invite = await client
          .from('friend_invites')
          .select('code, inviter_id, expires_at, max_uses, uses_count, profiles!friend_invites_inviter_id_fkey(id, username, tag, friend_code, avatar_url, custom_status, last_seen_at)')
          .eq('code', cleanCode)
          .maybeSingle();

      if (invite == null || invite.isEmpty) return null;

      // Проверка срока и лимита
      final expiresAt = DateTime.tryParse(invite['expires_at']?.toString() ?? '');
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        return {'isExpired': true, 'code': cleanCode};
      }

      final maxUses = (invite['max_uses'] as num?)?.toInt();
      final usesCount = (invite['uses_count'] as num?)?.toInt() ?? 0;
      if (maxUses != null && usesCount >= maxUses) {
        return {'isLimitReached': true, 'code': cleanCode};
      }

      final profileMap = invite['profiles'] as Map<String, dynamic>?;
      return {
        'isValid': true,
        'code': cleanCode,
        'inviter': profileMap != null ? FriendProfile.fromMap(profileMap) : null,
      };
    } catch (e) {
      debugPrint('FriendsService resolveInvite error: $e');
      return null;
    }
  }

  /// Принять инвайт в друзья через безопасную Postgres RPC-функцию accept_friend_invite
  static Future<Map<String, dynamic>> acceptInvite(String rawCodeOrUrl) async {
    final cleanCode = extractInviteCode(rawCodeOrUrl);
    if (cleanCode.isEmpty) {
      return {'success': false, 'message': 'Некорректный код приглашения'};
    }

    final client = _supabaseClient;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) {
      return {'success': false, 'message': 'Войдите в аккаунт для добавления друзей'};
    }

    try {
      final res = await client.rpc('accept_friend_invite', params: {
        'invite_code': cleanCode,
      });

      if (res is Map) {
        final success = res['success'] == true;
        if (success && res['friend'] is Map) {
          final friendMap = res['friend'] as Map<String, dynamic>;
          final friend = FriendProfile.fromMap(friendMap);
          await addFriend(friend.toMap());
        }
        return Map<String, dynamic>.from(res);
      }
      return {'success': true, 'message': 'Приглашение принято!'};
    } catch (e) {
      debugPrint('FriendsService acceptInvite error: $e');
      return {'success': false, 'message': 'Ошибка добавления: $e'};
    }
  }

  /// Извлечь чистый код из любого формата:
  /// - 'SP-8F3K9A'
  /// - 'syncpai://invite/friend/SP-8F3K9A'
  /// - 'https://syncpai.app/f/SP-8F3K9A'
  static String extractInviteCode(String input) {
    var trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    // URL: https://syncpai.app/f/{code}
    if (trimmed.contains('/f/')) {
      final parts = trimmed.split('/f/');
      if (parts.length > 1) {
        trimmed = parts.last.split('?').first.split('/').first;
      }
    }
    // Deep Link: syncpai://invite/friend/{code}
    if (trimmed.contains('/friend/')) {
      final parts = trimmed.split('/friend/');
      if (parts.length > 1) {
        trimmed = parts.last.split('?').first.split('/').first;
      }
    }

    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
  }

  /// Определяет UUID собеседников (другой стороны) из строк таблицы friendships.
  static List<String> resolveOtherUserIds(
    Iterable<dynamic> friendshipRows,
    String currentUid,
  ) {
    final friendUids = <String>{};
    for (final row in friendshipRows) {
      if (row is! Map) continue;
      final userId = row['user_id']?.toString().trim() ?? '';
      final friendId = row['friend_id']?.toString().trim() ?? '';
      final otherUserId = (userId == currentUid) ? friendId : userId;
      if (otherUserId.isNotEmpty && otherUserId != currentUid) {
        friendUids.add(otherUserId);
      }
    }
    return friendUids.toList();
  }

  /// Подписаться на изменения таблицы friendships в реальном времени.
  static void subscribeRealtime() {
    if (!isCurrentUserPermanent) return;
    final client = _supabaseClient;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) return;
    if (_realtimeChannel != null && _subscribedUid == currentUid) return;

    unsubscribeRealtime();
    _subscribedUid = currentUid;
    try {
      _realtimeChannel = client
          .channel('friendships_live_$currentUid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'friendships',
            callback: (payload) {
              final newRec = payload.newRecord;
              final oldRec = payload.oldRecord;
              final involvesMe =
                  newRec['user_id'] == currentUid ||
                  newRec['friend_id'] == currentUid ||
                  oldRec['user_id'] == currentUid ||
                  oldRec['friend_id'] == currentUid;
              if (involvesMe) {
                unawaited(getFriends());
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('FriendsService subscribeRealtime error: $e');
    }
  }

  static void unsubscribeRealtime() {
    try {
      if (_realtimeChannel != null) {
        _supabaseClient?.removeChannel(_realtimeChannel!);
      }
    } catch (_) {}
    _realtimeChannel = null;
    _subscribedUid = null;
  }

  /// Получить сохраненный список друзей (локально + Supabase friendships)
  static Future<List<Map<String, dynamic>>> getFriends() async {
    final list = <Map<String, dynamic>>[];

    // 1. Читаем локальный кэш
    if (getIt.isRegistered<SharedPreferences>()) {
      try {
        final raw = getIt<SharedPreferences>().getString(_storageKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as List<dynamic>;
          for (final item in decoded) {
            if (item is Map) {
              list.add(FriendProfile.fromMap(Map<String, dynamic>.from(item)).toMap());
            }
          }
        }
      } catch (e) {
        debugPrint('FriendsService getFriends cache error: $e');
      }
    }

    if (list.isNotEmpty && friendsNotifier.value.isEmpty) {
      friendsNotifier.value = List<Map<String, dynamic>>.from(list);
    }

    // 2. Синхронизируем с Supabase friendships (только для зарегистрированных пользователей, без PostgrestException у гостей)
    if (!isCurrentUserPermanent) {
      return list;
    }
    try {
      final client = _supabaseClient;
      final currentUid = client?.auth.currentUser?.id;

      if (client != null && currentUid != null) {
        final dynamic friendships = await client
            .from('friendships')
            .select('user_id, friend_id, status, created_at')
            .or('user_id.eq.$currentUid,friend_id.eq.$currentUid')
            .eq('status', 'accepted')
            .limit(50);

        if (friendships is Iterable) {
          final otherUserIds = resolveOtherUserIds(friendships, currentUid);
          if (otherUserIds.isEmpty) {
            await saveFriends(const []);
            friendsNotifier.value = const [];
            return const [];
          }

          final friendProfiles = await client
              .from('profiles')
              .select(_profileSelectColumns)
              .inFilter('id', otherUserIds);

          final remoteList = <Map<String, dynamic>>[];
          for (final row in friendProfiles) {
            final profile = FriendProfile.fromMap(Map<String, dynamic>.from(row));
            remoteList.add(profile.toMap());
          }

          await saveFriends(remoteList);
          friendsNotifier.value = List<Map<String, dynamic>>.from(remoteList);
          return remoteList;
        }
      }
    } catch (e) {
      debugPrint('FriendsService getFriends cloud fetch error: $e');
    }

    return list;
  }

  /// Получить входящие и исходящие заявки в друзья (Pending requests)
  static Future<List<FriendRequestItem>> getFriendRequests() async {
    if (!isCurrentUserPermanent) return [];
    final client = _supabaseClient;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) return [];

    try {
      final dynamic raw = await client
          .from('friendships')
          .select('id, user_id, friend_id, status, created_at')
          .or('user_id.eq.$currentUid,friend_id.eq.$currentUid')
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (raw is! Iterable || raw.isEmpty) return [];

      final requests = <FriendRequestItem>[];
      final profileUids = <String>{};

      for (final r in raw) {
        if (r is! Map) continue;
        final sender = r['user_id']?.toString() ?? '';
        final receiver = r['friend_id']?.toString() ?? '';
        final otherId = sender == currentUid ? receiver : sender;
        if (otherId.isNotEmpty) profileUids.add(otherId);
      }

      if (profileUids.isEmpty) return [];

      final profiles = await client
          .from('profiles')
          .select('id, username, tag, friend_code, avatar_url, custom_status, last_seen_at')
          .filter('id', 'in', profileUids.toList());

      final profileMap = <String, FriendProfile>{};
      for (final p in profiles) {
        final prof = FriendProfile.fromMap(p);
        profileMap[prof.id] = prof;
      }

      for (final r in raw) {
        if (r is! Map) continue;
        final id = r['id']?.toString() ?? '';
        final sender = r['user_id']?.toString() ?? '';
        final receiver = r['friend_id']?.toString() ?? '';
        final isIncoming = receiver == currentUid;
        final targetUid = isIncoming ? sender : receiver;
        final prof = profileMap[targetUid] ?? FriendProfile(id: targetUid, username: 'Пользователь');

        requests.add(FriendRequestItem(
          id: id,
          senderId: sender,
          receiverId: receiver,
          status: FriendshipStatus.pending,
          profile: prof,
          isIncoming: isIncoming,
          createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '') ?? DateTime.now(),
        ));
      }

      return requests;
    } catch (e) {
      debugPrint('FriendsService getFriendRequests error: $e');
      return [];
    }
  }

  /// Ответить на заявку в друзья (принять или отклонить)
  static Future<bool> respondToFriendRequest(String requestId, {required bool accept}) async {
    final client = _supabaseClient;
    if (client == null) return false;
    try {
      if (accept) {
        await client.from('friendships').update({'status': 'accepted'}).eq('id', requestId);
      } else {
        await client.from('friendships').delete().eq('id', requestId);
      }
      return true;
    } catch (e) {
      debugPrint('FriendsService respondToFriendRequest error: $e');
      return false;
    }
  }

  /// Сохранить список друзей в SharedPreferences
  static Future<void> saveFriends(List<Map<String, dynamic>> friends) async {
    if (getIt.isRegistered<SharedPreferences>()) {
      try {
        await getIt<SharedPreferences>().setString(_storageKey, jsonEncode(friends));
      } catch (e) {
        debugPrint('FriendsService saveFriends error: $e');
      }
    }
  }

  /// Добавить нового друга (мгновенное оптимистичное обновление + облако)
  static Future<bool> addFriend(Map<String, dynamic> newFriend) async {
    final currentList = friendsNotifier.value.isNotEmpty
        ? List<Map<String, dynamic>>.from(friendsNotifier.value)
        : await getFriends();

    final friendId = newFriend['id']?.toString().trim();
    final currentUid = _supabaseClient?.auth.currentUser?.id;
    if (friendId != null && friendId.isNotEmpty && friendId == currentUid) {
      return false;
    }

    final resolvedProfile = FriendProfile.fromMap(newFriend);
    if (resolvedProfile.username.isEmpty && (friendId == null || friendId.isEmpty)) {
      return false;
    }

    final exists = currentList.any((f) {
      final fId = f['id']?.toString().trim();
      if (friendId != null && friendId.isNotEmpty && fId != null && fId.isNotEmpty) {
        return fId == friendId;
      }
      return (f['username'] ?? f['name'] ?? '').toString().trim().toLowerCase() ==
          resolvedProfile.username.toLowerCase();
    });
    if (exists) return false;

    final normalized = resolvedProfile
        .copyWith(
          id: (friendId != null && friendId.isNotEmpty)
              ? friendId
              : 'fr_${DateTime.now().millisecondsSinceEpoch}',
        )
        .toMap();

    final updatedList = [normalized, ...currentList];
    // 0ms оптимистичное обновление UI и локального кэша
    friendsNotifier.value = updatedList;
    await saveFriends(updatedList);

    // Синхронизируем с Supabase
    try {
      final client = _supabaseClient;
      if (client != null &&
          currentUid != null &&
          friendId != null &&
          friendId.isNotEmpty &&
          friendId != currentUid &&
          !friendId.startsWith('fr_')) {
        await client.from('friendships').upsert({
          'user_id': currentUid,
          'friend_id': friendId,
          'status': 'accepted',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('FriendsService addFriend cloud upsert error: $e');
    }

    return true;
  }

  /// Добавить друга по friend_code, username#tag или UUID с мгновенным обновлением UI
  static Future<Map<String, dynamic>> addFriendByCodeOrTag(String rawInput) async {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return {'success': false, 'message': 'Введите код друга или Ник#тег'};
    }

    final client = _supabaseClient;
    final currentUid = client?.auth.currentUser?.id;
    if (client == null || currentUid == null) {
      return {'success': false, 'message': 'Войдите в аккаунт для добавления друзей'};
    }

    try {
      final target = await _lookupProfileByCodeOrTag(client, trimmed);
      if (target == null) {
        return {'success': false, 'message': 'Пользователь не найден'};
      }
      if (target.id == currentUid) {
        return {'success': false, 'message': 'Нельзя добавить самого себя'};
      }

      final added = await addFriend(target.toMap());
      if (!added) {
        return {
          'success': false,
          'message': '${target.username} уже в списке друзей',
        };
      }
      return {
        'success': true,
        'friend': target.toMap(),
        'message': 'Друг ${target.username} добавлен',
      };
    } catch (e) {
      debugPrint('FriendsService addFriendByCodeOrTag error: $e');
      return {'success': false, 'message': 'Ошибка добавления: $e'};
    }
  }

  static Future<FriendProfile?> _lookupProfileByCodeOrTag(
    SupabaseClient client,
    String rawInput,
  ) async {
    final trimmed = rawInput.trim();
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );

    if (uuidRegex.hasMatch(trimmed)) {
      final row = await client
          .from('profiles')
          .select(_profileSelectColumns)
          .eq('id', trimmed)
          .maybeSingle();
      return row != null ? FriendProfile.fromMap(row) : null;
    }

    if (trimmed.contains('#')) {
      final parts = trimmed.split('#');
      final uName = parts.first.trim();
      final cleanTag = parts.last.trim().replaceFirst(RegExp(r'^#+'), '');
      if (uName.isNotEmpty && cleanTag.isNotEmpty) {
        final rows = await client
            .from('profiles')
            .select(_profileSelectColumns)
            .ilike('username', uName)
            .inFilter('tag', [cleanTag, '#$cleanTag'])
            .limit(1);
        if (rows.isNotEmpty) {
          return FriendProfile.fromMap(rows.first);
        }
      }
    }

    final noHash = trimmed.replaceFirst(RegExp(r'^#+'), '');
    final upperCode = noHash.toUpperCase();
    final normalizedCode = upperCode.startsWith('SP-')
        ? upperCode
        : (upperCode.startsWith('SP') && upperCode.length > 2
            ? 'SP-${upperCode.substring(2)}'
            : upperCode);

    final byCode = await client
        .from('profiles')
        .select(_profileSelectColumns)
        .ilike('friend_code', normalizedCode)
        .limit(1);
    if (byCode.isNotEmpty) {
      return FriendProfile.fromMap(byCode.first);
    }

    return null;
  }

  /// Удалить друга по ID (мгновенный 0ms UI + откат при ошибке Supabase)
  static Future<bool> removeFriend(String idOrName) async {
    final previousList = friendsNotifier.value.isNotEmpty
        ? List<Map<String, dynamic>>.from(friendsNotifier.value)
        : await getFriends();

    final target = idOrName.trim().toLowerCase();
    final nextList = previousList
        .where((f) =>
            f['id']?.toString().toLowerCase() != target &&
            f['name']?.toString().toLowerCase() != target &&
            f['username']?.toString().toLowerCase() != target)
        .toList();

    // 0ms оптимистичное обновление UI и локального кэша
    friendsNotifier.value = nextList;
    await saveFriends(nextList);

    try {
      final client = _supabaseClient;
      final currentUid = client?.auth.currentUser?.id;
      if (client != null && currentUid != null && !idOrName.startsWith('fr_')) {
        await client
            .from('friendships')
            .delete()
            .or('and(user_id.eq.$currentUid,friend_id.eq.$idOrName),and(user_id.eq.$idOrName,friend_id.eq.$currentUid)');
      }
      return true;
    } catch (e) {
      debugPrint('FriendsService removeFriend rollback on error: $e');
      friendsNotifier.value = previousList;
      await saveFriends(previousList);
      return false;
    }
  }

  /// Мгновенный поиск по friend_code, username#tag, UUID или префиксу username
  static Future<List<FriendProfile>> searchUsers(String query) async {
    final raw = query.trim();
    if (raw.isEmpty) return [];

    try {
      final client = _supabaseClient;
      final currentUid = client?.auth.currentUser?.id;
      if (client == null) return [];

      final q = client.from('profiles').select(_profileSelectColumns);

      // 1. Точный UUID
      final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      if (uuidRegex.hasMatch(raw)) {
        final rows = await q.eq('id', raw).limit(5);
        return rows.map((r) => FriendProfile.fromMap(r)).where((p) => p.id != currentUid).toList();
      }

      // 2. Поиск по точному Friend Code (SP-XXXXXX, без учёта регистра)
      final noHash = raw.replaceFirst(RegExp(r'^#+'), '');
      final upper = noHash.toUpperCase();
      if (upper.startsWith('SP-') || (upper.startsWith('SP') && upper.length >= 6)) {
        final code = upper.startsWith('SP-') ? upper : 'SP-${upper.substring(2)}';
        final rows = await q.ilike('friend_code', code).limit(5);
        return rows.map((r) => FriendProfile.fromMap(r)).where((p) => p.id != currentUid).toList();
      }

      // 3. Поиск по Username#Tag (например, "keori#5727" — поддержка tag с # и без #)
      if (raw.contains('#')) {
        final parts = raw.split('#');
        final uName = parts.first.trim();
        final cleanTag = parts.last.trim().replaceFirst(RegExp(r'^#+'), '');
        if (uName.isNotEmpty && cleanTag.isNotEmpty) {
          final rows = await q
              .ilike('username', uName)
              .inFilter('tag', [cleanTag, '#$cleanTag'])
              .limit(5);
          return rows.map((r) => FriendProfile.fromMap(r)).where((p) => p.id != currentUid).toList();
        }
      }

      // 4. Общий поиск по префиксу username
      final clean = noHash.replaceAll('@', '');
      final rows = await q.ilike('username', '%$clean%').limit(15);
      return rows.map((r) => FriendProfile.fromMap(r)).where((p) => p.id != currentUid).toList();
    } catch (e) {
      debugPrint('FriendsService searchUsers error: $e');
      return [];
    }
  }

  static String _generateInviteToken() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final rand = Random.secure();
    return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
