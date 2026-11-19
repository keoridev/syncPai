import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/core/theme/cubit/theme_cubit.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/auth/domain/repositories/auth_repository.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/profile/domain/entities/customization_tier_policy.dart';
import 'package:sync_pai/features/profile/domain/services/achievement_service.dart';
import 'package:sync_pai/features/profile/presentation/cubit/profile_cubit.dart';
import 'package:sync_pai/features/profile/presentation/widgets/steam_profile_customizer_sheet.dart';
import 'package:sync_pai/features/support/domain/entities/supporter_tier.dart';

class _FakeAuthRepo implements AuthRepository {
  final _ctrl = StreamController<UserProfile?>.broadcast();
  UserProfile current;
  _FakeAuthRepo(this.current);

  @override
  Stream<UserProfile?> get authStateChanges => _ctrl.stream;

  @override
  Future<UserProfile> getCurrentProfile() async => current;

  @override
  UserProfile? getCachedProfile() => current;

  @override
  Future<UserProfile> updateProfile({
    required String username,
    String? avatarUrl,
    String? frameId,
    String? backgroundId,
    String? customTitle,
    String? customStatus,
    String? bio,
    String? badgeId,
    String? favoriteAnimeTitle,
    String? favoriteAnimeId,
    String? favoriteAnimePoster,
    String? artworkUrl,
    String? artworkTitle,
    String? accentColor,
    String? showcaseType,
    String? countryFlag,
    String? countryName,
    String? avatarShape,
  }) async {
    current = current.copyWith(
      username: username,
      avatarUrl: avatarUrl,
      frameId: frameId,
      backgroundId: backgroundId,
      customTitle: customTitle,
      customStatus: customStatus,
      bio: bio,
      badgeId: badgeId,
      favoriteAnimeTitle: favoriteAnimeTitle,
      favoriteAnimeId: favoriteAnimeId,
      favoriteAnimePoster: favoriteAnimePoster,
      artworkUrl: artworkUrl,
      artworkTitle: artworkTitle,
      accentColor: accentColor,
      showcaseType: showcaseType,
      countryFlag: countryFlag,
      countryName: countryName,
      avatarShape: avatarShape,
    );
    _ctrl.add(current);
    return current;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CustomizationTierPolicy enforces 4 free frames/banners, 3 free themes, and Pro showcase gates', () {
    final freeFrames = CustomizationTierPolicy.frames
        .where((f) => f.requiredTier == SupporterTier.free)
        .toList();
    final animFrames = CustomizationTierPolicy.frames
        .where((f) => f.isAnimated)
        .toList();
    expect(freeFrames.length, 4);
    expect(animFrames.length, 3);

    final freeBanners = CustomizationTierPolicy.banners
        .where((b) => b.requiredTier == SupporterTier.free)
        .toList();
    final animBanners = CustomizationTierPolicy.banners
        .where((b) => b.isAnimated)
        .toList();
    expect(freeBanners.length, 4);
    expect(animBanners.length, 3);

    expect(CustomizationTierPolicy.freeThemeIds.length, 3);
    expect(
      CustomizationTierPolicy.isThemeUnlocked(SupporterTier.free, 'winter_2026'),
      isTrue,
    );
    expect(
      CustomizationTierPolicy.isThemeUnlocked(SupporterTier.free, 'eva_violet'),
      isFalse,
    );
    expect(
      CustomizationTierPolicy.isThemeUnlocked(SupporterTier.supporter, 'eva_violet'),
      isTrue,
    );

    expect(CustomizationTierPolicy.maxFavoriteAnimeCount(SupporterTier.free), 1);
    expect(CustomizationTierPolicy.maxFavoriteAnimeCount(SupporterTier.vip), 3);
    expect(CustomizationTierPolicy.canUseHeroArtwork(SupporterTier.free), isFalse);
    expect(CustomizationTierPolicy.canUseHeroArtwork(SupporterTier.vip), isTrue);
    expect(CustomizationTierPolicy.canEditCustomTitle(SupporterTier.free), isFalse);
    expect(CustomizationTierPolicy.canEditCustomTitle(SupporterTier.vip), isTrue);
  });

  test('AchievementService party_soul requires 3 distinct Watch-Together rooms', () async {
    final service = AchievementService.instance;
    await service.init();

    await service.recordWatchTogetherJoined('111111');
    await service.recordWatchTogetherJoined('111111');
    await service.recordWatchTogetherJoined('111111');
    expect(service.unlockedIds.contains('party_soul'), isFalse);

    await service.recordWatchTogetherJoined('222222');
    await service.recordWatchTogetherJoined('333333');
    expect(service.unlockedIds.contains('party_soul'), isTrue);
  });

  test('UserProfile tier getters & ProfileCubit.applyCustomization enforce Free vs Pro sanitization',
      () async {
    final freeUser = UserProfile(
      id: 'u-free',
      username: 'FreeUser',
      supporterTier: SupporterTier.free,
      createdAt: DateTime(2026, 11, 19),
    );
    expect(freeUser.isPlusOrHigher, isFalse);
    expect(freeUser.isProOrHigher, isFalse);

    final plusUser = freeUser.copyWith(supporterTier: SupporterTier.supporter);
    expect(plusUser.isPlusOrHigher, isTrue);
    expect(plusUser.isProOrHigher, isFalse);

    final proUser = freeUser.copyWith(supporterTier: SupporterTier.vip);
    expect(proUser.isPlusOrHigher, isTrue);
    expect(proUser.isProOrHigher, isTrue);

    final freeRepo = _FakeAuthRepo(freeUser);
    final freeCubit = ProfileCubit(authRepository: freeRepo);
    await freeCubit.loadProfile();

    final sanitizedFree = await freeCubit.applyCustomization(
      frameId: 'aurora', // Plus-only
      backgroundId: 'cyber_grid', // Pro-only
      customTitle: 'Взломщик', // Pro-only
      artworkUrl: 'live:sakura', // Pro-only
      artworkTitle: 'Сакура',
      favoriteAnimeTitle: 'Стальной алхимик',
      favoriteAnimeId: '5114',
      favoriteAnimePoster: 'https://example.com/fma.jpg',
    );
    expect(sanitizedFree.frameId, 'none');
    expect(sanitizedFree.backgroundId, 'none');
    expect(sanitizedFree.customTitle, isNull);
    expect(sanitizedFree.artworkUrl, isNull);
    expect(sanitizedFree.favoriteAnimeTitle, 'Стальной алхимик');
    await freeCubit.close();

    final proRepo = _FakeAuthRepo(proUser);
    final proCubit = ProfileCubit(authRepository: proRepo);
    await proCubit.loadProfile();
    final savedPro = await proCubit.applyCustomization(
      frameId: 'aurora',
      backgroundId: 'cyber_grid',
      customTitle: 'Архимаг Синхрона',
      artworkUrl: 'live:sakura',
      artworkTitle: 'Сакура',
    );
    expect(savedPro.frameId, 'aurora');
    expect(savedPro.backgroundId, 'cyber_grid');
    expect(savedPro.customTitle, 'Архимаг Синхрона');
    expect(savedPro.artworkUrl, 'live:sakura');
    await proCubit.close();
  });

  testWidgets('SteamProfileCustomizerSheet separates Artwork from Favorite Anime and gates Pro items on Free',
      (tester) async {
    await GetIt.instance.reset();
    final prefs = await SharedPreferences.getInstance();
    final freeProfile = UserProfile(
      id: 'u-free-ui',
      username: 'FreeUI',
      supporterTier: SupporterTier.free,
      favoriteAnimeTitle: 'Тетрадь смерти',
      favoriteAnimeId: '1535',
      favoriteAnimePoster: 'https://example.com/dn.jpg',
      createdAt: DateTime(2026, 11, 19),
    );
    final repo = _FakeAuthRepo(freeProfile);
    final authCubit = AuthCubit(repository: repo);
    final themeCubit = ThemeCubit(prefs);
    GetIt.instance.registerSingleton<SharedPreferences>(prefs);
    GetIt.instance.registerSingleton<ThemeCubit>(themeCubit);

    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await authCubit.close();
      await themeCubit.close();
      await GetIt.instance.reset();
    });

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>.value(value: authCubit),
          BlocProvider<ThemeCubit>.value(value: themeCubit),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SteamProfileCustomizerSheet(
              profile: freeProfile,
              initialTabIndex: 4, // Вкладка «Витрина»
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 1. Выбираем статичный арт под "1. Главная витрина иллюстраций" -> Любимый тайтл НЕ должен перезаписаться!
    expect(find.text('1. Главная витрина иллюстраций (Steam Artwork):'), findsOneWidget);
    await tester.tap(find.text('Самурай').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Тетрадь смерти'), findsWidgets);

    // 2. Тап по "+ Свой арт (Pro)" на Free аккаунте открывает SupporterGateSheet
    await tester.tap(find.text('Свой арт (Pro)'));
    await tester.pumpAndSettle();
    expect(find.text('Открыть в @syncpai_bot'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 3. Тап по чипу кастомного титула на Free аккаунте открывает SupporterGateSheet вместо ввода
    await tester.scrollUntilVisible(
      find.text('Кастомный титул профиля:'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Мастер Синхрона').first);
    await tester.pumpAndSettle();
    expect(find.text('Открыть в @syncpai_bot'), findsOneWidget);
  });

  test('CustomizationTierPolicy unlocks hacker_glitch, hacker_matrix, and pai_hacker only with bug_hunter badge', () {
    expect(
      CustomizationTierPolicy.isFrameUnlocked(SupporterTier.free, 'hacker_glitch'),
      isFalse,
    );
    expect(
      CustomizationTierPolicy.isBannerUnlocked(SupporterTier.free, 'hacker_matrix'),
      isFalse,
    );
    expect(
      CustomizationTierPolicy.isAvatarUnlocked('pai_hacker'),
      isFalse,
    );

    expect(
      CustomizationTierPolicy.isFrameUnlocked(
        SupporterTier.free,
        'hacker_glitch',
        unlockedBadges: const ['bug_hunter'],
      ),
      isTrue,
    );
    expect(
      CustomizationTierPolicy.isBannerUnlocked(
        SupporterTier.free,
        'hacker_matrix',
        unlockedBadges: const ['bug_hunter'],
      ),
      isTrue,
    );
    expect(
      CustomizationTierPolicy.isAvatarUnlocked(
        'pai_hacker',
        unlockedBadges: const ['bug_hunter'],
      ),
      isTrue,
    );

    final blocked = CustomizationTierPolicy.sanitizePayload(
      tier: SupporterTier.free,
      frameId: 'hacker_glitch',
      backgroundId: 'hacker_matrix',
    );
    expect(blocked.frameId, 'none');
    expect(blocked.backgroundId, 'none');

    final unlocked = CustomizationTierPolicy.sanitizePayload(
      tier: SupporterTier.free,
      frameId: 'hacker_glitch',
      backgroundId: 'hacker_matrix',
      unlockedBadges: const ['bug_hunter'],
    );
    expect(unlocked.frameId, 'hacker_glitch');
    expect(unlocked.backgroundId, 'hacker_matrix');
  });
}

