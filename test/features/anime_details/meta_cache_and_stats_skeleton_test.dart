import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/anime_details/data/services/anime_meta_cache_service.dart';
import 'package:sync_pai/features/anime_details/domain/entities/user_lists_stats.dart';
import 'package:sync_pai/features/anime_details/presentation/widgets/user_lists_distribution_widget.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';

void main() {
  test('AnimeMetaCacheEntry serializes payload and enforces 24h freshness TTL', () {
    const title = AnimeTitle(
      id: 999,
      code: 'mashle-s3',
      russianTitle: 'Магия и мускулы: Турнир трёх магий',
      englishTitle: 'Mashle: Magic and Muscles',
      shikimoriId: 58939,
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      description: '',
      genres: [],
      status: 'ongoing',
      episodes: [],
    );

    expect(AnimeMetaCacheService.buildAnimeKey(title), 'shiki_58939');

    final freshEntry = AnimeMetaCacheEntry(
      animeKey: 'shiki_58939',
      shikimoriId: 58939,
      userStats: const UserListsStats(watching: 120, planned: 14500),
      screenshots: const ['https://example.com/1.jpg'],
      updatedAt: DateTime.now().subtract(const Duration(hours: 12)),
    );
    expect(freshEntry.isFresh, isTrue);

    final restored = AnimeMetaCacheEntry.fromRow({
      'anime_key': 'shiki_58939',
      'shikimori_id': 58939,
      'payload': freshEntry.toPayloadJson(),
      'updated_at': DateTime.now().subtract(const Duration(hours: 25)).toUtc().toIso8601String(),
    });
    expect(restored.userStats.planned, 14500);
    expect(restored.screenshots, ['https://example.com/1.jpg']);
    expect(restored.isFresh, isFalse);
  });

  testWidgets('UserListsDistributionWidget shows skeleton while loading and real stats once loaded',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserListsDistributionWidget(
            stats: UserListsStats(),
            isLoading: true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('user_lists_skeleton')), findsOneWidget);
    expect(find.text('Смотрю'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UserListsDistributionWidget(
            stats: UserListsStats(watching: 350, planned: 14200),
            isLoading: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user_lists_skeleton')), findsNothing);
    expect(find.text('Смотрю'), findsOneWidget);
    expect(find.text('В планах'), findsOneWidget);
  });
}
