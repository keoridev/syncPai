import '../entities/torrent_release.dart';

abstract class TorrentRepository {
  Future<List<TorrentRelease>> getTorrentsForTitle({
    required int titleId,
    required String titleCode,
    required String titleRu,
  });

  String buildTorrServeStreamUrl(String magnetUrl, {int fileIndex = 0});
}

