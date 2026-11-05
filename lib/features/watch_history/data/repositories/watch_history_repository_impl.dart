import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/watch_history_repository.dart';

class WatchHistoryRepositoryImpl implements WatchHistoryRepository {
  final SharedPreferences prefs;

  static const String _historyKey = 'syncpai_watch_history';

  WatchHistoryRepositoryImpl(this.prefs);

  @override
  Future<WatchHistoryItem?> getProgress(int titleId) async {
    final list = await getAllHistory();
    try {
      return list.firstWhere((item) => item.titleId == titleId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<WatchHistoryItem>> getAllHistory() async {
    final jsonStr = prefs.getString(_historyKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final decoded = jsonDecode(jsonStr) as List<dynamic>;
      final list = decoded
          .map((e) => WatchHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
      // Сортировка: самые свежие сверху
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveProgress(WatchHistoryItem item) async {
    final list = await getAllHistory();
    final updated = List<WatchHistoryItem>.from(list)
      ..removeWhere((e) => e.titleId == item.titleId)
      ..insert(0, item);

    // Храним последние 100 тайтлов
    if (updated.length > 100) {
      updated.removeLast();
    }

    final encoded = jsonEncode(updated.map((e) => e.toJson()).toList());
    await prefs.setString(_historyKey, encoded);
  }

  @override
  Future<void> removeProgress(int titleId) async {
    final list = await getAllHistory();
    final updated = List<WatchHistoryItem>.from(list)
      ..removeWhere((e) => e.titleId == titleId);

    final encoded = jsonEncode(updated.map((e) => e.toJson()).toList());
    await prefs.setString(_historyKey, encoded);
  }
}

