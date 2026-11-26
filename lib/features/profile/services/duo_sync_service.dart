import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../anime_lists/domain/entities/user_anime_entry.dart';
import 'friends_service.dart';

class DuoLinkRecord {
  final String id;
  final String userA;
  final String? userB;
  final String inviteCode;
  final String status; // 'pending' | 'active' | 'dissolved'
  final String relationLabel;
  final String diptychThemeId;
  final String? duoBannerUrl;
  final String? customLeftArtUrl;
  final String? customRightArtUrl;
  final String? pairedAvatarPreset;
  final String? sharedMilestoneTitle;
  final DateTime pairedAt;

  const DuoLinkRecord({
    required this.id,
    required this.userA,
    this.userB,
    required this.inviteCode,
    required this.status,
    required this.relationLabel,
    required this.diptychThemeId,
    this.duoBannerUrl,
    this.customLeftArtUrl,
    this.customRightArtUrl,
    this.pairedAvatarPreset,
    this.sharedMilestoneTitle,
    required this.pairedAt,
  });

  bool get isActive => status == 'active' && userB != null && userB!.isNotEmpty;

  String? get resolvedBannerUrl {
    final direct = duoBannerUrl?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final left = customLeftArtUrl?.trim();
    if (left != null && left.isNotEmpty) return left;
    return null;
  }

  String? partnerIdFor(String myUserId) {
    if (userA == myUserId) return userB;
    if (userB == myUserId) return userA;
    return null;
  }

  bool isLeftSideFor(String myUserId) => userA == myUserId;

  int get daysTogether =>
      math.max(1, DateTime.now().difference(pairedAt).inDays + 1);

