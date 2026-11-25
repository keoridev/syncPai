import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MangaReadingProgress {
  final String mangaId;
  final String chapterNumber;
  final int pageIndex;
  final DateTime updatedAt;

  const MangaReadingProgress({
    required this.mangaId,
    required this.chapterNumber,
    required this.pageIndex,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'mangaId': mangaId,
        'chapterNumber': chapterNumber,
        'pageIndex': pageIndex,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory MangaReadingProgress.fromJson(Map<String, dynamic> json) {
    return MangaReadingProgress(
      mangaId: (json['mangaId'] ?? '').toString(),
      chapterNumber: (json['chapterNumber'] ?? '1').toString(),
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

class FeaturedMangaShowcase {
  final String mangaId;
  final String mangaTitle;
  final String coverUrl;
  final String chapterLabel;
  final int? totalChapters;

  const FeaturedMangaShowcase({
    required this.mangaId,
    required this.mangaTitle,
    required this.coverUrl,
    required this.chapterLabel,
    this.totalChapters,
  });

  Map<String, dynamic> toJson() => {
        'mangaId': mangaId,
        'mangaTitle': mangaTitle,
        'coverUrl': coverUrl,
        'chapterLabel': chapterLabel,
        'totalChapters': totalChapters,
      };

  factory FeaturedMangaShowcase.fromJson(Map<String, dynamic> json) {
    return FeaturedMangaShowcase(
      mangaId: (json['mangaId'] ?? '').toString(),
      mangaTitle: (json['mangaTitle'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      chapterLabel: (json['chapterLabel'] ?? '1').toString(),
      totalChapters: (json['totalChapters'] as num?)?.toInt(),
    );
  }
}

enum ShowcaseMode {
  manga('Витрина манги'),
  anime('Витрина аниме'),
  dual('Двойная витрина');

  final String labelRu;
  const ShowcaseMode(this.labelRu);

  static ShowcaseMode fromKey(String raw) {
    for (final m in ShowcaseMode.values) {
      if (m.name == raw) return m;
    }
    return ShowcaseMode.dual;
  }
}

class ProfileShowcaseConfig {
  final ShowcaseMode mode;
  final String customCaption;
  final bool fullBleedBackdrop;
  final FeaturedMangaShowcase? selectedManga;

  const ProfileShowcaseConfig({
    this.mode = ShowcaseMode.dual,
    this.customCaption = 'Любимая манга',
    this.fullBleedBackdrop = true,
    this.selectedManga,
  });

  ProfileShowcaseConfig copyWith({
    ShowcaseMode? mode,
    String? customCaption,
    bool? fullBleedBackdrop,
    FeaturedMangaShowcase? selectedManga,
  }) {
    return ProfileShowcaseConfig(
      mode: mode ?? this.mode,
      customCaption: customCaption ?? this.customCaption,
      fullBleedBackdrop: fullBleedBackdrop ?? this.fullBleedBackdrop,
      selectedManga: selectedManga ?? this.selectedManga,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'customCaption': customCaption,
        'fullBleedBackdrop': fullBleedBackdrop,
        'selectedManga': selectedManga?.toJson(),
      };

  factory ProfileShowcaseConfig.fromJson(Map<String, dynamic> json) {
    return ProfileShowcaseConfig(
      mode: ShowcaseMode.fromKey((json['mode'] ?? 'dual').toString()),
      customCaption: (json['customCaption'] ?? 'Любимая манга').toString(),
      fullBleedBackdrop: json['fullBleedBackdrop'] as bool? ?? true,
      selectedManga: json['selectedManga'] is Map<String, dynamic>
          ? FeaturedMangaShowcase.fromJson(
              json['selectedManga'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// Персистентный прогресс чтения манги / манхвы (`SharedPreferences` + Supabase `user_manga_lists`).
class MangaProgressRepository {
  static const String _prefsPrefix = 'syncpai_manga_progress_';
  static const String _featuredMangaKey = 'syncpai_featured_manga_showcase_v1';
  static const String _showcaseConfigKey = 'syncpai_profile_showcase_config_v1';

  final SharedPreferences? _prefs;

  MangaProgressRepository([this._prefs]);

  Future<SharedPreferences> _getPrefs() async =>
      _prefs ?? await SharedPreferences.getInstance();

  Future<MangaReadingProgress?> getProgress(String mangaId) async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString('$_prefsPrefix$mangaId');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return MangaReadingProgress.fromJson(decoded);
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<MangaReadingProgress>> getAllProgress() async {
    try {
      final prefs = await _getPrefs();
      final list = <MangaReadingProgress>[];
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_prefsPrefix)) continue;
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            list.add(MangaReadingProgress.fromJson(decoded));
          }
        } catch (_) {}
      }
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveProgress({
    required String mangaId,
    required String mangaTitle,
    required String chapterNumber,
    required int pageIndex,
  }) async {
    final progress = MangaReadingProgress(
      mangaId: mangaId,
      chapterNumber: chapterNumber,
      pageIndex: pageIndex,
      updatedAt: DateTime.now(),
    );

    try {
      final prefs = await _getPrefs();
      await prefs.setString(
        '$_prefsPrefix$mangaId',
        jsonEncode(progress.toJson()),
      );
    } catch (_) {}

    unawaited(_syncToSupabase(
      mangaId: mangaId,
      mangaTitle: mangaTitle,
      chapterNumber: chapterNumber,
      pageIndex: pageIndex,
    ));
  }

  Future<void> _syncToSupabase({
    required String mangaId,
    required String mangaTitle,
    required String chapterNumber,
    required int pageIndex,
  }) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return;

      await client.from('user_manga_lists').upsert(
        {
          'user_id': userId,
          'manga_id': mangaId,
          'manga_title': mangaTitle,
          'chapter_number': chapterNumber,
          'page_index': pageIndex,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,manga_id',
      );
    } catch (_) {}
  }

  Future<int> getTotalChaptersRead() async {
    final entries = await getAllProgress();
    var total = 0;
    for (final e in entries) {
      final parsed = double.tryParse(e.chapterNumber)?.floor();
      if (parsed != null && parsed > 0) {
        total += parsed;
      } else {
        total += 1;
      }
    }
    return total;
  }

  Future<FeaturedMangaShowcase?> getFeaturedManga() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_featuredMangaKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final parsed = FeaturedMangaShowcase.fromJson(decoded);
          if (parsed.mangaId.isNotEmpty) return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveFeaturedManga(FeaturedMangaShowcase showcase) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_featuredMangaKey, jsonEncode(showcase.toJson()));
    } catch (_) {}
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return;
      await client
          .from('profiles')
          .update({'featured_manga': showcase.toJson()})
          .eq('id', userId);
    } catch (_) {}
  }

  Future<ProfileShowcaseConfig> getShowcaseConfig() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString(_showcaseConfigKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return ProfileShowcaseConfig.fromJson(decoded);
        }
      }
    } catch (_) {}
    final featured = await getFeaturedManga();
    return ProfileShowcaseConfig(selectedManga: featured);
  }

  Future<void> saveShowcaseConfig(ProfileShowcaseConfig config) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_showcaseConfigKey, jsonEncode(config.toJson()));
      if (config.selectedManga != null) {
        await prefs.setString(
          _featuredMangaKey,
          jsonEncode(config.selectedManga!.toJson()),
        );
      }
    } catch (_) {}
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return;
      await client
          .from('profiles')
          .update({'showcase_config': config.toJson()})
          .eq('id', userId);
    } catch (_) {}
  }
}

