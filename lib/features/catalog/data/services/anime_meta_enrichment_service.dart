import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/di/injection.dart';
import '../../../anime_details/data/datasources/shikimori_remote_datasource.dart';
import '../../domain/entities/anime_title.dart';

class AnimeMetaEnrichment {
  final int shikimoriId;
  final String hdPosterUrl;
  final double? score;
  final int? scoredBy;
  final DateTime updatedAt;

  const AnimeMetaEnrichment({
    required this.shikimoriId,
    required this.hdPosterUrl,
    this.score,
    this.scoredBy,
    required this.updatedAt,
  });

  bool get isFresh =>
      DateTime.now().difference(updatedAt) < const Duration(days: 7);

  Map<String, dynamic> toJson() => {
        'shikimori_id': shikimoriId,
        'hd_poster_url': hdPosterUrl,
        'score': score,
        'scored_by': scoredBy,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory AnimeMetaEnrichment.fromJson(Map<String, dynamic> json) {
    return AnimeMetaEnrichment(
      shikimoriId: (json['shikimori_id'] as num?)?.toInt() ?? 0,
      hdPosterUrl: (json['hd_poster_url'] ?? '').toString(),
      score: (json['score'] as num?)?.toDouble(),
      scoredBy: (json['scored_by'] as num?)?.toInt(),
      updatedAt: DateTime.tryParse((json['updated_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Сервис обогащения каталога и деталей аниме HD-постерами (`image.original`)
/// и реальными рейтингами Shikimori (`<= 3 req/sec`, кэш 7 дней + Supabase `anime_meta_cache`).
class AnimeMetaEnrichmentService {
  static final AnimeMetaEnrichmentService instance =
      AnimeMetaEnrichmentService();

  static const String _prefsPrefix = 'syncpai_hd_meta_v1_';
  static const Duration _minInterval = Duration(milliseconds: 360);

  final Dio _dio;
  final ShikimoriRemoteDataSource? _shikimoriOverride;
  final SharedPreferences? _prefsOverride;

  final Map<int, AnimeMetaEnrichment> _memory = {};
  Future<void> _queueTail = Future<void>.value();
  DateTime? _lastRequestAt;

  AnimeMetaEnrichmentService({
    Dio? dio,
    ShikimoriRemoteDataSource? shikimoriDataSource,
    SharedPreferences? prefs,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://shikimori.io/api',
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 7),
                headers: const {
                  'User-Agent': 'SyncPai/1.0',
                  'Accept': 'application/json',
                },
              ),
            ),
        _shikimoriOverride = shikimoriDataSource,
        _prefsOverride = prefs;

  bool get _isTestEnv {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  Future<SharedPreferences> _getPrefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  Future<T> _enqueueRateLimited<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queueTail = _queueTail.then((_) async {
      final now = DateTime.now();
      if (_lastRequestAt != null) {
        final elapsed = now.difference(_lastRequestAt!);
        if (elapsed < _minInterval) {
          await Future.delayed(_minInterval - elapsed);
        }
      }
      _lastRequestAt = DateTime.now();
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  AnimeTitle _applyEnrichment(AnimeTitle title, AnimeMetaEnrichment meta) {
    final hd = meta.hdPosterUrl.trim();
    final currentFallback =
        title.fallbackPosterUrl.isNotEmpty ? title.fallbackPosterUrl : title.posterUrl;
    return title.copyWith(
      shikimoriId: meta.shikimoriId > 0 ? meta.shikimoriId : title.shikimoriId,
      score: (meta.score != null && meta.score! > 0) ? meta.score : title.score,
      posterOriginal: hd.isNotEmpty ? hd : title.posterOriginal,
      posterMedium: hd.isNotEmpty ? hd : title.posterMedium,
      fallbackPosterUrl: currentFallback,
    );
  }

  Future<AnimeMetaEnrichment?> _readLocal(int animeId) async {
    final mem = _memory[animeId];
    if (mem != null && mem.isFresh) return mem;
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getString('$_prefsPrefix$animeId');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final parsed = AnimeMetaEnrichment.fromJson(Map<String, dynamic>.from(map));
      if (!parsed.isFresh) return null;
      _memory[animeId] = parsed;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeLocal(int animeId, AnimeMetaEnrichment meta) async {
    _memory[animeId] = meta;
    try {
      final prefs = await _getPrefs();
      await prefs.setString('$_prefsPrefix$animeId', jsonEncode(meta.toJson()));
    } catch (_) {}
  }

  Future<void> _upsertSupabase(int animeId, AnimeMetaEnrichment meta) async {
    if (_isTestEnv) return;
    try {
      final client = Supabase.instance.client;
      await client.from('anime_meta_cache').upsert(
        {
          'anime_key': 'anilibria_$animeId',
          'shikimori_id': meta.shikimoriId,
          'payload': {
            'shikimori_id': meta.shikimoriId,
            'hd_poster_url': meta.hdPosterUrl,
            'score': meta.score,
            'scored_by': meta.scoredBy,
          },
          'updated_at': meta.updatedAt.toUtc().toIso8601String(),
        },
        onConflict: 'anime_key',
      );
    } catch (_) {}
  }

  Future<AnimeMetaEnrichment?> fetchEnrichment(AnimeTitle title) async {
    if (title.id <= 0) return null;
    final cached = await _readLocal(title.id);
    if (cached != null) return cached;

    try {
      int? shikiId = title.shikimoriId;
      if (shikiId == null || shikiId <= 0) {
        final shiki = _shikimoriOverride ??
            (getIt.isRegistered<ShikimoriRemoteDataSource>()
                ? getIt<ShikimoriRemoteDataSource>()
                : null);
        if (shiki != null) {
          shikiId = await shiki.resolveShikimoriId(title);
        }
      }
      if (shikiId == null || shikiId <= 0) return null;

      final res = await _enqueueRateLimited(
        () => _dio.get('/animes/$shikiId'),
      );
      if (res.statusCode != 200 || res.data is! Map) return null;
      final data = res.data as Map;
      final imgMap = data['image'] is Map ? data['image'] as Map : null;
      final rawOrig = (imgMap?['original'] ?? '').toString().trim();
      final hdUrl = rawOrig.isEmpty
          ? ''
          : (rawOrig.startsWith('http')
              ? rawOrig
              : 'https://shikimori.one$rawOrig');
      final score = double.tryParse('${data['score'] ?? ''}');
      final scoredBy = (data['scored_by'] as num?)?.toInt();

      final meta = AnimeMetaEnrichment(
        shikimoriId: shikiId,
        hdPosterUrl: hdUrl,
        score: score,
        scoredBy: scoredBy,
        updatedAt: DateTime.now(),
      );
      await _writeLocal(title.id, meta);
      unawaited(_upsertSupabase(title.id, meta));
      return meta;
    } catch (_) {
      return null;
    }
  }

  Future<AnimeTitle> enrichSingle(AnimeTitle title) async {
    final meta = await fetchEnrichment(title);
    if (meta == null) return title;
    return _applyEnrichment(title, meta);
  }

  Future<void> enrichBatch(
    List<AnimeTitle> titles, {
    required void Function(List<AnimeTitle> updatedTitles) onUpdated,
    int maxFetchCount = 16,
  }) async {
    if (titles.isEmpty) return;

    // 1. Мгновенно применяем локальный кэш
    final updated = List<AnimeTitle>.from(titles);
    bool changed = false;
    final toFetch = <int>[];
    for (var i = 0; i < updated.length; i++) {
      final t = updated[i];
      final local = await _readLocal(t.id);
      if (local != null) {
        updated[i] = _applyEnrichment(t, local);
        changed = true;
      } else if (toFetch.length < maxFetchCount) {
        toFetch.add(i);
      }
    }
    if (changed) {
      onUpdated(List<AnimeTitle>.from(updated));
    }

    // 2. Последовательно (<= 3 req/sec) догружаем недостающие
    for (final idx in toFetch) {
      final meta = await fetchEnrichment(updated[idx]);
      if (meta != null) {
        updated[idx] = _applyEnrichment(updated[idx], meta);
        onUpdated(List<AnimeTitle>.from(updated));
      }
    }
  }
}

