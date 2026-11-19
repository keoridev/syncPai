import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/profile/presentation/widgets/friends_management_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extractValidClipboardInvite rejects >160 chars & arbitrary prose, accepts SP-XXXXXX, deep links, and 6-digit codes',
      () {
    final longText = 'A' * 3000;
    expect(FriendsManagementView.extractValidClipboardInvite(longText), isNull);
    expect(
      FriendsManagementView.extractValidClipboardInvite('Просто обычный текст в буфере обмена'),
      isNull,
    );
    expect(
      FriendsManagementView.extractValidClipboardInvite('Добавляй меня: sp-3b34e7'),
      'SP-3B34E7',
    );
    expect(
      FriendsManagementView.extractValidClipboardInvite('249714'),
      '249714',
    );
    expect(
      FriendsManagementView.extractValidClipboardInvite('https://t.me/syncpai_bot?start=link_SP9988AA'),
      'SP9988AA',
    );
    expect(
      FriendsManagementView.extractValidClipboardInvite('syncpai://room/481516'),
      '481516',
    );
  });

  testWidgets('FriendsManagementView hides clipboard banner on 3000-char clipboard and shows single-line banner on SP-3B34E7',
      (tester) async {
    String? mockClipboard = 'Lorem ipsum ' * 300; // > 3000 chars
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': mockClipboard};
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final profile = UserProfile(
      id: 'u-1',
      username: 'Keori',
      friendCode: 'SP-111111',
      createdAt: DateTime(2026, 11, 19),
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 1. 3000-char clipboard -> banner hidden, zero RenderFlex overflow
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FriendsManagementView(
            key: const ValueKey('friends_view_long_clipboard'),
            accentColor: const Color(0xFF35D9D5),
            userProfile: profile,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Поиск и Код'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('clipboard_invite_banner')), findsNothing);

    // 2. Valid SP-3B34E7 in clipboard -> banner visible with single-line code
    mockClipboard = 'SP-3B34E7';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: FriendsManagementView(
            key: const ValueKey('friends_view_valid_clipboard'),
            accentColor: const Color(0xFF35D9D5),
            userProfile: profile,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Поиск и Код'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('clipboard_invite_banner')), findsOneWidget);
    expect(find.text('Код: SP-3B34E7'), findsOneWidget);
  });
}

