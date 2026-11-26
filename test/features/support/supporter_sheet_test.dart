import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/support/presentation/widgets/supporter_sheet.dart';

void main() {
  testWidgets('SupporterSheet renders flat matte tiers, Telegram CTA, and live feature request statuses', (tester) async {
    final requests = [
      FeatureRequestItem(
        id: 'req-1',
        title: 'Тёмная OLED-тема',
        description: 'Чистый чёрный фон',
        paymentStatus: 'paid',
        implementationStatus: 'in_progress',
        deadlineAt: DateTime(2026, 12, 3),
        createdAt: DateTime(2026, 11, 26),
      ),
      FeatureRequestItem(
        id: 'req-2',
        title: 'Синхронизация закладок',
        description: 'Авто-экспорт',
        paymentStatus: 'pending',
        implementationStatus: 'review',
        createdAt: DateTime(2026, 11, 25),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupporterSheet(
            userIdOverride: 'user-uuid-123',
            requestsLoaderOverride: () async => requests,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SyncPai Sponsor'), findsOneWidget);
    expect(find.text('Своя фича за 7 дней'), findsOneWidget);
    expect(find.byKey(const ValueKey('supporter_order_feature_btn')), findsOneWidget);
    expect(find.text('Тёмная OLED-тема'), findsOneWidget);
    expect(find.text('В работе • до 03.12'), findsOneWidget);
    expect(find.text('Синхронизация закладок'), findsOneWidget);
    expect(find.text('На проверке'), findsOneWidget);
  });
}