  DuoLinkRecord copyWith({
    String? userB,
    String? status,
    String? relationLabel,
    String? diptychThemeId,
    String? duoBannerUrl,
    String? customLeftArtUrl,
    String? customRightArtUrl,
    String? pairedAvatarPreset,
    String? sharedMilestoneTitle,
    DateTime? pairedAt,
  }) {
    return DuoLinkRecord(
      id: id,
      userA: userA,
      userB: userB ?? this.userB,
      inviteCode: inviteCode,
      status: status ?? this.status,
      relationLabel: relationLabel ?? this.relationLabel,
      diptychThemeId: diptychThemeId ?? this.diptychThemeId,
      duoBannerUrl: duoBannerUrl ?? this.duoBannerUrl,
      customLeftArtUrl: customLeftArtUrl ?? this.customLeftArtUrl,
      customRightArtUrl: customRightArtUrl ?? this.customRightArtUrl,
      pairedAvatarPreset: pairedAvatarPreset ?? this.pairedAvatarPreset,
      sharedMilestoneTitle: sharedMilestoneTitle ?? this.sharedMilestoneTitle,
      pairedAt: pairedAt ?? this.pairedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_a': userA,
        'user_b': userB,
        'invite_code': inviteCode,
        'status': status,
        'relation_label': relationLabel,
        'diptych_theme_id': diptychThemeId,
        'duo_banner_url': duoBannerUrl,
        'custom_left_art_url': customLeftArtUrl,
        'custom_right_art_url': customRightArtUrl,
        'paired_avatar_preset': pairedAvatarPreset,
        'shared_milestone_title': sharedMilestoneTitle,
        'paired_at': pairedAt.toUtc().toIso8601String(),
      };

  factory DuoLinkRecord.fromJson(Map<String, dynamic> json) {
    return DuoLinkRecord(
      id: (json['id'] ?? '').toString(),
      userA: (json['user_a'] ?? '').toString(),
      userB: json['user_b']?.toString(),
      inviteCode: (json['invite_code'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      relationLabel: (json['relation_label'] ?? 'Напарники по аниме').toString(),
      diptychThemeId: (json['diptych_theme_id'] ?? 'sunset_bridge').toString(),
      duoBannerUrl: json['duo_banner_url']?.toString(),
      customLeftArtUrl: json['custom_left_art_url']?.toString(),
      customRightArtUrl: json['custom_right_art_url']?.toString(),
      pairedAvatarPreset: json['paired_avatar_preset']?.toString(),
      sharedMilestoneTitle: json['shared_milestone_title']?.toString(),
      pairedAt:
          DateTime.tryParse((json['paired_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class DuoSharedTitleItem {
  final int titleId;
  final String titleName;
  final String posterUrl;
  final String statusLabel;

  const DuoSharedTitleItem({
    required this.titleId,
    required this.titleName,
    required this.posterUrl,
    required this.statusLabel,
  });
}

class DuoAnalyticsSummary {
  final int compatibilityPercent;
  final int sharedTitlesCount;
  final double sharedHours;
  final List<DuoSharedTitleItem> sharedTitles;

  const DuoAnalyticsSummary({
    required this.compatibilityPercent,
    required this.sharedTitlesCount,
    required this.sharedHours,
    required this.sharedTitles,
  });
}

/// Сервис управления «Парным профилем (Duo)» — Supabase `duo_links` + локальный кэш.
class DuoSyncService {
  DuoSyncService._();
  static final DuoSyncService instance = DuoSyncService._();

  static const String _localCacheKey = 'syncpai_active_duo_link_v1';
  static bool _schemaUnavailable = false;

  static const List<String> relationPresets = [
    'Напарники по аниме',
    'Соулмейты',
    'Лучшие друзья',
    'Бро по тайтлам',
    'Клан / Дуо',
  ];

  static String generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = math.Random.secure();
    final suffix = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'PAI-$suffix';
  }

  Future<DuoLinkRecord?> getCurrentDuoLink({String? userId}) async {
    if (_schemaUnavailable) return _readLocalCache();
    final client = Supabase.instance.client;
    final uid = userId ?? client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return _readLocalCache();

    try {
      final rows = await client
          .from('duo_links')
          .select()
          .or('user_a.eq.$uid,user_b.eq.$uid')
          .neq('status', 'dissolved')
          .order('paired_at', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        final record = DuoLinkRecord.fromJson(Map<String, dynamic>.from(rows.first));
        await _writeLocalCache(record);
        return record;
      }
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01') {
        _schemaUnavailable = true;
      } else if (kDebugMode) {
        debugPrint('[DuoSyncService] getCurrentDuoLink error: $e');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DuoSyncService] getCurrentDuoLink error: $e');
      }
    }
    return _readLocalCache();
  }

  Future<DuoLinkRecord> createOrGetPendingInvite({
    String relationLabel = 'Напарники по аниме',
    String diptychThemeId = 'sunset_bridge',
  }) async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id ?? 'local_user';
    final code = generateInviteCode();

    final localFallback = DuoLinkRecord(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      userA: uid,
      inviteCode: code,
      status: 'pending',
      relationLabel: relationLabel,
      diptychThemeId: diptychThemeId,
      pairedAt: DateTime.now(),
    );

    try {
      final existing = await getCurrentDuoLink(userId: uid);
      if (existing != null && existing.status == 'pending' && existing.userA == uid) {
        return existing;
      }
      final inserted = await client
          .from('duo_links')
          .insert({
            'user_a': uid,
            'invite_code': code,
            'status': 'pending',
            'relation_label': relationLabel,
            'diptych_theme_id': diptychThemeId,
          })
          .select()
          .single();
      final record = DuoLinkRecord.fromJson(Map<String, dynamic>.from(inserted));
      await _writeLocalCache(record);
      return record;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DuoSyncService] createOrGetPendingInvite fallback: $e');
      }
      await _writeLocalCache(localFallback);
      return localFallback;
    }
  }

  Future<DuoLinkRecord?> acceptInviteCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return null;

    try {
      final row = await client
          .from('duo_links')
          .select()
          .eq('invite_code', code)
          .eq('status', 'pending')
          .maybeSingle();
      if (row == null) return null;
      final existing = DuoLinkRecord.fromJson(Map<String, dynamic>.from(row));
      if (existing.userA == uid) return null;

      final updated = await client
          .from('duo_links')
          .update({
            'user_b': uid,
            'status': 'active',
            'paired_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', existing.id)
          .select()
          .single();
      final record = DuoLinkRecord.fromJson(Map<String, dynamic>.from(updated));
      await _writeLocalCache(record);
      return record;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[DuoSyncService] acceptInviteCode error: $e');
      }
      return null;
    }
  }

  Future<DuoLinkRecord?> updateDuoSettings(
    DuoLinkRecord current, {
    String? relationLabel,
    String? diptychThemeId,
    String? duoBannerUrl,
    String? customLeftArtUrl,
    String? customRightArtUrl,
  }) async {
    final next = current.copyWith(
      relationLabel: relationLabel,
      diptychThemeId: diptychThemeId,
      duoBannerUrl: duoBannerUrl,
      customLeftArtUrl: customLeftArtUrl ?? duoBannerUrl,
      customRightArtUrl: customRightArtUrl,
    );
    await _writeLocalCache(next);

    try {
      final client = Supabase.instance.client;
      try {
        await client.from('duo_links').update({
          'relation_label': next.relationLabel,
          'diptych_theme_id': next.diptychThemeId,
          'duo_banner_url': next.duoBannerUrl,
          'custom_left_art_url': next.customLeftArtUrl,
          'custom_right_art_url': next.customRightArtUrl,
        }).eq('id', next.id);
      } catch (_) {
        // Fallback if duo_banner_url column is not yet migrated in remote DB
        await client.from('duo_links').update({
          'relation_label': next.relationLabel,
          'diptych_theme_id': next.diptychThemeId,
          'custom_left_art_url': next.customLeftArtUrl,
          'custom_right_art_url': next.customRightArtUrl,
        }).eq('id', next.id);
      }
    } catch (_) {}
    return next;
  }

  Future<void> dissolveDuoLink(DuoLinkRecord current) async {
    await _clearLocalCache();
    try {
      final client = Supabase.instance.client;
      await client
          .from('duo_links')
          .update({'status': 'dissolved'})
          .eq('id', current.id);
    } catch (_) {}
  }

  Future<DuoAnalyticsSummary> computeSharedAnalytics({
    required String partnerId,
    required List<UserAnimeEntry> myEntries,
  }) async {
    final partnerStats = await FriendsService.fetchSharedWatchStats(partnerId);
    List<UserAnimeEntry> partnerEntries = const [];
    try {
      final rows = await Supabase.instance.client
          .from('user_anime_lists')
          .select()
          .eq('user_id', partnerId)
          .limit(200);
      partnerEntries = rows
          .map((e) => UserAnimeEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {}

    final myById = {for (final e in myEntries) e.animeId: e};
    final shared = <DuoSharedTitleItem>[];
    for (final p in partnerEntries) {
      if (myById.containsKey(p.animeId)) {
        shared.add(
          DuoSharedTitleItem(
            titleId: p.animeId,
            titleName: p.titleRu,
            posterUrl: p.posterUrl ?? '',
            statusLabel: p.status.labelRu,
          ),
        );
      }
    }

    final baseCount = math.max(1, math.min(myEntries.length, partnerEntries.length));
    final compat = partnerEntries.isEmpty || myEntries.isEmpty
        ? 78
        : (55 + ((shared.length / baseCount) * 45)).round().clamp(55, 99);

    return DuoAnalyticsSummary(
      compatibilityPercent: compat,
      sharedTitlesCount: shared.length,
      sharedHours: partnerStats.sharedHours,
      sharedTitles: shared,
    );
  }

  Future<DuoLinkRecord?> _readLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return DuoLinkRecord.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeLocalCache(DuoLinkRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localCacheKey, jsonEncode(record.toJson()));
    } catch (_) {}
  }

  Future<void> _clearLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localCacheKey);
    } catch (_) {}
  }
}
