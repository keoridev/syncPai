import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/profile/domain/entities/customization_tier_policy.dart';
import 'package:sync_pai/features/profile/presentation/widgets/duo_pairing_widgets.dart';
import 'package:sync_pai/features/profile/presentation/widgets/friend_action_sheet.dart';
import 'package:sync_pai/features/profile/presentation/widgets/pai_chan_artwork_banner.dart';
import 'package:sync_pai/features/support/domain/entities/supporter_tier.dart';

void main() {
  group('Pai-chan Showcase, FriendActionSheet & Duo Pairing', () {
    testWidgets('PaiChanArtworkBanner renders all 4 redesigned scenes cleanly',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  PaiChanArtworkBanner(
                    artworkId: 'pai_chill',
                    width: 340,
                    height: 180,
                  ),
                  PaiChanArtworkBanner(
                    artworkId: 'pai_winter',
                    width: 340,
                    height: 180,
                  ),
                  PaiChanArtworkBanner(
                    artworkId: 'pai_celebrate',
                    width: 340,
                    height: 180,
                  ),
                  PaiChanArtworkBanner(
                    artworkId: 'pai_hacker_art',
                    width: 340,
                    height: 180,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Ночной марафон'), findsOneWidget);
      expect(find.text('НОЧНОЙ МАРАФОН • PAI-CHAN'), findsOneWidget);
      expect(find.text('Зимняя Пай-тян'), findsOneWidget);
      expect(find.text('Абсолют кино'), findsOneWidget);
      expect(find.text('Кодинг-хакер'), findsOneWidget);
    });

    test('UserProfile roundtrips Duo fields and CustomizationTierPolicy gates diptychs',
        () {
      final since = DateTime.now().subtract(const Duration(days: 6));
      final profile = UserProfile.fromJson({
        'id': 'u-1',
        'username': 'Keori',
        'partner_id': 'u-2',
        'duo_theme_id': 'duo_sunset_left',
        'duo_since': since.toIso8601String(),
        'created_at': since.toIso8601String(),
      });

      expect(profile.hasPartner, isTrue);
      expect(profile.partnerId, 'u-2');
      expect(profile.duoThemeId, 'duo_sunset_left');
      expect(profile.daysInDuo, greaterThanOrEqualTo(6));

      final json = profile.toJson();
      expect(json['partner_id'], 'u-2');
      expect(json['duo_theme_id'], 'duo_sunset_left');

      expect(
        CustomizationTierPolicy.isArtworkUnlocked(
          SupporterTier.free,
          'duo_sunset_left',
        ),
        isTrue,
      );
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(
          SupporterTier.free,
          'duo_neon_right',
        ),
        isTrue,
      );
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(
          SupporterTier.free,
          'duo_cosmic_left',
        ),
        isFalse,
      );
      expect(
        CustomizationTierPolicy.isArtworkUnlocked(
          SupporterTier.supporter,
          'duo_cosmic_left',
        ),
        isTrue,
      );
      expect(
        CustomizationTierPolicy.partnerSideForDuoTheme('duo_sunset_left'),
        'duo_sunset_right',
      );
    });

    testWidgets('FriendActionSheet displays all 5 vector actions without emojis',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFriendActionSheet(
                  context,
                  friend: const {
                    'id': 'f-1',
                    'username': 'Sora',
                    'tag': '#1234',
                    'friend_code': 'SP-1234AB',
                    'isOnline': true,
                  },
                  accentColor: const Color(0xFF35D9D5),
                ),
                child: const Text('Open Friend Menu'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Friend Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Открыть профиль'), findsOneWidget);
      expect(find.text('Пригласить смотреть вместе'), findsOneWidget);
      expect(find.text('Подарить подписку (Plus / Pro)'), findsOneWidget);
      expect(find.text('Удалить из друзей'), findsOneWidget);
      expect(find.text('Пожаловаться'), findsOneWidget);
    });

    testWidgets('DuoDiptychBanner, DuoBadgePill and DuoCompatibilityCardSheet render cleanly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const DuoDiptychBanner(
                    themeId: 'duo_sunset_left',
                    width: 300,
                    height: 110,
                  ),
                  DuoBadgePill(
                    partnerName: 'Yuki',
                    daysTogether: 14,
                    sharedEpisodes: 8,
                    sharedHours: 3.2,
                    onTap: () => showDuoCompatibilityCardSheet(
                      context,
                      myName: 'Keori',
                      myAvatarUrl: null,
                      partnerName: 'Yuki',
                      partnerAvatarUrl: null,
                      daysTogether: 14,
                      matchPercent: 92,
                      sharedEpisodes: 8,
                      sharedHours: 3.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('В паре с Yuki • 14 дн.'), findsOneWidget);
      expect(find.text('Смотрят вместе: 8 сер. (3.2 ч)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile_duo_badge_pill')));
      await tester.pumpAndSettle();

      expect(find.text('92%'), findsOneWidget);
      expect(find.text('Поделиться парной карточкой'), findsOneWidget);
    });
  });
}

