import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/winter_theme/domain/services/winter_theme_service.dart';
import 'package:sync_pai/features/winter_theme/presentation/widgets/winter_snowfall_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final service = WinterThemeService.instance;
    await service.setWinterTheme(true);
    await service.setSnowfall(true);
    await service.setSnowInPlayer(false);
    while (service.isVideoPlayerActive) {
      service.exitVideoPlayer();
    }
  });

  testWidgets(
      'WinterSnowfallOverlay renders outside player, hides inside player by default, and renders when snowInPlayerEnabled is true',
      (tester) async {
    final service = WinterThemeService.instance;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: WinterSnowfallOverlay()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(service.shouldRenderSnowfall, isTrue);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(WinterSnowfallOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );

    // Открытие видеоплеера: снег по умолчанию скрыт
    service.enterVideoPlayer();
    await tester.pump();

    expect(service.isVideoPlayerActive, isTrue);
    expect(service.shouldRenderSnowfall, isFalse);
    expect(
      find.descendant(
        of: find.byType(WinterSnowfallOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );

    // Включаем "Снег во время просмотра аниме"
    await service.setSnowInPlayer(true);
    await tester.pump();

    expect(service.shouldRenderSnowfall, isTrue);
    expect(
      find.descendant(
        of: find.byType(WinterSnowfallOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('syncpai_snow_in_player_enabled'), isTrue);

    // Выход из плеера
    service.exitVideoPlayer();
    await tester.pump();
    expect(service.isVideoPlayerActive, isFalse);
    expect(service.shouldRenderSnowfall, isTrue);
  });
}

