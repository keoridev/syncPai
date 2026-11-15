import 'package:equatable/equatable.dart';

enum FriendshipStatus {
  pending,
  accepted,
  blocked,
}

class FriendProfile extends Equatable {
  final String id;
  final String username;
  final String tag;
  final String? friendCode;
  final String? avatarUrl;
  final String? customStatus;
  final DateTime? lastSeenAt;
  final String? currentRoomCode;
  final String? currentAnimeTitle;
  final int streakDays;

  const FriendProfile({
    required this.id,
    required this.username,
    this.tag = '#0001',
    this.friendCode,
    this.avatarUrl,
    this.customStatus,
    this.lastSeenAt,
    this.currentRoomCode,
    this.currentAnimeTitle,
    this.streakDays = 1,
  });

  String get fullHandle => '$username$tag';

  bool get isOnline {
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt!).inMinutes < 5;
  }

  FriendProfile copyWith({
    String? id,
    String? username,
    String? tag,
    String? friendCode,
    String? avatarUrl,
    String? customStatus,
    DateTime? lastSeenAt,
    String? currentRoomCode,
    String? currentAnimeTitle,
    int? streakDays,
  }) {
    return FriendProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      tag: tag ?? this.tag,
      friendCode: friendCode ?? this.friendCode,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      customStatus: customStatus ?? this.customStatus,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      currentRoomCode: currentRoomCode ?? this.currentRoomCode,
      currentAnimeTitle: currentAnimeTitle ?? this.currentAnimeTitle,
      streakDays: streakDays ?? this.streakDays,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': username,
        'username': username,
        'tag': tag,
        'friend_code': friendCode,
        'avatar': avatarUrl ?? 'cat',
        'avatar_url': avatarUrl,
        'status': customStatus ?? (isOnline ? 'В сети' : 'Не в сети'),
        'statusText': customStatus ?? (isOnline ? 'В сети' : 'Не в сети'),
        'custom_status': customStatus,
        'last_seen_at': lastSeenAt?.toIso8601String(),
        'room': currentRoomCode,
        'roomCode': currentRoomCode,
        'isOnline': isOnline,
        'canJoin': currentRoomCode != null && currentRoomCode!.isNotEmpty,
        'streakDays': streakDays,
      };

  factory FriendProfile.fromMap(Map<String, dynamic> map) {
    DateTime? lastSeen;
    final rawLast = map['last_seen_at'];
    if (rawLast is String) {
      lastSeen = DateTime.tryParse(rawLast);
    } else if (rawLast is DateTime) {
      lastSeen = rawLast;
    }

    return FriendProfile(
      id: (map['id'] ?? map['user_id'] ?? '').toString(),
      username: (map['username'] ?? map['name'] ?? 'Друг').toString().trim(),
      tag: (map['tag'] ?? '#0001').toString(),
      friendCode: map['friend_code']?.toString(),
      avatarUrl: (map['avatar_url'] ?? map['avatar'])?.toString(),
      customStatus: map['custom_status']?.toString() ?? map['status']?.toString(),
      lastSeenAt: lastSeen,
      currentRoomCode: (map['roomCode'] ?? map['room'])?.toString(),
      currentAnimeTitle: map['current_anime_title']?.toString(),
      streakDays: (map['streakDays'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  List<Object?> get props => [
        id,
        username,
        tag,
        friendCode,
        avatarUrl,
        customStatus,
        lastSeenAt,
        currentRoomCode,
        currentAnimeTitle,
        streakDays,
      ];
}

class FriendInvite extends Equatable {
  final String code;
  final String inviterId;
  final int? maxUses;
  final int usesCount;
  final DateTime? expiresAt;
  final DateTime createdAt;

  const FriendInvite({
    required this.code,
    required this.inviterId,
    this.maxUses,
    this.usesCount = 0,
    this.expiresAt,
    required this.createdAt,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isLimitReached => maxUses != null && usesCount >= maxUses!;
  bool get isValid => !isExpired && !isLimitReached;

  String get universalUrl => 'https://syncpai.app/f/$code';
  String get customSchemeUrl => 'syncpai://invite/friend/$code';

  factory FriendInvite.fromMap(Map<String, dynamic> map) {
    return FriendInvite(
      code: map['code']?.toString() ?? '',
      inviterId: map['inviter_id']?.toString() ?? '',
      maxUses: (map['max_uses'] as num?)?.toInt(),
      usesCount: (map['uses_count'] as num?)?.toInt() ?? 0,
      expiresAt: DateTime.tryParse(map['expires_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [code, inviterId, maxUses, usesCount, expiresAt, createdAt];
}

class FriendRequestItem extends Equatable {
  final String id;
  final String senderId;
  final String receiverId;
  final FriendshipStatus status;
  final FriendProfile profile;
  final bool isIncoming;
  final DateTime createdAt;

  const FriendRequestItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.profile,
    required this.isIncoming,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, senderId, receiverId, status, profile, isIncoming, createdAt];
}

