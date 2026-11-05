import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Статус тайтла в списках пользователя (как в Anixart и Shikimori)
enum AnimeListStatus {
  watching,  // Смотрю
  planned,   // В планах
  completed, // Просмотрено
  dropped;   // Брошено

  String get labelRu {
    switch (this) {
      case AnimeListStatus.watching:
        return 'Смотрю';
      case AnimeListStatus.planned:
        return 'В планах';
      case AnimeListStatus.completed:
        return 'Просмотрено';
      case AnimeListStatus.dropped:
        return 'Брошено';
    }
  }

  IconData get icon {
    switch (this) {
      case AnimeListStatus.watching:
        return Icons.play_arrow_rounded;
      case AnimeListStatus.planned:
        return Icons.bookmark_outline_rounded;
      case AnimeListStatus.completed:
        return Icons.check_circle_outline_rounded;
      case AnimeListStatus.dropped:
        return Icons.remove_circle_outline_rounded;
    }
  }

  Color get color {
    switch (this) {
      case AnimeListStatus.watching:
        return AppColors.primary;
      case AnimeListStatus.planned:
        return const Color(0xFFFFB300);
      case AnimeListStatus.completed:
        return AppColors.syncActive;
      case AnimeListStatus.dropped:
        return AppColors.syncError;
    }
  }

  static AnimeListStatus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'watching':
      case 'смотрим':
      case 'смотрю':
        return AnimeListStatus.watching;
      case 'planned':
      case 'планирую':
      case 'в планах':
        return AnimeListStatus.planned;
      case 'completed':
      case 'просмотрено':
      case 'завершено':
        return AnimeListStatus.completed;
      case 'dropped':
      case 'брошено':
        return AnimeListStatus.dropped;
      default:
        return AnimeListStatus.watching;
    }
  }
}

/// Запись тайтла в закладках пользователя
class UserAnimeEntry extends Equatable {
  final String id;
  final String userId;
  final int animeId;
  final String titleRu;
  final String? posterUrl;
  final AnimeListStatus status;
  final int lastEpisode;
  final int positionMs;
  final int? episodesTotal;
  final DateTime updatedAt;

  const UserAnimeEntry({
    required this.id,
    required this.userId,
    required this.animeId,
    required this.titleRu,
    this.posterUrl,
    required this.status,
    this.lastEpisode = 1,
    this.positionMs = 0,
    this.episodesTotal,
    required this.updatedAt,
  });

