import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/player/presentation/widgets/player_onboarding_overlay.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SettingsCubit persists hasSeenPlayerOnboarding and supports reset',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = SettingsCubit(prefs);
    expect(cubit.state.hasSeenPlayerOnboarding, isFalse);

    await cubit.completePlayerOnboarding();
    expect(cubit.state.hasSeenPlayerOnboarding, isTrue);

    final reloaded = SettingsCubit(prefs);
    expect(reloaded.state.hasSeenPlayerOnboarding, isTrue);

    await reloaded.resetPlayerOnboarding();
    expect(reloaded.state.hasSeenPlayerOnboarding, isFalse);

    await cubit.close();
    await reloaded.close();
  });

  testWidgets(
      'PlayerOnboardingOverlay walks through all 4 visual spotlight steps and dismisses',
      (tester) async {
    bool dismissed = false;
    final seenSteps = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerOnboardingOverlay(
            onStepChanged: seenSteps.add,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Step 1: Brightness (left 35%)
    expect(find.byKey(const ValueKey('player_onboarding_pill_banner')), findsOneWidget);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('Яркость — свайп слева'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_zone_brightness')), findsOneWidget);
    expect(find.text('Пропустить'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player_onboarding_next_btn')));
    await tester.pump(const Duration(milliseconds: 100));

    // Step 2: Volume (right 35%)
    expect(find.text('2 / 4'), findsOneWidget);
    expect(find.text('Громкость — свайп справа'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_zone_volume')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player_onboarding_next_btn')));
    await tester.pump(const Duration(milliseconds: 100));

    // Step 3: Double-tap ±10s
    expect(find.text('3 / 4'), findsOneWidget);
    expect(find.text('Перемотка ±10с — двойной тап'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_zone_seek_left')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_zone_seek_right')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player_onboarding_next_btn')));
    await tester.pump(const Duration(milliseconds: 100));

    // Step 4: Next episode & settings HUD spotlight
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.text('Следующая серия и настройки ⚙️'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_zone_hud_episodes')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding_zone_hud_settings')), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
    expect(seenSteps, [0, 1, 2, 3]);

    await tester.tap(find.byKey(const ValueKey('player_onboarding_dismiss_btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(dismissed, isTrue);
  });

  testWidgets('PlayerOnboardingOverlay Skip button dismisses immediately from step 1',
      (tester) async {
    bool dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerOnboardingOverlay(
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byKey(const ValueKey('player_onboarding_skip_btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(dismissed, isTrue);
  });
}
