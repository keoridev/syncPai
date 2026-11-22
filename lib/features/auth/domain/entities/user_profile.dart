import 'package:equatable/equatable.dart';
import '../../../profile/domain/entities/steam_profile_customization.dart';
import '../../../support/domain/entities/supporter_tier.dart';

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
  /// URL и название для витрины иллюстраций (Steam Artwork Showcase) — полностью независимо от любимого тайтла
  final String? artworkUrl;
  final String? artworkTitle;
  final String? accentColor;
  final String? email;
  final String? provider;
  final bool isAnonymous;
  final String showcaseType; // 'favorite_anime', 'stats_badges', 'custom_text'
  final String? countryFlag; // '🇰🇬'
  final String? countryName; // 'Kyrgyzstan'
  final String avatarShape; // 'square' или 'circle'
  final String tag; // '#0421'
  final String? friendCode; // 'SP-8F3K9A'
  final bool autoAcceptInvites;
  final SupporterTier supporterTier;
  final int? telegramId;
  final String? telegramUsername;
  final List<String> unlockedBadges;
  final String? partnerId;
  final String? duoThemeId;
  final DateTime? duoSince;
  final DateTime createdAt;

  bool get isPlusOrHigher =>
      supporterTier.index >= SupporterTier.supporter.index;

  bool get isProOrHigher =>
      supporterTier.index >= SupporterTier.vip.index;

  bool get hasPartner => partnerId != null && partnerId!.isNotEmpty;

  int get daysInDuo => duoSince == null
      ? 1
      : (DateTime.now().difference(duoSince!).inDays + 1).clamp(1, 99999);

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
    this.artworkUrl,
    this.artworkTitle,
    this.accentColor,
    this.email,
    this.provider,
    this.isAnonymous = false,
    this.showcaseType = 'favorite_anime',
    this.countryFlag = '🇰🇬',
    this.countryName = 'Kyrgyzstan',
    this.avatarShape = 'square',
    this.tag = '#0001',
    this.friendCode,
    this.autoAcceptInvites = true,
    this.supporterTier = SupporterTier.free,
    this.telegramId,
    this.telegramUsername,
    this.unlockedBadges = const [],
    this.partnerId,
    this.duoThemeId,
    this.duoSince,
    required this.createdAt,
  });

  /// Модель кастомизации Steam Profile Customization
  ProfileCustomization get customization => ProfileCustomization(
        backgroundType: (backgroundId?.endsWith('.mp4') == true ||
                backgroundId?.endsWith('.webm') == true ||
                backgroundId?.endsWith('.mov') == true)
            ? 'video'
            : (backgroundId?.startsWith('http') == true ? 'image' : 'color'),
        backgroundUrl: backgroundId ?? 'none',
        avatarFrameUrl: frameId,
        themeColorHex: accentColor ?? '#8A2BE2',
        showcaseType: showcaseType,
        customBio: bio,
        countryFlag: countryFlag ?? '🇰🇬',
        countryName: countryName ?? 'Kyrgyzstan',
        avatarShape: avatarShape,
      );

  /// Пул стильных аниме-никнеймов для новых и гостевых пользователей (вместо хардкода «Сенпай»)
  static const List<String> curatedNicknames = [
    'Kuro',
    'Sora',
    'Ren',
    'Yuki',
    'Akira',
    'Kaito',
    'Shin',
    'Riku',
  ];

  /// Генерация чистого аниме-никнейма на основе ID/seed
  static String generateAnimeNickname([String? seed]) {
    final s = (seed != null && seed.isNotEmpty) ? seed : '${DateTime.now().millisecondsSinceEpoch}';
    int hash = 0;
    for (int i = 0; i < s.length; i++) {
      hash = (hash * 31 + s.codeUnitAt(i)) & 0x7fffffff;
    }
    final baseName = curatedNicknames[hash % curatedNicknames.length];
    return baseName;
  }

  /// Генерация 4-значного числового тега (#0421)
  static String generateTag([String? seed]) {
    final s = (seed != null && seed.isNotEmpty) ? seed : '${DateTime.now().millisecondsSinceEpoch}';
    int hash = 0;
    for (int i = 0; i < s.length; i++) {
      hash = (hash * 37 + s.codeUnitAt(i)) & 0x7fffffff;
    }
    final digits = (1000 + (hash % 9000)).toString();
    return '#$digits';
  }

  /// Проверка, является ли никнейм сгенерированным по умолчанию (не измененным вручную)
  static bool isDefaultGeneratedNickname(String? rawName) {
    if (rawName == null || rawName.trim().isEmpty) return true;
    final clean = rawName.trim();
    if (clean == 'Анимешник' ||
        clean == 'Сенпай' ||
        clean.startsWith('Сенпай #') ||
        clean.startsWith('Гость #') ||
        clean == 'Гость') {
      return true;
    }
    for (final preset in curatedNicknames) {
      if (clean == preset || clean.startsWith('$preset #')) {
        return true;
      }
    }
    return false;
  }

  /// Дефолтный гостевой профиль при первом запуске (Anonymous Auth)
  factory UserProfile.guest([String? id]) {
    final uid = id ?? 'guest_${DateTime.now().millisecondsSinceEpoch}';
    final generatedName = generateAnimeNickname(uid);
    final generatedTag = generateTag(uid);
    return UserProfile(
      id: uid,
      username: generatedName,
      avatarUrl: 'cat',
      frameId: 'none',
      backgroundId: 'none',
      customTitle: null,
      customStatus: 'Смотрю аниме...',
      bio: null,
      badgeId: 'sync_master',
      favoriteAnimeTitle: null,
      favoriteAnimeId: null,
      accentColor: '#8A2BE2',
      email: null,
      provider: 'anonymous',
      isAnonymous: true,
      showcaseType: 'favorite_anime',
      countryFlag: '🇰🇬',
      countryName: 'Kyrgyzstan',
      avatarShape: 'square',
      tag: generatedTag,
      friendCode: 'SP-${uid.length >= 6 ? uid.substring(uid.length - 6).toUpperCase() : '777AAA'}',
      autoAcceptInvites: true,
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
    String? artworkUrl,
    String? artworkTitle,
    String? accentColor,
    String? email,
    String? provider,
    bool? isAnonymous,
    String? showcaseType,
    String? countryFlag,
    String? countryName,
    String? avatarShape,
    String? tag,
    String? friendCode,
    bool? autoAcceptInvites,
    SupporterTier? supporterTier,
    int? telegramId,
    String? telegramUsername,
    List<String>? unlockedBadges,
    String? partnerId,
    bool clearPartner = false,
    String? duoThemeId,
    DateTime? duoSince,
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
      artworkUrl: artworkUrl ?? this.artworkUrl,
      artworkTitle: artworkTitle ?? this.artworkTitle,
      accentColor: accentColor ?? this.accentColor,
      email: email ?? this.email,
      provider: provider ?? this.provider,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      showcaseType: showcaseType ?? this.showcaseType,
      countryFlag: countryFlag ?? this.countryFlag,
      countryName: countryName ?? this.countryName,
      avatarShape: avatarShape ?? this.avatarShape,
      tag: tag ?? this.tag,
      friendCode: friendCode ?? this.friendCode,
      autoAcceptInvites: autoAcceptInvites ?? this.autoAcceptInvites,
      supporterTier: supporterTier ?? this.supporterTier,
      telegramId: telegramId ?? this.telegramId,
      telegramUsername: telegramUsername ?? this.telegramUsername,
      unlockedBadges: unlockedBadges ?? this.unlockedBadges,
      partnerId: clearPartner ? null : (partnerId ?? this.partnerId),
      duoThemeId: clearPartner ? null : (duoThemeId ?? this.duoThemeId),
      duoSince: clearPartner ? null : (duoSince ?? this.duoSince),
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
        'artwork_url': artworkUrl,
        'artwork_title': artworkTitle,
        'accent_color': accentColor,
        'email': email,
        'provider': provider,
        'is_anonymous': isAnonymous,
        'showcase_type': showcaseType,
        'country_flag': countryFlag,
        'country_name': countryName,
        'avatar_shape': avatarShape,
        'tag': tag,
        'friend_code': friendCode,
        'auto_accept_invites': autoAcceptInvites,
        'supporter_tier': supporterTier.id,
        'telegram_id': telegramId,
        'telegram_username': telegramUsername,
        'unlocked_badges': unlockedBadges,
        'partner_id': partnerId,
        'duo_theme_id': duoThemeId,
        'duo_since': duoSince?.toIso8601String(),
        'customization': customization.toJson(),
        'created_at': createdAt.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final customObj = json['customization'] is Map<String, dynamic>
        ? json['customization'] as Map<String, dynamic>
        : null;

    final frame = json['frame_id'] as String? ??
        json['avatar_frame_id'] as String? ??
        customObj?['avatar_frame_url'] as String? ??
        'none';
    final bg = json['background_id'] as String? ??
        json['background_url'] as String? ??
        customObj?['background_url'] as String? ??
        'none';
    final accent = json['accent_color'] as String? ??
        customObj?['theme_color_hex'] as String? ??
        '#8A2BE2';
    final showcase = json['showcase_type'] as String? ??
        customObj?['showcase_type'] as String? ??
        'favorite_anime';
    final userBio = json['bio'] as String? ??
        customObj?['custom_bio'] as String?;
    final flag = json['country_flag'] as String? ??
        json['countryFlag'] as String? ??
        customObj?['country_flag'] as String? ??
        '🇰🇬';
    final country = json['country_name'] as String? ??
        json['countryName'] as String? ??
        customObj?['country_name'] as String? ??
        'Kyrgyzstan';
    final shape = json['avatar_shape'] as String? ??
        json['avatarShape'] as String? ??
        customObj?['avatar_shape'] as String? ??
        'square';

    final rawId = json['id'] as String? ?? '';
    final rawUsername = json['username'] as String?;
    final resolvedUsername = (rawUsername == null ||
            rawUsername.trim().isEmpty ||
            rawUsername == 'Анимешник' ||
            rawUsername == 'Сенпай' ||
            rawUsername.startsWith('Сенпай #'))
        ? generateAnimeNickname(rawId)
        : rawUsername;

    return UserProfile(
      id: rawId,
      username: resolvedUsername,
      avatarUrl: json['avatar_url'] as String?,
      frameId: frame,
      backgroundId: bg,
      customTitle: json['custom_title'] as String?,
      customStatus: json['custom_status'] as String? ?? 'Смотрю аниме...',
      bio: userBio,
      badgeId: json['badge_id'] as String?,
      favoriteAnimeTitle: json['favorite_anime_title'] as String?,
      favoriteAnimeId: json['favorite_anime_id'] as String?,
      favoriteAnimePoster: json['favorite_anime_poster'] as String?,
      artworkUrl: json['artwork_url'] as String? ?? (customObj?['artwork_url'] as String?),
      artworkTitle: json['artwork_title'] as String? ?? (customObj?['artwork_title'] as String?),
      accentColor: accent,
      email: json['email'] as String?,
      provider: json['provider'] as String?,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      showcaseType: showcase,
      countryFlag: flag,
      countryName: country,
      avatarShape: shape,
      tag: json['tag'] as String? ?? '#0001',
      friendCode: json['friend_code'] as String?,
      autoAcceptInvites: json['auto_accept_invites'] as bool? ?? true,
      supporterTier: SupporterTier.fromId(json['supporter_tier'] as String?),
      telegramId: (json['telegram_id'] as num?)?.toInt(),
      telegramUsername: json['telegram_username'] as String?,
      unlockedBadges: (json['unlocked_badges'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      partnerId: json['partner_id'] as String?,
      duoThemeId: json['duo_theme_id'] as String?,
      duoSince: DateTime.tryParse(json['duo_since'] as String? ?? ''),
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
        artworkUrl,
        artworkTitle,
        accentColor,
        email,
        provider,
        isAnonymous,
        showcaseType,
        countryFlag,
        countryName,
        avatarShape,
        tag,
        friendCode,
        autoAcceptInvites,
        supporterTier,
        telegramId,
        telegramUsername,
        unlockedBadges,
        partnerId,
        duoThemeId,
        duoSince,
        createdAt,
      ];
}