  UserAnimeEntry copyWith({
    String? id,
    String? userId,
    int? animeId,
    String? titleRu,
    String? posterUrl,
    AnimeListStatus? status,
    int? lastEpisode,
    int? positionMs,
    int? episodesTotal,
    DateTime? updatedAt,
  }) {
    return UserAnimeEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      animeId: animeId ?? this.animeId,
      titleRu: titleRu ?? this.titleRu,
      posterUrl: posterUrl ?? this.posterUrl,
      status: status ?? this.status,
      lastEpisode: lastEpisode ?? this.lastEpisode,
      positionMs: positionMs ?? this.positionMs,
      episodesTotal: episodesTotal ?? this.episodesTotal,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Очищенное человекочитаемое русское название без сырых артефактов выгрузки Anixart
  String get cleanTitleRu {
    if (titleRu.isEmpty) return '';
    var cleaned = titleRu.trim();
    if (cleaned.contains(' / ') || cleaned.contains(' /"')) {
      final parts = cleaned.split(RegExp(r'\s*/\s*'));
      if (parts.length > 1 && RegExp(r'^\d+$').hasMatch(parts[0].trim())) {
        cleaned = parts[1].trim();
      } else if (parts.isNotEmpty) {
        cleaned = parts[0].trim();
      }
    }
    final idPrefixMatch = RegExp(r'^\d+\s*/\s*(.*)$').firstMatch(cleaned);
    if (idPrefixMatch != null) {
      cleaned = idPrefixMatch.group(1)!.trim();
      if (cleaned.contains(' / ')) {
        cleaned = cleaned.split(RegExp(r'\s*/\s*')).first.trim();
      }
    }
    cleaned = cleaned.replaceAll(RegExp(r'''^["'«„\s]+|["'»”\s]+$'''), '').trim();
    cleaned = cleaned.replaceAll(r'\"', '"').replaceAll('""', '"').trim();
    while (cleaned.startsWith('"') || cleaned.startsWith("'") || cleaned.startsWith('«')) {
      cleaned = cleaned.substring(1).trim();
    }
    while (cleaned.endsWith('"') || cleaned.endsWith("'") || cleaned.endsWith('»')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    return cleaned.isNotEmpty ? cleaned : titleRu;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'anime_id': animeId,
        'title_ru': titleRu,
        'poster_url': posterUrl,
        'status': status.name,
        'last_episode': lastEpisode,
        'position_ms': positionMs,
        'episodes_total': episodesTotal,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory UserAnimeEntry.fromJson(Map<String, dynamic> json) {
    return UserAnimeEntry(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      animeId: json['anime_id'] as int? ?? 0,
      titleRu: json['title_ru'] as String? ?? '',
      posterUrl: json['poster_url'] as String?,
      status: AnimeListStatus.fromString(json['status'] as String?),
      lastEpisode: json['last_episode'] as int? ?? 1,
      positionMs: (json['position_ms'] as num?)?.toInt() ?? 0,
      episodesTotal: json['episodes_total'] as int?,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        animeId,
        titleRu,
        posterUrl,
        status,
        lastEpisode,
        positionMs,
        episodesTotal,
        updatedAt,
      ];
}

/// Статистика пользователя «как в Anixart»
class UserAnimeStats extends Equatable {
  final int totalTitles;
  final int completedTitles;
  final int watchingTitles;
  final int plannedTitles;
  final int droppedTitles;
  final int totalEpisodesCompleted;
  final int totalMinutesWatched;

  const UserAnimeStats({
    required this.totalTitles,
    required this.completedTitles,
    required this.watchingTitles,
    required this.plannedTitles,
    required this.droppedTitles,
    required this.totalEpisodesCompleted,
    required this.totalMinutesWatched,
  });

  /// Форматированное время: ⏱️ 14 дн. 6 ч. или 5 ч. 20 мин.
  String get formattedTime {
    final days = totalMinutesWatched ~/ (24 * 60);
    final hours = (totalMinutesWatched % (24 * 60)) ~/ 60;
    final mins = totalMinutesWatched % 60;

    if (days > 0) {
      return '$days дн. $hours ч.';
    }
    if (hours > 0) {
      return '$hours ч. $mins мин.';
    }
    return '$mins мин.';
  }

  factory UserAnimeStats.compute(List<UserAnimeEntry> entries) {
    int completed = 0;
    int watching = 0;
    int planned = 0;
    int dropped = 0;
    int episodes = 0;
    int totalMinutes = 0;

    for (final e in entries) {
      switch (e.status) {
        case AnimeListStatus.completed:
          completed++;
          final count = e.episodesTotal ?? e.lastEpisode;
          episodes += count;
          totalMinutes += count * 24; // 24 мин средняя серия
          break;
        case AnimeListStatus.watching:
          watching++;
          final finishedEps = (e.lastEpisode > 0 ? e.lastEpisode - 1 : 0);
          final currentEpDone = e.positionMs >= 20 * 60 * 1000;
          final completed = finishedEps + (currentEpDone ? 1 : 0);
          episodes += completed;
          totalMinutes += finishedEps * 24;
          if (!currentEpDone) {
            totalMinutes += (e.positionMs ~/ 60000);
          } else {
            totalMinutes += 24;
          }
          break;
        case AnimeListStatus.planned:
          planned++;
          break;
        case AnimeListStatus.dropped:
          dropped++;
          episodes += e.lastEpisode;
          totalMinutes += e.lastEpisode * 24;
          break;
      }
    }

    return UserAnimeStats(
      totalTitles: entries.length,
      completedTitles: completed,
      watchingTitles: watching,
      plannedTitles: planned,
      droppedTitles: dropped,
      totalEpisodesCompleted: episodes,
      totalMinutesWatched: totalMinutes,
    );
  }

  @override
  List<Object?> get props => [
        totalTitles,
        completedTitles,
        watchingTitles,
        plannedTitles,
        droppedTitles,
        totalEpisodesCompleted,
        totalMinutesWatched,
      ];
}

