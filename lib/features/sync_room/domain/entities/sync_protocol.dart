import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/widgets/mascot/mascot_state.dart';
import '../../../support/domain/entities/supporter_tier.dart';

/// Типы событий протокола синхронизации SyncPai.
abstract final class SyncActionTypes {
  static const String roomJoin = 'ROOM_JOIN';
  static const String heartbeat = 'HEARTBEAT';
  static const String controlAction = 'CONTROL_ACTION';
  static const String bufferWait = 'BUFFER_WAIT';
  static const String bufferReady = 'BUFFER_READY';
  static const String reaction = 'REACTION';
  static const String paiStickerReaction = 'PAI_STICKER_REACTION';
  static const String chatMessage = 'CHAT_MESSAGE';
  static const String requestPause = 'REQUEST_PAUSE';
  static const String changeEpisode = 'CHANGE_EPISODE';
  static const String quickPhrase = 'QUICK_PHRASE';
  static const String presenceUpdate = 'PRESENCE_UPDATE';
  static const String swipeVote = 'SWIPE_VOTE';
  static const String matchFound = 'MATCH_FOUND';
  static const String voiceTalking = 'VOICE_TALKING';
  static const String timestampedReaction = 'TIMESTAMPED_REACTION';
  static const String startPlayback = 'START_PLAYBACK';
  static const String roomInfo = 'ROOM_INFO';
  static const String pokeNudge = 'POKE_NUDGE';
  static const String coopSkipVote = 'COOP_SKIP_VOTE';
  static const String changeAnime = 'CHANGE_ANIME';
  static const String roomClosed = 'ROOM_CLOSED';
}

/// 6 круговых стикер-эмоций Пай-чан для совместного просмотра (Watch-Together)
enum PaiChanSticker {
  excited(
    id: 'excited',
    label: 'Хайп',
    tooltip: 'Восторг / Хайп',
    mascotState: MascotState.friendsJoined,
    assetPath: 'assets/stickers/pai_hype.png',
    fallbackEmoji: '🔥',
    glowColor: Colors.amber,
  ),
  happy(
    id: 'happy',
    label: 'Смех',
    tooltip: 'Радость / Смех',
    mascotState: MascotState.happy,
    assetPath: 'assets/stickers/pai_laugh.png',
    fallbackEmoji: '😂',
    glowColor: Colors.cyan,
  ),
  surprised(
    id: 'surprised',
    label: 'Шок',
    tooltip: 'Шок / Поворот',
    mascotState: MascotState.serverError,
    assetPath: 'assets/stickers/pai_shock.png',
    fallbackEmoji: '😮',
    glowColor: Colors.purple,
  ),
  sad(
    id: 'sad',
    label: 'Слёзы',
    tooltip: 'Грусть / Слёзы',
    mascotState: MascotState.emptyFavorites,
    assetPath: 'assets/stickers/pai_cry.png',
    fallbackEmoji: '😭',
    glowColor: Colors.blue,
  ),
  love(
    id: 'love',
    label: 'Любовь',
    tooltip: 'Любовь / Сердечко',
    mascotState: MascotState.favoriteAdded,
    assetPath: 'assets/stickers/pai_love.png',
    fallbackEmoji: '❤️',
    glowColor: Colors.pink,
  ),
  sleepy(
    id: 'sleepy',
    label: 'Чилл',
    tooltip: 'Чилл / Сон',
    mascotState: MascotState.sleeping,
    assetPath: 'assets/stickers/pai_sleepy.png',
    fallbackEmoji: '😴',
    glowColor: Colors.indigo,
  );

  final String id;
  final String label;
  final String tooltip;
  final MascotState mascotState;
  final String assetPath;
  final String fallbackEmoji;
  final Color glowColor;

  const PaiChanSticker({
    required this.id,
    required this.label,
    required this.tooltip,
    required this.mascotState,
    required this.assetPath,
    required this.fallbackEmoji,
    required this.glowColor,
  });

  static PaiChanSticker fromIdOrEmoji(String raw) {
    final cleaned = raw.trim().toLowerCase();
    for (final s in PaiChanSticker.values) {
      if (s.id == cleaned || s.name.toLowerCase() == cleaned || s.fallbackEmoji == raw.trim()) {
        return s;
      }
    }
    switch (raw.trim()) {
      case '🔥':
      case '👍':
      case 'hype':
        return PaiChanSticker.excited;
      case '😂':
      case '😆':
      case 'laugh':
        return PaiChanSticker.happy;
      case '😱':
      case '😮':
      case 'shock':
        return PaiChanSticker.surprised;
      case '😭':
      case '😢':
      case 'cry':
        return PaiChanSticker.sad;
      case '❤️':
      case '❤':
      case '😍':
      case 'heart':
        return PaiChanSticker.love;
      case '😴':
      case '💤':
      case 'chill':
        return PaiChanSticker.sleepy;
      default:
        return PaiChanSticker.love;
    }
  }
}

/// Легковесный сетевой пакет протокола совместного просмотра.
class SyncPacket extends Equatable {
  final String action;
  final String sender;
  final String roomCode;
  final int timestampMs;
  final Map<String, dynamic> payload;

  const SyncPacket({
    required this.action,
    required this.sender,
    required this.roomCode,
    required this.timestampMs,
    required this.payload,
  });

  Map<String, dynamic> toJson() => {
        'action': action,
        'sender': sender,
        'room_code': roomCode,
        'timestamp_ms': timestampMs,
        'payload': payload,
      };

