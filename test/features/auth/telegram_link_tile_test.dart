import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/widgets/telegram_link_tile.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';

void main() {
  test('UserProfile serializes and copies telegramId & telegramUsername', () {
    final profile = UserProfile(
      id: 'user-1',
      username: 'Keori',
      friendCode: 'SP-8F3K9A',
      telegramId: 123456789,
      telegramUsername: 'keori_dev',
      createdAt: DateTime(2026, 11, 17),
    );

    final json = profile.toJson();
    expect(json['telegram_id'], 123456789);
    expect(json['telegram_username'], 'keori_dev');

    final restored = UserProfile.fromJson(json);
    expect(restored.telegramId, 123456789);
    expect(restored.telegramUsername, 'keori_dev');
  });

  testWidgets('TelegramLinkTile builds deep link when unlinked and shows handle when linked',
      (tester) async {
    Uri? launched;

    final unlinked = UserProfile(
      id: 'user-1',
      username: 'Keori',
      friendCode: 'SP-8F3K9A',
      createdAt: DateTime(2026, 11, 17),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TelegramLinkTile(
            profile: unlinked,
            themePrimary: Colors.cyan,
            onLaunchUri: (uri) async => launched = uri,
          ),
        ),
      ),
    );

    expect(find.text('Привязать Telegram'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('telegram_link_tile')));
    await tester.pump();
    expect(
      launched.toString(),
      'https://t.me/syncpai_bot?start=link_SP-8F3K9A',
    );

    final linked = unlinked.copyWith(
      telegramId: 987654321,
      telegramUsername: 'keori_dev',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TelegramLinkTile(
            profile: linked,
            themePrimary: Colors.cyan,
            onLaunchUri: (uri) async => launched = uri,
          ),
        ),
      ),
    );

    expect(find.text('Telegram привязан (@keori_dev)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('telegram_link_tile')));
    await tester.pump();
    expect(launched.toString(), 'https://t.me/syncpai_bot');
  });
}

