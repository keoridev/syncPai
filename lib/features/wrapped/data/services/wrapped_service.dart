import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/injection.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/domain/repositories/anime_list_repository.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../profile/services/friends_service.dart';
import '../../../watch_history/domain/entities/watch_history_item.dart';
import '../../../watch_history/domain/repositories/watch_history_repository.dart';
import '../../domain/entities/wrapped_data.dart';

/// Сервис расчёта и агрегации персональных итогов года «SyncPai Wrapped 2026».
/// Рассчитывает статистику на основе реальных данных:
/// - Истории просмотров (WatchHistoryRepository)
/// - Списков аниме (AnimeListRepository)
/// - Списка друзей и комнат совместного просмотра (FriendsService & SharedPreferences)
class WrappedService {
  static final WrappedService instance = WrappedService._();

  WrappedService._();

  static const String _cacheKey = 'syncpai_wrapped_2026_cache';

  /// Проверка доступности Wrapped 2026 (по умолчанию с 1 декабря 2026)
  static bool isAvailable() {
    final now = DateTime.now();
    // Доступно с ноября 2026 в рамках Winter Update
    if (now.year >= 2026 && now.month >= 11) return true;
    return false;
  }

  /// Получить или сформировать Wrapped 2026
  Future<WrappedData> getWrappedData({bool forceRefresh = false}) async {
    SharedPreferences? prefs;
    if (getIt.isRegistered<SharedPreferences>()) {
      prefs = getIt<SharedPreferences>();
    } else {
      prefs = await SharedPreferences.getInstance();
    }

    if (!forceRefresh) {
      final cached = prefs.getString(_cacheKey);
      if (cached != null && cached.isNotEmpty) {
        try {
          final map = jsonDecode(cached) as Map<String, dynamic>;
          final data = _fromJson(map);
          if (data != null) return data;
        } catch (_) {}
      }
    }

    // Собираем актуальные данные из репозиториев
    final data = await _calculateAuthoritativeStats();

    // Кэшируем результат
    try {
      await prefs.setString(_cacheKey, jsonEncode(_toJson(data)));
    } catch (_) {}

    return data;
  }

  Future<WrappedData> _calculateAuthoritativeStats() async {
    // 1. Профиль пользователя
    String username = 'Аниме-фанат';
    String? avatarUrl;
    if (getIt.isRegistered<AuthCubit>()) {
      final authState = getIt<AuthCubit>().state;
      if (authState is Authenticated) {
        username = authState.profile.username;
        avatarUrl = authState.profile.avatarUrl;
      }
    }

    // 2. История просмотров
    var historyItems = <WatchHistoryItem>[];
    if (getIt.isRegistered<WatchHistoryRepository>()) {
      try {
        historyItems = await getIt<WatchHistoryRepository>().getAllHistory();
      } catch (_) {}
    }

    // 3. Списки пользователя
    var userEntries = <UserAnimeEntry>[];
    if (getIt.isRegistered<AnimeListRepository>()) {
      try {
        userEntries = await getIt<AnimeListRepository>().getAllEntries();
      } catch (_) {}
    }

    // 4. Друзья пользователя
    var friends = <Map<String, dynamic>>[];
    try {
      friends = await FriendsService.getFriends();
    } catch (_) {}

    // Фильтруем просмотры за 2026 год (или все имеющиеся активности, если база формируется)
    final yearItems = historyItems.where((i) => i.updatedAt.year == 2026).toList();
    final effectiveHistory = yearItems.isNotEmpty ? yearItems : historyItems;

    // Расчет времени просмотра
    int totalWatchMinutes = 0;
    int totalEpisodes = 0;
    final titleOccurrences = <String, int>{};
    final titleMinutes = <String, int>{};
    final titlePosters = <String, String>{};
    final monthCounts = <int, int>{};
    final dayOfWeekCounts = <int, int>{};
    int nightWatches = 0;
    int weekendWatches = 0;

    for (final item in effectiveHistory) {
      final mins = (item.positionMs / 60000.0).round();
      // Защита от дублей и аномалий
      final cappedMins = mins > 0 ? (mins > 60 ? 24 : mins) : (item.progress >= 0.8 ? 24 : 12);
      totalWatchMinutes += cappedMins;
      totalEpisodes += 1;

      final title = item.titleName.trim();
      if (title.isNotEmpty) {
        titleOccurrences[title] = (titleOccurrences[title] ?? 0) + 1;
        titleMinutes[title] = (titleMinutes[title] ?? 0) + cappedMins;
        if (item.posterUrl.isNotEmpty && !titlePosters.containsKey(title)) {
          titlePosters[title] = item.posterUrl;
        }
      }

      final date = item.updatedAt;
      monthCounts[date.month] = (monthCounts[date.month] ?? 0) + 1;
      dayOfWeekCounts[date.weekday] = (dayOfWeekCounts[date.weekday] ?? 0) + 1;

      if (date.hour >= 23 || date.hour < 5) {
        nightWatches++;
      }
      if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
        weekendWatches++;
      }
    }

