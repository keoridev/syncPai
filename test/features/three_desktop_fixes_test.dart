import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/auth/domain/repositories/auth_repository.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_state.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_updates.dart';
import 'package:sync_pai/features/catalog/domain/usecases/search_titles.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:sync_pai/features/profile/domain/entities/steam_profile_customization.dart';
import 'package:sync_pai/features/profile/presentation/widgets/pai_chan_artwork_banner.dart';
import 'package:sync_pai/features/profile/services/avatar_upload_service.dart';

class _SearchCatalogRepo implements CatalogRepository {
  List<AnimeTitle> searchResults = const [];

  @override
  Future<List<AnimeTitle>> getUpdates({int page = 1, int limit = 20}) async =>
      const [];

  @override
  Future<List<AnimeTitle>> searchTitles(String query, {int limit = 20}) async =>
      searchResults;

  @override
  Future<AnimeTitle> getTitleDetails({int? id, String? code}) async =>
      throw UnimplementedError();
}

class _FakeAuthRepository implements AuthRepository {
  UserProfile current;
  final _ctrl = StreamController<UserProfile?>.broadcast();
  final List<String?> savedAvatarUrls = [];

  _FakeAuthRepository(this.current);

  @override
  Future<UserProfile> getCurrentProfile() async => current;

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
    savedAvatarUrls.add(avatarUrl);
    current = current.copyWith(
      username: username,
      avatarUrl: avatarUrl ?? current.avatarUrl,
    );
    _ctrl.add(current);
    return current;
  }

  @override
  Future<UserProfile> updateCustomization(ProfileCustomization customization) async =>
      current;

  @override
  UserProfile? getCachedProfile() => current;

  @override
  Future<UserProfile> signInAnonymously() async => current;

  @override
  Future<UserProfile> signInWithEmail({
    required String email,
    required String password,
  }) async =>
      current;

  @override
  Future<UserProfile> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async =>
      current;

  @override
  Future<UserProfile> signUpWithEmail({
    required String email,
    required String password,
    String? username,
  }) async =>
      current;

  @override
  Future<UserProfile?> signInWithGoogle() async => current;

  @override
  Future<UserProfile> linkGoogleAccount({
    required String email,
    String? displayName,
    String? photoUrl,
  }) async =>
      current;

  @override
  Future<void> signOut() async {}

  @override
  Stream<UserProfile?> get authStateChanges => _ctrl.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('CatalogScreen search clears bottom spinner and shows empty search state cleanly',
      (tester) async {
    final repo = _SearchCatalogRepo();
    repo.searchResults = const [
      AnimeTitle(
        id: 501,
        code: 'bocchi',
        russianTitle: 'Рок-тихоня',
        englishTitle: 'Bocchi the Rock!',
        description: 'История о гитаристке.',
        status: 'Завершён',
        genres: ['Комедия'],
        posterSmall: '',
        posterMedium: '',
        posterOriginal: '',
        year: 2022,
      ),
    ];

    final cubit = CatalogCubit(
      getUpdates: GetUpdates(repo),
      searchTitles: SearchTitles(repo),
    );
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    cubit.emit(const CatalogLoaded(titles: [], filteredTitles: []));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CatalogScreen(),
        ),
      ),
    );
    await tester.pump();

    // 1. Поиск с < pageSize (1 элемент): hasMore=false, isLoadingMore=false, спиннера внизу нет
    await cubit.performSearch('Рок');
    await tester.pump();
    final loaded = cubit.state as CatalogLoaded;
    expect(loaded.hasMore, isFalse);
    expect(loaded.isLoadingMore, isFalse);
    expect(loaded.isSearching, isFalse);
    expect(find.byKey(const ValueKey('catalog_bottom_pagination_spinner')), findsNothing);
    expect(find.text('Рок-тихоня'), findsOneWidget);

    // 2. Поиск с пустым ответом: чистый empty state + «Сбросить поиск», спиннера нет
    repo.searchResults = const [];
    await cubit.performSearch('НесуществующийТайтл123');
    await tester.pump();
    expect(find.byKey(const ValueKey('catalog_bottom_pagination_spinner')), findsNothing);
    expect(find.text('По запросу ничего не найдено'), findsOneWidget);
    expect(find.text('Сбросить поиск'), findsOneWidget);

    await cubit.close();
  });

  testWidgets('PaiChanArtworkBanner uses Alignment(0, -0.35) and 245px height on desktop',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PaiChanArtworkBanner(
            artworkId: 'pai_hacker_art',
            width: 800,
            height: 245,
          ),
        ),
      ),
    );
    await tester.pump();

    final desktopImg = tester.widget<Image>(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/banners/pai_hacker_bg.png',
      ),
    );
    expect(desktopImg.alignment, const Alignment(0.0, -0.35));
    expect(tester.getSize(find.byType(PaiChanArtworkBanner)).height, 245.0);
  });

  testWidgets('PaiChanArtworkBanner uses 195px height and Alignment(0, -0.35) on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PaiChanArtworkBanner(
            artworkId: 'pai_hacker_art',
            width: 360,
            height: 195,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byType(PaiChanArtworkBanner)).height, 195.0);
  });

  test('AvatarUploadService compresses oversized images to <=512px JPEG and detects local paths',
      () {
    final huge = img.Image(width: 1024, height: 768);
    img.fill(huge, color: img.ColorRgb8(53, 217, 213));
    final rawPng = Uint8List.fromList(img.encodePng(huge));

    final jpegBytes = AvatarUploadService.compressAvatarToJpeg(rawPng);
    final decoded = img.decodeJpg(jpegBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 384);

    expect(
      AvatarUploadService.isLocalFilePath('/data/user/0/com.syncpai/cache/custom_avatar_1.jpg'),
      isTrue,
    );
    expect(
      AvatarUploadService.isLocalFilePath(r'C:\Users\emame\Documents\custom_avatar.jpg'),
      isTrue,
    );
    expect(
      AvatarUploadService.isLocalFilePath('https://xyz.supabase.co/storage/v1/object/public/avatars/u1/avatar.jpg'),
      isFalse,
    );
  });

  test('AuthCubit.updateProfile keeps optimistic local preview then persists HTTPS cloud URL',
      () async {
    final initial = UserProfile(
      id: 'user-123',
      username: 'Keori',
      avatarUrl: null,
      createdAt: DateTime(2026, 11, 20),
    );
    final repo = _FakeAuthRepository(initial);
    final cubit = AuthCubit(repository: repo);
    await Future<void>.delayed(Duration.zero);

    final tinyImg = img.Image(width: 64, height: 64);
    final bytes = Uint8List.fromList(img.encodeJpg(tinyImg, quality: 85));
    const localPreviewPath = '/data/user/0/com.syncpai/app_flutter/custom_avatar_1.jpg';
    const expectedHttpsUrl =
        'https://proj.supabase.co/storage/v1/object/public/avatars/user-123/avatar_999.jpg';

    final states = <UserProfile>[];
    final sub = cubit.stream.listen((st) {
      if (st is Authenticated) states.add(st.profile);
    });

    await cubit.updateProfile(
      username: 'Keori',
      avatarUrl: localPreviewPath,
      avatarBytes: bytes,
      avatarUploader: (b, uid) async {
        expect(uid, 'user-123');
        expect(b, isNotEmpty);
        return expectedHttpsUrl;
      },
    );

    // 1й оптимистичный стейт показывает локальный путь сразу; финальный сохраняет HTTPS URL в облаке и состоянии
    expect(states.first.avatarUrl, localPreviewPath);
    expect(repo.savedAvatarUrls.last, expectedHttpsUrl);
    expect((cubit.state as Authenticated).profile.avatarUrl, expectedHttpsUrl);

    await sub.cancel();
    await cubit.close();
  });
}
