import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../domain/entities/sync_event.dart';
import '../../domain/entities/sync_protocol.dart';
import '../../domain/entities/sync_room.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../player/domain/entities/player_quality.dart';
import 'sync_room_state.dart';

class SyncRoomCubit extends Cubit<SyncRoomState> {
  final SyncRoomRepository repository;
  StreamSubscription<SyncEvent>? _eventSubscription;
  StreamSubscription<List<PeerPresence>>? _presenceSubscription;
  String? _currentRoomCode;

  SyncRoomCubit({required this.repository}) : super(const SyncRoomInitial());

  /// 1. Режим хоста: создать комнату и открыть интерактивное лобби
  Future<void> createRoom({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality quality = PlayerQuality.hd,
  }) async {
    emit(const SyncRoomCreating());
    try {
      final room = await repository.createRoom(
        title: title,
        episode: episode,
        quality: quality,
      );
      _currentRoomCode = room.code;

      // Подписка на присутствие участников в лобби
      await _presenceSubscription?.cancel();
      _presenceSubscription = repository.subscribeToPresence(room.code).listen((presences) {
        final s = state;
        if (s is SyncRoomHostWaiting) {
          final guestPresence = presences.where((p) => !p.isHost).firstOrNull;
          emit(s.copyWith(
            participants: presences,
            room: guestPresence != null
                ? s.room.copyWith(peerName: guestPresence.name, status: SyncRoomStatus.connected)
                : s.room,
          ));
        } else if (s is SyncRoomJoined) {
          emit(s.copyWith(participants: presences));
        }
      });

      // Подписываемся на события комнаты (подключение гостя, старт плеера)
      await _eventSubscription?.cancel();
      _eventSubscription = repository.subscribeToRoom(room.code).listen((event) {
        if (event.type == SyncEventType.peerJoined) {
          final s = state;
          if (s is SyncRoomHostWaiting) {
            emit(s.copyWith(
              room: s.room.copyWith(
                peerName: event.senderName,
                status: SyncRoomStatus.connected,
              ),
            ));
          }
        } else if (event.type == SyncEventType.startPlayback) {
          final s = state;
          if (s is SyncRoomHostWaiting) {
            emit(SyncRoomPlaybackStarting(room: s.room, isHost: true));
          } else if (s is SyncRoomJoined) {
            emit(SyncRoomPlaybackStarting(room: s.room, isHost: false));
          }
        }
      });

      emit(SyncRoomHostWaiting(
        room: room,
        participants: [
          PeerPresence(
            userId: 'host_${room.code}',
            name: room.hostName,
            avatar: '👑',
            status: PresenceStatus.online,
            lastSeen: DateTime.now(),
            isHost: true,
          ),
        ],
      ));
    } catch (e) {
      emit(SyncRoomError('Не удалось создать комнату: $e'));
    }
  }

  /// 2. Режим гостя: валидация и подключение к лобби по коду
  Future<void> joinRoom(String rawCode, {String peerName = 'Друг'}) async {
    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty) {
      emit(const SyncRoomError('Введите код комнаты'));
      return;
    }