  factory SyncPacket.fromJson(Map<String, dynamic> json) {
    return SyncPacket(
      action: json['action'] as String? ?? '',
      sender: json['sender'] as String? ?? 'Аноним',
      roomCode: json['room_code'] as String? ?? '',
      timestampMs: json['timestamp_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  List<Object?> get props => [action, sender, roomCode, timestampMs, payload];
}

/// Статус присутствия в комнате (Presence).
enum PresenceStatus {
  online,
  away,
  offline;

  String get label {
    switch (this) {
      case PresenceStatus.online:
        return 'В сети';
      case PresenceStatus.away:
        return 'Отошел';
      case PresenceStatus.offline:
        return 'Не в сети';
    }
  }
}

/// Карточка участника комнаты в онлайн-радаре Presence.
class PeerPresence extends Equatable {
  final String userId;
  final String name;
  final String avatar; // Милый аватар: '🐱', '🦊', '🐼', '🐰', '🐯'
  final PresenceStatus status;
  final DateTime lastSeen;
  final bool isHost;

  const PeerPresence({
    required this.userId,
    required this.name,
    this.avatar = '🐱',
    this.status = PresenceStatus.online,
    required this.lastSeen,
    this.isHost = false,
  });

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'name': name,
        'avatar': avatar,
        'status': status.name,
        'last_seen': lastSeen.millisecondsSinceEpoch,
        'is_host': isHost,
      };

  factory PeerPresence.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'online';
    final status = PresenceStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => PresenceStatus.online,
    );
    final lastSeenMs = json['last_seen'] as int?;
    final lastSeen = lastSeenMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lastSeenMs)
        : DateTime.now();

    return PeerPresence(
      userId: json['user_id'] as String? ?? 'peer',
      name: json['name'] as String? ?? 'Друг',
      avatar: json['avatar'] as String? ?? '🐱',
      status: status,
      lastSeen: lastSeen,
      isHost: json['is_host'] as bool? ?? false,
    );
  }

  PeerPresence copyWith({
    String? userId,
    String? name,
    String? avatar,
    PresenceStatus? status,
    DateTime? lastSeen,
    bool? isHost,
  }) {
    return PeerPresence(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      isHost: isHost ?? this.isHost,
    );
  }

  @override
  List<Object?> get props => [userId, name, avatar, status, lastSeen, isHost];
}

/// Всплывающее уведомление шортката быстрой фразы (Quick Phrase Toast).
class QuickPhraseToast extends Equatable {
  final String id;
  final String sender;
  final String phrase;
  final String? emoji;
  final DateTime timestamp;

  const QuickPhraseToast({
    required this.id,
    required this.sender,
    required this.phrase,
    this.emoji,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender,
        'phrase': phrase,
        'emoji': emoji,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };

  factory QuickPhraseToast.fromJson(Map<String, dynamic> json) {
    final timestampMs = json['timestamp'] as int?;
    return QuickPhraseToast(
      id: json['id'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}',
      sender: json['sender'] as String? ?? 'Друг',
      phrase: json['phrase'] as String? ?? '',
      emoji: json['emoji'] as String?,
      timestamp: timestampMs != null
          ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, sender, phrase, emoji, timestamp];
}

/// Сообщение в чате совместного просмотра (Twitch style).
/// [type]: 'user' — сообщение участника, 'system' — системное событие комнаты
/// («Хост поставил на паузу», «Серия переключена»).
class ChatMessage extends Equatable {
  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isHost;
  final String type;
  final String? supporterTierId;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.isHost = false,
    this.type = 'user',
    this.supporterTierId,
  });

  bool get isSystem => type == 'system';
  SupporterTier get supporterTier => SupporterTier.fromId(supporterTierId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender,
        'text': text,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'is_host': isHost,
        'type': type,
        if (supporterTierId != null) 'supporter_tier': supporterTierId,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}',
      sender: json['sender'] as String? ?? 'Аноним',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      isHost: json['is_host'] as bool? ?? false,
      type: json['type'] as String? ?? 'user',
      supporterTierId: json['supporter_tier'] as String?,
    );
  }

  /// Маппинг строки таблицы `public.room_messages`
  factory ChatMessage.fromRoomMessageRow(Map<String, dynamic> row) {
    final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final rawText = (row['text'] as String?) ?? (row['content'] as String?) ?? '';
    final rawType = row['type'] as String? ?? 'user';
    return ChatMessage(
      id: row['id']?.toString() ?? '${DateTime.now().microsecondsSinceEpoch}',
      sender: row['sender_name'] as String? ?? 'Гость',
      text: rawText,
      timestamp: created?.toLocal() ?? DateTime.now(),
      isHost: row['is_host'] as bool? ?? false,
      type: rawType == 'text' ? 'user' : rawType,
      supporterTierId: row['supporter_tier'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, sender, text, timestamp, isHost, type, supporterTierId];
}

/// Плавающая анимированная стикер-реакция Пай-чан (Floating Pai-chan Reaction).
class FloatingReaction extends Equatable {
  final String id;
  final String emoji;
  final String stickerId;
  final String sender;
  final String? senderId;
  final double startXOffset;
  final DateTime timestamp;

  FloatingReaction({
    required this.id,
    required this.emoji,
    String? stickerId,
    required this.sender,
    this.senderId,
    this.startXOffset = 0.85,
    required this.timestamp,
  }) : stickerId = stickerId ?? PaiChanSticker.fromIdOrEmoji(emoji).id;

  PaiChanSticker get sticker =>
      PaiChanSticker.fromIdOrEmoji(stickerId.isNotEmpty ? stickerId : emoji);

  @override
  List<Object?> get props =>
      [id, emoji, stickerId, sender, senderId, startXOffset, timestamp];
}
