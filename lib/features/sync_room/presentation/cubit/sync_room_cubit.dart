import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../../core/network/network_status_helper.dart';
import '../../../../core/services/mascot_companion_service.dart';
import '../../data/repositories/sync_room_repository_impl.dart';
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
  bool _isCreatingOrJoiningRoom = false;

  SyncRoomCubit({required this.repository}) : super(const SyncRoomInitial());

  void _safeEmit(SyncRoomState newState) {
    if (!isClosed) {
      emit(newState);
    }
  }

  /// Сбросить ошибку комнаты
  void clearError() {
    if (isClosed) return;
    if (state is SyncRoomError) {
      _safeEmit(const SyncRoomInitial());
    }
  }

  /// 1. Режим хоста: создать комнату и открыть интерактивное лобби
  Future<void> createRoom({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality quality = PlayerQuality.hd,
  }) async {
    if (isClosed || _isCreatingOrJoiningRoom) return;
    _isCreatingOrJoiningRoom = true;

    final hasNet = await NetworkStatusHelper.hasInternet();
    if (!hasNet) {
      _isCreatingOrJoiningRoom = false;
      _safeEmit(const SyncRoomError(
        'Нет подключения к интернету. Для совместного просмотра подключись к сети.',
      ));
      return;
    }

    _safeEmit(const SyncRoomCreating());
    try {
      final room = await repository.createRoom(
        title: title,
        episode: episode,
        quality: quality,
      );
      if (isClosed) return;
      _currentRoomCode = room.code;

      // Подписка на присутствие участников в лобби
      await _presenceSubscription?.cancel();
      if (isClosed) return;
      _presenceSubscription = repository.subscribeToPresence(room.code).listen((presences) {
        if (isClosed) return;
        final s = state;
        if (s is SyncRoomHostWaiting) {
          final guestPresence = presences.where((p) => !p.isHost).firstOrNull;
          _safeEmit(s.copyWith(
            participants: presences,
            room: guestPresence != null
                ? s.room.copyWith(peerName: guestPresence.name, status: SyncRoomStatus.connected)
                : s.room,
          ));
        } else if (s is SyncRoomJoined) {
          _safeEmit(s.copyWith(participants: presences));
        }
      });

      // Подписываемся на события комнаты (подключение гостя, старт плеера, смена аниме)
      await _eventSubscription?.cancel();
      if (isClosed) return;
      _eventSubscription = repository.subscribeToRoom(room.code).listen((event) {
        if (isClosed) return;
        if (event.type == SyncEventType.peerJoined) {
          final s = state;
          if (s is SyncRoomHostWaiting) {
            _safeEmit(s.copyWith(
              room: s.room.copyWith(
                peerName: event.senderName,
                status: SyncRoomStatus.connected,
              ),
            ));
          }
        } else if (event.type == SyncEventType.startPlayback) {
          final s = state;
          if (s is SyncRoomHostWaiting) {
            _safeEmit(SyncRoomPlaybackStarting(room: s.room, isHost: true));
          } else if (s is SyncRoomJoined) {
            _safeEmit(SyncRoomPlaybackStarting(room: s.room, isHost: false));
          }
        } else if (event.type == SyncEventType.animeChanged && event.newTitle != null) {
          final s = state;
          final ep = event.newEpisode ??
              (event.newTitle!.episodes.isNotEmpty
                  ? event.newTitle!.episodes.first
                  : const EpisodeItem(episode: 1));
          if (s is SyncRoomHostWaiting) {
            _safeEmit(s.copyWith(
              room: s.room.copyWith(title: event.newTitle, episode: ep),
            ));
          } else if (s is SyncRoomJoined) {
            _safeEmit(s.copyWith(
              room: s.room.copyWith(title: event.newTitle, episode: ep),
            ));
          }
        } else if (event.type == SyncEventType.roomClosed) {
          _safeEmit(const SyncRoomClosedByHost('Хост закрыл комнату для всех'));
        }
      });

      _safeEmit(SyncRoomHostWaiting(
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
      MascotCompanionService.instance.onWatchPartyJoined();
    } catch (e) {
      if (isClosed) return;
      if (e is PostgrestException) {
        _safeEmit(SyncRoomError(e.message));
      } else {
        _safeEmit(SyncRoomError('Не удалось создать комнату: $e'));
      }
    } finally {
      _isCreatingOrJoiningRoom = false;
    }
  }

  /// 2. Режим гостя: валидация и подключение к лобби по коду
  Future<void> joinRoom(String rawCode, {String peerName = 'Друг'}) async {
    if (isClosed || _isCreatingOrJoiningRoom) return;
    _isCreatingOrJoiningRoom = true;
    final cleanCode = rawCode.trim();
    if (cleanCode.isEmpty) {
      _isCreatingOrJoiningRoom = false;
      _safeEmit(const SyncRoomError('Введите код комнаты'));
      return;
    }

    final hasNet = await NetworkStatusHelper.hasInternet();
    if (!hasNet) {
      _isCreatingOrJoiningRoom = false;
      _safeEmit(const SyncRoomError(
        'Нет подключения к интернету. Для совместного просмотра подключись к сети.',
      ));
      return;
    }

    _safeEmit(const SyncRoomJoining());
    try {
      final room = await repository.joinRoom(code: cleanCode, peerName: peerName);
      if (isClosed) return;
      _currentRoomCode = room.code;

      // Подписка на присутствие участников в лобби
      await _presenceSubscription?.cancel();
      if (isClosed) return;
      _presenceSubscription = repository.subscribeToPresence(room.code).listen((presences) {
        if (isClosed) return;
        final s = state;
        if (s is SyncRoomJoined) {
          _safeEmit(s.copyWith(participants: presences, isHost: false));
        }
      });

      // Подписываемся на события комнаты (старт воспроизведения хостом, смена аниме)
      await _eventSubscription?.cancel();
      if (isClosed) return;
      _eventSubscription = repository.subscribeToRoom(room.code).listen((event) {
        if (isClosed) return;
        if (event.type == SyncEventType.startPlayback) {
          final s = state;
          if (s is SyncRoomJoined) {
            _safeEmit(SyncRoomPlaybackStarting(room: s.room, isHost: false));
          }
        } else if (event.type == SyncEventType.animeChanged && event.newTitle != null) {
          final s = state;
          final ep = event.newEpisode ??
              (event.newTitle!.episodes.isNotEmpty
                  ? event.newTitle!.episodes.first
                  : const EpisodeItem(episode: 1));
          if (s is SyncRoomJoined) {
            _safeEmit(s.copyWith(
              room: s.room.copyWith(title: event.newTitle, episode: ep),
              isHost: false,
            ));
          }
        } else if (event.type == SyncEventType.roomClosed) {
          _safeEmit(const SyncRoomClosedByHost('Хост закрыл комнату для всех'));
        }
      });

      _safeEmit(SyncRoomJoined(
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
      MascotCompanionService.instance.onWatchPartyFriendJoined(peerName);
    } catch (e) {
      if (isClosed) return;
      _safeEmit(SyncRoomError(e.toString().replaceAll('Exception: ', '')));
    } finally {
      _isCreatingOrJoiningRoom = false;
    }
  }

  /// 3. Хост запускает воспроизведение для всех участников лобби одновременно
  Future<void> startPlaybackForAll() async {
    if (isClosed) return;
    final s = state;
    if (s is SyncRoomHostWaiting) {
      final code = s.room.code;
      await repository.startPlayback(code);
      if (isClosed) return;
      final runningRoom = s.room.copyWith(
        status: SyncRoomStatus.connected,
        peerName: s.room.peerName ?? 'Гость',
      );
      _safeEmit(SyncRoomPlaybackStarting(room: runningRoom, isHost: true));
    } else if (s is SyncRoomJoined && s.isHost) {
      final code = s.room.code;
      await repository.startPlayback(code);
      if (isClosed) return;
      final runningRoom = s.room.copyWith(
        status: SyncRoomStatus.connected,
        peerName: s.room.peerName ?? 'Гость',
      );
      _safeEmit(SyncRoomPlaybackStarting(room: runningRoom, isHost: true));
    }
  }

  /// Смена аниме в активном лобби без пересоздания комнаты
  Future<void> changeRoomAnime(AnimeTitle newTitle, {EpisodeItem? episode}) async {
    if (isClosed) return;
    final s = state;
    final ep = episode ??
        (newTitle.episodes.isNotEmpty
            ? newTitle.episodes.first
            : const EpisodeItem(episode: 1));

    if (s is SyncRoomHostWaiting) {
      final code = s.room.code;
      final updatedRoom = s.room.copyWith(title: newTitle, episode: ep);
      _safeEmit(s.copyWith(room: updatedRoom));
      try {
        await repository.changeRoomAnime(
          roomCode: code,
          title: newTitle,
          episode: ep,
          sender: s.room.hostName,
        );
      } catch (_) {}
    } else if (s is SyncRoomJoined) {
      final code = s.room.code;
      final updatedRoom = s.room.copyWith(title: newTitle, episode: ep);
      _safeEmit(s.copyWith(room: updatedRoom));
      try {
        await repository.changeRoomAnime(
          roomCode: code,
          title: newTitle,
          episode: ep,
          sender: s.isHost ? s.room.hostName : (s.room.peerName ?? 'Участник'),
        );
      } catch (_) {}
    }
  }

  /// Смена тайтла на совпавший в Anime Match и синхронный запуск воспроизведения для комнаты
  Future<void> startMatchedTitlePlayback(AnimeTitle matchedTitle) async {
    if (isClosed) return;
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
        await repository.changeRoomAnime(
          roomCode: code,
          title: matchedTitle,
          episode: ep,
          sender: s.room.hostName,
        );
        await repository.startPlayback(code);
      } catch (_) {}
      if (isClosed) return;
      _safeEmit(SyncRoomPlaybackStarting(room: updatedRoom, isHost: true));
    } else if (s is SyncRoomJoined) {
      final code = s.room.code;
      final updatedRoom = s.room.copyWith(
        title: matchedTitle,
        episode: ep,
        status: SyncRoomStatus.connected,
      );
      try {
        if (s.isHost) {
          await repository.changeRoomAnime(
            roomCode: code,
            title: matchedTitle,
            episode: ep,
            sender: s.room.hostName,
          );
        }
        await repository.startPlayback(code);
      } catch (_) {}
      if (isClosed) return;
      _safeEmit(SyncRoomPlaybackStarting(room: updatedRoom, isHost: false));
    }
  }

  /// Скопировать 6-значный PIN-код комнаты
  Future<void> copyCode() async {
    if (isClosed) return;
    final s = state;
    if (s is SyncRoomHostWaiting) {
      try {
        final pinCode = SyncRoomRepositoryImpl.extractPinCode(s.room.code);
        await Clipboard.setData(ClipboardData(text: pinCode));
      } catch (_) {}
      if (isClosed) return;
      _safeEmit(s.copyWith(codeCopied: true, linkCopied: false));
    }
  }

  /// Скопировать ссылку на комнату
  Future<void> copyShareLink() async {
    if (isClosed) return;
    final s = state;
    if (s is SyncRoomHostWaiting) {
      try {
        await Clipboard.setData(ClipboardData(text: s.room.shareUrl));
      } catch (_) {}
      if (isClosed) return;
      _safeEmit(s.copyWith(linkCopied: true, codeCopied: false));
    }
  }

  /// Симуляция подключения друга (для быстрого тестирования в одном окне)
  void simulatePeerJoin() {
    if (isClosed) return;
    final code = _currentRoomCode;
    if (code != null) {
      repository.simulatePeerJoin(code, peerName: 'Ren');
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
    if (!isClosed) {
      _safeEmit(const SyncRoomInitial());
    }
  }

  /// Полное закрытие и удаление комнаты хостом для всех участников
  Future<void> closeRoomForAll() async {
    final code = _currentRoomCode;
    if (code != null) {
      await repository.closeRoomForAll(code);
    }
    await _eventSubscription?.cancel();
    await _presenceSubscription?.cancel();
    _currentRoomCode = null;
    if (!isClosed) {
      _safeEmit(const SyncRoomInitial());
    }
  }

  @override
  Future<void> close() async {
    // Не закрываем комнату в репозитории при переходе в плеер (SyncRoomPlaybackStarting),
    // иначе канал room_$pinCode отпишется перед открытием PlayerScreen!
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
