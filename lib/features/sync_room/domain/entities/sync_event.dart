import 'package:equatable/equatable.dart';

enum SyncEventType {
  peerJoined,
  peerLeft,
  play,
  pause,
  seek,
  buffering,
  syncReady,
  startPlayback,
}

/// Событие реального времени в канале совместной комнаты.
class SyncEvent extends Equatable {
  final String roomCode;
  final SyncEventType type;
  final String senderName;
  final Duration? position;
  final DateTime timestamp;

  const SyncEvent({
    required this.roomCode,
    required this.type,
    required this.senderName,
    this.position,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [roomCode, type, senderName, position, timestamp];
}

