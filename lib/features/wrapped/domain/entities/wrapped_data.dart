import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import '../../../../core/widgets/mascot/mascot_state.dart';

/// Типаж аниме-зрителя (Deterministic Personality Classifier)
enum ViewingPersonality {
  bingeWatcher(
    id: 'binge_watcher',
    titleRu: 'Серийный марафонец',
    titleEn: 'The Binge Watcher',
    tagline: '«Ещё одну серию и спать» — фраза, с которой всё только начинается.',
    description: 'Вы способны проглотить целый сезон за один присест. Опенинги пролетают как секунды, а эмоции бьют через край!',
    icon: Icons.bolt_rounded,
    color: Color(0xFFFF806D),
    mascotState: MascotState.happy,
  ),
  nightOwl(
    id: 'night_owl',
    titleRu: 'Ночной смотритель',
    titleEn: 'The Night Owl',
    tagline: 'Когда город засыпает, открывается портал в другие миры.',
    description: 'Ваше любимое время для шедевров — глубокая ночь. Звёзды, наушники и волшебная атмосфера любимых тайтлов.',
    icon: Icons.nightlight_round,
    color: Color(0xFFB388FF),
    mascotState: MascotState.sleeping,
  ),
  romanceEnthusiast(
    id: 'romance_enthusiast',
    titleRu: 'Безнадёжный романтик',
    titleEn: 'The Romance Enthusiast',
    tagline: 'В поисках искренних чувств, признаний под сакурой и школьных драм.',
    description: 'Вы цените трепетные взгляды, неловкие моменты и слезы счастья. Ваше сердце бьется в унисон с героями.',
    icon: Icons.favorite_rounded,
    color: Color(0xFFFF4081),
    mascotState: MascotState.favoriteAdded,
  ),
  actionAddict(
    id: 'action_addict',
    titleRu: 'Адреналиновый фанат',
    titleEn: 'The Action Addict',
    tagline: 'Эпичные битвы, взрывной саундтрек и превозмогание на пределе сил.',
    description: 'Вам нужен драйв, скорость и динамика. Каждый бой заставляет пульс биться быстрее, а финал серии — требовать продолжения!',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFFF9100),
    mascotState: MascotState.welcome,
  ),
  weekendWarrior(
    id: 'weekend_warrior',
    titleRu: 'Воин выходных',
    titleEn: 'The Weekend Warrior',
    tagline: 'Будни для дел, а суббота и воскресенье — священное время аниме.',
    description: 'Вы накапливаете список серий всю неделю, чтобы в законный выходной погрузиться в просмотр с головой.',
    icon: Icons.weekend_rounded,
    color: Color(0xFF00E5FF),
    mascotState: MascotState.idle,
  ),
  socialWatcher(
    id: 'social_watcher',
    titleRu: 'Душа компании',
    titleEn: 'The Social Watcher',
    tagline: 'Аниме создано для того, чтобы переживать его вместе с друзьями.',
    description: 'Синхронные комнаты, голосовой чат, крики в кульминационных моментах — вот ваша настоящая стихия в SyncPai.',
    icon: Icons.groups_rounded,
    color: Color(0xFF35D9D5),
    mascotState: MascotState.friendsJoined,
  ),
  animeExplorer(
    id: 'anime_explorer',
    titleRu: 'Аниме-исследователь',
    titleEn: 'The Anime Explorer',
    tagline: 'Жажда редких жемчужин, глубоких сюжетов и разных жанров.',
    description: 'Вы не ограничиваетесь популярным: пробуете необычные тайтлы, авторскую анимацию и цените разнообразие.',
    icon: Icons.explore_rounded,
    color: Color(0xFF00E676),
    mascotState: MascotState.thinking,
  );

  final String id;
  final String titleRu;
  final String titleEn;
  final String tagline;
  final String description;
  final IconData icon;
  final Color color;
  final MascotState mascotState;

  const ViewingPersonality({
    required this.id,
    required this.titleRu,
    required this.titleEn,
    required this.tagline,
    required this.description,
    required this.icon,
    required this.color,
    required this.mascotState,
  });
}

/// Агрегированные годовые итоги пользователя «SyncPai Wrapped 2026»
class WrappedData extends Equatable {
  final int year;
  final String username;
  final String? avatarUrl;

  final int totalWatchTimeMinutes;
  final int totalEpisodesWatched;
  final int totalTitlesWatched;

  final String topAnimeTitle;
  final String topAnimePoster;
  final int topAnimeEpisodes;

  final String favoriteGenre;
  final Map<String, int> genreDistribution;

  final String mostActiveMonth;
  final String mostActiveDayOfWeek;
  final String? mostRewatchedTitle;

  final int totalWatchParties;
  final String? topWatchPartnerName;
  final String? topWatchPartnerAvatar;
  final int timeWithFriendsMinutes;
  final int friendsCount;

  final ViewingPersonality personality;
  final bool isLowActivity;

  const WrappedData({
    this.year = 2026,
    required this.username,
    this.avatarUrl,
    required this.totalWatchTimeMinutes,
    required this.totalEpisodesWatched,
    required this.totalTitlesWatched,
    required this.topAnimeTitle,
    required this.topAnimePoster,
    required this.topAnimeEpisodes,
    required this.favoriteGenre,
    this.genreDistribution = const {},
    required this.mostActiveMonth,
    required this.mostActiveDayOfWeek,
    this.mostRewatchedTitle,
    this.totalWatchParties = 0,
    this.topWatchPartnerName,
    this.topWatchPartnerAvatar,
    this.timeWithFriendsMinutes = 0,
    this.friendsCount = 0,
    required this.personality,
    this.isLowActivity = false,
  });

  /// Общее время просмотра в часах (с округлением)
  double get totalWatchHours => (totalWatchTimeMinutes / 60.0);

  /// Форматированное строковое время (например, "48 ч. 20 мин.")
  String get formattedWatchTime {
    final hours = totalWatchTimeMinutes ~/ 60;
    final mins = totalWatchTimeMinutes % 60;
    if (hours == 0) return '$mins мин.';
    if (mins == 0) return '$hours ч.';
    return '$hours ч. $mins мин.';
  }

  /// Форматированное время совместного просмотра
  String get formattedFriendsTime {
    final hours = timeWithFriendsMinutes ~/ 60;
    final mins = timeWithFriendsMinutes % 60;
    if (hours == 0) return '$mins мин.';
    if (mins == 0) return '$hours ч.';
    return '$hours ч. $mins мин.';
  }

  @override
  List<Object?> get props => [
        year,
        username,
        avatarUrl,
        totalWatchTimeMinutes,
        totalEpisodesWatched,
        totalTitlesWatched,
        topAnimeTitle,
        topAnimePoster,
        topAnimeEpisodes,
        favoriteGenre,
        genreDistribution,
        mostActiveMonth,
        mostActiveDayOfWeek,
        mostRewatchedTitle,
        totalWatchParties,
        topWatchPartnerName,
        topWatchPartnerAvatar,
        timeWithFriendsMinutes,
        friendsCount,
        personality,
        isLowActivity,
      ];
}
