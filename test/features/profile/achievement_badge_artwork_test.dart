import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/profile/domain/services/achievement_service.dart';
import 'package:sync_pai/features/profile/presentation/widgets/achievement_badge_artwork.dart';

void main() {
  final emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]',
    unicode: true,
  );

  group('AchievementBadgeArtwork & Steam rarity system', () {
    test('all 9 achievement IDs and asset keys resolve without Unicode emojis', () {
      const expectedKeys = <String, String>{
        'first_episode': 'first_step',
        'watch_hour': 'watch_hour',
        'op_skipper': 'op_skipper',
        'night_owl': 'night_owl',
        'marathon_runner': 'marathoner',
        'party_soul': 'party_soul',
        'collector': 'collector',
        'bug_hunter': 'bug_hunter',
        'critic': 'founder',
      };

      expect(kSyncPaiAchievements.length, 9);
      for (final badge in kSyncPaiAchievements) {
        expect(emojiRegex.hasMatch(badge.title), isFalse, reason: badge.id);
        expect(emojiRegex.hasMatch(badge.hint), isFalse, reason: badge.id);
        expect(emojiRegex.hasMatch(badge.rarity), isFalse, reason: badge.id);

        final style = AchievementBadgeStyle.resolve(badge.id, rarityLabel: badge.rarity);
        expect(style.assetKey, expectedKeys[badge.id]);
        expect(emojiRegex.hasMatch(style.label), isFalse);
      }

      expect(
        AchievementBadgeStyle.resolve('bug_hunter').tier,
        AchievementRarityTier.legendary,
      );
      expect(
        AchievementBadgeStyle.resolve('founder').tier,
        AchievementRarityTier.legendary,
      );
    });

    testWidgets('renders unlocked, locked (28% grayscale + lock icon), and fallback states',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AchievementBadgeArtwork(
                  key: ValueKey('unlocked_badge'),
                  badgeId: 'bug_hunter',
                  isUnlocked: true,
                  size: 48,
                ),
                AchievementBadgeArtwork(
                  key: ValueKey('locked_badge'),
                  badgeId: 'night_owl',
                  isUnlocked: false,
                  size: 48,
                ),
                AchievementBadgeArtwork(
                  key: ValueKey('missing_badge'),
                  badgeId: 'non_existent_badge_id',
                  isUnlocked: true,
                  size: 48,
                ),
                AchievementRarityPill(
                  badgeId: 'founder',
                  isUnlocked: true,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Locked badge has 28% opacity, grayscale filter, and 12px lock icon
      final lockedFinder = find.byKey(const ValueKey('locked_badge'));
      expect(lockedFinder, findsOneWidget);
      expect(
        find.descendant(of: lockedFinder, matching: find.byIcon(Icons.lock_rounded)),
        findsOneWidget,
      );
      final opacityWidget = tester.widget<Opacity>(
        find.descendant(of: lockedFinder, matching: find.byType(Opacity)).first,
      );
      expect(opacityWidget.opacity, closeTo(0.28, 0.001));
      expect(
        find.descendant(of: lockedFinder, matching: find.byType(ColorFiltered)),
        findsOneWidget,
      );

      // Unlocked badge has no lock icon
      final unlockedFinder = find.byKey(const ValueKey('unlocked_badge'));
      expect(
        find.descendant(of: unlockedFinder, matching: find.byIcon(Icons.lock_rounded)),
        findsNothing,
      );

      // Rarity pill shows clean Russian label without emojis
      expect(find.text('Легендарный'), findsOneWidget);
    });
  });
}