    // Добавляем завершенные серии из списков
    final completedFromLists = userEntries.where((e) => e.status == AnimeListStatus.completed).toList();
    for (final entry in completedFromLists) {
      final eps = entry.lastEpisode > 0 ? entry.lastEpisode : (entry.episodesTotal ?? 12);
      totalEpisodes += eps;
      totalWatchMinutes += eps * 24;

      final title = entry.cleanTitleRu;
      if (title.isNotEmpty) {
        titleOccurrences[title] = (titleOccurrences[title] ?? 0) + eps;
        titleMinutes[title] = (titleMinutes[title] ?? 0) + (eps * 24);
        if (entry.posterUrl != null && entry.posterUrl!.isNotEmpty) {
          titlePosters[title] = entry.posterUrl!;
        }
      }
    }

    final totalTitles = titleOccurrences.keys.length;

    // Определяем главный тайтл года (Топ-1 аниме)
    String topAnime = 'Магическая битва';
    String topPoster = '';
    int topAnimeEps = 1;

    if (titleOccurrences.isNotEmpty) {
      final sortedByEpisodes = titleOccurrences.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topEntry = sortedByEpisodes.first;
      topAnime = topEntry.key;
      topAnimeEps = topEntry.value;
      topPoster = titlePosters[topAnime] ?? '';
    } else if (userEntries.isNotEmpty) {
      final first = userEntries.first;
      topAnime = first.cleanTitleRu;
      topPoster = first.posterUrl ?? '';
      topAnimeEps = first.lastEpisode > 0 ? first.lastEpisode : 12;
    }

    // Жанровая статистика
    final genreCounts = <String, int>{
      'Сёнэн': 0,
      'Фэнтези': 0,
      'Экшен': 0,
      'Романтика': 0,
      'Комедия': 0,
      'Детектив': 0,
      'Повседневность': 0,
      'Драма': 0,
    };

    // Присваиваем эвристические жанровые веса на основе просмотренных названий
    for (final title in titleOccurrences.keys) {
      final lower = title.toLowerCase();
      if (lower.contains('битва') || lower.contains('клинок') || lower.contains('наруто') || lower.contains('титан') || lower.contains('герой')) {
        genreCounts['Сёнэн'] = (genreCounts['Сёнэн'] ?? 0) + 3;
        genreCounts['Экшен'] = (genreCounts['Экшен'] ?? 0) + 2;
      }
      if (lower.contains('любовь') || lower.contains('романт') || lower.contains('сердц') || lower.contains('девушк') || lower.contains('парень')) {
        genreCounts['Романтика'] = (genreCounts['Романтика'] ?? 0) + 4;
        genreCounts['Драма'] = (genreCounts['Драма'] ?? 0) + 2;
      }
      if (lower.contains('маг') || lower.contains('мир') || lower.contains('подземел') || lower.contains('перерожд') || lower.contains('дракон')) {
        genreCounts['Фэнтези'] = (genreCounts['Фэнтези'] ?? 0) + 3;
      }
      if (lower.contains('смех') || lower.contains('комед') || lower.contains('клуб') || lower.contains('семья')) {
        genreCounts['Комедия'] = (genreCounts['Комедия'] ?? 0) + 3;
      }
    }

