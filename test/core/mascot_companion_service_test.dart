import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/core/widgets/mascot/pai_companion_toast.dart';
import 'package:sync_pai/features/profile/domain/services/achievement_service.dart';

void main() {
  final emojiRegex = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]',
    unicode: true,
  );

  setUp(() {
    MascotCompanionService.instance.resetForTest();
  });

  group('MascotExpression & MascotCompanionService', () {
    test('all 7 MascotExpression states map cleanly without Unicode emojis', () {
      expect(MascotExpression.values.length, 7);
      for (final expr in MascotExpression.values) {
        expect(emojiRegex.hasMatch(expr.title), isFalse);
        expect(emojiRegex.hasMatch(expr.defaultMessage), isFalse);
        expect(expr.assetPath, startsWith('assets/mascot/'));
        expect(expr.toMascotState(), isA<MascotState>());
      }
    });

    test('triggers contextual reactions and respects enabled toggle', () {
      final service = MascotCompanionService.instance;

      service.onOpeningSkipped();
      expect(service.currentReaction?.expression, MascotExpression.speedster);
      expect(emojiRegex.hasMatch(service.currentReaction!.message), isFalse);

      service.onWatchPartyFriendJoined('Sora');
      expect(service.currentReaction?.expression, MascotExpression.popcornWatch);
      expect(service.currentReaction?.message, contains('Sora'));

      service.onCollectionAdded('Смотрю', 'Frieren');
      expect(
        service.currentReaction?.expression,
        MascotExpression.proudCollector,
      );

      service.onSearchOrFilterEmpty();
      expect(
        service.currentReaction?.expression,
        MascotExpression.curiousSearch,
      );

      // Late night greeting -> cozyNight, once per session
      service.showDailyGreeting(
        now: DateTime(2026, 11, 23, 2, 15),
        lastAnimeTitle: 'Frieren',
        lastEpisode: 5,
      );
      expect(service.currentReaction?.expression, MascotExpression.cozyNight);
      expect(service.currentReaction?.message, contains('Frieren'));

      // Subsequent showDailyGreeting in same session is ignored
      service.dismiss();
      service.showDailyGreeting(now: DateTime(2026, 11, 23, 14, 0));
      expect(service.currentReaction, isNull);

      // Disabling reactions hides active toast and suppresses new ones
      service.onOpeningSkipped();
      expect(service.currentReaction, isNotNull);
      service.setEnabled(false);
      expect(service.currentReaction, isNull);
      service.onOpeningSkipped();
      expect(service.currentReaction, isNull);
    });

    testWidgets('PaiCompanionToast renders badge achievement and handles action & tap-to-dismiss',
        (tester) async {
      final service = MascotCompanionService.instance;
      bool nextTapped = false;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Center(child: Text('App Body')),
                PaiCompanionToast(),
              ],
            ),
          ),
        ),
      );

      // 1. Achievement unlock reaction
      final badge = kSyncPaiAchievements.firstWhere((b) => b.id == 'night_owl');
      service.onAchievementUnlocked(badge);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('pai_companion_toast_card')), findsOneWidget);
      expect(find.textContaining('Ночной дозор'), findsOneWidget);

      // 2. Episode near-end reaction with 1-tap action
      service.onEpisodeNearEnd(
        animeTitle: 'Frieren',
        nextEpisode: 6,
        onNextEpisode: () => nextTapped = true,
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('pai_companion_action_btn')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pai_companion_action_btn')));
      await tester.pump();
      expect(nextTapped, isTrue);
      expect(find.byKey(const ValueKey('pai_companion_toast_card')), findsNothing);
    });
  });
}

