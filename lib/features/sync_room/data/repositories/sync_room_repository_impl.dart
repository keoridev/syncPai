import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/sync_event.dart';
import '../../domain/entities/sync_protocol.dart';
import '../../domain/entities/sync_room.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../player/domain/entities/player_quality.dart';
import '../../../../app/di/injection.dart';

class SyncRoomRepositoryImpl implements SyncRoomRepository {
  static final Map<String, SyncRoom> _sharedRooms = {};
  Map<String, SyncRoom> get _rooms => _sharedRooms;
  final Map<String, StreamController<SyncEvent>> _roomControllers = {};
  final Map<String, StreamController<SyncPacket>> _packetControllers = {};
  final Map<String, StreamController<List<PeerPresence>>> _presenceControllers = {};
  final Map<String, Map<String, PeerPresence>> _presences = {};
  final Map<String, RealtimeChannel> _supabaseChannels = {};
  final Random _random = Random();

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static String normalizeCode(String rawCode) {
    final cleaned = rawCode.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.startsWith('SP')) {
      final rest = cleaned.substring(2);
      return 'SP-$rest';
    }
    if (cleaned.length == 6) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3)}';
    }
    if (cleaned.length == 4) {
      return 'SP-$cleaned';
    }
    return rawCode.trim().toUpperCase();
  }

  StreamController<SyncEvent> _getOrCreateRoomController(String roomCode) {
    final key = normalizeCode(roomCode);
    return _roomControllers.putIfAbsent(
      key,
      () => StreamController<SyncEvent>.broadcast(),
    );
  }

  StreamController<SyncPacket> _getOrCreatePacketController(String roomCode) {
    final key = normalizeCode(roomCode);
    return _packetControllers.putIfAbsent(
      key,
      () => StreamController<SyncPacket>.broadcast(),
    );
  }

  StreamController<List<PeerPresence>> _getOrCreatePresenceController(String roomCode) {
    final key = normalizeCode(roomCode);
    return _presenceControllers.putIfAbsent(
      key,
      () => StreamController<List<PeerPresence>>.broadcast(),
    );
  }

  void _handleIncomingPacketInternal(String roomKey, SyncPacket packet) {
    if (packet.action == SyncActionTypes.presenceUpdate) {
      final presence = PeerPresence.fromJson(packet.payload);
      final roomPresences = _presences.putIfAbsent(roomKey, () => <String, PeerPresence>{});
      roomPresences[presence.userId] = presence;
      final controller = _presenceControllers[roomKey];
      if (controller != null && !controller.isClosed) {
        controller.add(roomPresences.values.toList());
      }
    } else if (packet.action == SyncActionTypes.roomJoin) {
      final peerName = packet.sender;
      final room = _rooms[roomKey];
      if (room != null) {
        _rooms[roomKey] = room.copyWith(
          peerName: peerName,
          status: SyncRoomStatus.connected,
        );
      }
      final roomPresences = _presences.putIfAbsent(roomKey, () => <String, PeerPresence>{});
      roomPresences[packet.sender] = PeerPresence(
        userId: 'peer_${packet.sender}',
        name: packet.sender,
        avatar: '🐱',
        status: PresenceStatus.online,
        lastSeen: DateTime.now(),
        isHost: false,
      );
      final presController = _presenceControllers[roomKey];
      if (presController != null && !presController.isClosed) {
        presController.add(roomPresences.values.toList());
      }
      final roomController = _roomControllers[roomKey];
      if (roomController != null && !roomController.isClosed) {
        roomController.add(SyncEvent(
          roomCode: roomKey,
          type: SyncEventType.peerJoined,
          senderName: peerName,
          timestamp: DateTime.now(),
        ));
      }
    } else if (packet.action == SyncActionTypes.startPlayback) {
      final roomController = _roomControllers[roomKey];
      if (roomController != null && !roomController.isClosed) {
        roomController.add(SyncEvent(
          roomCode: roomKey,
          type: SyncEventType.startPlayback,
          senderName: packet.sender,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  void _syncSupabasePresence(String roomKey, RealtimeChannel channel) {
    try {
      final state = channel.presenceState();
      final roomPresences = _presences.putIfAbsent(roomKey, () => <String, PeerPresence>{});

      for (final stateItem in state) {
        for (final presence in stateItem.presences) {
          final p = PeerPresence.fromJson(presence.payload);
          roomPresences[p.userId] = p;
        }
      }
      final controller = _presenceControllers[roomKey];
      if (controller != null && !controller.isClosed) {
        controller.add(roomPresences.values.toList());
      }
    } catch (_) {}
  }

  RealtimeChannel? _initSupabaseChannel(String roomCode) {
    final sb = _supabase;
    if (sb == null) return null;

    final key = normalizeCode(roomCode);
    if (_supabaseChannels.containsKey(key)) {
      return _supabaseChannels[key];
    }

    // Топик канала Supabase Realtime: room_$roomId
    final topic = 'room_$key';
    final channel = sb.channel(topic);

    // 1. Postgres Changes: для отслеживания новых участников в таблице rooms
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'rooms',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: key,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          final peerName = newRecord['peer_name'] as String? ?? newRecord['guest_name'] as String?;
          if (peerName != null && peerName.isNotEmpty) {
            final room = _rooms[key];
            if (room != null) {
              _rooms[key] = room.copyWith(
                peerName: peerName,
                status: SyncRoomStatus.connected,
              );
            }
            _getOrCreateRoomController(key).add(SyncEvent(
              type: SyncEventType.peerJoined,
              roomCode: key,
              senderName: peerName,
              timestamp: DateTime.now(),
            ));
          }
        }
      },
    );

    // 2. Broadcast: для быстрой передачи таймкода и состояния плеера (play/pause) по WebSockets
    channel.onBroadcast(
      event: 'sync_player',
      callback: (payload) {
        final time = payload['time'];
        final isPlaying = payload['is_playing'];
        final timeMs = time is num ? (time * 1000).toInt() : (time as int? ?? 0);
        final playingBool = isPlaying is bool ? isPlaying : false;

        final packet = SyncPacket(
          roomCode: key,
          action: SyncActionTypes.controlAction,
          sender: payload['sender'] as String? ?? 'Peer',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'action': playingBool ? 'play' : 'pause',
            'position_ms': timeMs,
            'is_playing': playingBool,
            'time': time,
          },
        );
        _handleIncomingPacketInternal(key, packet);
        _getOrCreatePacketController(key).add(packet);
      },
    );

    channel.onBroadcast(event: 'action', callback: (payload) {
      final packet = SyncPacket.fromJson(payload);
      _handleIncomingPacketInternal(key, packet);
      _getOrCreatePacketController(key).add(packet);
    });

    // Supabase Realtime Presence listeners
    channel.onPresenceSync((_) {
      _syncSupabasePresence(key, channel);
    });
    channel.onPresenceJoin((_) {
      _syncSupabasePresence(key, channel);
    });
    channel.onPresenceLeave((_) {
      _syncSupabasePresence(key, channel);
    });

    channel.subscribe();
    _supabaseChannels[key] = channel;
    return channel;
  }

  @override
  Future<SyncRoom> createRoom({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality quality = PlayerQuality.hd,
    String hostName = 'Хост (Вы)',
  }) async {
    String code;
    String rawPin;
    do {
      rawPin = (100000 + _random.nextInt(900000)).toString();
      code = 'SP-$rawPin';
    } while (_rooms.containsKey(code));

    final room = SyncRoom(
      code: code,
      title: title,
      episode: episode,
      quality: quality,
      hostName: hostName,
      status: SyncRoomStatus.waiting,
      createdAt: DateTime.now(),
    );

    _rooms[code] = room;
    final normCode = normalizeCode(code);
    _rooms[normCode] = room;
    // Регистрируем локально под всеми вариантами ввода: чистый 6-значный PIN и дефис
    _rooms[rawPin] = room;
    final splitPin = '${rawPin.substring(0, 3)}-${rawPin.substring(3)}';
    _rooms[splitPin] = room;
    _rooms['SP$rawPin'] = room;

    _getOrCreateRoomController(code);
    _getOrCreatePacketController(code);
    _getOrCreatePresenceController(code);
    _initSupabaseChannel(code);

    // Запись в Supabase таблицу rooms
    final client = _supabase;
    if (client != null) {
      try {
        await client.from('rooms').upsert({
          'id': code,
          'host_name': hostName,
          'status': 'waiting',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Supabase create room error: $e');
        try {
          await client.from('rooms').upsert({
            'id': code,
            'status': 'waiting',
          });
        } catch (e2) {
          debugPrint('Supabase create room fallback error: $e2');
        }
      }
    }

    return room;
  }

  @override
  Future<SyncRoom?> getRoom(String code) async {
    final key = normalizeCode(code);
    _initSupabaseChannel(key);
    final cleanedDigits = code.replaceAll(RegExp(r'[^0-9]'), '');
    return _rooms[key] ?? _rooms[code] ?? (_rooms[cleanedDigits]);
  }

  @override
  Future<bool> validateRoomExists(String code) async {
    final key = normalizeCode(code);
    if (key.isEmpty) return false;

    final cleanedDigits = code.replaceAll(RegExp(r'[^0-9]'), '');

    // 1. Проверяем в локальной памяти (активная сессия)
    final localRoom = _rooms[key] ?? _rooms[code] ?? (_rooms[cleanedDigits]);
    if (localRoom != null) {
      return localRoom.status != SyncRoomStatus.closed;
    }

    // 2. Проверяем в таблице Supabase rooms
    final client = _supabase;
    if (client != null) {
      try {
        final queryOr = [
          'id.eq.$key',
          if (code != key) 'id.eq.$code',
          if (cleanedDigits.isNotEmpty) 'id.eq.SP-$cleanedDigits',
          if (cleanedDigits.isNotEmpty) 'id.eq.$cleanedDigits',
        ].join(',');

        final res = await client
            .from('rooms')
            .select('id, status')
            .or(queryOr)
            .maybeSingle();

        if (res == null) return false;
        final status = res['status'] as String?;
        if (status == 'closed') return false;
        return true;
      } catch (e) {
        debugPrint('Supabase room validation check: $e');
      }
    }

    // Тестовая комната для тестирования и демо
    if (key == 'SP4821' || key == 'SP-4821') {
      return true;
    }

    return false;
  }

  @override
  Future<SyncRoom> joinRoom({
    required String code,
    String peerName = 'Друг',
  }) async {
    final key = normalizeCode(code);
    final exists = await validateRoomExists(key);
    if (!exists) {
      throw Exception('Комната с кодом $key не найдена или уже закрыта');
    }

    _initSupabaseChannel(key);

    final cleanedDigits = code.replaceAll(RegExp(r'[^0-9]'), '');
    var room = _rooms[key] ?? _rooms[code] ?? (_rooms[cleanedDigits]);
    if (room == null) {
      AnimeTitle? resolvedTitle;
      EpisodeItem? resolvedEpisode;

      if (getIt.isRegistered<CatalogRepository>()) {
        try {
          final catalog = getIt<CatalogRepository>();
          List<AnimeTitle> candidates = [];
          if (key == 'SP4821' || key.contains('4821')) {
            candidates = await catalog.searchTitles('Магическая битва', limit: 1);
          }
          if (candidates.isEmpty) {
            candidates = await catalog.getUpdates();
          }
          if (candidates.isNotEmpty) {
            final cand = candidates.first;
            resolvedTitle = await catalog.getTitleDetails(id: cand.id, code: cand.code);
            if (resolvedTitle.episodes.isNotEmpty) {
              resolvedEpisode = resolvedTitle.episodes.firstWhere(
                (e) => (key == 'SP4821' || key.contains('4821')) ? e.episode == 4 : true,
                orElse: () => resolvedTitle!.episodes.first,
              );
            }
          }
        } catch (_) {}
      }

      final safeTitle = resolvedTitle ?? const AnimeTitle(
        id: 0,
        code: 'sync_title',
        russianTitle: 'Тайтл совместного просмотра',
        englishTitle: 'Watch Party',
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        episodesTotal: 12,
        latestEpisode: 1,
        season: '',
        year: 2024,
        genres: ['Аниме'],
        description: '',
        status: 'Онгоинг',
        playerHost: null,
      );

      final safeEpisode = resolvedEpisode ?? (safeTitle.episodes.isNotEmpty
          ? safeTitle.episodes.first
          : const EpisodeItem(
              episode: 1,
              name: 'Эпизод 1',
            ));

      room = SyncRoom(
        code: key,
        title: safeTitle,
        episode: safeEpisode,
        quality: PlayerQuality.hd,
        hostName: 'Хост',
        peerName: peerName,
        status: SyncRoomStatus.connected,
        createdAt: DateTime.now(),
      );
      _rooms[key] = room;
    } else {
      room = room.copyWith(
        peerName: peerName,
        status: SyncRoomStatus.connected,
      );
      _rooms[key] = room;
    }

    emitEvent(SyncEvent(
      roomCode: key,
      type: SyncEventType.peerJoined,
      senderName: peerName,
      timestamp: DateTime.now(),
    ));

    await sendPacket(SyncPacket(
      action: SyncActionTypes.roomJoin,
      sender: peerName,
      roomCode: key,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'user_name': peerName,
        'is_host': false,
      },
    ));

    await updatePresence(
      roomCode: key,
      presence: PeerPresence(
        userId: 'guest_${DateTime.now().millisecondsSinceEpoch}',
        name: peerName,
        avatar: '🐱',
        status: PresenceStatus.online,
        lastSeen: DateTime.now(),
        isHost: false,
      ),
    );

    final client = _supabase;
    if (client != null) {
      try {
        final queryOr = [
          'id.eq.$key',
          if (code != key) 'id.eq.$code',
          if (cleanedDigits.isNotEmpty) 'id.eq.SP-$cleanedDigits',
          if (cleanedDigits.isNotEmpty) 'id.eq.$cleanedDigits',
        ].join(',');
        await client.from('rooms').update({
          'peer_name': peerName,
          'guest_name': peerName,
          'status': 'connected',
        }).or(queryOr);
      } catch (e) {
        debugPrint('Supabase joinRoom update: $e');
      }
    }

    return room;
  }

  @override
  Stream<SyncEvent> subscribeToRoom(String roomCode) {
    return _getOrCreateRoomController(roomCode).stream;
  }

  @override
  Stream<SyncPacket> subscribeToPackets(String roomCode) {
    final key = normalizeCode(roomCode);
    _initSupabaseChannel(key);
    return _getOrCreatePacketController(key).stream;
  }

  @override
  Stream<List<PeerPresence>> subscribeToPresence(String roomCode) {
    final key = normalizeCode(roomCode);
    _initSupabaseChannel(key);
    final controller = _getOrCreatePresenceController(key);
    final current = _presences[key]?.values.toList() ?? [];
    if (current.isNotEmpty) {
      scheduleMicrotask(() {
        if (!controller.isClosed) controller.add(current);
      });
    }
    return controller.stream;
  }

  @override
  Future<void> updatePresence({
    required String roomCode,
    required PeerPresence presence,
  }) async {
    final key = normalizeCode(roomCode);
    final roomPresences = _presences.putIfAbsent(key, () => <String, PeerPresence>{});
    roomPresences[presence.userId] = presence;

    final controller = _presenceControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(roomPresences.values.toList());
    }

    // Мгновенный Broadcast для надежности < 50 мс
    await sendPacket(SyncPacket(
      action: SyncActionTypes.presenceUpdate,
      sender: presence.name,
      roomCode: key,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: presence.toJson(),
    ));

    // Supabase Presence tracking
    final channel = _supabaseChannels[key];
    if (channel != null) {
      try {
        await channel.track(presence.toJson());
      } catch (_) {}
    }
  }

  @override
  Future<void> sendPacket(SyncPacket packet) async {
    final key = normalizeCode(packet.roomCode);

    // 1. Supabase Realtime Broadcast
    final channel = _supabaseChannels[key];
    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'action',
          payload: packet.toJson(),
        );
      } catch (_) {}
    }

    // 2. Локальный контроллер для мгновенного отклика
    _handleIncomingPacketInternal(key, packet);
    final controller = _packetControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(packet);
    }
  }

  @override
  Future<void> sendHeartbeat({
    required String roomCode,
    required int positionMs,
    required bool isPlaying,
    required double rate,
    required String sender,
  }) {
    return sendPacket(SyncPacket(
      action: SyncActionTypes.heartbeat,
      sender: sender,
      roomCode: roomCode,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'position_ms': positionMs,
        'is_playing': isPlaying,
        'rate': rate,
      },
    ));
  }

  @override
  Future<void> sendControlAction({
    required String roomCode,
    required String action,
    required int positionMs,
    required String sender,
  }) {
    return sendPacket(SyncPacket(
      action: SyncActionTypes.controlAction,
      sender: sender,
      roomCode: roomCode,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'control_action': action,
        'position_ms': positionMs,
      },
    ));
  }

  @override
  Future<void> sendSyncEvent({
    required String roomCode,
    required double time,
    required bool isPlaying,
  }) async {
    final key = normalizeCode(roomCode);
    final channel = _supabaseChannels[key] ?? _initSupabaseChannel(key);
    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'sync_player',
          payload: {
            'time': time,
            'is_playing': isPlaying,
          },
        );
      } catch (e) {
        debugPrint('Supabase sendSyncEvent broadcast error: $e');
      }
    }

    _getOrCreatePacketController(key).add(SyncPacket(
      roomCode: key,
      action: SyncActionTypes.controlAction,
      sender: 'Self',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'action': isPlaying ? 'play' : 'pause',
        'position_ms': (time * 1000).toInt(),
        'is_playing': isPlaying,
        'time': time,
      },
    ));
  }

  @override
  Future<void> sendBufferState({
    required String roomCode,
    required bool isBuffering,
    required String sender,
  }) {
    return sendPacket(SyncPacket(
      action: isBuffering ? SyncActionTypes.bufferWait : SyncActionTypes.bufferReady,
      sender: sender,
      roomCode: roomCode,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'is_buffering': isBuffering,
        'user_name': sender,
      },
    ));
  }

  @override
  Future<void> sendReaction({
    required String roomCode,
    required String emoji,
    required String sender,
  }) {
    return sendPacket(SyncPacket(
      action: SyncActionTypes.reaction,
      sender: sender,
      roomCode: roomCode,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'emoji': emoji,
        'id': '${DateTime.now().microsecondsSinceEpoch}',
      },
    ));
  }

  @override
  Future<void> sendChatMessage({
    required String roomCode,
    required String text,
    required String sender,
    bool isHost = false,
  }) {
    return sendPacket(SyncPacket(
      action: SyncActionTypes.chatMessage,
      sender: sender,
      roomCode: roomCode,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'id': '${DateTime.now().microsecondsSinceEpoch}',
        'text': text,
        'is_host': isHost,
      },
    ));
  }

  @override
  Future<void> sendRequestPause({
    required String roomCode,
    required String sender,
  }) {
    return sendPacket(SyncPacket(
      action: SyncActionTypes.requestPause,
      sender: sender,
      roomCode: roomCode,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {'user_name': sender},
    ));
  }

  @override
  Future<void> sendChangeEpisode({
    required String roomCode,
    required int episodeNumber,
    required String quality,
    required String sender,
  }) async {
    final key = normalizeCode(roomCode);
    final room = _rooms[key];
    if (room != null) {
      final nextEp = room.title.episodes.firstWhere(
        (e) => e.episode == episodeNumber,
        orElse: () => room.episode,
      );
      _rooms[key] = room.copyWith(episode: nextEp);
    }

    await sendPacket(SyncPacket(
      action: SyncActionTypes.changeEpisode,
      sender: sender,
      roomCode: key,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'episode': episodeNumber,
        'quality': quality,
      },
    ));
  }

  @override
  Future<void> sendQuickPhrase({
    required String roomCode,
    required String phrase,
    String? emoji,
    required String sender,
  }) async {
    final key = normalizeCode(roomCode);
    final toast = QuickPhraseToast(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      sender: sender,
      phrase: phrase,
      emoji: emoji,
      timestamp: DateTime.now(),
    );

    await sendPacket(SyncPacket(
      action: SyncActionTypes.quickPhrase,
      sender: sender,
      roomCode: key,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: toast.toJson(),
    ));
  }

  @override
  void emitEvent(SyncEvent event) {
    final key = normalizeCode(event.roomCode);
    final controller = _roomControllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(event);
    }
  }

  @override
  Future<void> startPlayback(String roomCode) async {
    final key = normalizeCode(roomCode);
    final senderName = _rooms[key]?.hostName ?? 'Хост';
    await sendPacket(SyncPacket(
      action: SyncActionTypes.startPlayback,
      sender: senderName,
      roomCode: key,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {},
    ));
    emitEvent(SyncEvent(
      roomCode: key,
      type: SyncEventType.startPlayback,
      senderName: senderName,
      timestamp: DateTime.now(),
    ));
  }

  @override
  Future<void> leaveRoom(String roomCode) async {
    final key = normalizeCode(roomCode);
    emitEvent(SyncEvent(
      roomCode: key,
      type: SyncEventType.peerLeft,
      senderName: 'Участник',
      timestamp: DateTime.now(),
    ));

    final sbChannel = _supabaseChannels.remove(key);
    if (sbChannel != null && _supabase != null) {
      try {
        await _supabase!.removeChannel(sbChannel);
      } catch (_) {}
    }

    _presences.remove(key);
    final presenceController = _presenceControllers.remove(key);
    await presenceController?.close();

    _rooms.remove(key);
    final controller = _roomControllers.remove(key);
    await controller?.close();

    final packetController = _packetControllers.remove(key);
    await packetController?.close();
  }

  @override
  void simulatePeerJoin(String roomCode, {String peerName = 'Сенпай'}) {
    final key = normalizeCode(roomCode);
    final existing = _rooms[key];
    if (existing != null) {
      final updated = existing.copyWith(
        peerName: peerName,
        status: SyncRoomStatus.connected,
      );
      _rooms[key] = updated;
    }

    emitEvent(SyncEvent(
      roomCode: key,
      type: SyncEventType.peerJoined,
      senderName: peerName,
      timestamp: DateTime.now(),
    ));

    sendPacket(SyncPacket(
      action: SyncActionTypes.roomJoin,
      sender: peerName,
      roomCode: key,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {'user_name': peerName, 'is_host': false},
    ));

    updatePresence(
      roomCode: key,
      presence: PeerPresence(
        userId: 'simulated_peer',
        name: peerName,
        avatar: '🐱',
        status: PresenceStatus.online,
        lastSeen: DateTime.now(),
        isHost: false,
      ),
    );
  }
}
