import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/theme/cubit/theme_cubit.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_gallery_widget.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/auth/domain/repositories/auth_repository.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/profile/presentation/screens/profile_screen.dart';
import 'package:sync_pai/features/settings/presentation/cubit/settings_cubit.dart';
import 'package:sync_pai/features/settings/presentation/screens/settings_screen.dart';

class _FakeAuthRepository implements AuthRepository {
  final _ctrl = StreamController<UserProfile?>.broadcast();
  final UserProfile _profile;

  _FakeAuthRepository(this._profile);

  @override
  Stream<UserProfile?> get authStateChanges => _ctrl.stream;

  @override
  Future<UserProfile> getCurrentProfile() async => _profile;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final getIt = GetIt.instance;

  late UserProfile testProfile;
  late AuthCubit authCubit;
  late ThemeCubit themeCubit;
  late SettingsCubit settingsCubit;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    testProfile = UserProfile(
      id: 'test-user-1',
      username: 'Keori',
      friendCode: 'SP-123456',
      createdAt: DateTime(2026, 11, 17),
    );

    authCubit = AuthCubit(repository: _FakeAuthRepository(testProfile));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    themeCubit = ThemeCubit(prefs);
    settingsCubit = SettingsCubit(prefs);

    getIt.registerSingleton<SharedPreferences>(prefs);
    getIt.registerSingleton<SettingsCubit>(settingsCubit);
    getIt.registerSingleton<ThemeCubit>(themeCubit);
    getIt.registerSingleton<AuthCubit>(authCubit);
  });

  tearDown(() async {
    await authCubit.close();
    await themeCubit.close();
    await settingsCubit.close();
    await getIt.reset();
  });

  Widget wrapWithProviders(Widget child, {Size size = const Size(390, 844)}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>.value(value: authCubit),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: child,
        ),
      ),
    );
  }

  testWidgets('SettingsScreen mobile declutter: filter chips, single mascot tile, unified clear sheet, symmetrical HUD buttons',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrapWithProviders(const SettingsScreen()));
    await tester.pumpAndSettle();

    // 1. Mobile filter bar & chips
    expect(find.byKey(const ValueKey('settings_mobile_filter_bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_filter_all')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_filter_player')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings_filter_appearance')), findsOneWidget);

    // 2. Filter to Player -> symmetrical HUD buttons visible, Appearance hidden
    await tester.tap(find.byKey(const ValueKey('settings_filter_player')));
    await tester.pumpAndSettle();

    expect(find.text('НАСТРОЙКИ ПЛЕЕРА И СИСТЕМЫ'), findsOneWidget);
    expect(find.text('ВНЕШНИЙ ВИД'), findsNothing);
    expect(find.byKey(const ValueKey('hud_customize_buttons_btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('hud_reset_default_btn')), findsOneWidget);
    expect(find.text('Настроить кнопки HUD'), findsOneWidget);
    expect(find.text('Сбросить'), findsOneWidget);
    expect(find.text('Очистить кэш плеера и историю'), findsNothing);

    // 3. Filter to Data -> unified clear cache & data tile opens selective sheet
    final filterScrollable = find.descendant(
      of: find.byKey(const ValueKey('settings_mobile_filter_bar')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings_filter_data')),
      150,
      scrollable: filterScrollable,
    );
    await tester.tap(find.byKey(const ValueKey('settings_filter_data')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings_clear_cache_data_tile')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_clear_cache_data_tile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('clear_opt_cache')), findsOneWidget);
    expect(find.byKey(const ValueKey('clear_opt_history')), findsOneWidget);
    expect(find.byKey(const ValueKey('clear_opt_lists')), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    // 4. Filter to Appearance -> single Mascot Gallery tile, inline grid collapsed until tapped
    await tester.tap(find.byKey(const ValueKey('settings_filter_appearance')));
    await tester.pumpAndSettle();

    expect(find.byType(MascotGalleryWidget), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings_mascot_gallery_tile')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('settings_mascot_gallery_tile')));
    await tester.pumpAndSettle();
    expect(find.text('Галерея маскота Пай-тян'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_mascot_gallery_tile')));
    await tester.pumpAndSettle();

    expect(find.byType(MascotGalleryWidget), findsOneWidget);
  });

  testWidgets('ProfileScreen mobile cleanup: single artwork showcase, compact 4-col badges with Все 9 ->, collapsed stats toggle',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithProviders(const ProfileScreen(), size: const Size(430, 932)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Single artwork showcase (no duplicate ГЛАВНАЯ ИЛЛЮСТРАЦИЯ, single 'Сменить арт')
    expect(find.text('ГЛАВНАЯ ИЛЛЮСТРАЦИЯ'), findsNothing);
    expect(find.text('ВИТРИНА ИЛЛЮСТРАЦИЙ'), findsOneWidget);
    expect(find.text('Сменить арт'), findsOneWidget);
    expect(find.text('Сменить'), findsNothing);
    expect(find.text('Любимое аниме'), findsOneWidget);

    // Scroll to Badges & Stats on Mobile
    final customScrollFinder = find.byType(CustomScrollView).first;
    await tester.drag(customScrollFinder, const Offset(0, -450));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byKey(const ValueKey('badges_view_all_btn')));
    await tester.pump(const Duration(milliseconds: 100));

    // Tap 'Все 9 →' to open full achievements sheet
    await tester.tap(find.byKey(const ValueKey('badges_view_all_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Все достижения (9)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    // Stats collapsed by default on mobile with 'Подробнее ▾'
    await tester.drag(customScrollFinder, const Offset(0, -220));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byKey(const ValueKey('stats_mobile_expand_btn')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Подробнее ▾'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stats_mobile_expand_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Свернуть ▴'), findsOneWidget);

    // Full watch history sheet opens on 'Вся история >'
    await tester.drag(customScrollFinder, const Offset(0, -240));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byKey(const ValueKey('profile_full_history_btn')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('profile_full_history_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('История просмотров ('), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    await tester.drag(customScrollFinder, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('3 записи'), findsOneWidget);
  });
}
