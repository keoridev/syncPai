import 'package:equatable/equatable.dart';
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

class SyncRoomHostWaiting extends SyncRoomState {
  final SyncRoom room;
  final bool codeCopied;
  final bool linkCopied;

  const SyncRoomHostWaiting({
    required this.room,
    this.codeCopied = false,
    this.linkCopied = false,
  });

  SyncRoomHostWaiting copyWith({
    SyncRoom? room,
    bool? codeCopied,
    bool? linkCopied,
  }) {
    return SyncRoomHostWaiting(
      room: room ?? this.room,
      codeCopied: codeCopied ?? this.codeCopied,
      linkCopied: linkCopied ?? this.linkCopied,
    );
  }

  @override
  List<Object?> get props => [room, codeCopied, linkCopied];
}

class SyncRoomJoining extends SyncRoomState {
  const SyncRoomJoining();
}

class SyncRoomJoined extends SyncRoomState {
  final SyncRoom room;
  final bool isHost;

  const SyncRoomJoined({
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

