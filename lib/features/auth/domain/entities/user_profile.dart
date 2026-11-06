import 'package:equatable/equatable.dart';

/// Модель профиля пользователя SyncPai
class UserProfile extends Equatable {
  final String id;
  final String username;
  final String? avatarUrl;
  final String? frameId;
  final String? backgroundId;
  final String? customTitle;
  final String? customStatus;
  final String? bio;
  final String? badgeId;
  final String? favoriteAnimeTitle;
  final String? favoriteAnimeId;
  /// URL постера любимого тайтла — кэшируется при выборе в кастомизаторе
  final String? favoriteAnimePoster;
  final String? accentColor;
  final String? email;
  final String? provider;
  final bool isAnonymous;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.frameId,
    this.backgroundId,
    this.customTitle,
    this.customStatus,
    this.bio,
    this.badgeId,
    this.favoriteAnimeTitle,
    this.favoriteAnimeId,
    this.favoriteAnimePoster,
    this.accentColor,
    this.email,
    this.provider,
    this.isAnonymous = false,
    required this.createdAt,
  });

  /// Дефолтный гостевой профиль при первом запуске (Anonymous Auth)
  factory UserProfile.guest([String? id]) {
    final uid = id ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
    return UserProfile(
      id: uid,
      username: 'Сенпай #${uid.length > 5 ? uid.substring(uid.length - 4) : '777'}',
      avatarUrl: 'cat',
      frameId: 'none',
      backgroundId: 'none',
      customTitle: null,
      customStatus: 'Смотрю аниме...',
      bio: null,
      badgeId: 'sync_master',
      favoriteAnimeTitle: null,
      favoriteAnimeId: null,
      accentColor: '#E06C53',
      email: null,
      provider: 'anonymous',
      isAnonymous: true,
      createdAt: DateTime.now(),
    );
  }

  UserProfile copyWith({
    String? id,
    String? username,
    String? avatarUrl,
    String? frameId,
    String? backgroundId,
    String? customTitle,
    String? customStatus,
    String? bio,
    String? badgeId,
    String? favoriteAnimeTitle,
    String? favoriteAnimeId,
    String? favoriteAnimePoster,
    String? accentColor,
    String? email,
    String? provider,
    bool? isAnonymous,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      frameId: frameId ?? this.frameId,
      backgroundId: backgroundId ?? this.backgroundId,
      customTitle: customTitle ?? this.customTitle,
      customStatus: customStatus ?? this.customStatus,
      bio: bio ?? this.bio,
      badgeId: badgeId ?? this.badgeId,
      favoriteAnimeTitle: favoriteAnimeTitle ?? this.favoriteAnimeTitle,
      favoriteAnimeId: favoriteAnimeId ?? this.favoriteAnimeId,
      favoriteAnimePoster: favoriteAnimePoster ?? this.favoriteAnimePoster,
      accentColor: accentColor ?? this.accentColor,
      email: email ?? this.email,
      provider: provider ?? this.provider,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'avatar_url': avatarUrl,
        'frame_id': frameId,
        'avatar_frame_id': frameId,
        'background_id': backgroundId,
        'background_url': backgroundId,
        'custom_title': customTitle,
        'custom_status': customStatus,
        'bio': bio,
        'badge_id': badgeId,
        'favorite_anime_title': favoriteAnimeTitle,
        'favorite_anime_id': favoriteAnimeId,
        'favorite_anime_poster': favoriteAnimePoster,
        'accent_color': accentColor,
        'email': email,
        'provider': provider,
        'is_anonymous': isAnonymous,
        'created_at': createdAt.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? 'Анимешник',
      avatarUrl: json['avatar_url'] as String?,
      frameId: json['frame_id'] as String? ?? json['avatar_frame_id'] as String? ?? 'none',
      backgroundId: json['background_id'] as String? ?? json['background_url'] as String? ?? 'none',
      customTitle: json['custom_title'] as String?,
      customStatus: json['custom_status'] as String? ?? 'Смотрю аниме...',
      bio: json['bio'] as String?,
      badgeId: json['badge_id'] as String?,
      favoriteAnimeTitle: json['favorite_anime_title'] as String?,
      favoriteAnimeId: json['favorite_anime_id'] as String?,
      favoriteAnimePoster: json['favorite_anime_poster'] as String?,
      accentColor: json['accent_color'] as String? ?? '#E06C53',
      email: json['email'] as String?,
      provider: json['provider'] as String?,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        username,
        avatarUrl,
        frameId,
        backgroundId,
        customTitle,
        customStatus,
        bio,
        badgeId,
        favoriteAnimeTitle,
        favoriteAnimeId,
        favoriteAnimePoster,
        accentColor,
        email,
        provider,
        isAnonymous,
        createdAt,
      ];
}

