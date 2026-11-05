import 'package:dio/dio.dart';
import 'package:sync_pai/core/network/api_constants.dart';
import 'package:sync_pai/features/torrents/domain/entities/torrent_release.dart';
import 'package:sync_pai/features/torrents/domain/repositories/torrent_repository.dart';

class TorrentRepositoryImpl implements TorrentRepository {
  final Dio _dio;

  TorrentRepositoryImpl({Dio? dio}) : _dio = dio ?? Dio();

  @override
  Future<List<TorrentRelease>> getTorrentsForTitle({
    required int titleId,
    required String titleCode,
    required String titleRu,
  }) async {
    final releases = <TorrentRelease>[];

    // 1. Извлекаем прямые торренты из AniLibria API (BDRip 1080p, HEVC, WEBRip)
    try {
      final endpoint = titleId > 0
          ? '${ApiConstants.baseUrl}${ApiConstants.releaseDetails}/$titleId'
          : '${ApiConstants.baseUrl}${ApiConstants.releaseDetails}/$titleCode';

      final response = await _dio.get<Map<String, dynamic>>(
        endpoint,
        options: Options(receiveTimeout: const Duration(seconds: 6)),
      );

      if (response.statusCode == 200 && response.data != null) {
        final torrentsData = response.data!['torrents'];
        if (torrentsData is Map && torrentsData['list'] is List) {
          final list = torrentsData['list'] as List<dynamic>;
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              releases.add(TorrentRelease.fromAniLibria(item, titleRu));
            }
          }
        }
      }
    } catch (_) {}

    // 2. Если AniLibria не вернула раздачи, запрашиваем открытый поиск TorLook
    if (releases.isEmpty && titleRu.isNotEmpty) {
      try {
        final encodedQuery = Uri.encodeComponent(titleRu);
        final searchUrl = 'https://api.torlook.info/api.php?key=syncpai&q=$encodedQuery';
        final response = await _dio.get<dynamic>(
          searchUrl,
          options: Options(receiveTimeout: const Duration(seconds: 5)),
        );

        if (response.data is Map && response.data['result'] is List) {
          final results = response.data['result'] as List<dynamic>;
          for (final item in results.take(10)) {
            if (item is Map<String, dynamic>) {
              releases.add(TorrentRelease.fromTorLook(item));
            }
          }
        }
      } catch (_) {}
    }

    // Сортируем по сидерам (наиболее живые раздачи первыми)
    releases.sort((a, b) => b.seeders.compareTo(a.seeders));
    return releases;
  }

  @override
  String buildTorrServeStreamUrl(String magnetUrl, {int fileIndex = 0}) {
    final encoded = Uri.encodeComponent(magnetUrl);
    return 'http://127.0.0.1:8090/stream?link=$encoded&index=$fileIndex&play';
  }
}
