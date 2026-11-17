import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../app/di/injection.dart';
import '../../catalog/domain/entities/anime_title.dart';
import '../../catalog/domain/entities/episode_item.dart';
import '../../catalog/domain/usecases/get_player_links_usecase.dart';
import '../../kodik/presentation/cubit/kodik_cubit.dart';
import '../domain/entities/player_quality.dart';
import '../presentation/cubit/player_cubit.dart';

/// Сервис упреждающей предзагрузки следующей серии (Smart Next-Episode Prefetch).
/// Срабатывает перед началом финальных титров (ending.start или duration - 120s),
/// разрешает ссылку на поток следующего эпизода в выбранном качестве (1080p/720p/SD)
/// и прогревает .m3u8 плейлист и первые 2 медиа-сегмента (.ts чанки, ~10 сек видео),
/// обеспечивая бесшовный мгновенный переход к следующей серии с нулевой задержкой буферизации.
class EpisodePrefetchService {
  static final EpisodePrefetchService instance = EpisodePrefetchService._();

  EpisodePrefetchService._({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  // In-Memory кэш разрешенных прямых URL потоков следующей серии
  // Ключ: '${titleId}_${episodeNum}_${quality.name}'
  final Map<String, String> _resolvedStreamUrls = {};

  // In-Memory кэш манифестов .m3u8
  final Map<String, String> _playlistCache = {};

  // In-Memory кэш прогретых сегментов: URL сегмента -> размер в байтах
  final Map<String, int> _prewarmedSegments = {};

  // Активные фоновые задачи предзагрузки для предотвращения дублирования запросов
  final Set<String> _inFlightPrefetches = {};

  /// Получить предзагруженный URL потока для серии
  String? getPrefetchedStreamUrl(int titleId, int episodeNum, PlayerQuality quality) {
    final key = _buildKey(titleId, episodeNum, quality);
    return _resolvedStreamUrls[key];
  }

  /// Проверен ли и прогрет ли сегмент
  bool isSegmentPrewarmed(String segmentUrl) => _prewarmedSegments.containsKey(segmentUrl);

  /// Общее количество прогретых сегментов
  int get prewarmedSegmentsCount => _prewarmedSegments.length;

  /// Очистить кэш предзагрузки (например, при смене тайтла)
  void clear() {
    _resolvedStreamUrls.clear();
    _playlistCache.clear();
    _prewarmedSegments.clear();
    _inFlightPrefetches.clear();
  }

  static String _buildKey(int titleId, int episodeNum, PlayerQuality quality) =>
      '${titleId}_${episodeNum}_${quality.name}';

  /// Запуск упреждающей предзагрузки следующего эпизода
  Future<String?> prefetchNext({
    required AnimeTitle title,
    required EpisodeItem currentEpisode,
    required EpisodeItem nextEpisode,
    required PlayerQuality quality,
  }) async {
    final cacheKey = _buildKey(title.id, nextEpisode.episode, quality);
    if (_inFlightPrefetches.contains(cacheKey)) {
      return _resolvedStreamUrls[cacheKey];
    }
    _inFlightPrefetches.add(cacheKey);

    try {
      debugPrint(
        '[EpisodePrefetchService] Запуск предзагрузки серии ${nextEpisode.episode} '
        'для «${title.displayTitle}» (Качество: ${quality.label})',
      );

      // 1. Разрешаем ссылку на поток следующей серии
      String? streamUrl = _resolvedStreamUrls[cacheKey];
      if (streamUrl == null || streamUrl.isEmpty) {
        streamUrl = await _resolveNextStreamUrl(
          title: title,
          nextEpisode: nextEpisode,
          quality: quality,
        );
        if (streamUrl != null && streamUrl.isNotEmpty) {
          _resolvedStreamUrls[cacheKey] = streamUrl;
        }
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        debugPrint('[EpisodePrefetchService] Не удалось разрешить поток для серии ${nextEpisode.episode}');
        return null;
      }

      // 2. Выполняем легковесный HTTP GET для .m3u8 и прогреваем первые 2 .ts сегмента
      await _prewarmM3u8AndSegments(streamUrl);

      debugPrint(
        '[EpisodePrefetchService] Успешно предзагружена серия ${nextEpisode.episode} '
        'для «${title.displayTitle}» ($streamUrl). Прогрето сегментов: ${_prewarmedSegments.length}',
      );
      return streamUrl;
    } catch (e) {
      debugPrint('[EpisodePrefetchService] Ошибка предзагрузки серии ${nextEpisode.episode}: $e');
      return null;
    } finally {
      _inFlightPrefetches.remove(cacheKey);
    }
  }

  /// Разрешение URL потока следующего эпизода (AniLibria / Kodik / BFF)
  Future<String?> _resolveNextStreamUrl({
    required AnimeTitle title,
    required EpisodeItem nextEpisode,
    required PlayerQuality quality,
  }) async {
    // 1. Проверяем активна ли сторонняя озвучка Kodik
    if (getIt.isRegistered<KodikCubit>()) {
      try {
        final kodik = getIt<KodikCubit>();
        if (!kodik.state.isAniLibriaActive) {
          final kodikStream = await kodik.getStreamForEpisode(nextEpisode.episode);
          if (kodikStream != null && kodikStream.isNotEmpty && !kodikStream.contains('sample.com')) {
            return kodikStream;
          }
        }
      } catch (_) {}
    }

    // 2. Прямые ссылки из EpisodeItem (AniLibria)
    String? url = _getUrlForQuality(nextEpisode, quality);

    // 3. Если прямая ссылка отсутствует — запрашиваем через GetPlayerLinksUseCase
    if ((url == null || url.isEmpty || url.contains('sample.com')) &&
        getIt.isRegistered<GetPlayerLinksUseCase>() &&
        title.id > 0) {
      try {
        final links = await getIt<GetPlayerLinksUseCase>().call(
          title.id,
          title: title.displayTitle,
        );
        if (links.isNotEmpty) {
          final direct = links.where((t) => t.isDirectStream && t.episodes.isNotEmpty);
          if (direct.isNotEmpty) {
            final target = direct.first.episodes.firstWhere(
              (e) => e.episode == nextEpisode.episode,
              orElse: () => direct.first.episodes.first,
            );
            url = _getUrlForQuality(target.toEpisodeItem(), quality);
          }
        }
      } catch (_) {}
    }

    if (url != null && url.isNotEmpty) {
      var trimmed = url.trim();
      if (trimmed.startsWith('//')) {
        trimmed = 'https:$trimmed';
      }
      if (!trimmed.contains('sample.com')) {
        return trimmed;
      }
    }
    return null;
  }

  String? _getUrlForQuality(EpisodeItem ep, PlayerQuality quality) {
    switch (quality) {
      case PlayerQuality.fhd:
        return ep.fhdUrl ?? ep.hdUrl ?? ep.sdUrl;
      case PlayerQuality.hd:
        return ep.hdUrl ?? ep.fhdUrl ?? ep.sdUrl;
      case PlayerQuality.sd:
        return ep.sdUrl ?? ep.hdUrl ?? ep.fhdUrl;
    }
  }

  /// Загрузка .m3u8 плейлиста и предзагрузка первых 2 сегментов видео (~10 сек)
  Future<void> _prewarmM3u8AndSegments(String streamUrl) async {
    try {
      final response = await _dio.get<String>(
        streamUrl,
        options: Options(
          headers: PlayerCubit.defaultStreamingHeaders,
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      final m3u8Content = response.data;
      if (m3u8Content == null || m3u8Content.isEmpty) return;
      _playlistCache[streamUrl] = m3u8Content;

      final baseUri = Uri.parse(streamUrl);
      final lines = m3u8Content.split('\n');

      // Проверяем, является ли плейлист Master Playlist со ссылками на варианты качеств
      final subPlaylists = lines
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#') && l.contains('.m3u8'))
          .toList();

      List<String> segmentUrls = [];

      if (subPlaylists.isNotEmpty) {
        final subUrl = baseUri.resolve(subPlaylists.first).toString();
        try {
          final subRes = await _dio.get<String>(
            subUrl,
            options: Options(
              headers: PlayerCubit.defaultStreamingHeaders,
              responseType: ResponseType.plain,
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );
          final subContent = subRes.data;
          if (subContent != null && subContent.isNotEmpty) {
            _playlistCache[subUrl] = subContent;
            segmentUrls = _extractSegments(subContent.split('\n'), Uri.parse(subUrl));
          }
        } catch (_) {
          segmentUrls = _extractSegments(lines, baseUri);
        }
      } else {
        segmentUrls = _extractSegments(lines, baseUri);
      }

      // Прогреваем первые 2 медиа-сегмента (первые ~10 секунд воспроизведения)
      final segmentsToPrewarm = segmentUrls.take(2).toList();
      for (final segUrl in segmentsToPrewarm) {
        if (_prewarmedSegments.containsKey(segUrl)) continue;
        try {
          final segRes = await _dio.get<List<int>>(
            segUrl,
            options: Options(
              headers: {
                ...PlayerCubit.defaultStreamingHeaders,
                'Range': 'bytes=0-524287', // Первые 512 КБ сегмента для моментального старта декодера
              },
              responseType: ResponseType.bytes,
              sendTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
            ),
          );
          final bytesCount = segRes.data?.length ?? 0;
          _prewarmedSegments[segUrl] = bytesCount;
          debugPrint(
            '[EpisodePrefetchService] Прогрет сегмент: '
            '${segUrl.split('/').last.split('?').first} ($bytesCount байт)',
          );
        } catch (e) {
          debugPrint('[EpisodePrefetchService] Ошибка прогрева сегмента ($segUrl): $e');
        }
      }
    } catch (e) {
      debugPrint('[EpisodePrefetchService] Ошибка чтения .m3u8 ($streamUrl): $e');
    }
  }

  List<String> _extractSegments(List<String> lines, Uri baseUri) {
    final result = <String>[];
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.contains('.ts') || line.contains('.m4s') || !line.contains('.m3u8')) {
        try {
          final resolved = baseUri.resolve(line).toString();
          result.add(resolved);
        } catch (_) {}
      }
    }
    return result;
  }
}
