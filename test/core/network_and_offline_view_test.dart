import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/network/network_status_helper.dart';
import 'package:sync_pai/core/widgets/pai_chan_offline_view.dart';

void main() {
  group('NetworkStatusHelper', () {
    tearDown(() {
      NetworkStatusHelper.testOverride = null;
    });

    test('respects testOverride true and false', () async {
      NetworkStatusHelper.testOverride = true;
      expect(await NetworkStatusHelper.hasInternet(), isTrue);

      NetworkStatusHelper.testOverride = false;
      expect(await NetworkStatusHelper.hasInternet(), isFalse);
    });

    test('isConnectionError correctly detects various socket and timeout errors', () {
      expect(NetworkStatusHelper.isConnectionError(null), isFalse);
      expect(NetworkStatusHelper.isConnectionError('SocketException: OS Error: Failed host lookup'), isTrue);
      expect(NetworkStatusHelper.isConnectionError('Connection timed out'), isTrue);
      expect(NetworkStatusHelper.isConnectionError('Нет подключения к интернету'), isTrue);
      expect(NetworkStatusHelper.isConnectionError('network is unreachable'), isTrue);
      expect(NetworkStatusHelper.isConnectionError('Normal error 404 Not Found'), isFalse);
    });
  });

  group('PaiChanOfflineView Widget Tests', () {
    testWidgets('renders title, subtitle, and retry button', (tester) async {
      bool retried = false;
      bool savedOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaiChanOfflineView(
              title: 'Нет подключения к интернету',
              subtitle: 'Пай-тян не может достучаться до сервера.',
              onRetry: () => retried = true,
              onOpenSaved: () => savedOpened = true,
            ),
          ),
        ),
      );

      expect(find.text('Нет подключения к интернету'), findsOneWidget);
      expect(find.text('Пай-тян не может достучаться до сервера.'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.text('Открыть сохранённое'), findsOneWidget);

      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(retried, isTrue);

      await tester.tap(find.text('Открыть сохранённое'));
      await tester.pump();
      expect(savedOpened, isTrue);
    });
  });
}
