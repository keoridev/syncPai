import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/player/presentation/widgets/twitch_chat_overlay.dart';
import 'package:sync_pai/features/support/data/support_config_service.dart';
import 'package:sync_pai/features/support/domain/entities/supporter_tier.dart';
import 'package:sync_pai/features/support/presentation/screens/support_screen.dart';
import 'package:sync_pai/features/support/presentation/widgets/support_prompt_overlay.dart';
import 'package:sync_pai/features/support/services/session_support_timer_service.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupporterTier clean naming, zero emojis & UserProfile serialization', () {
    test('enforces room capacity, custom GIF/title locks and clean chat badges per tier', () {
      expect(SupporterTier.free.maxRoomParticipants, 5);
      expect(SupporterTier.supporter.maxRoomParticipants, 10);
      expect(SupporterTier.vip.maxRoomParticipants, 10);
      expect(SupporterTier.producer.maxRoomParticipants, 10);

      expect(SupporterTier.free.unlocksRamenFrame, isFalse);
      expect(SupporterTier.supporter.unlocksRamenFrame, isTrue);
      expect(SupporterTier.supporter.unlocksCustomArtworkUpload, isFalse);
      expect(SupporterTier.vip.unlocksCustomArtworkUpload, isTrue);
      expect(SupporterTier.vip.unlocksCustomProfileTitle, isTrue);

      expect(SupporterTier.supporter.title, 'SyncPai Plus');
      expect(SupporterTier.vip.title, 'SyncPai Pro');
      expect(SupporterTier.producer.title, 'Founders Club');

      expect(SupporterTier.supporter.chatBadgeLabel, 'Plus');
      expect(SupporterTier.vip.chatBadgeLabel, 'Pro');
      expect(SupporterTier.producer.chatBadgeLabel, 'Founder');

      final emojiRegex = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
      for (final tier in SupporterTier.values) {
        expect(emojiRegex.hasMatch(tier.title), isFalse);
        expect(emojiRegex.hasMatch(tier.badgeLabel ?? ''), isFalse);
        for (final perk in tier.perks) {
          expect(emojiRegex.hasMatch(perk), isFalse);
        }
      }
    });

    test('UserProfile roundtrips supporter_tier via JSON', () {
      final profile = UserProfile.guest('u1').copyWith(supporterTier: SupporterTier.vip);
      final json = profile.toJson();
      expect(json['supporter_tier'], 'vip');
      final restored = UserProfile.fromJson(json);
      expect(restored.supporterTier, SupporterTier.vip);
    });

    test('SupportConfig.fromRow parses app_config fields and hall_of_fame', () {
      final cfg = SupportConfig.fromRow({
        'support_goal_title': 'Оплата серверов и API',
        'support_goal_percent': 72,
        'boosty_url': 'https://boosty.to/syncpai',
        'tribute_url': 'https://t.me/tribute/syncpai',
        'ton_address': 'UQ_TEST_TON',
        'usdt_trc20_address': 'T_TEST_USDT',
        'hall_of_fame': ['keori #5727', 'Senpai #1337'],
      });
      expect(cfg.goalPercent, 72);
      expect(cfg.tonAddress, 'UQ_TEST_TON');
      expect(cfg.hallOfFame, ['keori #5727', 'Senpai #1337']);
    });
  });

  group('SupportScreen minimalist layout, Goal Bar & Telegram Stars CTA', () {
    testWidgets('loads goal bar, displays clean tier names, Telegram Stars CTA & TON copy', (tester) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map?)?['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SupportScreen(
            configLoader: () async => const SupportConfig(
              goalTitle: 'Оплата серверов и API',
              goalPercent: 45,
              boostyUrl: 'https://boosty.to/syncpai',
              tributeUrl: 'https://t.me/tribute/syncpai',
              tonAddress: 'UQ_TEST_TON_WALLET_123',
              usdtTrc20Address: 'T_TEST_USDT_WALLET_456',
              hallOfFame: ['keori #5727', 'PaiProducer #0001'],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1 450 / 3 000 сом (45%) — Оплата серверов и API'), findsOneWidget);
      expect(find.text('SyncPai Plus'), findsNWidgets(2)); // tier card + selected pill
      expect(find.text('SyncPai Pro'), findsOneWidget);
      expect(find.text('Founders Club'), findsNWidgets(2)); // tier card + section header
      expect(find.text('keori #5727'), findsOneWidget);
      expect(find.byKey(const ValueKey('support_stars_cta_btn')), findsOneWidget);
      expect(find.text('⭐ Оплатить 55 ⭐ в @syncpai_bot (Авто-активация)'), findsOneWidget);
      expect(find.byKey(const ValueKey('support_tribute_btn')), findsOneWidget);

      // Tap TON -> copies TON address directly to clipboard
      await tester.ensureVisible(find.byKey(const ValueKey('support_ton_btn')));
      await tester.tap(find.byKey(const ValueKey('support_ton_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(copiedText, 'UQ_TEST_TON_WALLET_123');
      expect(find.text('TON-адрес скопирован в буфер обмена'), findsOneWidget);
    });
  });

  group('Watch-Together Chat supporter badge', () {
    testWidgets('TwitchChatOverlay displays clean supporter badge next to nickname', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TwitchChatOverlay(
              isVisible: true,
              onToggleVisibility: () {},
              messages: [
                ChatMessage(
                  id: 'm1',
                  sender: 'keori',
                  text: 'Всем привет!',
                  timestamp: DateTime.now(),
                  supporterTierId: 'supporter',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('[Plus]'), findsOneWidget);
      expect(find.textContaining('keori'), findsOneWidget);
    });
  });

  group('SessionSupportTimerService & SupportPromptOverlay (30-min trigger + 72h snooze)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('triggers at 30 minutes for free tier and snoozes for 72 hours', () async {
      var now = DateTime(2026, 11, 16, 12, 0);
      final service = SessionSupportTimerService.forTest(
        nowProvider: () => now,
      );
      await service.start();

      service.tick(const Duration(minutes: 29));
      expect(service.shouldShowPrompt, isFalse);

      service.tick(const Duration(minutes: 1));
      expect(service.shouldShowPrompt, isTrue);

      await service.snoozeFor72Hours();
      expect(service.shouldShowPrompt, isFalse);

      // Verify snooze persisted in SharedPreferences for 72h
      final prefs = await SharedPreferences.getInstance();
      final snoozedUntilMs = prefs.getInt(SessionSupportTimerService.snoozedUntilPrefsKey);
      expect(snoozedUntilMs, now.add(const Duration(hours: 72)).millisecondsSinceEpoch);

      // Even a fresh session within 72h does not trigger
      now = now.add(const Duration(hours: 24));
      final serviceWithin72h = SessionSupportTimerService.forTest(
        nowProvider: () => now,
      );
      await serviceWithin72h.start();
      serviceWithin72h.tick(const Duration(minutes: 35));
      expect(serviceWithin72h.shouldShowPrompt, isFalse);

      // Paid users never see the prompt
      serviceWithin72h.updateSupporterTier(SupporterTier.vip);
      now = now.add(const Duration(hours: 60));
      serviceWithin72h.tick(const Duration(minutes: 35));
      expect(serviceWithin72h.shouldShowPrompt, isFalse);

      service.dispose();
      serviceWithin72h.dispose();
    });

    testWidgets('SupportPromptOverlay renders Pai-chan card and handles Позже / Посмотреть', (tester) async {
      final service = SessionSupportTimerService.forTest(
        threshold: const Duration(seconds: 5),
      );
      await service.start();

      var openedSupport = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SupportPromptOverlay(
                  service: service,
                  onOpenSupport: () => openedSupport = true,
                ),
              ],
            ),
          ),
        ),
      );

      service.tick(const Duration(seconds: 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('Нравится смотреть в SyncPai?'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('support_prompt_view_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('support_prompt_later_btn')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('support_prompt_view_btn')));
      await tester.pump();
      expect(openedSupport, isTrue);
      expect(service.shouldShowPrompt, isFalse);

      service.dispose();
    });
  });
}
