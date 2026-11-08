import 'package:equatable/equatable.dart';

/// Типы событий протокола синхронизации SyncPai.
abstract final class SyncActionTypes {
  static const String roomJoin = 'ROOM_JOIN';
  static const String heartbeat = 'HEARTBEAT';
  static const String controlAction = 'CONTROL_ACTION';
  static const String bufferWait = 'BUFFER_WAIT';
  static const String bufferReady = 'BUFFER_READY';
  static const String reaction = 'REACTION';
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
class ChatMessage extends Equatable {
  final String id;
  final String sender;
  final String text;
  final DateTime timestamp;
  final bool isHost;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.isHost = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender,
        'text': text,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'is_host': isHost,
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
    );
  }

  @override
  List<Object?> get props => [id, sender, text, timestamp, isHost];
}

/// Плавающая анимированная реакция (Floating Reaction).
class FloatingReaction extends Equatable {
  final String id;
  final String emoji;
  final String sender;
  final double startXOffset;
  final DateTime timestamp;

  const FloatingReaction({
    required this.id,
    required this.emoji,
    required this.sender,
    this.startXOffset = 0.85,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [id, emoji, sender, startXOffset, timestamp];
}
