import 'package:equatable/equatable.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';

enum SyncEventType {
  peerJoined,
  peerLeft,
  play,
  pause,
  seek,
  buffering,
  syncReady,
  startPlayback,
  animeChanged,
}

/// Событие реального времени в канале совместной комнаты.
class SyncEvent extends Equatable {
  final String roomCode;
  final SyncEventType type;
  final String senderName;
  final Duration? position;
  final DateTime timestamp;
  final AnimeTitle? newTitle;
  final EpisodeItem? newEpisode;

  const SyncEvent({
    required this.roomCode,
    required this.type,
    required this.senderName,
    this.position,
    required this.timestamp,
    this.newTitle,
    this.newEpisode,
  });

  @override
  List<Object?> get props => [roomCode, type, senderName, position, timestamp, newTitle, newEpisode];
}

