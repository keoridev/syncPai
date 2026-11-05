import 'package:equatable/equatable.dart';

/// Модель студии перевода и озвучки из базы данных Kodik.
class KodikTranslation extends Equatable {
  final int id;
  final String title;
  final String type; // 'voice' (озвучка) или 'subtitles' (субтитры)
  final int episodesCount;
  final String? embedLink;
  final Map<int, String> episodeEmbedLinks; // episodeNumber -> iframe URL

  const KodikTranslation({
    required this.id,
    required this.title,
    required this.type,
    required this.episodesCount,
    this.embedLink,
    this.episodeEmbedLinks = const {},
  });

  /// Является ли дефолтным источником AniLibria
  bool get isAniLibria => id == 0;

  /// Является ли субтитрами
  bool get isSubtitles => type == 'subtitles' || title.toLowerCase().contains('субтитр');

  /// Иконка для отображения
  String get displayIcon => isSubtitles ? '💬' : '🎙️';

  /// Пресет по умолчанию: Официальная озвучка AniLibria
  factory KodikTranslation.anilibria() => const KodikTranslation(
        id: 0,
        title: 'AniLibria',
        type: 'voice',
        episodesCount: 0,
      );

  factory KodikTranslation.fromJson(Map<String, dynamic> json) {
    final tr = json['translation'] as Map<String, dynamic>?;
    final trId = tr?['id'] as int? ?? json['id'] as int? ?? 0;
    final trTitle = tr?['title'] as String? ?? json['title'] as String? ?? 'Неизвестная студия';
    final trType = tr?['type'] as String? ?? json['type'] as String? ?? 'voice';
    final epCount = json['episodes_count'] as int? ?? 1;
    final link = json['link'] as String?;

    final Map<int, String> epLinks = {};
    if (json['seasons'] is Map) {
      final seasons = json['seasons'] as Map<String, dynamic>;
      for (final sKey in seasons.keys) {
        final seasonObj = seasons[sKey];
        if (seasonObj is Map && seasonObj['episodes'] is Map) {
          final eps = seasonObj['episodes'] as Map<String, dynamic>;
          for (final epKey in eps.keys) {
            final epNum = int.tryParse(epKey);
            final epUrl = eps[epKey] as String?;
            if (epNum != null && epUrl != null) {
              epLinks[epNum] = epUrl.startsWith('//') ? 'https:$epUrl' : epUrl;
            }
          }
        }
      }
    }

    return KodikTranslation(
      id: trId,
      title: trTitle,
      type: trType,
      episodesCount: epLinks.isNotEmpty ? epLinks.length : epCount,
      embedLink: link != null ? (link.startsWith('//') ? 'https:$link' : link) : null,
      episodeEmbedLinks: epLinks,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'episodes_count': episodesCount,
        'link': embedLink,
        'episode_links': episodeEmbedLinks.map((k, v) => MapEntry('$k', v)),
      };

  @override
  List<Object?> get props => [id, title, type, episodesCount, embedLink, episodeEmbedLinks];
}

