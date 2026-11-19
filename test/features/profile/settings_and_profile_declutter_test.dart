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

  testWidgets('ProfileScreen mobile cleanup: 3 focused tabs (Обзор, Статистика, Сообщество), single showcase, full history sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapWithProviders(const ProfileScreen(), size: const Size(430, 932)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Tab 1 (Обзор): Header + Showcase + Favorite Anime + Recently Watched (clean, no Stats/Badges/Wall)
    expect(find.text('ГЛАВНАЯ ИЛЛЮСТРАЦИЯ'), findsNothing);
    expect(find.text('ВИТРИНА ИЛЛЮСТРАЦИЙ'), findsOneWidget);
    expect(find.text('Сменить арт'), findsOneWidget);
    expect(find.text('Сменить'), findsNothing);
    expect(find.text('Любимое аниме'), findsOneWidget);
    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Статистика'), findsOneWidget);
    expect(find.text('Сообщество'), findsOneWidget);
    expect(find.text('СТАТИСТИКА ПРОСМОТРА'), findsNothing);

    final customScrollFinder = find.byType(CustomScrollView).first;
    await tester.drag(customScrollFinder, const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.byKey(const ValueKey('profile_full_history_btn')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('profile_full_history_btn')));
    await tester.pumpAndSettle();
    expect(find.textContaining('История просмотров ('), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    // Tab 2 (Статистика): Stats + Badges with Все 9 ->
    await tester.drag(customScrollFinder, const Offset(0, 320));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Статистика'));
    await tester.pumpAndSettle();
    expect(find.text('СТАТИСТИКА ПРОСМОТРА'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('badges_view_all_btn')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('badges_view_all_btn')));
    await tester.tap(find.byKey(const ValueKey('badges_view_all_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Все достижения (9)'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();

    // Tab 3 (Сообщество): Friends + Comments Wall (3 записи)
    await tester.scrollUntilVisible(
      find.text('Сообщество'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Сообщество'));
    await tester.pumpAndSettle();
    expect(find.text('СТЕНА КОММЕНТАРИЕВ'), findsOneWidget);
    expect(find.text('3 записи'), findsOneWidget);
  });
}