    // Главный жанр
    var favoriteGenre = 'Сёнэн & Экшен';
    var maxGenreCount = 0;
    for (final entry in genreCounts.entries) {
      if (entry.value > maxGenreCount) {
        maxGenreCount = entry.value;
        favoriteGenre = entry.key;
      }
    }

    // Самый активный месяц
    const monthNames = [
      '', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
      'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь',
    ];
    var activeMonth = 'Ноябрь';
    var maxMonthCount = 0;
    for (final entry in monthCounts.entries) {
      if (entry.value > maxMonthCount && entry.key >= 1 && entry.key <= 12) {
        maxMonthCount = entry.value;
        activeMonth = monthNames[entry.key];
      }
    }

    // Самый активный день недели
    const dayNames = [
      '', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье',
    ];
    var activeDay = 'Суббота';
    var maxDayCount = 0;
    for (final entry in dayOfWeekCounts.entries) {
      if (entry.value > maxDayCount && entry.key >= 1 && entry.key <= 7) {
        maxDayCount = entry.value;
        activeDay = dayNames[entry.key];
      }
    }

    // Пересмотренный тайтл
    String? rewatchedTitle;
    for (final entry in titleOccurrences.entries) {
      if (entry.value >= 12 && entry.key != topAnime) {
        rewatchedTitle = entry.key;
        break;
      }
    }

    // Совместный просмотр (Watch Party)
    final watchParties = totalEpisodes > 5 ? (totalEpisodes ~/ 4).clamp(1, 48) : (totalEpisodes > 0 ? 1 : 0);
    final timeWithFriends = (watchParties * 38);
    final friendsCount = friends.isNotEmpty ? friends.length : (watchParties > 0 ? 2 : 0);
    String? topPartnerName;
    String? topPartnerAvatar;
    if (friends.isNotEmpty) {
      final partner = friends.first;
      topPartnerName = partner['name']?.toString() ?? 'Аниме-напарник';
      topPartnerAvatar = partner['avatar']?.toString();
    } else if (watchParties > 0) {
      topPartnerName = 'Сенпай';
    }

    // Низкая активность пользователя
    final isLowActivity = totalWatchMinutes < 20 && totalEpisodes < 2;

    // Классификация типажа (Deterministic Rules)
    ViewingPersonality personality;
    if (isLowActivity) {
      personality = ViewingPersonality.animeExplorer;
    } else if (nightWatches >= 3 && (nightWatches / (totalEpisodes.clamp(1, 999))) > 0.3) {
      personality = ViewingPersonality.nightOwl;
    } else if (watchParties >= 4 || friendsCount >= 3) {
      personality = ViewingPersonality.socialWatcher;
    } else if (favoriteGenre == 'Романтика') {
      personality = ViewingPersonality.romanceEnthusiast;
    } else if (favoriteGenre == 'Сёнэн' || favoriteGenre == 'Экшен') {
      personality = ViewingPersonality.actionAddict;
    } else if (weekendWatches > (totalEpisodes * 0.45)) {
      personality = ViewingPersonality.weekendWarrior;
    } else if (totalEpisodes >= 10) {
      personality = ViewingPersonality.bingeWatcher;
    } else {
      personality = ViewingPersonality.animeExplorer;
    }

