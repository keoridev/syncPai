import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/widgets/steam_avatar_frame.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/services/catalog_prefetch_service.dart';
import 'package:sync_pai/features/profile/domain/entities/customization_tier_policy.dart';
import 'package:sync_pai/features/profile/domain/entities/steam_profile_customization.dart';
import 'package:sync_pai/features/profile/presentation/widgets/pai_chan_artwork_banner.dart';
import 'package:sync_pai/features/profile/presentation/widgets/steam_style_profile_header.dart';
import 'package:sync_pai/features/support/domain/entities/supporter_tier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    if (!getIt.isRegistered<SharedPreferences>()) {
      getIt.registerSingleton<SharedPreferences>(prefs);
    }
    CatalogPrefetchService.instance.clearCache();
  });

  group('CatalogPrefetchService & AnimeTitle serialization', () {
    test('AnimeTitle roundtrips toJson and fromJson cleanly', () {
      const title = AnimeTitle(
        id: 9999,
        shikimoriId: 1234,
        score: 9.15,
        code: 'pai-chan-adventure',
        russianTitle: 'Приключения Пай-тян',
        englishTitle: 'Pai-chan Adventures',
        posterSmall: 'https://example.com/small.jpg',
        posterMedium: 'https://example.com/medium.jpg',
        posterOriginal: 'https://example.com/orig.jpg',
        genres: ['Экшен', 'Комедия'],
        description: 'Классное аниме',
        status: 'ongoing',
        episodesTotal: 12,
        latestEpisode: 4,
        episodes: [
          EpisodeItem(
            episode: 1,
            name: 'Первая серия',
            hdUrl: 'https://stream.com/ep1.m3u8',
            opening: TimecodeRange(start: 90, stop: 180),
          ),
        ],
      );

      final json = title.toJson();
      final restored = AnimeTitle.fromJson(json);

      expect(restored.id, 9999);
      expect(restored.russianTitle, 'Приключения Пай-тян');
      expect(restored.score, 9.15);
      expect(restored.genres, ['Экшен', 'Комедия']);
      expect(restored.episodes.length, 1);
      expect(restored.episodes.first.opening?.start, 90);
      expect(restored.episodes.first.opening?.stop, 180);
    });

    test('CatalogPrefetchService normalizes bucket keys correctly', () {
      final service = CatalogPrefetchService.instance;
      expect(service.normalizeBucketKey('Все'), 'all');
      expect(service.normalizeBucketKey('Онгоинги'), 'ongoing');
      expect(service.normalizeBucketKey('Популярное'), 'popular');
      expect(service.normalizeBucketKey('Фильмы'), 'movies');
      expect(service.normalizeBucketKey('Экшен'), 'Экшен');
    });

    test('CatalogPrefetchService caches and retrieves titles with TTL check', () async {
      final service = CatalogPrefetchService.instance;
      const testTitle = AnimeTitle(
        id: 1,
        code: 'test',
        russianTitle: 'Тест',
        englishTitle: 'Test',
        posterSmall: '',
        posterMedium: 'https://example.com/poster.jpg',
        posterOriginal: '',
        genres: ['Фэнтези'],
        description: '',
        status: 'released',
      );

      expect(service.getCached('Фэнтези'), isNull);
      expect(service.isFresh('Фэнтези'), isFalse);

      await service.putCache('Фэнтези', [testTitle]);

      final cached = service.getCached('Фэнтези');
      expect(cached, isNotNull);
      expect(cached!.length, 1);
      expect(cached.first.id, 1);
      expect(service.isFresh('Фэнтези'), isTrue);
      expect(service.isStale('Фэнтези'), isFalse);
    });
  });

  group('Pai-chan Avatar Frames', () {
    test('SteamAvatarFrame contains signature Pai-chan frames', () {
      final frames = SteamAvatarFrame.all;
      expect(frames.any((f) => f.id == 'pai_headphones'), isTrue);
      expect(frames.any((f) => f.id == 'pai_peek'), isTrue);
      expect(frames.any((f) => f.id == 'pai_hacker'), isTrue);
    });

    test('CustomizationTierPolicy correctly gates Pai-chan frames', () {
      // pai_headphones is Free
      expect(
        CustomizationTierPolicy.isFrameUnlocked(SupporterTier.free, 'pai_headphones'),
        isTrue,
      );

      // pai_peek requires Plus (SupporterTier.supporter)
      expect(
        CustomizationTierPolicy.isFrameUnlocked(SupporterTier.free, 'pai_peek'),
        isFalse,
      );
      expect(
        CustomizationTierPolicy.isFrameUnlocked(SupporterTier.supporter, 'pai_peek'),
        isTrue,
      );

      // pai_hacker requires bug_hunter badge
      expect(
        CustomizationTierPolicy.isFrameUnlocked(SupporterTier.free, 'pai_hacker'),
        isFalse,
      );
      expect(
        CustomizationTierPolicy.isFrameUnlocked(
          SupporterTier.free,
          'pai_hacker',
          unlockedBadges: ['bug_hunter'],
        ),
        isTrue,
      );
    });

    testWidgets('SteamAvatarFrameWidget renders Pai-chan frames cleanly', (tester) async {
      for (final frameId in ['pai_headphones', 'pai_peek', 'pai_hacker']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SteamAvatarFrameWidget(
                  frameId: frameId,
                  size: 64,
                  child: const CircleAvatar(child: Text('P')),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(SteamAvatarFrameWidget), findsOneWidget);
        expect(find.text('P'), findsOneWidget);
      }
    });
  });

  group('Pai-chan Showcase Artworks', () {
    test('SteamStyleProfileHeader includes curated Pai-chan artwork presets', () {
      final presets = SteamStyleProfileHeader.curatedPresets;
      expect(presets.any((p) => p.imageUrl == 'pai_chill'), isTrue);
      expect(presets.any((p) => p.imageUrl == 'pai_winter'), isTrue);
      expect(presets.any((p) => p.imageUrl == 'pai_celebrate'), isTrue);
      expect(presets.any((p) => p.imageUrl == 'pai_hacker_art'), isTrue);
    });

    test('CustomizationTierPolicy gates Pai-chan showcase artworks properly', () {
      // pai_chill & pai_winter are Free
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(SupporterTier.free, 'pai_chill'),
        isTrue,
      );
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(SupporterTier.free, 'pai_winter'),
        isTrue,
      );

      // pai_celebrate requires Plus
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(SupporterTier.free, 'pai_celebrate'),
        isFalse,
      );
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(SupporterTier.supporter, 'pai_celebrate'),
        isTrue,
      );

      // pai_hacker_art requires bug_hunter badge
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(SupporterTier.free, 'pai_hacker_art'),
        isFalse,
      );
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(
          SupporterTier.free,
          'pai_hacker_art',
          unlockedBadges: ['bug_hunter'],
        ),
        isTrue,
      );
    });

    testWidgets('PaiChanArtworkBanner renders all 4 artwork variants cleanly', (tester) async {
      for (final artId in ['pai_chill', 'pai_winter', 'pai_celebrate', 'pai_hacker_art']) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: PaiChanArtworkBanner(
                  artworkId: artId,
                  width: 320,
                  height: 180,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(PaiChanArtworkBanner), findsOneWidget);
      }
    });
  });
}
