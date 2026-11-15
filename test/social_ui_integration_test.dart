import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/widgets/app_search_bar.dart';
import 'package:sync_pai/core/widgets/vector_country_flag.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/auth/presentation/widgets/pai_chan_auth_gate.dart';
import 'package:sync_pai/features/profile/presentation/widgets/friend_invite_dialog.dart';
import 'package:sync_pai/features/profile/presentation/widgets/qr_invite_sheet.dart';
import 'package:sync_pai/features/profile/presentation/widgets/qr_scanner_sheet.dart';
import 'package:sync_pai/features/profile/presentation/widgets/friends_management_sheet.dart';
import 'package:sync_pai/features/profile/presentation/widgets/steam_style_profile_header.dart';
import 'package:sync_pai/features/profile/services/pending_invite_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Social System Integration & UI Tests', () {
    testWidgets('QrInviteSheet renders user profile info, copy button and QR view', (tester) async {
      final profile = UserProfile(
        id: 'test_user_id',
        username: 'KeoriDev',
        tag: '#0421',
        friendCode: 'SP-8F3K9A',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: QrInviteSheet(
              profile: profile,
              accentColor: const Color(0xFF35D9D5),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Проверяем элементы визитки
      expect(find.text('KeoriDev'), findsOneWidget);
      expect(find.text('#0421'), findsOneWidget);
      expect(find.text('SP-8F3K9A'), findsOneWidget);
      expect(find.text('Поделиться'), findsOneWidget);
    });

    testWidgets('QrScannerSheet renders desktop fallback with manual input field', (tester) async {
      String? detectedResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: QrScannerSheet(
              accentColor: const Color(0xFF35D9D5),
              onCodeDetected: (code) {
                detectedResult = code;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Сканировать QR-код'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Вводим инвайт-ссылку вручную
      final input = find.byType(TextField).first;
      await tester.enterText(input, 'https://syncpai.app/f/SP-9988AA');
      await tester.pumpAndSettle();

      // Нажимаем «Принять»
      await tester.tap(find.text('Принять'));
      await tester.pumpAndSettle();

      expect(detectedResult, 'SP-9988AA');
    });

    testWidgets('FriendsManagementView renders 3 tabs: Друзья, Заявки, Поиск и Код', (tester) async {
      final profile = UserProfile(
        id: 'test_user_id',
        username: 'KeoriDev',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: FriendsManagementView(
              accentColor: const Color(0xFF35D9D5),
              userProfile: profile,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Проверяем заголовки и вкладки
      expect(find.text('Друзья и Сообщество'), findsOneWidget);
      expect(find.textContaining('Друзья ('), findsOneWidget);
      expect(find.textContaining('Заявки'), findsOneWidget);
      expect(find.text('Поиск и Код'), findsOneWidget);

      // Переключаемся на Заявки
      await tester.tap(find.textContaining('Заявки'));
      await tester.pumpAndSettle();
      expect(find.text('Нет активных заявок'), findsOneWidget);

      // Переключаемся на Поиск и Код
      await tester.tap(find.text('Поиск и Код'));
      await tester.pumpAndSettle();
      expect(find.text('Моя визитка QR'), findsOneWidget);
      expect(find.text('Сканировать QR'), findsOneWidget);
    });

    testWidgets('FriendInviteConfirmationDialog renders invalid state cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: FriendInviteConfirmationDialog(
              inviteCode: 'INVALID_CODE',
              accentColor: Color(0xFF35D9D5),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Приглашение в друзья'), findsOneWidget);
      expect(find.text('Приглашение не найдено или ссылка повреждена.'), findsOneWidget);
      expect(find.text('Закрыть'), findsOneWidget);
    });

    testWidgets('FriendsManagementView renders embedded Pai-chan Auth Gate for anonymous guest user', (tester) async {
      final guestProfile = UserProfile.guest('guest_user_123');

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: FriendsManagementView(
              accentColor: const Color(0xFF35D9D5),
              userProfile: guestProfile,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Хочешь добавлять друзей?'), findsOneWidget);
      expect(find.text('Войти через Google'), findsOneWidget);
      expect(find.text('Регистрация по Email'), findsOneWidget);
      expect(find.text('Позже'), findsOneWidget);
    });

    testWidgets('PaiChanAuthGate caches pendingInviteCode and shows invite continuation badge', (tester) async {
      PendingInviteStorage.clear();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PaiChanAuthGate(
              pendingInviteCode: 'SP-8F3K9A',
              isEmbedded: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(PendingInviteStorage.pendingInviteCode, 'SP-8F3K9A');
      expect(
        find.text('Почти готово! Войди в аккаунт, чтобы добавить этого друга'),
        findsOneWidget,
      );
      expect(find.text('Хочешь добавлять друзей?'), findsOneWidget);
      PendingInviteStorage.clear();
    });

    testWidgets('AppSearchBar shows clear button inside suffixIcon only when text is not empty', (tester) async {
      final ctrl = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: AppSearchBar(controller: ctrl),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsNothing);

      await tester.enterText(find.byType(TextField), 'Магическая битва');
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(ctrl.text, isEmpty);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
    });

    testWidgets('SteamStyleProfileHeader renders VectorCountryFlag, copyable #Tag pill and interactive nickname editor', (tester) async {
      final profile = UserProfile(
        id: 'riku_1',
        username: 'Riku',
        tag: '#0421',
        countryFlag: '🇰🇬',
        countryName: 'Kyrgyzstan',
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SteamStyleProfileHeader(
                profile: profile,
                isCurrentUser: true,
                onEditProfileTap: () {},
                onCustomizerTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(VectorCountryFlag), findsOneWidget);
      expect(find.text('Kyrgyzstan'), findsOneWidget);
      expect(find.text('#0421'), findsOneWidget);
      expect(find.text('SyncPai'), findsNothing);

      // Нажимаем на #0421 для копирования тега
      await tester.tap(find.text('#0421'));
      await tester.pump();
      expect(find.text('Тег скопирован! Отправь его другу'), findsOneWidget);

      // Нажимаем на никнейм Riku — открывается диалог быстрого редактирования никнейма и статуса
      await tester.tap(find.text('Riku'));
      await tester.pumpAndSettle();
      expect(find.text('Никнейм и быстрый статус'), findsOneWidget);
    });
  });
}
