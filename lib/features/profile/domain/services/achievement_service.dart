import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/di/injection.dart';

class AchievementBadge {
  final String id;
  final String title;
  final String hint;
  final String rarity;
  final int targetCount;
  final String unitLabel;
  final IconData icon;
  final Color color;

  const AchievementBadge({
    required this.id,
    required this.title,
    required this.hint,
    this.rarity = 'Обычный',
    this.targetCount = 1,
    this.unitLabel = '',
    required this.icon,
    required this.color,
  });
}

const List<AchievementBadge> kSyncPaiAchievements = [
  AchievementBadge(
    id: 'first_episode',
    title: 'Первый шаг',
    hint: 'Посмотрите первую серию аниме в SyncPai',
    rarity: 'Обычный',
    targetCount: 1,
    unitLabel: 'серий',
    icon: Icons.play_circle_filled_rounded,
    color: Color(0xFF35D9D5),
  ),
  AchievementBadge(
    id: 'watch_hour',
    title: 'Киноман — 1 час',
    hint: 'Посмотрите суммарно 1 час аниме в плеере',
    rarity: 'Редкий',
    targetCount: 60,
    unitLabel: 'мин',
    icon: Icons.hourglass_full_rounded,
    color: Color(0xFF38BDF8),
  ),
  AchievementBadge(
    id: 'op_skipper',
    title: 'Мастер перемотки',
    hint: 'Пропустите опенинг 5 раз с помощью таймкодов',
    rarity: 'Обычный',
    targetCount: 5,
    unitLabel: 'пропусков',
    icon: Icons.fast_forward_rounded,
    color: Color(0xFFA78BFA),
  ),
  AchievementBadge(
    id: 'night_owl',
    title: 'Ночной дозор',
    hint: 'Посмотрите 3+ серии с 01:00 до 05:00 ночи',
    rarity: 'Редкий',
    targetCount: 3,
    unitLabel: 'серий',
    icon: Icons.nightlight_round,
    color: Color(0xFF7B61FF),
  ),
  AchievementBadge(
    id: 'marathon_runner',
    title: 'Марафонец',
    hint: 'Посмотрите 5+ серий за один день',
    rarity: 'Редкий',
    targetCount: 5,
    unitLabel: 'серий',
    icon: Icons.bolt_rounded,
    color: Color(0xFFFFB74D),
  ),
  AchievementBadge(
    id: 'party_soul',
    title: 'Душа компании',
    hint: 'Участвуйте в 3+ сеансах Watch-Together',
    rarity: 'Редкий',
    targetCount: 3,
    unitLabel: 'сеансов',
    icon: Icons.groups_rounded,
    color: Color(0xFFFF806D),
  ),
  AchievementBadge(
    id: 'critic',
    title: 'Критик сообщества',
    hint: 'Опубликуйте 3+ отзыва на аниме в SyncPai',
    rarity: 'Редкий',
    targetCount: 3,
    unitLabel: 'отзывов',
    icon: Icons.rate_review_rounded,
    color: Color(0xFF68B684),
  ),
  AchievementBadge(
    id: 'collector',
    title: 'Коллекционер',
    hint: 'Добавьте 50+ тайтлов в списки закладок',
    rarity: 'Редкий',
    targetCount: 50,
    unitLabel: 'тайтлов',
    icon: Icons.collections_bookmark_rounded,
    color: Color(0xFF42A5F5),
  ),
  AchievementBadge(
    id: 'bug_hunter',
    title: 'Кодинг-хакер',
    hint: 'Найдите баг и отправьте репорт в поддержку @syncpai_bot',
    rarity: 'Эксклюзив',
    targetCount: 1,
    unitLabel: 'репорт',
    icon: Icons.bug_report_rounded,
    color: Color(0xFF00E676),
  ),
];

/// Сервис бесплатных Steam-достижений за активность в SyncPai.
class AchievementService extends ChangeNotifier {
  static final AchievementService instance = AchievementService._();
  AchievementService._();

  static const String _prefUnlockedKey = 'syncpai_unlocked_badges';
  static const String _prefNightCountKey = 'syncpai_ach_night_count';
  static const String _prefDailyDateKey = 'syncpai_ach_daily_date';
  static const String _prefDailyCountKey = 'syncpai_ach_daily_count';
  static const String _prefPartyCountKey = 'syncpai_ach_party_count';
  static const String _prefReviewsCountKey = 'syncpai_ach_reviews_count';
  static const String _prefWatchSecondsKey = 'syncpai_ach_watch_seconds';
  static const String _prefOpSkipsKey = 'syncpai_ach_op_skips';
  static const String _prefCollectorCountKey = 'syncpai_ach_collector_count';

  final Set<String> _unlockedIds = {};
  final StreamController<AchievementBadge> _unlockController =
      StreamController<AchievementBadge>.broadcast();
  bool _initialized = false;

  Set<String> get unlockedIds => Set.unmodifiable(_unlockedIds);
  Stream<AchievementBadge> get onUnlocked => _unlockController.stream;

  Future<SharedPreferences> _getPrefs() async {
    if (getIt.isRegistered<SharedPreferences>()) {
      return getIt<SharedPreferences>();
    }
    return SharedPreferences.getInstance();
  }

