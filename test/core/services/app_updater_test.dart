import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/services/app_updater_service.dart';
import 'package:sync_pai/core/widgets/update_available_dialog.dart';

void main() {
  group('AppUpdaterService version comparison & config parsing', () {
    test('compareVersions handles semantic versions, v prefix and +build', () {
      expect(AppUpdaterService.compareVersions('1.0.2', '1.0.1'), greaterThan(0));
      expect(AppUpdaterService.compareVersions('1.0.10', '1.0.2'), greaterThan(0));
      expect(AppUpdaterService.compareVersions('v1.2.0+5', '1.2.0'), equals(0));
      expect(AppUpdaterService.compareVersions('1.0.0', '1.1.0'), lessThan(0));
    });

    test('parseConfigRow selects platform URL and computes mandatory flag', () {
      final row = <String, dynamic>{
        'latest_version': '1.2.0',
        'min_required_version': '1.1.0',
        'changelog': '• Новый OTA-обновлятор\n• Исправления синхронизации',
        'android_apk_url': 'https://github.com/org/syncpai/releases/download/v1.2.0/app.apk',
        'windows_exe_url': 'https://github.com/org/syncpai/releases/download/v1.2.0/setup.exe',
      };

      final androidMandatory = AppUpdaterService.parseConfigRow(
        row: row,
        currentVersion: '1.0.0',
        isAndroidOverride: true,
        isWindowsOverride: false,
      );
      expect(androidMandatory, isNotNull);
      expect(androidMandatory!.downloadUrl, endsWith('.apk'));
      expect(androidMandatory.isMandatory, isTrue);

      final windowsOptional = AppUpdaterService.parseConfigRow(
        row: row,
        currentVersion: '1.1.0',
        isAndroidOverride: false,
        isWindowsOverride: true,
      );
      expect(windowsOptional, isNotNull);
      expect(windowsOptional!.downloadUrl, endsWith('.exe'));
      expect(windowsOptional.isMandatory, isFalse);

      final upToDate = AppUpdaterService.parseConfigRow(
        row: row,
        currentVersion: '1.2.0',
        isAndroidOverride: true,
        isWindowsOverride: false,
      );
      expect(upToDate, isNull);
    });
  });

  group('UpdateAvailableDialog UI', () {
    testWidgets('shows Позже button for optional update and hides it for mandatory update', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UpdateAvailableDialog(
              info: AppUpdateInfo(
                currentVersion: '1.0.0',
                latestVersion: '1.1.0',
                changelog: '• Быстрая загрузка деталей',
                downloadUrl: 'https://example.com/app.apk',
                isMandatory: false,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Доступно обновление!'), findsOneWidget);
      expect(find.text('v1.0.0 → v1.1.0'), findsOneWidget);
      expect(find.text('Обновить сейчас'), findsOneWidget);
      expect(find.text('Позже'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UpdateAvailableDialog(
              info: AppUpdateInfo(
                currentVersion: '1.0.0',
                latestVersion: '1.2.0',
                minRequiredVersion: '1.1.0',
                changelog: '• Обязательное обновление безопасности',
                downloadUrl: 'https://example.com/setup.exe',
                isMandatory: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Обновить сейчас'), findsOneWidget);
      expect(find.text('Позже'), findsNothing);
    });
  });
}

