import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/services/mascot_companion_service.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/core/widgets/mascot/pai_companion_toast.dart';

void main() {
  setUp(() {
    MascotCompanionService.instance.resetForTest();
  });

  tearDown(() {
    MascotCompanionService.instance.resetForTest();
  });

  testWidgets('PaiCompanionToast renders as compact bottom pill on 360x800 small phone', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    MascotCompanionService.instance.showReaction(
      expression: MascotExpression.cheering,
      message: 'Вышла новая серия любимого аниме!',
      actionLabel: 'Смотреть',
      onAction: () {},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: SizedBox()),
              PaiCompanionToast(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final cardFinder = find.byKey(const ValueKey('pai_companion_toast_card'));
    expect(cardFinder, findsOneWidget);

    final rect = tester.getRect(cardFinder);
    // Must be docked near the bottom (above navbar), never covering top header
    expect(rect.top, greaterThan(600));
    expect(rect.height, greaterThanOrEqualTo(46));
    expect(rect.height, lessThan(90));
    // Redundant subtitle removed
    expect(find.textContaining('Пай-тян •'), findsNothing);
    MascotCompanionService.instance.dismiss();
    await tester.pump();
  });

  testWidgets('PaiCompanionToast renders as compact bottom pill on 412x915 Pixel 8 Pro', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    MascotCompanionService.instance.showReaction(
      expression: MascotExpression.curiousSearch,
      message: 'Продолжить чтение манги?',
      actionLabel: 'Читать с 12 гл.',
      onAction: () {},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: SizedBox()),
              PaiCompanionToast(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final rect = tester.getRect(find.byKey(const ValueKey('pai_companion_toast_card')));
    expect(rect.top, greaterThan(700));
    expect(rect.height, greaterThanOrEqualTo(46));
    expect(rect.height, lessThan(90));
    MascotCompanionService.instance.dismiss();
    await tester.pump();
  });

  test('MascotCompanionService suppresses generic welcome-back toast on activity', () {
    final service = MascotCompanionService.instance;
    service.reportUserActivity();
    expect(service.currentReaction, isNull);
  });
}
