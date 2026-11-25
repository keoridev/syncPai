import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MangaHistoryEntry extends Equatable {
  final String mangaId;
  final String title;
  final String coverUrl;
  final String formatLabel;
  final String chapterId;
  final String chapterLabel;
  /// 1-based current page number.
  final int pageIndex;
  final int totalPages;
  final DateTime updatedAt;

  const MangaHistoryEntry({
    required this.mangaId,
    required this.title,
    required this.coverUrl,
    required this.formatLabel,
    required this.chapterId,
    required this.chapterLabel,
    required this.pageIndex,
    required this.totalPages,
    required this.updatedAt,
  });

  MangaHistoryEntry copyWith({
    String? title,
    String? coverUrl,
    String? formatLabel,
    String? chapterId,
    String? chapterLabel,
    int? pageIndex,
    int? totalPages,
    DateTime? updatedAt,
  }) {
    return MangaHistoryEntry(
      mangaId: mangaId,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      formatLabel: formatLabel ?? this.formatLabel,
      chapterId: chapterId ?? this.chapterId,
      chapterLabel: chapterLabel ?? this.chapterLabel,
      pageIndex: pageIndex ?? this.pageIndex,
      totalPages: totalPages ?? this.totalPages,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'mangaId': mangaId,
        'title': title,
        'coverUrl': coverUrl,
        'formatLabel': formatLabel,
        'chapterId': chapterId,
        'chapterLabel': chapterLabel,
        'pageIndex': pageIndex,
        'totalPages': totalPages,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory MangaHistoryEntry.fromJson(Map<String, dynamic> json) {
    return MangaHistoryEntry(
      mangaId: (json['mangaId'] ?? json['manga_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? json['cover_url'] ?? '').toString(),
      formatLabel: (json['formatLabel'] ?? json['format_label'] ?? 'Манга').toString(),
      chapterId: (json['chapterId'] ?? json['chapter_id'] ?? '').toString(),
      chapterLabel: (json['chapterLabel'] ?? json['chapter_label'] ?? 'Глава 1').toString(),
      pageIndex: ((json['pageIndex'] ?? json['page_index']) as num?)?.toInt() ?? 1,
      totalPages: ((json['totalPages'] ?? json['total_pages']) as num?)?.toInt() ?? 1,
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        mangaId,
        title,
        coverUrl,
        formatLabel,
        chapterId,
        chapterLabel,
        pageIndex,
        totalPages,
        updatedAt,
      ];
}

class MangaReadHistoryState extends Equatable {
  final List<MangaHistoryEntry> entries;
  final bool isLoading;

  const MangaReadHistoryState({
    this.entries = const [],
    this.isLoading = false,
  });

  MangaHistoryEntry? getEntryFor(String mangaId) {
    for (final e in entries) {
      if (e.mangaId == mangaId) return e;
    }
    return null;
  }

  MangaReadHistoryState copyWith({
    List<MangaHistoryEntry>? entries,
    bool? isLoading,
  }) {
    return MangaReadHistoryState(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [entries, isLoading];
}

/// История чтения манги и манхвы с точностью до страницы (`SharedPreferences` + Supabase).
class MangaReadHistoryCubit extends Cubit<MangaReadHistoryState> {
  static const String _prefsKey = 'syncpai_manga_read_history_v1';
  final SharedPreferences? _prefs;

  MangaReadHistoryCubit([this._prefs]) : super(const MangaReadHistoryState()) {
    load();
  }

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    var localEntries = <MangaHistoryEntry>[];
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          localEntries = decoded
              .whereType<Map>()
              .map((m) => MangaHistoryEntry.fromJson(Map<String, dynamic>.from(m)))
              .where((e) => e.mangaId.isNotEmpty)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        }
      }
    } catch (_) {}

    if (isClosed) return;
    if (localEntries.isNotEmpty || state.entries.isEmpty) {
      emit(state.copyWith(entries: localEntries, isLoading: false));
    } else {
      emit(state.copyWith(isLoading: false));
    }

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return;
      final rows = await client
          .from('user_manga_history')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false)
          .limit(50);
      if (isClosed) return;
      final remote = (rows as List)
          .whereType<Map>()
          .map((r) => MangaHistoryEntry.fromJson(Map<String, dynamic>.from(r)))
          .where((e) => e.mangaId.isNotEmpty)
          .toList();
      if (remote.isEmpty) return;

      final mergedById = <String, MangaHistoryEntry>{
        for (final e in localEntries) e.mangaId: e,
      };
      for (final r in remote) {
        final existing = mergedById[r.mangaId];
        if (existing == null || r.updatedAt.isAfter(existing.updatedAt)) {
          mergedById[r.mangaId] = r;
        }
      }
      final merged = mergedById.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      emit(state.copyWith(entries: merged));
      final prefs = await _getPrefs();
      await prefs.setString(
        _prefsKey,
        jsonEncode(merged.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> recordProgress(MangaHistoryEntry entry) async {
    if (entry.mangaId.trim().isEmpty) return;
    final list = List<MangaHistoryEntry>.from(state.entries)
      ..removeWhere((e) => e.mangaId == entry.mangaId);
    list.insert(0, entry);
    if (list.length > 100) {
      list.removeRange(100, list.length);
    }
    emit(state.copyWith(entries: list));

    try {
      final prefs = await _getPrefs();
      await prefs.setString(
        _prefsKey,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return;
      await client.from('user_manga_history').upsert(
        {
          'user_id': userId,
          'manga_id': entry.mangaId,
          'title': entry.title,
          'cover_url': entry.coverUrl,
          'format_label': entry.formatLabel,
          'chapter_id': entry.chapterId,
          'chapter_label': entry.chapterLabel,
          'page_index': entry.pageIndex,
          'total_pages': entry.totalPages,
          'updated_at': entry.updatedAt.toUtc().toIso8601String(),
        },
        onConflict: 'user_id,manga_id',
      );
    } catch (_) {}
  }
}

