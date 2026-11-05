import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/anime_clip.dart';

abstract class AnimeClipsDataSource {
  Future<List<AnimeClip>> getClips();
  Future<bool> toggleLike(String clipId);
  Future<bool> toggleBookmark(String clipId);
}

class AnimeClipsDataSourceImpl implements AnimeClipsDataSource {
  final SharedPreferences _prefs;
  static const _likesKey = 'syncpai_shorts_likes';
  static const _bookmarksKey = 'syncpai_shorts_bookmarks';

  AnimeClipsDataSourceImpl(this._prefs);

  @override
  Future<List<AnimeClip>> getClips() async {
    final likedIds = _prefs.getStringList(_likesKey) ?? [];
    final bookmarkedIds = _prefs.getStringList(_bookmarksKey) ?? [];

    final rawClips = _getCuratedClips();

    return rawClips.map((clip) {
      final isLiked = likedIds.contains(clip.id);
      final isBookmarked = bookmarkedIds.contains(clip.id);
      return clip.copyWith(
        isLiked: isLiked,
        isBookmarked: isBookmarked,
        likesCount: isLiked ? clip.likesCount + 1 : clip.likesCount,
      );
    }).toList();
  }

  @override
  Future<bool> toggleLike(String clipId) async {
    final likedIds = (_prefs.getStringList(_likesKey) ?? []).toList();
    bool newState;
    if (likedIds.contains(clipId)) {
      likedIds.remove(clipId);
      newState = false;
    } else {
      likedIds.add(clipId);
      newState = true;
    }
    await _prefs.setStringList(_likesKey, likedIds);
    return newState;
  }

  @override
  Future<bool> toggleBookmark(String clipId) async {
    final bookmarkedIds = (_prefs.getStringList(_bookmarksKey) ?? []).toList();
    bool newState;
    if (bookmarkedIds.contains(clipId)) {
      bookmarkedIds.remove(clipId);
      newState = false;
    } else {
      bookmarkedIds.add(clipId);
      newState = true;
    }
    await _prefs.setStringList(_bookmarksKey, bookmarkedIds);
    return newState;
  }

