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
  final Map<String, List<void Function(double timeSec, bool isPlaying, int episodeIndex)>>
      _playbackSyncCallbacks = {};
  final Random _random = Random();

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Извлекает чистый 6-значный PIN-код для таблицы `public.rooms` и канала `room_$pinCode`
  static String extractPinCode(String rawCode) {
    final digits = rawCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty) {
      return digits;
    }
    return rawCode.trim().toUpperCase();
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
    final key = extractPinCode(roomCode);
    return _roomControllers.putIfAbsent(
      key,
      () => StreamController<SyncEvent>.broadcast(),
    );
  }

  StreamController<SyncPacket> _getOrCreatePacketController(String roomCode) {
    final key = extractPinCode(roomCode);
    return _packetControllers.putIfAbsent(
      key,
      () => StreamController<SyncPacket>.broadcast(),
    );
  }

  StreamController<List<PeerPresence>> _getOrCreatePresenceController(String roomCode) {
    final key = extractPinCode(roomCode);
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

    final pinKey = extractPinCode(roomCode);
    if (_supabaseChannels.containsKey(pinKey)) {
      return _supabaseChannels[pinKey];
    }

    // Топик канала Supabase Realtime: room_$pinCode
    final topic = 'room_$pinKey';
    final channel = sb.channel(topic);

    // 1. Postgres Changes: для отслеживания обновлений состояния в таблице public.rooms
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'rooms',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: pinKey,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          final isPlaying = newRecord['is_playing'] as bool?;
          final currentTimeSec = (newRecord['current_time_sec'] as num?)?.toDouble();
          final episodeIndex = (newRecord['episode_index'] as num?)?.toInt();

          if (isPlaying != null || currentTimeSec != null || episodeIndex != null) {
            final time = currentTimeSec ?? 0.0;
            final playingBool = isPlaying ?? false;
            final ep = episodeIndex ?? 0;

            final callbacks = _playbackSyncCallbacks[pinKey];
            if (callbacks != null) {
              for (final cb in List.of(callbacks)) {
                cb(time, playingBool, ep);
              }
            }
          }
        }
      },
    );

    // 2. Broadcast: основной канал синхронизации плеера (playback_sync) по ТЗ
    channel.onBroadcast(
      event: 'playback_sync',
      callback: (payload) {
        final time = (payload['time'] as num?)?.toDouble() ?? 0.0;
        final isPlaying = payload['is_playing'] as bool? ?? false;
        final episode = (payload['episode'] as num?)?.toInt() ?? 0;
        final timeMs = (time * 1000).toInt();

        final callbacks = _playbackSyncCallbacks[pinKey];
        if (callbacks != null) {
          for (final cb in List.of(callbacks)) {
            cb(time, isPlaying, episode);
          }
        }

        final packet = SyncPacket(
          roomCode: pinKey,
          action: SyncActionTypes.controlAction,
          sender: payload['sender'] as String? ?? 'Peer',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'action': isPlaying ? 'play' : 'pause',
            'control_action': isPlaying ? 'play' : 'pause',
            'position_ms': timeMs,
            'is_playing': isPlaying,
            'time': time,
            'episode': episode,
          },
        );
        _handleIncomingPacketInternal(pinKey, packet);
        _getOrCreatePacketController(pinKey).add(packet);
      },
    );

    // 3. Обратная совместимость для sync_player
    channel.onBroadcast(
      event: 'sync_player',
      callback: (payload) {
        final time = (payload['time'] as num?)?.toDouble() ?? 0.0;
        final isPlaying = payload['is_playing'] as bool? ?? false;
        final episode = (payload['episode'] as num?)?.toInt() ?? 0;
        final timeMs = (time * 1000).toInt();

        final callbacks = _playbackSyncCallbacks[pinKey];
        if (callbacks != null) {
          for (final cb in List.of(callbacks)) {
            cb(time, isPlaying, episode);
          }
        }

        final packet = SyncPacket(
          roomCode: pinKey,
          action: SyncActionTypes.controlAction,
          sender: payload['sender'] as String? ?? 'Peer',
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'action': isPlaying ? 'play' : 'pause',
            'control_action': isPlaying ? 'play' : 'pause',
            'position_ms': timeMs,
            'is_playing': isPlaying,
            'time': time,
            'episode': episode,
          },
        );
        _handleIncomingPacketInternal(pinKey, packet);
        _getOrCreatePacketController(pinKey).add(packet);
      },
    );

    channel.onBroadcast(event: 'action', callback: (payload) {
      final packet = SyncPacket.fromJson(payload);
      _handleIncomingPacketInternal(pinKey, packet);
      _getOrCreatePacketController(pinKey).add(packet);
    });

    // Supabase Realtime Presence listeners
    channel.onPresenceSync((_) {
      _syncSupabasePresence(pinKey, channel);
    });
    channel.onPresenceJoin((_) {
      _syncSupabasePresence(pinKey, channel);
    });
    channel.onPresenceLeave((_) {
      _syncSupabasePresence(pinKey, channel);
    });

    channel.subscribe();
    _supabaseChannels[pinKey] = channel;
    return channel;
  }

  /// Прямое создание комнаты в таблице `public.rooms` по схеме БД
  Future<String?> createRoomRecord({
    required String animeId,
    required String animeTitle,
    required String posterUrl,
    int episodeIndex = 0,
    String? customPinCode,
  }) async {
    try {
      final client = Supabase.instance.client;
      var currentUser = client.auth.currentUser;
      if (currentUser == null) {
        try {
          final authRes = await client.auth.signInAnonymously();
          currentUser = authRes.user;
        } catch (authErr) {
          debugPrint('[WatchTogether] Анонимная авторизация пропущена: $authErr');
        }
      }

      final pinCode = customPinCode ?? (100000 + _random.nextInt(900000)).toString();

      final payload = <String, dynamic>{
        'id': pinCode,
        'anime_id': animeId,
        'anime_title': animeTitle,
        'poster_url': posterUrl,
        'episode_index': episodeIndex,
        'current_time_sec': 0.0,
        'is_playing': false,
        if (currentUser != null && !currentUser.isAnonymous) 'host_id': currentUser.id,
      };

      try {
        await client.from('rooms').upsert(payload);
      } catch (upsertErr) {
        // Fallback без foreign key host_id (для анонимных пользователей)
        final fallbackPayload = Map<String, dynamic>.from(payload)..remove('host_id');
        await client.from('rooms').upsert(fallbackPayload);
      }

      // ignore: avoid_print
      print('[WatchTogether] Комната успешно создана в Supabase: $pinCode');
      return pinCode;
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[WatchTogether] Ошибка создания комнаты: $e');
      // ignore: avoid_print
      print(stackTrace);
      return null;
    }
  }

  /// Прямое чтение комнаты по PIN-коду из `public.rooms`
  Future<Map<String, dynamic>?> joinRoomByPin(String pinCode) async {
    try {
      final cleanPin = extractPinCode(pinCode);
      final spCode = 'SP-$cleanPin';
      final queryOr = 'id.eq.$cleanPin,id.eq.$spCode,id.eq.$pinCode';

      final roomData = await Supabase.instance.client
          .from('rooms')
          .select()
          .or(queryOr)
          .maybeSingle();

      if (roomData == null) {
        throw Exception('Комната с кодом $pinCode не найдена');
      }

      // ignore: avoid_print
      print('[WatchTogether] Успешное подключение к комнате: $pinCode');
      return roomData;
    } catch (e) {
      // ignore: avoid_print
      print('[WatchTogether] Ошибка входа в комнату: $e');
      rethrow;
    }
  }

  @override
  Future<SyncRoom> createRoom({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality quality = PlayerQuality.hd,
    String hostName = 'Хост (Вы)',
  }) async {
    String code;
    String pinCode;
    do {
      pinCode = (100000 + _random.nextInt(900000)).toString();
      code = 'SP-$pinCode';
    } while (_rooms.containsKey(pinCode) || _rooms.containsKey(code));

    final room = SyncRoom(
      code: code,
      title: title,
      episode: episode,
      quality: quality,
      hostName: hostName,
      status: SyncRoomStatus.waiting,
      createdAt: DateTime.now(),
    );

    _rooms[pinCode] = room;
    _rooms[code] = room;
    final normCode = normalizeCode(code);
    _rooms[normCode] = room;
    final splitPin = '${pinCode.substring(0, 3)}-${pinCode.substring(3)}';
    _rooms[splitPin] = room;
    _rooms['SP$pinCode'] = room;

    _getOrCreateRoomController(pinCode);
    _getOrCreatePacketController(pinCode);
    _getOrCreatePresenceController(pinCode);
    _initSupabaseChannel(pinCode);

    // Запись в таблицу public.rooms строго по схеме БД:
    // id (text PK), anime_id (text NOT NULL), anime_title (text), poster_url (text),
    // episode_index (int4), current_time_sec (float8), is_playing (bool), host_id (uuid nullable)
    final client = _supabase;
    if (client != null) {
      final posterUrl = title.posterOriginal.isNotEmpty
          ? title.posterOriginal
          : (title.posterMedium.isNotEmpty ? title.posterMedium : title.posterSmall);

      await createRoomRecord(
        animeId: title.id.toString(),
        animeTitle: title.displayTitle,
        posterUrl: posterUrl,
        episodeIndex: episode.episode,
        customPinCode: pinCode,
      );
    }

    // Инициализация Supabase Presence для хоста
    final channel = _supabaseChannels[pinCode];
    if (channel != null) {
      try {
        await channel.track({
          'user_id': 'host_$pinCode',
          'name': hostName,
          'avatar': '👑',
          'status': 'online',
          'is_host': true,
          'last_seen': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {}
    }

    return room;
  }

  @override
  Future<SyncRoom?> getRoom(String code) async {
    final pinKey = extractPinCode(code);
    final normKey = normalizeCode(code);
    _initSupabaseChannel(pinKey);
    return _rooms[pinKey] ?? _rooms[normKey] ?? _rooms[code];
  }

  @override
  Future<bool> validateRoomExists(String code) async {
    final cleanPin = extractPinCode(code);
    final normKey = normalizeCode(code);
    if (cleanPin.isEmpty && normKey.isEmpty) return false;

    // 1. Проверяем в локальной памяти (активная сессия)
    final localRoom = _rooms[cleanPin] ?? _rooms[normKey] ?? _rooms[code];
    if (localRoom != null) {
      return localRoom.status != SyncRoomStatus.closed;
    }

    // 2. Проверяем в таблице Supabase public.rooms по PIN-коду
    final client = _supabase;
    if (client != null) {
      try {
        final spCode = 'SP-$cleanPin';
        final queryOr = 'id.eq.$cleanPin,id.eq.$spCode,id.eq.$code,id.eq.$normKey';

        final roomData = await client
            .from('rooms')
            .select()
            .or(queryOr)
            .maybeSingle();

        if (roomData != null) {
          return true;
        }
      } catch (e) {
        debugPrint('[WatchTogether] Supabase room validation error: $e');
      }
    }

    // Тестовая демо-комната
    if (cleanPin == '4821' || normKey == 'SP-4821' || normKey == 'SP4821') {
      return true;
    }

    return false;
  }

  @override
  Future<SyncRoom> joinRoom({
    required String code,
    String peerName = 'Друг',
  }) async {
    final cleanPin = extractPinCode(code);
    final normKey = normalizeCode(code);

    // 1. Пробуем прочитать комнату из таблицы public.rooms по PIN-коду
    Map<String, dynamic>? roomData;
    final client = _supabase;
    if (client != null) {
      try {
        roomData = await joinRoomByPin(cleanPin);
      } catch (_) {
        roomData = null;
      }
    }

    var room = _rooms[cleanPin] ?? _rooms[normKey] ?? _rooms[code];
    final isDemoRoom = cleanPin == '4821' || normKey == 'SP-4821' || normKey == 'SP4821';

    if (roomData == null && room == null && !isDemoRoom) {
      throw Exception('Комната с кодом $cleanPin не найдена');
    }

    _initSupabaseChannel(cleanPin);

    if (room == null) {
      final int? remoteTitleId = int.tryParse(roomData?['anime_id']?.toString() ?? '');
      final String? remoteTitleName = roomData?['anime_title'] as String?;
      final String? remotePosterUrl = roomData?['poster_url'] as String?;
      final int? remoteEpisode = (roomData?['episode_index'] as num?)?.toInt();

      AnimeTitle? resolvedTitle;
      EpisodeItem? resolvedEpisode;

      // Попытка подгрузить полные детали тайтла из каталога
      if (getIt.isRegistered<CatalogRepository>()) {
        try {
          final catalog = getIt<CatalogRepository>();
          List<AnimeTitle> candidates = [];

          if (remoteTitleId != null && remoteTitleId > 0) {
            try {
              resolvedTitle = await catalog.getTitleDetails(id: remoteTitleId, code: '');
            } catch (_) {}
          }

          if (resolvedTitle == null && remoteTitleName != null && remoteTitleName.isNotEmpty) {
            candidates = await catalog.searchTitles(remoteTitleName, limit: 1);
          }

          if (resolvedTitle == null && candidates.isEmpty && isDemoRoom) {
            candidates = await catalog.searchTitles('Магическая битва', limit: 1);
          }
          if (resolvedTitle == null && candidates.isEmpty) {
            candidates = await catalog.getUpdates();
          }
          if (resolvedTitle == null && candidates.isNotEmpty) {
            final cand = candidates.first;
            resolvedTitle = await catalog.getTitleDetails(id: cand.id, code: cand.code);
          }
          if (resolvedTitle != null && resolvedTitle.episodes.isNotEmpty) {
            final targetEp = (remoteEpisode != null && remoteEpisode > 0)
                ? remoteEpisode
                : (isDemoRoom ? 4 : 1);
            resolvedEpisode = resolvedTitle.episodes.firstWhere(
              (e) => e.episode == targetEp,
              orElse: () => resolvedTitle!.episodes.first,
            );
          }
        } catch (_) {}
      }

      final safePoster = remotePosterUrl ?? '';
      final safeTitle = resolvedTitle ?? AnimeTitle(
        id: remoteTitleId ?? 0,
        code: 'sync_title',
        russianTitle: remoteTitleName ?? 'Тайтл совместного просмотра',
        englishTitle: 'Watch Party',
        posterSmall: safePoster,
        posterMedium: safePoster,
        posterOriginal: safePoster,
        episodesTotal: 12,
        latestEpisode: (remoteEpisode != null && remoteEpisode > 0) ? remoteEpisode : 1,
        season: '',
        year: 2024,
        genres: const ['Аниме'],
        description: '',
        status: 'Онгоинг',
        playerHost: null,
      );

      final targetEpNum = (remoteEpisode != null && remoteEpisode > 0) ? remoteEpisode : 1;
      final safeEpisode = resolvedEpisode ?? (safeTitle.episodes.isNotEmpty
          ? safeTitle.episodes.first
          : EpisodeItem(
              episode: targetEpNum,
              name: 'Эпизод $targetEpNum',
            ));

      room = SyncRoom(
        code: 'SP-$cleanPin',
        title: safeTitle,
        episode: safeEpisode,
        quality: PlayerQuality.hd,
        hostName: 'Хост',
        peerName: peerName,
        status: SyncRoomStatus.connected,
        createdAt: DateTime.now(),
      );
      _rooms[cleanPin] = room;
      _rooms[normKey] = room;
      _rooms['SP-$cleanPin'] = room;
    } else {
      room = room.copyWith(
        peerName: peerName,
        status: SyncRoomStatus.connected,
      );
      _rooms[cleanPin] = room;
      _rooms[normKey] = room;
      _rooms[room.code] = room;
    }

    emitEvent(SyncEvent(
      roomCode: cleanPin,
      type: SyncEventType.peerJoined,
      senderName: peerName,
      timestamp: DateTime.now(),
    ));

    await sendPacket(SyncPacket(
      action: SyncActionTypes.roomJoin,
      sender: peerName,
      roomCode: cleanPin,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'user_name': peerName,
        'is_host': false,
      },
    ));

    await updatePresence(
      roomCode: cleanPin,
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
    final pinKey = extractPinCode(roomCode);
    _initSupabaseChannel(pinKey);
    return _getOrCreateRoomController(pinKey).stream;
  }

  @override
  Stream<SyncPacket> subscribeToPackets(String roomCode) {
    final pinKey = extractPinCode(roomCode);
    _initSupabaseChannel(pinKey);
    return _getOrCreatePacketController(pinKey).stream;
  }

  @override
  Stream<List<PeerPresence>> subscribeToPresence(String roomCode) {
    final pinKey = extractPinCode(roomCode);
    _initSupabaseChannel(pinKey);
    final controller = _getOrCreatePresenceController(pinKey);
    final current = _presences[pinKey]?.values.toList() ?? [];
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
    final pinKey = extractPinCode(roomCode);
    final roomPresences = _presences.putIfAbsent(pinKey, () => <String, PeerPresence>{});
    roomPresences[presence.userId] = presence;

    final controller = _presenceControllers[pinKey];
    if (controller != null && !controller.isClosed) {
      controller.add(roomPresences.values.toList());
    }

    // Мгновенный Broadcast для надежности < 50 мс
    await sendPacket(SyncPacket(
      action: SyncActionTypes.presenceUpdate,
      sender: presence.name,
      roomCode: pinKey,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: presence.toJson(),
    ));

    // Supabase Presence tracking
    final channel = _supabaseChannels[pinKey];
    if (channel != null) {
      try {
        await channel.track(presence.toJson());
      } catch (_) {}
    }
  }

  @override
  Future<void> sendPacket(SyncPacket packet) async {
    final pinKey = extractPinCode(packet.roomCode);

    // 1. Supabase Realtime Broadcast
    final channel = _supabaseChannels[pinKey];
    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'action',
          payload: packet.toJson(),
        );
      } catch (_) {}
    }

    // 2. Локальный контроллер для мгновенного отклика
    _handleIncomingPacketInternal(pinKey, packet);
    final controller = _packetControllers[pinKey];
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
    final pinKey = extractPinCode(roomCode);
    final currentEp = _rooms[pinKey]?.episode.episode ?? 0;
    await broadcastPlayback(
      roomCode: pinKey,
      time: time,
      isPlaying: isPlaying,
      episode: currentEp,
    );
  }

  @override
  Future<void> broadcastPlayback({
    required String roomCode,
    required double time,
    required bool isPlaying,
    required int episode,
  }) async {
    final pinKey = extractPinCode(roomCode);
    final channel = _supabaseChannels[pinKey] ?? _initSupabaseChannel(pinKey);
    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'playback_sync',
          payload: {
            'time': time,
            'is_playing': isPlaying,
            'episode': episode,
          },
        );
      } catch (e) {
        debugPrint('[WatchTogether] broadcastPlayback error: $e');
      }
    }

    // Синхронно обновляем состояние в таблице public.rooms
    final client = _supabase;
    if (client != null) {
      try {
        await client.from('rooms').update({
          'current_time_sec': time,
          'is_playing': isPlaying,
          if (episode > 0) 'episode_index': episode,
        }).eq('id', pinKey);
      } catch (_) {}
    }

    _getOrCreatePacketController(pinKey).add(SyncPacket(
      roomCode: pinKey,
      action: SyncActionTypes.controlAction,
      sender: 'Self',
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'action': isPlaying ? 'play' : 'pause',
        'control_action': isPlaying ? 'play' : 'pause',
        'position_ms': (time * 1000).toInt(),
        'is_playing': isPlaying,
        'time': time,
        'episode': episode,
      },
    ));
  }

  @override
  void subscribeToPlaybackSync(
    String pinCode, {
    required void Function(double timeSec, bool isPlaying, int episodeIndex) onSyncReceived,
  }) {
    final cleanPin = extractPinCode(pinCode);
    _initSupabaseChannel(cleanPin);
    final list = _playbackSyncCallbacks.putIfAbsent(cleanPin, () => []);
    list.add(onSyncReceived);
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
    final pinKey = extractPinCode(roomCode);
    final room = _rooms[pinKey];
    if (room != null) {
      final nextEp = room.title.episodes.firstWhere(
        (e) => e.episode == episodeNumber,
        orElse: () => room.episode,
      );
      final updated = room.copyWith(episode: nextEp);
      _rooms[pinKey] = updated;
      _rooms[room.code] = updated;
    }

    await broadcastPlayback(
      roomCode: pinKey,
      time: 0.0,
      isPlaying: true,
      episode: episodeNumber,
    );

    await sendPacket(SyncPacket(
      action: SyncActionTypes.changeEpisode,
      sender: sender,
      roomCode: pinKey,
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
    final pinKey = extractPinCode(roomCode);
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
      roomCode: pinKey,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: toast.toJson(),
    ));
  }

  @override
  void emitEvent(SyncEvent event) {
    final pinKey = extractPinCode(event.roomCode);
    final controller = _roomControllers[pinKey];
    if (controller != null && !controller.isClosed) {
      controller.add(event);
    }
  }

  @override
  Future<void> startPlayback(String roomCode) async {
    final pinKey = extractPinCode(roomCode);
    final senderName = _rooms[pinKey]?.hostName ?? 'Хост';

    // Обновляем is_playing в таблице public.rooms
    final client = _supabase;
    if (client != null) {
      try {
        await client.from('rooms').update({
          'is_playing': true,
        }).eq('id', pinKey);
      } catch (_) {}
    }

    await sendPacket(SyncPacket(
      action: SyncActionTypes.startPlayback,
      sender: senderName,
      roomCode: pinKey,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {},
    ));
    emitEvent(SyncEvent(
      roomCode: pinKey,
      type: SyncEventType.startPlayback,
      senderName: senderName,
      timestamp: DateTime.now(),
    ));
  }

  @override
  Future<void> leaveRoom(String roomCode) async {
    final pinKey = extractPinCode(roomCode);
    emitEvent(SyncEvent(
      roomCode: pinKey,
      type: SyncEventType.peerLeft,
      senderName: 'Участник',
      timestamp: DateTime.now(),
    ));

    // Обновляем is_playing в таблице public.rooms
    final client = _supabase;
    if (client != null) {
      try {
        await client.from('rooms').update({
          'is_playing': false,
        }).eq('id', pinKey);
      } catch (_) {}
    }

    final sbChannel = _supabaseChannels.remove(pinKey);
    if (sbChannel != null && _supabase != null) {
      try {
        await sbChannel.untrack();
      } catch (_) {}
      try {
        await _supabase!.removeChannel(sbChannel);
      } catch (_) {}
    }

    _playbackSyncCallbacks.remove(pinKey);
    _presences.remove(pinKey);
    final presenceController = _presenceControllers.remove(pinKey);
    await presenceController?.close();

    _rooms.remove(pinKey);
    final controller = _roomControllers.remove(pinKey);
    await controller?.close();

    final packetController = _packetControllers.remove(pinKey);
    await packetController?.close();
  }

  @override
  void simulatePeerJoin(String roomCode, {String peerName = 'Сенпай'}) {
    final pinKey = extractPinCode(roomCode);
    final existing = _rooms[pinKey];
    if (existing != null) {
      final updated = existing.copyWith(
        peerName: peerName,
        status: SyncRoomStatus.connected,
      );
      _rooms[pinKey] = updated;
      _rooms[existing.code] = updated;
    }

    emitEvent(SyncEvent(
      roomCode: pinKey,
      type: SyncEventType.peerJoined,
      senderName: peerName,
      timestamp: DateTime.now(),
    ));

    sendPacket(SyncPacket(
      action: SyncActionTypes.roomJoin,
      sender: peerName,
      roomCode: pinKey,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {'user_name': peerName, 'is_host': false},
    ));

    updatePresence(
      roomCode: pinKey,
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
