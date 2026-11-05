import 'dart:async';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/sync_event.dart';
import '../../domain/entities/sync_protocol.dart';
import '../../domain/entities/sync_room.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../player/domain/entities/player_quality.dart';

class SyncRoomRepositoryImpl implements SyncRoomRepository {
  final Map<String, SyncRoom> _rooms = {};
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
    if (cleaned.startsWith('SP') && cleaned.length >= 6) {
      return 'SP-${cleaned.substring(2, 6)}';
    }
    if (cleaned.length == 6) {
      if (cleaned.startsWith('SP')) {
        return 'SP-${cleaned.substring(2)}';
      }
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3)}';
    }
    if (cleaned.length == 4) {
      return 'SP-$cleaned';
    }
    return rawCode.trim().toUpperCase();
  }

  String _generateRoomCode() {
    final digits = 1000 + _random.nextInt(9000);
    return 'SP-$digits';
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

    // Топик канала Supabase Realtime Broadcast: sync_room:{room_code}
    final topic = 'sync_room:$key';
    final channel = sb.channel(topic);

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
    do {
      code = _generateRoomCode();
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
    _getOrCreateRoomController(code);
    _getOrCreatePacketController(code);
    _getOrCreatePresenceController(code);
    _initSupabaseChannel(code);

    return room;
  }

  @override
  Future<SyncRoom?> getRoom(String code) async {
    final key = normalizeCode(code);
    _initSupabaseChannel(key);
    return _rooms[key];
  }

  @override
  Future<SyncRoom> joinRoom({
    required String code,
    String peerName = 'Друг',
  }) async {
    final key = normalizeCode(code);
    _initSupabaseChannel(key);

    var room = _rooms[key];
    if (room == null) {
      room = SyncRoom(
        code: key,
        title: const AnimeTitle(
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
          episodes: [
            EpisodeItem(
              episode: 1,
              name: 'Эпизод 1',
              hdUrl: 'https://sample.com/720.m3u8',
            ),
          ],
        ),
        episode: const EpisodeItem(
          episode: 1,
          name: 'Эпизод 1',
          hdUrl: 'https://sample.com/720.m3u8',
        ),
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
