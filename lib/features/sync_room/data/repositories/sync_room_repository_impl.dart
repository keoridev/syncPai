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
import '../../../../core/utils/qr_payload_router.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

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
  final Map<String, bool> _messageHostRoles = {};

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Извлекает чистый 6-значный ID комнаты для таблицы `public.rooms` и канала `room:$pinCode`
  static String extractPinCode(String rawCode) {
    final cleanId = RoomCodeParser.extractCleanRoomId(rawCode);
    if (cleanId.isNotEmpty) {
      return cleanId;
    }
    return rawCode.trim().toUpperCase();
  }

  /// Нормализует код комнаты без вставки дефиса в 6-значный ID (`639245` -> `639245`)
  static String normalizeCode(String rawCode) {
    final trimmed = rawCode.trim();
    if (trimmed.isEmpty) return '';

    // Если передана ссылка или JSON, извлекаем чистый ID
    if (trimmed.contains('/') || trimmed.contains(':') || trimmed.startsWith('{')) {
      return RoomCodeParser.extractCleanRoomId(trimmed);
    }

    final cleaned = trimmed.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.startsWith('SP')) {
      final rest = cleaned.substring(2);
      if (rest.length == 6 && RegExp(r'^\d{6}$').hasMatch(rest)) {
        return rest;
      }
      return 'SP-$rest';
    }
    if (cleaned.length == 6) {
      return cleaned;
    }
    if (cleaned.length == 4) {
      return 'SP-$cleaned';
    }
    return cleaned.isNotEmpty ? cleaned : trimmed.toUpperCase();
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
    } else if (packet.action == SyncActionTypes.changeAnime) {
      final p = packet.payload;
      final animeId = (p['anime_id'] as num?)?.toInt() ??
          int.tryParse('${p['anime_id'] ?? 0}') ??
          0;
      final animeTitleStr = (p['anime_title'] as String?) ?? 'Аниме';
      final englishTitleStr = (p['english_title'] as String?) ?? animeTitleStr;
      final codeStr = (p['code'] as String?) ?? 'sync_anime_$animeId';
      final posterUrl = (p['poster_url'] as String?) ?? '';
      final epNum = (p['episode'] as num?)?.toInt() ?? 1;
      final epName = p['episode_name'] as String?;
      final fhdUrl = p['fhd_url'] as String?;
      final hdUrl = p['hd_url'] as String?;
      final sdUrl = p['sd_url'] as String?;

      final existingRoom = _rooms[roomKey];
      final newEpisode = (existingRoom != null &&
              existingRoom.title.id == animeId &&
              existingRoom.title.episodes.isNotEmpty)
          ? existingRoom.title.episodes.firstWhere(
              (e) => e.episode == epNum,
              orElse: () => existingRoom.title.episodes.first,
            )
          : EpisodeItem(
              episode: epNum,
              name: epName ?? 'Серия $epNum',
              fhdUrl: fhdUrl,
              hdUrl: hdUrl,
              sdUrl: sdUrl,
            );

      final newTitle = (existingRoom != null && existingRoom.title.id == animeId)
          ? existingRoom.title
          : AnimeTitle(
              id: animeId,
              code: codeStr,
              russianTitle: animeTitleStr,
              englishTitle: englishTitleStr,
              posterSmall: posterUrl,
              posterMedium: posterUrl,
              posterOriginal: posterUrl,
              genres: const ['Аниме'],
              description: '',
              status: 'Онгоинг',
              episodes: [newEpisode],
            );

      if (existingRoom != null) {
        final updatedRoom = existingRoom.copyWith(
          title: newTitle,
          episode: newEpisode,
        );
        _rooms[roomKey] = updatedRoom;
        _rooms['SP-$roomKey'] = updatedRoom;
        _rooms[existingRoom.code] = updatedRoom;
      }

      final roomController = _roomControllers[roomKey];
      if (roomController != null && !roomController.isClosed) {
        roomController.add(SyncEvent(
          roomCode: roomKey,
          type: SyncEventType.animeChanged,
          senderName: packet.sender,
          timestamp: DateTime.now(),
          newTitle: newTitle,
          newEpisode: newEpisode,
        ));
      }
    } else if (packet.action == SyncActionTypes.roomClosed) {
      final roomController = _roomControllers[roomKey];
      if (roomController != null && !roomController.isClosed) {
        roomController.add(SyncEvent(
          roomCode: roomKey,
          type: SyncEventType.roomClosed,
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

    // Единый топик канала Supabase Realtime для Phone <-> Windows PC: room:$roomId
    final topic = 'room:$pinKey';
    final channel = sb.channel(topic);

    // 1. Postgres Changes: отслеживание обновлений состояния в таблице public.rooms
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
          final animeId = newRecord['anime_id']?.toString();
          final playbackRate = (newRecord['playback_rate'] as num?)?.toDouble();
          final updatedBy = newRecord['updated_by']?.toString();

          if (isPlaying != null || currentTimeSec != null || episodeIndex != null || playbackRate != null) {
            final time = currentTimeSec ?? 0.0;
            final playingBool = isPlaying ?? false;
            final ep = episodeIndex ?? 0;

            final callbacks = _playbackSyncCallbacks[pinKey];
            if (callbacks != null) {
              for (final cb in List.of(callbacks)) {
                cb(time, playingBool, ep);
              }
            }

            final packet = SyncPacket(
              roomCode: pinKey,
              action: SyncActionTypes.controlAction,
              sender: updatedBy ?? 'Peer',
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              payload: {
                'action': playingBool ? 'play' : 'pause',
                'control_action': playingBool ? 'play' : 'pause',
                'position_ms': (time * 1000).toInt(),
                'current_time_sec': time,
                'time': time,
                'is_playing': playingBool,
                'episode_index': ep,
                'episode': ep,
                if (animeId != null) 'anime_id': animeId,
                if (playbackRate != null) 'playback_rate': playbackRate,
                if (updatedBy != null) 'updated_by': updatedBy,
              },
            );
            _handleIncomingPacketInternal(pinKey, packet);
            _getOrCreatePacketController(pinKey).add(packet);
          }
        }
      },
    );

    // 1.1. Postgres Changes на public.room_messages (надежная доставка сообщений чата)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'room_messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: pinKey,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          final msg = ChatMessage.fromRoomMessageRow(newRecord);
          final resolvedIsHost =
              (newRecord['is_host'] as bool?) ?? _messageHostRoles[msg.id] ?? false;
          final packet = SyncPacket(
            roomCode: pinKey,
            action: SyncActionTypes.chatMessage,
            sender: msg.sender,
            timestampMs: msg.timestamp.millisecondsSinceEpoch,
            payload: {
              'id': msg.id,
              'text': msg.text,
              'sender_name': msg.sender,
              'user_id': newRecord['user_id']?.toString(),
              'is_host': resolvedIsHost,
              'type': msg.type,
            },
          );
          _handleIncomingPacketInternal(pinKey, packet);
          _getOrCreatePacketController(pinKey).add(packet);
        }
      },
    );

    // 2. Broadcast: основной канал синхронизации плеера (playback_sync) Phone <-> PC
    channel.onBroadcast(
      event: 'playback_sync',
      callback: (payload) {
        final time = (payload['current_time_sec'] as num?)?.toDouble() ??
            (payload['time'] as num?)?.toDouble() ??
            0.0;
        final isPlaying = payload['is_playing'] as bool? ?? false;
        final episode = (payload['episode_index'] as num?)?.toInt() ??
            (payload['episode'] as num?)?.toInt() ??
            0;
        final playbackRate = (payload['playback_rate'] as num?)?.toDouble();
        final animeId = payload['anime_id']?.toString();
        final updatedBy = payload['updated_by']?.toString();
        final controlAct = payload['control_action'] as String? ??
            (isPlaying ? 'play' : 'pause');
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
            'action': controlAct,
            'control_action': controlAct,
            'position_ms': timeMs,
            'current_time_sec': time,
            'is_playing': isPlaying,
            'time': time,
            'episode_index': episode,
            'episode': episode,
            if (playbackRate != null) 'playback_rate': playbackRate,
            if (animeId != null) 'anime_id': animeId,
            if (updatedBy != null) 'updated_by': updatedBy,
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
        final time = (payload['current_time_sec'] as num?)?.toDouble() ??
            (payload['time'] as num?)?.toDouble() ??
            0.0;
        final isPlaying = payload['is_playing'] as bool? ?? false;
        final episode = (payload['episode_index'] as num?)?.toInt() ??
            (payload['episode'] as num?)?.toInt() ??
            0;
        final playbackRate = (payload['playback_rate'] as num?)?.toDouble();
        final updatedBy = payload['updated_by']?.toString();
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
            'current_time_sec': time,
            'is_playing': isPlaying,
            'time': time,
            'episode_index': episode,
            'episode': episode,
            if (playbackRate != null) 'playback_rate': playbackRate,
            if (updatedBy != null) 'updated_by': updatedBy,
          },
        );
        _handleIncomingPacketInternal(pinKey, packet);
        _getOrCreatePacketController(pinKey).add(packet);
      },
    );

    // 4. Broadcast: мгновенные стикер-реакции Пай-чан (pai_sticker_reaction)
    channel.onBroadcast(
      event: 'pai_sticker_reaction',
      callback: (payload) {
        final stickerId = payload['sticker_id'] as String? ??
            payload['emoji'] as String? ??
            'love';
        final senderName = payload['sender_name'] as String? ??
            payload['sender'] as String? ??
            'Друг';
        final senderId = payload['sender_id'] as String?;
        final reactionId = payload['id'] as String? ??
            '${DateTime.now().microsecondsSinceEpoch}';
        final sticker = PaiChanSticker.fromIdOrEmoji(stickerId);

        final packet = SyncPacket(
          roomCode: pinKey,
          action: SyncActionTypes.paiStickerReaction,
          sender: senderName,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'id': reactionId,
            'sticker_id': sticker.id,
            'emoji': sticker.fallbackEmoji,
            'sender_name': senderName,
            if (senderId != null) 'sender_id': senderId,
          },
        );
        _handleIncomingPacketInternal(pinKey, packet);
        _getOrCreatePacketController(pinKey).add(packet);
      },
    );

    // 5. Broadcast: мгновенные сообщения чата (chat_message)
    channel.onBroadcast(
      event: 'chat_message',
      callback: (payload) {
        final msgId = payload['id'] as String? ??
            '${DateTime.now().microsecondsSinceEpoch}';
        final senderName = payload['sender_name'] as String? ??
            payload['sender'] as String? ??
            'Гость';
        final text = payload['text'] as String? ??
            payload['content'] as String? ??
            '';
        final userId = payload['user_id'] as String?;
        final isHost = payload['is_host'] as bool? ?? false;
        _messageHostRoles[msgId] = isHost;

        final packet = SyncPacket(
          roomCode: pinKey,
          action: SyncActionTypes.chatMessage,
          sender: senderName,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'id': msgId,
            'text': text,
            'sender_name': senderName,
            if (userId != null) 'user_id': userId,
            'is_host': isHost,
            'type': payload['type'] as String? ?? 'text',
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
    int? maxParticipants,
  }) async {
    try {
      final client = Supabase.instance.client;
      final currentUser = client.auth.currentSession?.user ?? client.auth.currentUser;

      final pinCode = customPinCode ?? (100000 + _random.nextInt(900000)).toString();
      int resolvedMaxParticipants = maxParticipants ?? 5;
      if (maxParticipants == null && getIt.isRegistered<AuthCubit>()) {
        final authState = getIt<AuthCubit>().state;
        if (authState is Authenticated) {
          resolvedMaxParticipants = authState.profile.supporterTier.maxRoomParticipants;
        }
      }

      final nowIso = DateTime.now().toUtc().toIso8601String();
      final payload = <String, dynamic>{
        'id': pinCode,
        'anime_id': animeId,
        'anime_title': animeTitle,
        'poster_url': posterUrl,
        'episode_index': episodeIndex,
        'current_time_sec': 0.0,
        'current_position_ms': 0,
        'is_playing': false,
        'max_participants': resolvedMaxParticipants,
        if (currentUser != null && !currentUser.isAnonymous) 'host_id': currentUser.id,
        'created_at': nowIso,
        'updated_at': nowIso,
      };

      _inMemoryRooms[pinCode] = payload;
      _inMemoryRooms['SP-$pinCode'] = payload;

      try {
        await client.from('rooms').upsert(payload);
        // ignore: avoid_print
        print('[WatchTogether] Комната успешно создана в Supabase: $pinCode');
      } catch (upsertErr) {
        try {
          // Fallback без foreign key host_id (для анонимных пользователей)
          final fallbackPayload = Map<String, dynamic>.from(payload)..remove('host_id');
          await client.from('rooms').upsert(fallbackPayload);
          // ignore: avoid_print
          print('[WatchTogether] Комната успешно создана в Supabase (fallback): $pinCode');
        } on PostgrestException catch (pgErr) {
          // ignore: avoid_print
          print('[WatchTogether] Ошибка записи комнаты в Supabase (${pgErr.code}): ${pgErr.message}');
          rethrow;
        } catch (e) {
          // ignore: avoid_print
          print('[WatchTogether] Ошибка сети/БД при создании комнаты: $e');
          rethrow;
        }
      }

      return pinCode;
    } on PostgrestException {
      rethrow;
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[WatchTogether] Ошибка создания комнаты: $e');
      // ignore: avoid_print
      print(stackTrace);
      rethrow;
    }
  }

  static final Map<String, Map<String, dynamic>> _inMemoryRooms = {};

  @override
  Future<Map<String, dynamic>?> getRoomData(String roomCode) => joinRoomByPin(roomCode);

  /// Прямое чтение комнаты по чистому 6-значному ID из `public.rooms`
  Future<Map<String, dynamic>?> joinRoomByPin(String pinCode) async {
    final cleanId = RoomCodeParser.extractCleanRoomId(pinCode);
    if (cleanId.isEmpty) {
      throw Exception('Некорректный код комнаты');
    }
    final spCode = 'SP-$cleanId';

    try {
      final client = Supabase.instance.client;
      var roomData = await client
          .from('rooms')
          .select()
          .eq('id', cleanId)
          .maybeSingle();

      roomData ??= await client
          .from('rooms')
          .select()
          .eq('id', spCode)
          .maybeSingle();

      if (roomData != null) {
        // ignore: avoid_print
        print('[WatchTogether] Успешное подключение к комнате: $cleanId');
        return roomData;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[WatchTogether] Предупреждение при запросе к rooms: $e');
    }

    // Fallback: проверяем локальный реестр комнат сессии
    if (_inMemoryRooms.containsKey(cleanId)) {
      return _inMemoryRooms[cleanId];
    }
    if (_inMemoryRooms.containsKey(spCode)) {
      return _inMemoryRooms[spCode];
    }

    if (cleanId.length >= 4) {
      return {
        'id': cleanId,
        'anime_id': 'sync_session',
        'anime_title': 'Совместный просмотр',
        'poster_url': null,
        'episode_index': 1,
        'current_time_sec': 0.0,
        'is_playing': false,
      };
    }

    throw Exception('Комната с кодом $cleanId не найдена');
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
    final cleanId = RoomCodeParser.extractCleanRoomId(code);
    final normKey = normalizeCode(code);
    if (cleanId.isEmpty && normKey.isEmpty) return false;

    // 1. Проверяем в локальной памяти (активная сессия)
    final localRoom = _rooms[cleanId] ??
        _rooms['SP-$cleanId'] ??
        _rooms[normKey] ??
        _rooms[code];
    if (localRoom != null) {
      return localRoom.status != SyncRoomStatus.closed;
    }
    if (_inMemoryRooms.containsKey(cleanId) ||
        _inMemoryRooms.containsKey('SP-$cleanId')) {
      return true;
    }

    // 2. Проверяем в таблице Supabase public.rooms по чистому 6-значному ID
    final client = _supabase;
    if (client != null && cleanId.isNotEmpty) {
      try {
        var roomData = await client
            .from('rooms')
            .select()
            .eq('id', cleanId)
            .maybeSingle();

        roomData ??= await client
            .from('rooms')
            .select()
            .eq('id', 'SP-$cleanId')
            .maybeSingle();

        if (roomData != null) {
          return true;
        }
      } catch (e) {
        debugPrint('[WatchTogether] Supabase room validation error: $e');
      }
    }

    // Тестовая демо-комната
    if (cleanId == '4821' || normKey == 'SP-4821' || normKey == 'SP4821') {
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

      final posMs = (roomData?['current_position_ms'] as num?)?.toInt() ??
          (((roomData?['current_time_sec'] as num?)?.toDouble() ?? 0.0) * 1000).toInt();

      room = SyncRoom(
        code: 'SP-$cleanPin',
        title: safeTitle,
        episode: safeEpisode,
        quality: PlayerQuality.hd,
        hostName: (roomData?['host_name'] as String?) ?? 'Хост',
        peerName: peerName,
        status: SyncRoomStatus.connected,
        createdAt: DateTime.now(),
        initialPositionMs: posMs,
      );
      _rooms[cleanPin] = room;
      _rooms[normKey] = room;
      _rooms['SP-$cleanPin'] = room;
    } else {
      final posMs = (roomData?['current_position_ms'] as num?)?.toInt() ??
          (((roomData?['current_time_sec'] as num?)?.toDouble() ?? 0.0) * 1000).toInt();
      room = room.copyWith(
        peerName: peerName,
        status: SyncRoomStatus.connected,
        initialPositionMs: posMs > 0 ? posMs : room.initialPositionMs,
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
    bool? isPlaying,
    int? episode,
    String? animeId,
    double? playbackRate,
    String? updatedBy,
  }) {
    final timeSec = positionMs / 1000.0;
    return sendPacket(SyncPacket(
      action: SyncActionTypes.controlAction,
      sender: sender,
      roomCode: roomCode,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'action': action,
        'control_action': action,
        'position_ms': positionMs,
        'current_time_sec': timeSec,
        'time': timeSec,
        if (isPlaying != null) 'is_playing': isPlaying,
        if (episode != null) ...{
          'episode_index': episode,
          'episode': episode,
        },
        if (animeId != null) 'anime_id': animeId,
        if (playbackRate != null) 'playback_rate': playbackRate,
        if (updatedBy != null) 'updated_by': updatedBy,
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
    String? animeId,
    double? playbackRate,
    String? updatedBy,
  }) async {
    final pinKey = extractPinCode(roomCode);
    final resolvedAnimeId = animeId ?? _rooms[pinKey]?.title.id.toString();
    final resolvedUpdatedBy = updatedBy ?? _supabase?.auth.currentUser?.id;

    final channel = _supabaseChannels[pinKey] ?? _initSupabaseChannel(pinKey);
    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'playback_sync',
          payload: {
            'time': time,
            'current_time_sec': time,
            'is_playing': isPlaying,
            'episode': episode,
            'episode_index': episode,
            if (resolvedAnimeId != null) 'anime_id': resolvedAnimeId,
            if (playbackRate != null) 'playback_rate': playbackRate,
            if (resolvedUpdatedBy != null) 'updated_by': resolvedUpdatedBy,
          },
        );
      } catch (e) {
        debugPrint('[WatchTogether] broadcastPlayback error: $e');
      }
    }

    // Синхронно обновляем состояние в таблице public.rooms
    final client = _supabase;
    if (client != null) {
      final baseUpdate = <String, dynamic>{
        'current_time_sec': time,
        'current_position_ms': (time * 1000).toInt(),
        'is_playing': isPlaying,
        if (episode > 0) 'episode_index': episode,
        if (resolvedAnimeId != null && resolvedAnimeId.isNotEmpty) 'anime_id': resolvedAnimeId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        await client.from('rooms').update({
          ...baseUpdate,
          if (playbackRate != null) 'playback_rate': playbackRate,
          if (resolvedUpdatedBy != null) 'updated_by': resolvedUpdatedBy,
        }).eq('id', pinKey);
      } catch (_) {
        try {
          await client.from('rooms').update(baseUpdate).eq('id', pinKey);
        } catch (_) {}
      }
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
        'current_time_sec': time,
        'is_playing': isPlaying,
        'time': time,
        'episode': episode,
        'episode_index': episode,
        if (resolvedAnimeId != null) 'anime_id': resolvedAnimeId,
        if (playbackRate != null) 'playback_rate': playbackRate,
        if (resolvedUpdatedBy != null) 'updated_by': resolvedUpdatedBy,
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
    String? stickerId,
    String? senderId,
    String? reactionId,
  }) async {
    final pinKey = extractPinCode(roomCode);
    final sticker = PaiChanSticker.fromIdOrEmoji(stickerId ?? emoji);
    final resolvedId = reactionId ?? '${DateTime.now().microsecondsSinceEpoch}';
    final resolvedSenderId = senderId ?? _supabase?.auth.currentUser?.id;

    // 1. Отправка pai_sticker_reaction по каналу room:$roomId
    final channel = _supabaseChannels[pinKey] ?? _initSupabaseChannel(pinKey);
    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'pai_sticker_reaction',
          payload: {
            'id': resolvedId,
            'sticker_id': sticker.id,
            'emoji': sticker.fallbackEmoji,
            'sender_name': sender,
            if (resolvedSenderId != null) 'sender_id': resolvedSenderId,
          },
        );
      } catch (_) {}
    }

    // 2. Дублируем в основной поток пакетов
    await sendPacket(SyncPacket(
      action: SyncActionTypes.reaction,
      sender: sender,
      roomCode: pinKey,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'id': resolvedId,
        'sticker_id': sticker.id,
        'emoji': sticker.fallbackEmoji,
        'sender_name': sender,
        if (resolvedSenderId != null) 'sender_id': resolvedSenderId,
      },
    ));
  }

  @override
  Future<void> sendChatMessage({
    required String roomCode,
    required String text,
    required String sender,
    bool isHost = false,
    String? messageId,
    String? userId,
  }) async {
    final pinKey = extractPinCode(roomCode);
    final resolvedId = messageId ?? '${DateTime.now().microsecondsSinceEpoch}';
    final resolvedUserId = userId ?? _supabase?.auth.currentUser?.id;
    _messageHostRoles[resolvedId] = isHost;

    // 1. Мгновенная доставка через Realtime Broadcast (chat_message + action)
    final channel = _supabaseChannels[pinKey] ?? _initSupabaseChannel(pinKey);
    if (channel != null) {
      try {
        await channel.sendBroadcastMessage(
          event: 'chat_message',
          payload: {
            'id': resolvedId,
            'room_id': pinKey,
            if (resolvedUserId != null) 'user_id': resolvedUserId,
            'sender_name': sender,
            'text': text,
            'content': text,
            'type': 'text',
            'is_host': isHost,
          },
        );
      } catch (_) {}
    }

    await sendPacket(SyncPacket(
      action: SyncActionTypes.chatMessage,
      sender: sender,
      roomCode: pinKey,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'id': resolvedId,
        'text': text,
        'sender_name': sender,
        if (resolvedUserId != null) 'user_id': resolvedUserId,
        'is_host': isHost,
        'type': 'text',
      },
    ));

    // 2. Персистентность в public.room_messages
    await _persistChatMessage(
      roomCode: pinKey,
      text: text,
      sender: sender,
      isHost: isHost,
      userId: resolvedUserId,
    );
  }

  Future<void> _persistChatMessage({
    required String roomCode,
    required String text,
    required String sender,
    required bool isHost,
    String type = 'user',
    String? userId,
  }) async {
    final client = _supabase;
    if (client == null) return;
    final cleanRoomId = extractPinCode(roomCode);
    final content = text.length > 500 ? text.substring(0, 500) : text;
    final effectiveUserId = userId ?? client.auth.currentUser?.id;
    try {
      await client.from('room_messages').insert({
        'room_id': cleanRoomId,
        'user_id': effectiveUserId,
        'sender_name': sender,
        'content': content,
        'type': type == 'text' ? 'user' : type,
        'is_host': isHost,
      });
    } catch (_) {
      try {
        await client.from('room_messages').insert({
          'room_id': cleanRoomId,
          'user_id': effectiveUserId,
          'sender_name': sender,
          'text': content,
          'type': 'text',
        });
      } catch (e) {
        debugPrint('[WatchTogether] room_messages insert skipped: $e');
      }
    }

    // Touch updated_at на строке public.rooms для поддержания активности 24h сессии
    try {
      await client.from('rooms').update({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', cleanRoomId);
    } catch (_) {}
  }

  @override
  Future<List<ChatMessage>> fetchChatHistory(String roomCode, {int limit = 50}) async {
    final client = _supabase;
    if (client == null) return const [];
    try {
      final rows = await client
          .from('room_messages')
          .select()
          .eq('room_id', extractPinCode(roomCode))
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((r) => ChatMessage.fromRoomMessageRow(Map<String, dynamic>.from(r as Map)))
          .toList()
          .reversed
          .toList();
    } catch (e) {
      debugPrint('[WatchTogether] room_messages history unavailable: $e');
      return const [];
    }
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
  Future<SyncRoom?> changeRoomAnime({
    required String roomCode,
    required AnimeTitle title,
    EpisodeItem? episode,
    String sender = 'Хост',
  }) async {
    final pinKey = extractPinCode(roomCode);
    final targetEpisode = episode ??
        (title.episodes.isNotEmpty
            ? title.episodes.first
            : const EpisodeItem(episode: 1, name: 'Серия 1'));

    SyncRoom? updatedRoom;
    final existing = _rooms[pinKey] ?? _rooms['SP-$pinKey'] ?? _rooms[roomCode];
    if (existing != null) {
      updatedRoom = existing.copyWith(
        title: title,
        episode: targetEpisode,
      );
      _rooms[pinKey] = updatedRoom;
      _rooms['SP-$pinKey'] = updatedRoom;
      _rooms[existing.code] = updatedRoom;
    } else {
      updatedRoom = SyncRoom(
        code: 'SP-$pinKey',
        title: title,
        episode: targetEpisode,
        quality: PlayerQuality.hd,
        hostName: sender,
        status: SyncRoomStatus.connected,
        createdAt: DateTime.now(),
      );
      _rooms[pinKey] = updatedRoom;
      _rooms['SP-$pinKey'] = updatedRoom;
    }

    final memRecord = _inMemoryRooms[pinKey] ?? <String, dynamic>{'id': pinKey};
    memRecord['anime_id'] = title.id.toString();
    memRecord['anime_title'] = title.displayTitle;
    memRecord['poster_url'] = title.posterUrl;
    memRecord['episode_index'] = targetEpisode.episode;
    memRecord['current_time_sec'] = 0.0;
    memRecord['current_position_ms'] = 0;
    memRecord['is_playing'] = true;
    _inMemoryRooms[pinKey] = memRecord;
    _inMemoryRooms['SP-$pinKey'] = memRecord;

    final client = _supabase;
    if (client != null) {
      try {
        await client.from('rooms').update({
          'anime_id': title.id.toString(),
          'anime_title': title.displayTitle,
          'poster_url': title.posterUrl,
          'episode_index': targetEpisode.episode,
          'current_time_sec': 0.0,
          'current_position_ms': 0,
          'is_playing': true,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', pinKey);
      } catch (e) {
        debugPrint('[WatchTogether] changeRoomAnime DB update warning: $e');
      }
    }

    unawaited(_persistChatMessage(
      roomCode: pinKey,
      text: 'Хост сменил аниме на «${title.displayTitle}»',
      sender: sender,
      isHost: true,
      type: 'system',
    ));

    await sendPacket(SyncPacket(
      action: SyncActionTypes.changeAnime,
      sender: sender,
      roomCode: pinKey,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      payload: {
        'anime_id': title.id,
        'code': title.code,
        'anime_title': title.displayTitle,
        'english_title': title.englishTitle,
        'poster_url': title.posterUrl,
        'episode': targetEpisode.episode,
        'episode_name': targetEpisode.name,
        'fhd_url': targetEpisode.fhdUrl,
        'hd_url': targetEpisode.hdUrl,
        'sd_url': targetEpisode.sdUrl,
      },
    ));

    return updatedRoom;
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
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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

    // Обновляем is_playing и updated_at в public.rooms БЕЗ удаления комнаты (24h persistence)
    final client = _supabase;
    if (client != null) {
      try {
        await client.from('rooms').update({
          'is_playing': false,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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
  }

  @override
  Future<void> closeRoomForAll(String roomCode) async {
    final pinKey = extractPinCode(roomCode);

    // 1. Уведомляем участников через сетевой пакет
    try {
      await sendPacket(SyncPacket(
        action: SyncActionTypes.roomClosed,
        sender: 'Host',
        roomCode: pinKey,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        payload: {
          'reason': 'host_closed',
          'message': 'Хост закрыл комнату для всех',
        },
      ));
    } catch (_) {}

    emitEvent(SyncEvent(
      roomCode: pinKey,
      type: SyncEventType.roomClosed,
      senderName: 'Хост',
      timestamp: DateTime.now(),
    ));

    // 2. Полное удаление комнаты из public.rooms (каскадно удаляет сообщения)
    final client = _supabase;
    if (client != null) {
      try {
        await client.from('rooms').delete().eq('id', pinKey);
      } catch (e) {
        debugPrint('[WatchTogether] Ошибка удаления комнаты $pinKey: $e');
      }
      try {
        await client.from('rooms').delete().eq('id', 'SP-$pinKey');
      } catch (_) {}
    }

    // 3. Отписка и полная очистка локального состояния
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

    _inMemoryRooms.remove(pinKey);
    _inMemoryRooms.remove('SP-$pinKey');
    _rooms.remove(pinKey);
    _rooms.remove('SP-$pinKey');
    final controller = _roomControllers.remove(pinKey);
    await controller?.close();

    final packetController = _packetControllers.remove(pinKey);
    await packetController?.close();
  }

  @override
  void simulatePeerJoin(String roomCode, {String peerName = 'Ren'}) {
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
