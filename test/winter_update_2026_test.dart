import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/features/downloads/domain/entities/download_task.dart';
import 'package:sync_pai/features/winter_theme/domain/services/winter_theme_service.dart';
import 'package:sync_pai/features/wrapped/domain/entities/wrapped_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. WinterThemeService Tests', () {
    late WinterThemeService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = WinterThemeService.instance;
    });

    test('Initial default state has winter experience enabled', () {
      expect(service.isWinterThemeEnabled, true);
      expect(service.isSnowfallEnabled, true);
      expect(service.isWinterMascotEnabled, true);
      expect(service.isWinterActive, true);
    });

    test('Snowfall toggle works independently from winter theme and mascot', () async {
      await service.setSnowfall(false);
      expect(service.isSnowfallEnabled, false);
      expect(service.isWinterThemeEnabled, true);
      expect(service.isWinterMascotEnabled, true);

      await service.setSnowfall(true);
      expect(service.isSnowfallEnabled, true);
    });

    test('Winter mascot toggle works independently from falling snow', () async {
      await service.setWinterMascot(false);
      expect(service.isWinterMascotEnabled, false);
      expect(service.isSnowfallEnabled, true);

      await service.setWinterMascot(true);
      expect(service.isWinterMascotEnabled, true);
    });

    test('resetToDefault turns off winter theme, snow and mascot', () async {
      await service.resetToDefault();
      expect(service.isWinterThemeEnabled, false);
      expect(service.isSnowfallEnabled, false);
      expect(service.isWinterMascotEnabled, false);
      expect(service.isWinterActive, false);
    });

    test('enableFullWinterExperience turns all winter options back on', () async {
      await service.resetToDefault();
      expect(service.isWinterActive, false);

      await service.enableFullWinterExperience();
      expect(service.isWinterThemeEnabled, true);
      expect(service.isSnowfallEnabled, true);
      expect(service.isWinterMascotEnabled, true);
      expect(service.isWinterActive, true);
    });

    test('MascotState correctly maps to winter counterparts', () {
      expect(MascotState.welcome.toWinterState(), MascotState.winterWelcome);
      expect(MascotState.idle.toWinterState(), MascotState.winterIdle);
      expect(MascotState.happy.toWinterState(), MascotState.winterHappy);
      expect(MascotState.emptyAnime.toWinterState(), MascotState.winterEmpty);
      expect(MascotState.loading.toWinterState(), MascotState.winterLoading);
      expect(MascotState.success.toWinterState(), MascotState.winterSuccess);
    });
  });

  group('2. SyncPai Wrapped 2026 Tests', () {
    test('WrappedData formats watch time correctly', () {
      const data = WrappedData(
        username: 'Тестовый Пользователь',
        totalWatchTimeMinutes: 2880, // 48 часов
        totalEpisodesWatched: 120,
        totalTitlesWatched: 10,
        topAnimeTitle: 'Магическая битва',
        topAnimePoster: '',
        topAnimeEpisodes: 24,
        favoriteGenre: 'Сёнэн',
        mostActiveMonth: 'Ноябрь',
        mostActiveDayOfWeek: 'Суббота',
        totalWatchParties: 15,
        timeWithFriendsMinutes: 420, // 7 часов
        personality: ViewingPersonality.bingeWatcher,
      );

      expect(data.totalWatchHours, 48.0);
      expect(data.formattedWatchTime, '48 ч.');
      expect(data.formattedFriendsTime, '7 ч.');
      expect(data.isLowActivity, false);
    });

    test('Low activity recap is flagged correctly', () {
      const data = WrappedData(
        username: 'Новичок',
        totalWatchTimeMinutes: 12,
        totalEpisodesWatched: 1,
        totalTitlesWatched: 1,
        topAnimeTitle: 'Тайтл',
        topAnimePoster: '',
        topAnimeEpisodes: 1,
        favoriteGenre: 'Экшен',
        mostActiveMonth: 'Ноябрь',
        mostActiveDayOfWeek: 'Воскресенье',
        personality: ViewingPersonality.animeExplorer,
        isLowActivity: true,
      );

      expect(data.isLowActivity, true);
      expect(data.formattedWatchTime, '12 мин.');
    });

    test('ViewingPersonality enums have valid titles, taglines and colors', () {
      for (final p in ViewingPersonality.values) {
        expect(p.titleRu.isNotEmpty, true);
        expect(p.titleEn.isNotEmpty, true);
        expect(p.tagline.isNotEmpty, true);
        expect(p.description.isNotEmpty, true);
        expect(p.color, isNotNull);
      }
    });
  });

  group('3. Offline Mode & Download Task Tests', () {
    test('DownloadTask creation and generateId', () {
      final id = DownloadTask.generateId(1234, 5);
      expect(id, '1234_5');

      final task = DownloadTask(
        id: id,
        titleId: 1234,
        titleName: 'Атака титанов',
        posterUrl: 'https://example.com/poster.jpg',
        episode: 5,
        episodeName: 'Серия 5',
        quality: '1080p FHD',
        sourceUrl: 'https://example.com/video.mp4',
        localPath: '/local/path/video.mp4',
        status: DownloadStatus.downloading,
        progress: 0.5,
        downloadedBytes: 150000000,
        totalBytes: 300000000,
        createdAt: DateTime.now(),
      );

      expect(task.progress, 0.5);
      expect(task.status, DownloadStatus.downloading);
      expect(task.titleId, 1234);
      expect(task.episode, 5);
    });

    test('DownloadTask copyWith updates status and progress', () {
      final task = DownloadTask(
        id: '100_1',
        titleId: 100,
        titleName: 'Клинок',
        posterUrl: '',
        episode: 1,
        episodeName: 'Серия 1',
        quality: '720p',
        sourceUrl: 'https://example.com/1.mp4',
        localPath: '',
        createdAt: DateTime.now(),
      );

      final completed = task.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        localPath: '/downloads/100_1.mp4',
      );

      expect(completed.status, DownloadStatus.completed);
      expect(completed.progress, 1.0);
      expect(completed.localPath, '/downloads/100_1.mp4');
    });
  });
}