  Future<void> init({List<String>? cloudUnlocked}) async {
    final prefs = await _getPrefs();
    final local = prefs.getStringList(_prefUnlockedKey) ?? const [];
    _unlockedIds.addAll(local);
    if (cloudUnlocked != null && cloudUnlocked.isNotEmpty) {
      _unlockedIds.addAll(cloudUnlocked);
      await prefs.setStringList(_prefUnlockedKey, _unlockedIds.toList());
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _ensureInit() async {
    if (!_initialized) {
      await init();
    }
  }

  Future<void> _unlock(String badgeId) async {
    await _ensureInit();
    if (_unlockedIds.contains(badgeId)) return;

    final badge = kSyncPaiAchievements.where((b) => b.id == badgeId).firstOrNull;
    if (badge == null) return;

    _unlockedIds.add(badgeId);
    notifyListeners();
    _unlockController.add(badge);

    try {
      final prefs = await _getPrefs();
      await prefs.setStringList(_prefUnlockedKey, _unlockedIds.toList());
    } catch (_) {}

    unawaited(_syncToSupabase());
  }

  Future<void> _syncToSupabase() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      await client.from('profiles').update({
        'unlocked_badges': _unlockedIds.toList(),
      }).eq('id', uid);
    } catch (e) {
      debugPrint('[Achievements] Supabase sync skipped: $e');
    }
  }

  Future<int> getCurrentProgress(String badgeId) async {
    await _ensureInit();
    final prefs = await _getPrefs();
    switch (badgeId) {
      case 'first_episode':
      case 'bug_hunter':
        return _unlockedIds.contains(badgeId) ? 1 : 0;
      case 'watch_hour':
        final mins = (prefs.getInt(_prefWatchSecondsKey) ?? 0) ~/ 60;
        return mins.clamp(0, 60);
      case 'op_skipper':
        return (prefs.getInt(_prefOpSkipsKey) ?? 0).clamp(0, 5);
      case 'night_owl':
        return (prefs.getInt(_prefNightCountKey) ?? 0).clamp(0, 3);
      case 'marathon_runner':
        return (prefs.getInt(_prefDailyCountKey) ?? 0).clamp(0, 5);
      case 'party_soul':
        return (prefs.getInt(_prefPartyCountKey) ?? 0).clamp(0, 3);
      case 'critic':
        return (prefs.getInt(_prefReviewsCountKey) ?? 0).clamp(0, 3);
      case 'collector':
        return (prefs.getInt(_prefCollectorCountKey) ?? 0).clamp(0, 50);
      default:
        return 0;
    }
  }

  Future<void> addWatchSeconds(int seconds) async {
    if (seconds <= 0) return;
    await _ensureInit();
    final prefs = await _getPrefs();
    final total = (prefs.getInt(_prefWatchSecondsKey) ?? 0) + seconds;
    await prefs.setInt(_prefWatchSecondsKey, total);
    if (total >= 3600) {
      await _unlock('watch_hour');
    }
  }

  Future<void> recordOpeningSkipped() async {
    await _ensureInit();
    final prefs = await _getPrefs();
    final skips = (prefs.getInt(_prefOpSkipsKey) ?? 0) + 1;
    await prefs.setInt(_prefOpSkipsKey, skips);
    if (skips >= 5) {
      await _unlock('op_skipper');
    }
  }

  Future<void> recordEpisodeWatched({
    DateTime? now,
    bool isWatchTogether = false,
  }) async {
    await _ensureInit();
    await _unlock('first_episode');

    final ts = now ?? DateTime.now();
    final prefs = await _getPrefs();

    if (ts.hour >= 1 && ts.hour < 5) {
      final nightCount = (prefs.getInt(_prefNightCountKey) ?? 0) + 1;
      await prefs.setInt(_prefNightCountKey, nightCount);
      if (nightCount >= 3) {
        await _unlock('night_owl');
      }
    }

    final todayKey = '${ts.year}-${ts.month}-${ts.day}';
    final savedDay = prefs.getString(_prefDailyDateKey);
    final nextDaily = (savedDay == todayKey)
        ? (prefs.getInt(_prefDailyCountKey) ?? 0) + 1
        : 1;
    await prefs.setString(_prefDailyDateKey, todayKey);
    await prefs.setInt(_prefDailyCountKey, nextDaily);
    if (nextDaily >= 5) {
      await _unlock('marathon_runner');
    }

    if (isWatchTogether) {
      await recordWatchTogetherJoined();
    }
  }

  Future<void> recordWatchTogetherJoined() async {
    await _ensureInit();
    final prefs = await _getPrefs();
    final count = (prefs.getInt(_prefPartyCountKey) ?? 0) + 1;
    await prefs.setInt(_prefPartyCountKey, count);
    if (count >= 3) {
      await _unlock('party_soul');
    }
  }

  Future<void> recordReviewPublished() async {
    await _ensureInit();
    final prefs = await _getPrefs();
    final count = (prefs.getInt(_prefReviewsCountKey) ?? 0) + 1;
    await prefs.setInt(_prefReviewsCountKey, count);
    if (count >= 3) {
      await _unlock('critic');
    }
  }

  Future<void> checkCollectorCount(int totalTitles) async {
    await _ensureInit();
    final prefs = await _getPrefs();
    await prefs.setInt(_prefCollectorCountKey, totalTitles);
    if (totalTitles >= 50) {
      await _unlock('collector');
    }
  }
}
