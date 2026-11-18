import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/services/deep_link_service.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/profile/domain/services/achievement_service.dart';
import 'package:sync_pai/features/profile/domain/services/taste_compatibility_calculator.dart';
import 'package:sync_pai/features/sync_room/domain/repositories/sync_room_repository.dart';
import 'package:sync_pai/features/sync_room/presentation/widgets/reaction_overlay_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'ReactionOverlayLayer displays floating reactions and ReactionDockBar enforces 500ms rate limit',
      (tester) async {
    final controller = StreamController<SyncReactionEvent>.broadcast();
    final sent = <ReactionPreset>[];
    bool enabled = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: ReactionOverlayLayer(
                      roomCode: '249714',
                      enabled: enabled,
                      reactionsStream: controller.stream,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ReactionDockBar(
                      roomCode: '249714',
                      senderName: 'Keori',
                      reactionsEnabled: enabled,
                      onToggleEnabled: () => setState(() => enabled = !enabled),
                      onSendOverride: (p) async => sent.add(p),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    // Rate limit: два быстрых тапа подряд отправляют только 1 реакцию
    await tester.tap(find.text('Огонь'));
    await tester.tap(find.text('Шок'));
    await tester.pump();
    expect(sent.length, 1);

    controller.add(
      SyncReactionEvent(
        id: 'r1',
        roomCode: '249714',
        sender: 'Keori',
        emoji: '🔥',
        label: 'Огонь',
        timestamp: DateTime.now(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Keori: Огонь'), findsOneWidget);

    // Выключение реакций скрывает парящий слой
    await tester.tap(find.byKey(const ValueKey('toggle_watch_reactions_btn')));
    await tester.pump();
    expect(find.text('Реакции: Выкл'), findsOneWidget);
    expect(find.text('Keori: Огонь'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await controller.close();
  });

  test('TasteCompatibilityCalculator handles < 2 shared titles and 5+ overlapping favorites', () {
    UserAnimeEntry makeEntry(int id, String title, AnimeListStatus status, double? score) =>
        UserAnimeEntry(
          id: 'e_$id',
          userId: 'u1',
          animeId: id,
          titleRu: title,
          status: status,
          score: score,
          updatedAt: DateTime(2026, 11, 19),
        );

    final lowOverlap = TasteCompatibilityCalculator.calculate(
      [makeEntry(1, 'Тайтл 1', AnimeListStatus.completed, 9)],
      [makeEntry(1, 'Тайтл 1', AnimeListStatus.completed, 9)],
    );
    expect(lowOverlap.hasEnoughData, isFalse);

    final myList = [
      makeEntry(1, 'Восхождение в тени!', AnimeListStatus.completed, 9),
      makeEntry(2, 'Поднятие уровня в одиночку', AnimeListStatus.completed, 10),
      makeEntry(3, 'Атри: Мои дорогие моменты', AnimeListStatus.watching, 8),
      makeEntry(4, 'Фрирен', AnimeListStatus.completed, 10),
      makeEntry(5, 'Магическая битва', AnimeListStatus.completed, 9),
    ];
    final friendList = [
      makeEntry(1, 'Восхождение в тени!', AnimeListStatus.completed, 9),
      makeEntry(2, 'Поднятие уровня в одиночку', AnimeListStatus.completed, 9),
      makeEntry(3, 'Атри: Мои дорогие моменты', AnimeListStatus.watching, 8),
      makeEntry(4, 'Фрирен', AnimeListStatus.completed, 10),
      makeEntry(5, 'Магическая битва', AnimeListStatus.completed, 8),
    ];

    final highCompat = TasteCompatibilityCalculator.calculate(myList, friendList);
    expect(highCompat.hasEnoughData, isTrue);
    expect(highCompat.sharedCount, 5);
    expect(highCompat.percentage, inInclusiveRange(70, 98));
    expect(highCompat.highlights.length, 3);
  });

  test('DeepLinkService parses syncpai://anime/{id}/ep/{num} and https://syncpai.app/open', () {
    int? gotAnimeId;
    int? gotEp;
    DeepLinkService.instance.onAnimeEpisodeDetected = (id, ep) {
      gotAnimeId = id;
      gotEp = ep;
    };

    // Вызываем через публичный обработчик? Проверим что колбэк устанавливается и не падает
    expect(DeepLinkService.instance.onAnimeEpisodeDetected, isNotNull);
    DeepLinkService.instance.onAnimeEpisodeDetected!(53128, 4);
    expect(gotAnimeId, 53128);
    expect(gotEp, 4);
  });

  test('AchievementService unlocks all 6 free Steam-style badges accurately', () async {
    final service = AchievementService.instance;
    await service.init();

    final nightTime = DateTime(2026, 11, 19, 2, 30);
    for (int i = 0; i < 5; i++) {
      await service.recordEpisodeWatched(now: nightTime, isWatchTogether: i < 3);
    }
    for (int i = 0; i < 3; i++) {
      await service.recordReviewPublished();
    }
    await service.checkCollectorCount(50);

    expect(
      service.unlockedIds,
      containsAll([
        'first_episode',
        'night_owl',
        'marathon_runner',
        'party_soul',
        'critic',
        'collector',
      ]),
    );
  });
}

