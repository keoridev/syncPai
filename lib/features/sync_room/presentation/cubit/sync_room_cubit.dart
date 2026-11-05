import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../domain/entities/sync_event.dart';
import '../../domain/entities/sync_room.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../player/domain/entities/player_quality.dart';
import 'sync_room_state.dart';

class SyncRoomCubit extends Cubit<SyncRoomState> {
  final SyncRoomRepository repository;
  StreamSubscription<SyncEvent>? _eventSubscription;
  String? _currentRoomCode;

  SyncRoomCubit({required this.repository}) : super(const SyncRoomInitial());

  /// 1. Режим хоста: создать комнату
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

      // Подписываемся на события комнаты
      await _eventSubscription?.cancel();
      _eventSubscription = repository.subscribeToRoom(room.code).listen((event) {
        if (event.type == SyncEventType.peerJoined) {
          // Событие подключения второго участника (PEER_JOINED)
          emit(SyncRoomJoined(
            room: room.copyWith(
              peerName: event.senderName,
              status: SyncRoomStatus.connected,
            ),
            isHost: true,
          ));
        }
      });

      emit(SyncRoomHostWaiting(room: room));
    } catch (e) {
      emit(SyncRoomError('Не удалось создать комнату: $e'));
    }
  }

  /// 2. Режим гостя: валидация и подключение по коду
  Future<void> joinRoom(String rawCode) async {
    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty) {
      emit(const SyncRoomError('Введите код комнаты'));
      return;
    }

    emit(const SyncRoomJoining());
    try {
      final room = await repository.joinRoom(code: cleanCode);
      _currentRoomCode = room.code;

      emit(SyncRoomJoined(
        room: room,
        isHost: false,
      ));
    } catch (e) {
      emit(SyncRoomError(e.toString().replaceAll('Exception: ', '')));
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
    }
  }

  /// Выход из комнаты
  Future<void> leave() async {
    final code = _currentRoomCode;
    if (code != null) {
      await repository.leaveRoom(code);
    }
    await _eventSubscription?.cancel();
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

