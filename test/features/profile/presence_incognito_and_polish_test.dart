import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/services/presence_service.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/profile/presentation/widgets/steam_style_profile_header.dart';
import 'package:sync_pai/features/winter_theme/domain/services/winter_theme_service.dart';
import 'package:sync_pai/features/winter_theme/presentation/widgets/winter_snowfall_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PresenceService — Live watching activity, online stream & Incognito', () {
    test('tracks watching activity, clears on stop, and persists Incognito mode', () async {
      final service = PresenceService.forTest();

      await service.setWatchingActivity('Магическая битва', 3);
      expect(service.currentActivity, 'Смотрит: Магическая битва • 3 сер.');

      await service.clearWatchingActivity();
      expect(service.currentActivity, PresenceService.defaultActivity);

      expect(service.isIncognito, isFalse);
      await service.setIncognito(true);
      expect(service.isIncognito, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PresenceService.incognitoPrefsKey), isTrue);

      await service.toggleIncognito();
      expect(service.isIncognito, isFalse);

      service.setTestOnlineUsers({
        'friend-1': OnlinePresenceInfo(
          userId: 'friend-1',
          status: 'online',
          activity: 'Смотрит: Фрирен • 1 сер.',
          updatedAt: DateTime.now(),
        ),
      });
      expect(service.isUserOnline('friend-1'), isTrue);
      expect(service.activityForUser('friend-1'), 'Смотрит: Фрирен • 1 сер.');
      expect(service.isUserOnline('friend-2'), isFalse);
    });
  });

  group('WinterSnowfallOverlay — renders only when snowfall enabled', () {
    testWidgets('hides particles when disabled and renders CustomPaint when enabled', (tester) async {
      await WinterThemeService.instance.setWinterTheme(false);
      await WinterThemeService.instance.setSnowfall(false);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [WinterSnowfallOverlay()],
            ),
          ),
        ),
      );
      final snowPaintFinder = find.descendant(
        of: find.byType(WinterSnowfallOverlay),
        matching: find.byType(CustomPaint),
      );
      expect(snowPaintFinder, findsNothing);

      await WinterThemeService.instance.setWinterTheme(true);
      await WinterThemeService.instance.setSnowfall(true);
      await tester.pump();
      expect(snowPaintFinder, findsOneWidget);

      await WinterThemeService.instance.setWinterTheme(false);
      await WinterThemeService.instance.setSnowfall(false);
    });
  });

  group('SteamStyleProfileHeader — no CYBERPUNK // SAMURAI & tappable Incognito pill', () {
    testWidgets('omits CYBERPUNK // SAMURAI caption and toggles ONLINE / ИНКОГНИТО pill', (tester) async {
      await PresenceService.instance.setIncognito(false);
      final profile = UserProfile.guest('u1').copyWith(username: 'keori');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SteamStyleProfileHeader(
                profile: profile,
                isCurrentUser: true,
                onCustomizerTap: () {},
                onEditProfileTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('CYBERPUNK // SAMURAI'), findsNothing);
      expect(find.text('Сменить'), findsOneWidget);
      expect(find.text('ONLINE'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile_status_pill')));
      await tester.pump();

      expect(PresenceService.instance.isIncognito, isTrue);
      expect(find.text('ИНКОГНИТО'), findsOneWidget);

      await PresenceService.instance.setIncognito(false);
    });
  });
}