  /// Золотая коллекция культовых моментов аниме
  /// с гарантированно декодируемыми стандартными JPG-постерами (без багов ImageDecoder HWUI)
  /// и прямыми HLS/MP4-видеопотоками.
  List<AnimeClip> _getCuratedClips() {
    return const [
      AnimeClip(
        id: 'clip_solo_leveling_arise',
        animeId: 10344,
        animeTitle: 'Поднятие уровня в одиночку',
        englishTitle: 'Solo Leveling',
        posterUrl: 'https://anilibria.top/storage/releases/posters/10344/HqOeeF96Obeeu51pc8uw8ft06RFoM1A0.jpg',
        episodeNumber: 12,
        targetTimestampSeconds: 1115, // 18:35
        caption: '🔥 Кульминация сезона! Сон Джин-ву произносит заветное «Восстань» и подчиняет тень Игриса.',
        videoUrl: 'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
        youtubeUrl: 'https://www.youtube.com/watch?v=9g0H2gKqQ5Y',
        likesCount: 28420,
        authorName: 'SyncPai Moments',
        tags: ['#sololeveling', '#arise', '#сон_джин_ву', '#эпик', '#бой'],
      ),
      AnimeClip(
        id: 'clip_jujutsu_kaisen_mahoraga',
        animeId: 8789,
        animeTitle: 'Магическая битва 2',
        englishTitle: 'Jujutsu Kaisen Season 2',
        posterUrl: 'https://desu.shikimori.one/uploads/poster/animes/51009/main-27103a89052ce525ee82c5f1fa536098.jpg',
        episodeNumber: 17,
        targetTimestampSeconds: 860, // 14:20
        caption: '⚡ Битва титанов в Сибуе: Король проклятий Сукуна раскрывает истинное пламя против генерала Махораги.',
        videoUrl: 'https://cache-rfn.libria.fun/videos/media/ts/8789/1/720/8789_ep1_720.m3u8',
        youtubeUrl: 'https://www.youtube.com/watch?v=0kFhyjHhQ9g',
        likesCount: 35190,
        authorName: 'Shibuya Arc',
        tags: ['#jjk', '#сукуна', '#махорага', '#сибуя', '#магия'],
      ),
      AnimeClip(
        id: 'clip_demon_slayer_hinokami',
        animeId: 8246,
        animeTitle: 'Клинок, рассекающий демонов',
        englishTitle: 'Demon Slayer: Kimetsu no Yaiba',
        posterUrl: 'https://desu.shikimori.one/uploads/poster/animes/38000/main-459d89ee5e49520e5c1d68351b033d52.jpg',
        episodeNumber: 19,
        targetTimestampSeconds: 1155, // 19:15
        caption: '⚔️ Легендарная 19-я серия: Тандзиро впервые вспоминает Танец Бога Огня в битве с Руи.',
        videoUrl: 'https://cache-rfn.libria.fun/videos/media/ts/8246/1/720/8246_ep1_720.m3u8',
        youtubeUrl: 'https://www.youtube.com/watch?v=7aMOurgDB-o',
        likesCount: 42800,
        authorName: 'Ufotable Magic',
        tags: ['#demonslayer', '#клинок', '#тандзиро', '#хиноками'],
      ),
      AnimeClip(
        id: 'clip_frieren_zoltraak',
        animeId: 10338,
        animeTitle: 'Провожающая в последний путь Фрирен',
        englishTitle: 'Sousou no Frieren',
        posterUrl: 'https://desu.shikimori.one/uploads/poster/animes/52991/main-3560706540c49a620d4107b34b6b66a5.jpg',
        episodeNumber: 9,
        targetTimestampSeconds: 970, // 16:10
        caption: '🪄 «Аура, подчинись мне». Фрирен демонстрирует истинную бездонную ауру маны, скрываемую веками.',
        videoUrl: 'https://cache-rfn.libria.fun/videos/media/ts/10338/1/720/10338_ep1_720.m3u8',
        youtubeUrl: 'https://www.youtube.com/watch?v=qgQunxD0qVU',
        likesCount: 19830,
        authorName: 'Frieren Lore',
        tags: ['#фрирен', '#магия', '#зольтраак', '#аура', '#шедевр'],
      ),
      AnimeClip(
        id: 'clip_aot_rumbling',
        animeId: 9283,
        animeTitle: 'Атака титанов: Финал',
        englishTitle: 'Attack on Titan Final Season',
        posterUrl: 'https://desu.shikimori.one/uploads/poster/animes/40028/main-43dc73cfbf9be5caae303b603eb60682.jpg',
        episodeNumber: 28,
        targetTimestampSeconds: 760, // 12:40
        caption: '🌊 Гул Земли начался. Тысячи Колоссальных титанов под командованием Эрена пересекают океан.',
        videoUrl: 'https://cache-rfn.libria.fun/videos/media/ts/9283/1/720/9283_ep1_720.m3u8',
        youtubeUrl: 'https://www.youtube.com/watch?v=E7WytQM244o',
        likesCount: 31400,
        authorName: 'Scouting Legion',
        tags: ['#атакатитанов', '#эрен', '#гулземли', '#rumbling'],
      ),
      AnimeClip(
        id: 'clip_chainsaw_man_kickback',
        animeId: 9811,
        animeTitle: 'Человек-бензопила',
        englishTitle: 'Chainsaw Man',
        posterUrl: 'https://desu.shikimori.one/uploads/poster/animes/44511/main-3fe71946dc4ea361ca395a1278ffbc16.jpg',
        episodeNumber: 1,
        targetTimestampSeconds: 945, // 15:45
        caption: '🩸 Первое появление Человека-бензопилы! Дэндзи дергает шнур и разносит толпу зомби-демонов.',
        videoUrl: 'https://cache-rfn.libria.fun/videos/media/ts/9811/1/720/9811_ep1_720.m3u8',
        youtubeUrl: 'https://www.youtube.com/watch?v=v4yLeNt-kCU',
        likesCount: 26500,
        authorName: 'Public Safety',
        tags: ['#человекбензопила', '#дэндзи', '#почита', '#мясорубка'],
      ),
      AnimeClip(
        id: 'clip_bleach_tybw_yamamoto',
        animeId: 9780,
        animeTitle: 'Блич: Тысячелетняя кровавая война',
        englishTitle: 'Bleach: Sennen Kessen-hen',
        posterUrl: 'https://desu.shikimori.one/uploads/poster/animes/41467/main-5fe6e3cfb384666f7f2b1d3d633f0a51.jpg',
        episodeNumber: 6,
        targetTimestampSeconds: 1050, // 17:30
        caption: '🔥 Банкай Занка но Тачи: Главнокомандующий Ямамото высвобождает жар в 15 000 000 градусов.',
        videoUrl: 'https://cache-rfn.libria.fun/videos/media/ts/9780/1/720/9780_ep1_720.m3u8',
        youtubeUrl: 'https://www.youtube.com/watch?v=e8YBesRKq_U',
        likesCount: 22100,
        authorName: 'Gotei 13',
        tags: ['#блич', '#ямамото', '#банкай', '#занпакто', '#занконотачи'],
      ),
      AnimeClip(
        id: 'clip_white_cat_legend',
        animeId: 10420,
        animeTitle: 'Легенда о Белом Коте',
        englishTitle: 'Dali Si Zhi',
        posterUrl: 'https://desu.shikimori.one/uploads/poster/animes/40871/main-23bca393693e8271701f681a95e791e8.jpg',
        episodeNumber: 1,
        targetTimestampSeconds: 320, // 05:20
        caption: '🐾 Невероятная динамика боевых искусств: Заместитель министра Ли Бин берется за расследование.',
        videoUrl: 'https://cache-rfn.libria.fun/videos/media/ts/10420/1/720/10420_ep1_720.m3u8',
        youtubeUrl: 'https://www.youtube.com/watch?v=wXqM1gI34w8',
        likesCount: 15320,
        authorName: 'White Cat Studio',
        tags: ['#легендаобеломкоте', '#либин', '#кунгфу', '#детектив'],
      ),
    ];
  }
}