    emit(const SyncRoomJoining());
    try {
      final room = await repository.joinRoom(code: cleanCode, peerName: peerName);
      _currentRoomCode = room.code;

      // Подписка на присутствие участников в лобби
      await _presenceSubscription?.cancel();
      _presenceSubscription = repository.subscribeToPresence(room.code).listen((presences) {
        final s = state;
        if (s is SyncRoomJoined) {
          emit(s.copyWith(participants: presences));
        }
      });

      // Подписываемся на события комнаты (старт воспроизведения хостом)
      await _eventSubscription?.cancel();
      _eventSubscription = repository.subscribeToRoom(room.code).listen((event) {
        if (event.type == SyncEventType.startPlayback) {
          final s = state;
          if (s is SyncRoomJoined) {
            emit(SyncRoomPlaybackStarting(room: s.room, isHost: false));
          }
        }
      });

      emit(SyncRoomJoined(
        room: room,
        isHost: false,
        participants: [
          PeerPresence(
            userId: 'host_${room.code}',
            name: room.hostName,
            avatar: '👑',
            status: PresenceStatus.online,
            lastSeen: DateTime.now(),
            isHost: true,
          ),
          PeerPresence(
            userId: 'guest_${DateTime.now().millisecondsSinceEpoch}',
            name: peerName,
            avatar: '🐱',
            status: PresenceStatus.online,
            lastSeen: DateTime.now(),
            isHost: false,
          ),
        ],
      ));
    } catch (e) {
      emit(SyncRoomError(e.toString().replaceAll('Exception: ', '')));
    }
  }

  /// 3. Хост запускает воспроизведение для всех участников лобби одновременно
  Future<void> startPlaybackForAll() async {
    final s = state;
    if (s is SyncRoomHostWaiting) {
      final code = s.room.code;
      await repository.startPlayback(code);
      final runningRoom = s.room.copyWith(
        status: SyncRoomStatus.connected,
        peerName: s.room.peerName ?? 'Гость',
      );
      emit(SyncRoomPlaybackStarting(room: runningRoom, isHost: true));
    } else if (s is SyncRoomJoined && s.isHost) {
      final code = s.room.code;
      await repository.startPlayback(code);
      final runningRoom = s.room.copyWith(
        status: SyncRoomStatus.connected,
        peerName: s.room.peerName ?? 'Гость',
      );
      emit(SyncRoomPlaybackStarting(room: runningRoom, isHost: true));
    }
  }

  /// Смена тайтла на совпавший в Anime Match и синхронный запуск воспроизведения для комнаты
  Future<void> startMatchedTitlePlayback(AnimeTitle matchedTitle) async {
    final s = state;
    final ep = matchedTitle.episodes.isNotEmpty
        ? matchedTitle.episodes.first
        : const EpisodeItem(episode: 1);

    if (s is SyncRoomHostWaiting) {
      final code = s.room.code;
      final updatedRoom = s.room.copyWith(
        title: matchedTitle,
        episode: ep,
        status: SyncRoomStatus.connected,
        peerName: s.room.peerName ?? 'Гость',
      );
      try {
        await repository.sendChangeEpisode(
          roomCode: code,
          episodeNumber: ep.episode,
          quality: updatedRoom.quality.label,
          sender: s.room.hostName,
        );
        await repository.startPlayback(code);
      } catch (_) {}
      emit(SyncRoomPlaybackStarting(room: updatedRoom, isHost: true));
    } else if (s is SyncRoomJoined) {
      final code = s.room.code;
      final updatedRoom = s.room.copyWith(
        title: matchedTitle,
        episode: ep,
        status: SyncRoomStatus.connected,
      );
      try {
        if (s.isHost) {
          await repository.sendChangeEpisode(
            roomCode: code,
            episodeNumber: ep.episode,
            quality: updatedRoom.quality.label,
            sender: s.room.hostName,
          );
        }
        await repository.startPlayback(code);
      } catch (_) {}
      emit(SyncRoomPlaybackStarting(room: updatedRoom, isHost: s.isHost));
    }
  }

  /// Скопировать код комнаты
  Future<void> copyCode() async {
    final s = state;
    if (s is SyncRoomHostWaiting) {
      try {
        await Clipboard.setData(ClipboardData(text: s.room.code));
      } catch (_) {}
      emit(s.copyWith(codeCopied: true, linkCopied: false));
    }
  }

  /// Скопировать ссылку на комнату
  Future<void> copyShareLink() async {
    final s = state;
    if (s is SyncRoomHostWaiting) {
      try {
        await Clipboard.setData(ClipboardData(text: s.room.shareUrl));
      } catch (_) {}
      emit(s.copyWith(linkCopied: true, codeCopied: false));
    }
  }

  /// Симуляция подключения друга (для быстрого тестирования в одном окне)
  void simulatePeerJoin() {
    final code = _currentRoomCode;
    if (code != null) {
      repository.simulatePeerJoin(code, peerName: 'Сенпай');
      startPlaybackForAll();
    }
  }

  /// Выход из комнаты
  Future<void> leave() async {
    final code = _currentRoomCode;
    if (code != null) {
      await repository.leaveRoom(code);
    }
    await _eventSubscription?.cancel();
    await _presenceSubscription?.cancel();
    _currentRoomCode = null;
    emit(const SyncRoomInitial());
  }

  @override
  Future<void> close() async {
    final code = _currentRoomCode;
    if (code != null) {
      try {
        await repository.leaveRoom(code);
      } catch (_) {}
    }
    await _eventSubscription?.cancel();
    await _presenceSubscription?.cancel();
    if (!kIsWeb) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    return super.close();
  }
}
