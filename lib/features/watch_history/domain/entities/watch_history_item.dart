import 'package:equatable/equatable.dart';

/// Элемент истории просмотра аниме с фиксацией серии и точной секунды.
class WatchHistoryItem extends Equatable {
  final int titleId;
  final String titleName;
  final String posterUrl;
  final int episode;
  final String? episodeName;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const WatchHistoryItem({
    required this.titleId,
    required this.titleName,
    required this.posterUrl,
    required this.episode,
    this.episodeName,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  /// Прогресс просмотра от 0.0 до 1.0 для индикатора на карточке
  double get progress => durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  /// Форматированное время позиции: 12:25 или 1:12:25
  String get formattedPosition => _formatMs(positionMs);

  /// Форматированная длительность: 24:00
  String get formattedDuration => _formatMs(durationMs);

  static String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Map<String, dynamic> toJson() => {
        'title_id': titleId,
        'title_name': titleName,
        'poster_url': posterUrl,
        'last_episode': episode,
        'episode_name': episodeName,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) {
    return WatchHistoryItem(
      titleId: json['title_id'] as int? ?? 0,
      titleName: json['title_name'] as String? ?? '',
      posterUrl: json['poster_url'] as String? ?? '',
      episode: json['last_episode'] as int? ?? (json['episode'] as int? ?? 1),
      episodeName: json['episode_name'] as String?,
      positionMs: json['position_ms'] as int? ?? 0,
      durationMs: json['duration_ms'] as int? ?? 0,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        titleId,
        titleName,
        posterUrl,
        episode,
        episodeName,
        positionMs,
        durationMs,
        updatedAt,
      ];
}

