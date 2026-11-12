import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../app/di/injection.dart';

class FriendsService {
  static const String _storageKey = 'saved_friends_list';

  /// Получить сохраненный список друзей (локально + Supabase fallback)
  static Future<List<Map<String, dynamic>>> getFriends() async {
    final list = <Map<String, dynamic>>[];

    if (getIt.isRegistered<SharedPreferences>()) {
      try {
        final raw = getIt<SharedPreferences>().getString(_storageKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as List<dynamic>;
          for (final item in decoded) {
            if (item is Map) {
              list.add({
                'id': item['id']?.toString() ?? 'fr_${DateTime.now().millisecondsSinceEpoch}',
                'name': (item['name'] ?? item['username'] ?? 'Друг').toString(),
                'avatar': (item['avatar'] ?? item['avatar_url'] ?? 'cat').toString(),
                'status': (item['status'] ?? item['statusText'] ?? item['custom_status'] ?? 'В сети').toString(),
                'statusText': (item['statusText'] ?? item['status'] ?? item['custom_status'] ?? 'В сети').toString(),
                'room': item['room']?.toString() ?? item['roomCode']?.toString(),
                'roomCode': item['roomCode']?.toString() ?? item['room']?.toString(),
                'isOnline': item['isOnline'] == true,
                'canJoin': item['canJoin'] == true || (item['room'] != null || item['roomCode'] != null),
                'streakDays': item['streakDays'] ?? 1,
              });
            }
          }
        }
      } catch (e) {
        debugPrint('FriendsService getFriends error: $e');
      }
    }

    // Если список пуст, подтягиваем пользователей из Supabase
    if (list.isEmpty) {
      try {
        final client = Supabase.instance.client;
        final currentUid = client.auth.currentUser?.id;
        final query = client.from('profiles').select('id, username, avatar_url, custom_status');
        final rows = currentUid != null
            ? await query.neq('id', currentUid).limit(6)
            : await query.limit(6);

        for (final row in rows) {
          final username = (row['username'] ?? '').toString().trim();
          if (username.isNotEmpty) {
            list.add({
              'id': row['id']?.toString() ?? 'sup_${username.hashCode}',
              'name': username,
              'avatar': (row['avatar_url'] ?? 'cat').toString(),
              'status': (row['custom_status'] ?? 'В сети').toString(),
              'statusText': (row['custom_status'] ?? 'В сети').toString(),
              'room': null,
              'roomCode': null,
              'isOnline': true,
              'canJoin': false,
              'streakDays': 1,
            });
          }
        }
        if (list.isNotEmpty) {
          await saveFriends(list);
        }
      } catch (e) {
        debugPrint('FriendsService Supabase fetch fallback error: $e');
      }
    }

    return list;
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

  /// Добавить нового друга
  static Future<bool> addFriend(Map<String, dynamic> newFriend) async {
    final list = await getFriends();
    final nameLower = (newFriend['name'] ?? newFriend['username'] ?? '').toString().trim().toLowerCase();
    if (nameLower.isEmpty) return false;

    final exists = list.any((f) => (f['name'] ?? '').toString().toLowerCase() == nameLower);
    if (exists) return false;

    final normalized = {
      'id': newFriend['id']?.toString() ?? 'fr_${DateTime.now().millisecondsSinceEpoch}',
      'name': (newFriend['name'] ?? newFriend['username'] ?? '').toString().trim(),
      'avatar': (newFriend['avatar'] ?? newFriend['avatar_url'] ?? 'cat').toString(),
      'status': (newFriend['status'] ?? newFriend['statusText'] ?? newFriend['custom_status'] ?? 'В сети').toString(),
      'statusText': (newFriend['statusText'] ?? newFriend['status'] ?? newFriend['custom_status'] ?? 'В сети').toString(),
      'room': newFriend['room']?.toString() ?? newFriend['roomCode']?.toString(),
      'roomCode': newFriend['roomCode']?.toString() ?? newFriend['room']?.toString(),
      'isOnline': newFriend['isOnline'] == true,
      'canJoin': newFriend['canJoin'] == true,
      'streakDays': newFriend['streakDays'] ?? 1,
    };

    list.insert(0, normalized);
    await saveFriends(list);
    return true;
  }

  /// Удалить друга по ID или имени
  static Future<void> removeFriend(String idOrName) async {
    final list = await getFriends();
    final target = idOrName.toLowerCase();
    list.removeWhere((f) =>
        f['id']?.toString().toLowerCase() == target ||
        f['name']?.toString().toLowerCase() == target);
    await saveFriends(list);
  }

  /// Поиск пользователей в Supabase profiles
  static Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final clean = query.trim().replaceAll('@', '');
    if (clean.isEmpty) return [];

    try {
      final client = Supabase.instance.client;
      final currentUid = client.auth.currentUser?.id;

      final response = await client
          .from('profiles')
          .select('id, username, avatar_url, custom_status')
          .ilike('username', '%$clean%')
          .limit(15);

      final results = <Map<String, dynamic>>[];
      for (final row in response) {
        final uid = row['id']?.toString();
        if (uid != null && uid == currentUid) continue;
        final uname = (row['username'] ?? '').toString().trim();
        if (uname.isNotEmpty) {
          results.add({
            'id': uid ?? 'sup_${uname.hashCode}',
            'name': uname,
            'avatar': (row['avatar_url'] ?? 'cat').toString(),
            'status': (row['custom_status'] ?? 'В SyncPai').toString(),
            'isOnline': true,
          });
        }
      }
      return results;
    } catch (e) {
      debugPrint('FriendsService searchUsers error: $e');
      return [];
    }
  }
}

