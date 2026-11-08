import 'package:equatable/equatable.dart';
import '../../domain/entities/sync_protocol.dart';
import '../../domain/entities/sync_room.dart';

abstract class SyncRoomState extends Equatable {
  const SyncRoomState();

  @override
  List<Object?> get props => [];
}

class SyncRoomInitial extends SyncRoomState {
  const SyncRoomInitial();
}

class SyncRoomCreating extends SyncRoomState {
  const SyncRoomCreating();
}

/// Хост в лобби комнаты (ждет участников или готов к старту)
class SyncRoomHostWaiting extends SyncRoomState {
  final SyncRoom room;
  final bool codeCopied;
  final bool linkCopied;
  final List<PeerPresence> participants;

  const SyncRoomHostWaiting({
    required this.room,
    this.codeCopied = false,
    this.linkCopied = false,
    this.participants = const [],
  });

  bool get hasGuest =>
      room.peerName != null && room.peerName!.isNotEmpty ||
      participants.any((p) => !p.isHost);

  SyncRoomHostWaiting copyWith({
    SyncRoom? room,
    bool? codeCopied,
    bool? linkCopied,
    List<PeerPresence>? participants,
  }) {
    return SyncRoomHostWaiting(
      room: room ?? this.room,
      codeCopied: codeCopied ?? this.codeCopied,
      linkCopied: linkCopied ?? this.linkCopied,
      participants: participants ?? this.participants,
    );
  }

  @override
  List<Object?> get props => [room, codeCopied, linkCopied, participants];
}

class SyncRoomJoining extends SyncRoomState {
  const SyncRoomJoining();
}

/// Участник (хост или гость) подключен к лобби комнаты и видит список всех присутствующих
class SyncRoomJoined extends SyncRoomState {
  final SyncRoom room;
  final bool isHost;
  final List<PeerPresence> participants;

  const SyncRoomJoined({
    required this.room,
    required this.isHost,
    this.participants = const [],
  });

  SyncRoomJoined copyWith({
    SyncRoom? room,
    bool? isHost,
    List<PeerPresence>? participants,
  }) {
    return SyncRoomJoined(
      room: room ?? this.room,
      isHost: isHost ?? this.isHost,
      participants: participants ?? this.participants,
    );
  }

  @override
  List<Object?> get props => [room, isHost, participants];
}

/// Сигнал одновременного старта воспроизведения для всех участников лобби
class SyncRoomPlaybackStarting extends SyncRoomState {
  final SyncRoom room;
  final bool isHost;

  const SyncRoomPlaybackStarting({
    required this.room,
    required this.isHost,
  });

  @override
  List<Object?> get props => [room, isHost];
}

class SyncRoomError extends SyncRoomState {
  final String message;

  const SyncRoomError(this.message);

  @override
  List<Object?> get props => [message];
}
