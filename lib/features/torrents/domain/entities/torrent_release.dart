import 'package:equatable/equatable.dart';

class TorrentRelease extends Equatable {
  final String title;
  final String magnetUrl;
  final String? hash;
  final String sizeString;
  final int sizeBytes;
  final int seeders;
  final int leechers;
  final String quality;
  final String series;
  final String source;
  final String? torrentFileUrl;

  const TorrentRelease({
    required this.title,
    required this.magnetUrl,
    this.hash,
    required this.sizeString,
    this.sizeBytes = 0,
    required this.seeders,
    required this.leechers,
    required this.quality,
    required this.series,
    required this.source,
    this.torrentFileUrl,
  });

  factory TorrentRelease.fromAniLibria(Map<String, dynamic> json, String animeTitle) {
    final hash = json['hash'] as String? ?? '';
    final series = (json['series'] is Map)
        ? (json['series']['string'] as String? ?? '')
        : (json['series'] as String? ?? '');
    final quality = (json['quality'] is Map)
        ? (json['quality']['string'] as String? ?? '')
        : (json['quality'] as String? ?? '1080p');
    final totalSize = json['total_size'] as int? ?? 0;
    final seeders = json['seeders'] as int? ?? 0;
    final leechers = json['leechers'] as int? ?? 0;
    final magnet = json['magnet'] as String? ??
        (hash.isNotEmpty ? 'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(animeTitle)}' : '');

    String formattedSize = '';
    if (totalSize > 0) {
      final gb = totalSize / (1024 * 1024 * 1024);
      if (gb >= 1.0) {
        formattedSize = '${gb.toStringAsFixed(1)} ГБ';
      } else {
        formattedSize = '${(totalSize / (1024 * 1024)).toStringAsFixed(0)} МБ';
      }
    } else {
      formattedSize = json['size_string'] as String? ?? '—';
    }

    return TorrentRelease(
      title: animeTitle,
      magnetUrl: magnet,
      hash: hash,
      sizeString: formattedSize,
      sizeBytes: totalSize,
      seeders: seeders,
      leechers: leechers,
      quality: quality.isNotEmpty ? quality : 'BDRip 1080p',
      series: series.isNotEmpty ? series : 'Все серии',
      source: 'AniLibria BD/HEVC',
      torrentFileUrl: json['url'] != null ? 'https://www.anilibria.tv${json['url']}' : null,
    );
  }

  factory TorrentRelease.fromTorLook(Map<String, dynamic> json) {
    final title = json['title'] as String? ?? 'Торрент-релиз';
    final magnet = json['magnet'] as String? ?? '';
    final size = json['size'] as String? ?? '—';
    final seeds = int.tryParse('${json['seeders'] ?? json['seeds'] ?? 0}') ?? 0;
    final leechers = int.tryParse('${json['leechers'] ?? json['leeches'] ?? 0}') ?? 0;

    return TorrentRelease(
      title: title,
      magnetUrl: magnet,
      hash: json['hash'] as String?,
      sizeString: size,
      seeders: seeds,
      leechers: leechers,
      quality: title.contains('1080') ? 'BDRip 1080p' : (title.contains('720') ? '720p' : 'HD'),
      series: 'Торрент раздача',
      source: 'TorLook Tracker',
    );
  }

  @override
  List<Object?> get props => [
        title,
        magnetUrl,
        hash,
        sizeString,
        seeders,
        quality,
        series,
        source,
      ];
}

