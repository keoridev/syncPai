import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum MangaListStatus {
  reading('Читаю'),
  planned('В планах'),
  completed('Прочитано'),
  dropped('Брошено');

  final String labelRu;
  const MangaListStatus(this.labelRu);

  static MangaListStatus fromKey(String raw) {
    for (final s in MangaListStatus.values) {
      if (s.name == raw) return s;
    }
    return MangaListStatus.reading;
  }
}

class UserMangaEntry extends Equatable {
  final String mangaId;
  final String mangaTitle;
  final String coverUrl;
  final MangaListStatus status;
  final String lastReadChapter;
  final int lastReadPage;
  final int? chaptersCount;
  final DateTime updatedAt;

  const UserMangaEntry({
    required this.mangaId,
    required this.mangaTitle,
    required this.coverUrl,
    required this.status,
    required this.lastReadChapter,
    required this.lastReadPage,
    this.chaptersCount,
    required this.updatedAt,
  });

  UserMangaEntry copyWith({
    MangaListStatus? status,
    String? lastReadChapter,
    int? lastReadPage,
    int? chaptersCount,
    DateTime? updatedAt,
  }) {
    return UserMangaEntry(
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      coverUrl: coverUrl,
      status: status ?? this.status,
      lastReadChapter: lastReadChapter ?? this.lastReadChapter,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      chaptersCount: chaptersCount ?? this.chaptersCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'mangaId': mangaId,
        'mangaTitle': mangaTitle,
        'coverUrl': coverUrl,
        'status': status.name,
        'lastReadChapter': lastReadChapter,
        'lastReadPage': lastReadPage,
        'chaptersCount': chaptersCount,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory UserMangaEntry.fromJson(Map<String, dynamic> json) {
    return UserMangaEntry(
      mangaId: (json['mangaId'] ?? '').toString(),
      mangaTitle: (json['mangaTitle'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      status: MangaListStatus.fromKey((json['status'] ?? 'reading').toString()),
      lastReadChapter: (json['lastReadChapter'] ?? '1').toString(),
      lastReadPage: (json['lastReadPage'] as num?)?.toInt() ?? 0,
      chaptersCount: (json['chaptersCount'] as num?)?.toInt(),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        mangaId,
        mangaTitle,
        coverUrl,
        status,
        lastReadChapter,
        lastReadPage,
        chaptersCount,
        updatedAt,
      ];
}

class UserMangaListState extends Equatable {
  final List<UserMangaEntry> entries;
  final MangaListStatus selectedTab;
  final bool isLoading;

  const UserMangaListState({
    this.entries = const [],
    this.selectedTab = MangaListStatus.reading,
    this.isLoading = false,
  });

  List<UserMangaEntry> entriesFor(MangaListStatus status) =>
      entries.where((e) => e.status == status).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  UserMangaEntry? getEntryFor(String mangaId) {
    for (final e in entries) {
      if (e.mangaId == mangaId) return e;
    }
    return null;
  }

  UserMangaListState copyWith({
    List<UserMangaEntry>? entries,
    MangaListStatus? selectedTab,
    bool? isLoading,
  }) {
    return UserMangaListState(
      entries: entries ?? this.entries,
      selectedTab: selectedTab ?? this.selectedTab,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [entries, selectedTab, isLoading];
}

/// Единый Cubit для списков манги и манхвы с авто-трекингом прогресса чтения.
class UserMangaListCubit extends Cubit<UserMangaListState> {
  static const String _prefsKey = 'syncpai_user_manga_lists_v1';
  final SharedPreferences? _prefs;
  final Set<String> _optedOutMangaIds = {};

  UserMangaListCubit([this._prefs]) : super(const UserMangaListState()) {
    load();
  }

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<void> load() async {
    emit(state.copyWith(isLoading: true));
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final parsed = decoded
              .whereType<Map>()
              .map((m) => UserMangaEntry.fromJson(Map<String, dynamic>.from(m)))
              .where((e) => e.mangaId.isNotEmpty)
              .toList();
          emit(state.copyWith(entries: parsed, isLoading: false));
          return;
        }
      }
    } catch (_) {}
    emit(state.copyWith(isLoading: false));
  }

  void selectTab(MangaListStatus tab) {
    emit(state.copyWith(selectedTab: tab));
  }

  Future<void> setStatus({
    required String mangaId,
    required String mangaTitle,
    required String coverUrl,
    required MangaListStatus status,
    String lastReadChapter = '1',
    int lastReadPage = 0,
    int? chaptersCount,
  }) async {
    if (mangaId.trim().isEmpty) return;
    _optedOutMangaIds.remove(mangaId);
    final list = List<UserMangaEntry>.from(state.entries);
    final idx = list.indexWhere((e) => e.mangaId == mangaId);
    final now = DateTime.now();
    final updated = idx >= 0
        ? list[idx].copyWith(
            status: status,
            chaptersCount: chaptersCount ?? list[idx].chaptersCount,
            updatedAt: now,
          )
        : UserMangaEntry(
            mangaId: mangaId,
            mangaTitle: mangaTitle,
            coverUrl: coverUrl,
            status: status,
            lastReadChapter: lastReadChapter,
            lastReadPage: lastReadPage,
            chaptersCount: chaptersCount,
            updatedAt: now,
          );
    if (idx >= 0) {
      list[idx] = updated;
    } else {
      list.insert(0, updated);
    }
    emit(state.copyWith(entries: list));
    await _persist(list, updated);
  }

  /// Автоматически добавляет тайтл в «Читаю» (если ещё не «Прочитано») при чтении >3 страницы.
  Future<void> recordAutoProgress({
    required String mangaId,
    required String mangaTitle,
    required String coverUrl,
    required String chapterLabel,
    required int pageIndex,
    int? chaptersCount,
  }) async {
    if (mangaId.trim().isEmpty) return;
    _optedOutMangaIds.remove(mangaId);
    final list = List<UserMangaEntry>.from(state.entries);
    final idx = list.indexWhere((e) => e.mangaId == mangaId);
    final now = DateTime.now();
    final nextStatus = (idx >= 0 && list[idx].status == MangaListStatus.completed)
        ? MangaListStatus.completed
        : MangaListStatus.reading;

    final updated = idx >= 0
        ? list[idx].copyWith(
            status: nextStatus,
            lastReadChapter: chapterLabel,
            lastReadPage: pageIndex,
            chaptersCount: chaptersCount ?? list[idx].chaptersCount,
            updatedAt: now,
          )
        : UserMangaEntry(
            mangaId: mangaId,
            mangaTitle: mangaTitle,
            coverUrl: coverUrl,
            status: nextStatus,
            lastReadChapter: chapterLabel,
            lastReadPage: pageIndex,
            chaptersCount: chaptersCount,
            updatedAt: now,
          );
    if (idx >= 0) {
      list[idx] = updated;
    } else {
      list.insert(0, updated);
    }
    emit(state.copyWith(entries: list));
    await _persist(list, updated);
  }

  Future<void> removeEntry(String mangaId) async {
    if (mangaId.trim().isEmpty) return;
    _optedOutMangaIds.add(mangaId);
    final list = entriesWithout(mangaId);
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
      await client
          .from('user_manga_lists')
          .delete()
          .eq('user_id', userId)
          .eq('manga_id', mangaId);
    } catch (_) {}
  }

  List<UserMangaEntry> entriesWithout(String mangaId) =>
      state.entries.where((e) => e.mangaId != mangaId).toList();

  Future<void> _persist(
    List<UserMangaEntry> list,
    UserMangaEntry updated,
  ) async {
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
      await client.from('user_manga_lists').upsert(
        {
          'user_id': userId,
          'manga_id': updated.mangaId,
          'manga_title': updated.mangaTitle,
          'status': updated.status.name,
          'chapter_number': updated.lastReadChapter,
          'page_index': updated.lastReadPage,
          'updated_at': updated.updatedAt.toUtc().toIso8601String(),
        },
        onConflict: 'user_id,manga_id',
      );
    } catch (_) {}
  }
}