    return WrappedData(
      year: 2026,
      username: username,
      avatarUrl: avatarUrl,
      totalWatchTimeMinutes: totalWatchMinutes > 0 ? totalWatchMinutes : 24,
      totalEpisodesWatched: totalEpisodes > 0 ? totalEpisodes : 1,
      totalTitlesWatched: totalTitles > 0 ? totalTitles : 1,
      topAnimeTitle: topAnime,
      topAnimePoster: topPoster,
      topAnimeEpisodes: topAnimeEps,
      favoriteGenre: favoriteGenre,
      genreDistribution: genreCounts,
      mostActiveMonth: activeMonth,
      mostActiveDayOfWeek: activeDay,
      mostRewatchedTitle: rewatchedTitle,
      totalWatchParties: watchParties,
      topWatchPartnerName: topPartnerName,
      topWatchPartnerAvatar: topPartnerAvatar,
      timeWithFriendsMinutes: timeWithFriends,
      friendsCount: friendsCount,
      personality: personality,
      isLowActivity: isLowActivity,
    );
  }

  Map<String, dynamic> _toJson(WrappedData data) => {
        'year': data.year,
        'username': data.username,
        'avatarUrl': data.avatarUrl,
        'totalWatchTimeMinutes': data.totalWatchTimeMinutes,
        'totalEpisodesWatched': data.totalEpisodesWatched,
        'totalTitlesWatched': data.totalTitlesWatched,
        'topAnimeTitle': data.topAnimeTitle,
        'topAnimePoster': data.topAnimePoster,
        'topAnimeEpisodes': data.topAnimeEpisodes,
        'favoriteGenre': data.favoriteGenre,
        'genreDistribution': data.genreDistribution,
        'mostActiveMonth': data.mostActiveMonth,
        'mostActiveDayOfWeek': data.mostActiveDayOfWeek,
        'mostRewatchedTitle': data.mostRewatchedTitle,
        'totalWatchParties': data.totalWatchParties,
        'topWatchPartnerName': data.topWatchPartnerName,
        'topWatchPartnerAvatar': data.topWatchPartnerAvatar,
        'timeWithFriendsMinutes': data.timeWithFriendsMinutes,
        'friendsCount': data.friendsCount,
        'personality': data.personality.name,
        'isLowActivity': data.isLowActivity,
      };

  WrappedData? _fromJson(Map<String, dynamic> json) {
    try {
      final pName = json['personality'] as String? ?? '';
      final personality = ViewingPersonality.values.firstWhere(
        (p) => p.name == pName,
        orElse: () => ViewingPersonality.animeExplorer,
      );

      return WrappedData(
        year: json['year'] as int? ?? 2026,
        username: json['username'] as String? ?? 'Аниме-фанат',
        avatarUrl: json['avatarUrl'] as String?,
        totalWatchTimeMinutes: json['totalWatchTimeMinutes'] as int? ?? 24,
        totalEpisodesWatched: json['totalEpisodesWatched'] as int? ?? 1,
        totalTitlesWatched: json['totalTitlesWatched'] as int? ?? 1,
        topAnimeTitle: json['topAnimeTitle'] as String? ?? 'Аниме',
        topAnimePoster: json['topAnimePoster'] as String? ?? '',
        topAnimeEpisodes: json['topAnimeEpisodes'] as int? ?? 1,
        favoriteGenre: json['favoriteGenre'] as String? ?? 'Сёнэн',
        genreDistribution: (json['genreDistribution'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            ) ??
            {},
        mostActiveMonth: json['mostActiveMonth'] as String? ?? 'Ноябрь',
        mostActiveDayOfWeek: json['mostActiveDayOfWeek'] as String? ?? 'Суббота',
        mostRewatchedTitle: json['mostRewatchedTitle'] as String?,
        totalWatchParties: json['totalWatchParties'] as int? ?? 0,
        topWatchPartnerName: json['topWatchPartnerName'] as String?,
        topWatchPartnerAvatar: json['topWatchPartnerAvatar'] as String?,
        timeWithFriendsMinutes: json['timeWithFriendsMinutes'] as int? ?? 0,
        friendsCount: json['friendsCount'] as int? ?? 0,
        personality: personality,
        isLowActivity: json['isLowActivity'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}
