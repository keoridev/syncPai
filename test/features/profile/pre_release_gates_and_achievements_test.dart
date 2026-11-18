import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/widgets/auth_gate_sheet.dart';
import 'package:sync_pai/features/profile/domain/services/achievement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AuthGateSheet renders login prompt and primary action cleanly',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AuthGateSheet.show(context),
              child: const Text('Создать комнату Вместе'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Создать комнату Вместе'));
    await tester.pumpAndSettle();

    expect(find.text('Требуется профиль SyncPai'), findsOneWidget);
    expect(find.byKey(const ValueKey('auth_gate_login_btn')), findsOneWidget);
  });

  test('AchievementService tracks watch_hour (60m), op_skipper (5x), and bug_hunter metadata',
      () async {
    final service = AchievementService.instance;
    await service.init();

    await service.addWatchSeconds(2520); // 42 минуты
    expect(await service.getCurrentProgress('watch_hour'), 42);
    expect(service.unlockedIds.contains('watch_hour'), isFalse);

    await service.addWatchSeconds(1080); // +18 минут = 60 минут
    expect(await service.getCurrentProgress('watch_hour'), 60);
    expect(service.unlockedIds.contains('watch_hour'), isTrue);

    for (int i = 0; i < 4; i++) {
      await service.recordOpeningSkipped();
    }
    expect(await service.getCurrentProgress('op_skipper'), 4);
    expect(service.unlockedIds.contains('op_skipper'), isFalse);

    await service.recordOpeningSkipped();
    expect(await service.getCurrentProgress('op_skipper'), 5);
    expect(service.unlockedIds.contains('op_skipper'), isTrue);

    final bugHunter = kSyncPaiAchievements.firstWhere((b) => b.id == 'bug_hunter');
    expect(bugHunter.title, 'Кодинг-хакер');
    expect(bugHunter.rarity, 'Эксклюзив');
  });
}

