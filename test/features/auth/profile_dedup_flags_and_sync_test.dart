import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sync_pai/core/widgets/vector_country_flag.dart';
import 'package:sync_pai/features/anime_details/data/datasources/syncpai_reviews_datasource.dart';
import 'package:sync_pai/features/anime_lists/domain/entities/user_anime_entry.dart';
import 'package:sync_pai/features/anime_lists/services/lists_sync_service.dart';
import 'package:sync_pai/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/auth/presentation/utils/auth_error_formatter.dart';
import 'package:sync_pai/features/auth/presentation/widgets/auth_modal_sheet.dart';
import 'package:sync_pai/features/sync_room/services/active_room_service.dart';
import 'package:sync_pai/features/sync_room/services/room_audio_devices_service.dart';
import 'package:sync_pai/features/winter_theme/domain/services/winter_theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AuthRepositoryImpl reuses local guest UUID across restarts without duplicates', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final repo1 = AuthRepositoryImpl(prefs);
    final profile1 = await repo1.getCurrentProfile();
    expect(profile1.id, isNotEmpty);
    expect(profile1.isAnonymous, isTrue);

    final repo2 = AuthRepositoryImpl(prefs);
    final profile2 = await repo2.getCurrentProfile();
    expect(profile2.id, profile1.id);
    expect(profile2.username, profile1.username);
  });

  test('AuthErrorFormatter formats email_not_confirmed and provider disabled errors', () {
    const emailNotConfirmed = AuthApiException(
      'Email not confirmed',
      statusCode: '400',
      code: 'email_not_confirmed',
    );
    expect(
      AuthErrorFormatter.format(emailNotConfirmed),
      contains('Email не подтвержден'),
    );

    const providerDisabled = AuthApiException(
      'Unsupported provider: provider is not enabled',
      statusCode: '400',
      code: 'validation_failed',
    );
    expect(AuthErrorFormatter.isProviderDisabledError(providerDisabled), isTrue);
    expect(
      AuthErrorFormatter.format(providerDisabled),
      'Вход через Google временно недоступен — используй вход по Email выше.',
    );
  });

  testWidgets('VectorCountryFlag uses CountryFlag.fromCountryCode and defaults to KG', (tester) async {
    expect(VectorCountryFlag.resolveCountryCode('🇰🇬', 'Kyrgyzstan'), 'KG');
    expect(VectorCountryFlag.resolveCountryCode(null, null), 'KG');
    expect(VectorCountryFlag.resolveCountryCode('🇯🇵', 'Japan'), 'JP');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VectorCountryFlag(
            countryFlag: '🇰🇬',
            countryName: 'Kyrgyzstan',
          ),
        ),
      ),
    );

    expect(find.byType(CountryFlag), findsOneWidget);
  });

  test('ListsSyncService maps UserAnimeEntry to exact user_anime_lists columns', () {
    final now = DateTime.utc(2026, 11, 16, 0, 30);
    final entry = UserAnimeEntry(
      id: '101',
      userId: 'user_abc',
      animeId: 101,
      titleRu: 'Провожающая в последний путь Фрирен',
      posterUrl: 'https://example.com/frieren.jpg',
      status: AnimeListStatus.watching,
      lastEpisode: 12,
      episodesTotal: 28,
      updatedAt: now,
    );

    final row = ListsSyncService.toSupabaseRow(entry, userId: 'user_abc', score: 9.5);
    expect(row['user_id'], 'user_abc');
    expect(row['anime_id'], 101);
    expect(row['anime_title'], 'Провожающая в последний путь Фрирен');
    expect(row['poster_url'], 'https://example.com/frieren.jpg');
    expect(row['category'], 'watching');
    expect(row['episodes_watched'], 12);
    expect(row['total_episodes'], 28);
    expect(row['score'], 9.5);
    expect(row['updated_at'], now.toIso8601String());

    final restored = UserAnimeEntry.fromJson(row);
    expect(restored.animeId, 101);
    expect(restored.titleRu, 'Провожающая в последний путь Фрирен');
    expect(restored.status, AnimeListStatus.watching);
    expect(restored.lastEpisode, 12);
    expect(restored.episodesTotal, 28);
  });

  test('SyncPaiReviewsDataSourceImpl maps anime_reviews columns accurately', () {
    final now = DateTime.utc(2026, 11, 16, 0, 35);
    final row = SyncPaiReviewsDataSourceImpl.toSupabaseRow(
      animeId: 52991,
      userId: 'user_123',
      authorName: 'Riku',
      authorAvatar: 'https://example.com/avatar.jpg',
      rating: 10,
      comment: 'Шедевр сезона!',
      likesCount: 42,
      createdAt: now,
    );

    expect(row['anime_id'], 52991);
    expect(row['user_id'], 'user_123');
    expect(row['author_name'], 'Riku');
    expect(row['author_avatar'], 'https://example.com/avatar.jpg');
    expect(row['rating'], 10);
    expect(row['comment'], 'Шедевр сезона!');
    expect(row['likes_count'], 42);
    expect(row['created_at'], now.toUtc().toIso8601String());

    final review = SyncPaiReviewsDataSourceImpl.fromSupabaseRow({
      'id': 'rev_1',
      ...row,
    });
    expect(review.authorName, 'Riku');
    expect(review.authorAvatarUrl, 'https://example.com/avatar.jpg');
    expect(review.score, 10.0);
    expect(review.content, 'Шедевр сезона!');
    expect(review.likes, 42);
  });

  testWidgets('ListenableBuilder with ChangeNotifier services never throws during build', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              // Имитируем вызов notifyListeners() прямо во время фазы build()
              ActiveRoomService.instance.notifyListeners();
              RoomAudioDevicesService.instance.notifyListeners();
              WinterThemeService.instance.notifyListeners();
              return Column(
                children: [
                  ListenableBuilder(
                    listenable: ActiveRoomService.instance,
                    builder: (_, __) => Text('Room: ${ActiveRoomService.instance.hasActiveRoom}'),
                  ),
                  ListenableBuilder(
                    listenable: RoomAudioDevicesService.instance,
                    builder: (_, __) => Text('Audio: ${RoomAudioDevicesService.instance.selectedInputId}'),
                  ),
                  ListenableBuilder(
                    listenable: WinterThemeService.instance,
                    builder: (_, __) => Text('Winter: ${WinterThemeService.instance.isWinterActive}'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Room:'), findsOneWidget);
    expect(find.textContaining('Audio:'), findsOneWidget);
    expect(find.textContaining('Winter:'), findsOneWidget);
  });

  testWidgets('AuthModalSheet displays Email or Login field on Login tab and Email on Register tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = AuthRepositoryImpl(prefs);
    final cubit = AuthCubit(repository: repo);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          home: Scaffold(
            body: AuthModalSheet(
              currentProfile: UserProfile.guest('guest_1'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Email или логин'), findsOneWidget);
    final loginHints = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((tf) => tf.decoration?.hintText)
        .toList();
    expect(loginHints, contains('sync или name@gmail.com'));

    await tester.tap(find.text('Регистрация'));
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('name@example.com'), findsOneWidget);
  });

  test('AuthRepositoryImpl.resolveOAuthRedirectTo splits Android/iOS deep link and Desktop loopback', () {
    expect(
      AuthRepositoryImpl.resolveOAuthRedirectTo(
        isWeb: false,
        isMobileOS: true,
        isDesktopOS: false,
      ),
      'syncpai://login-callback',
    );
    expect(
      AuthRepositoryImpl.resolveOAuthRedirectTo(
        isWeb: false,
        isMobileOS: false,
        isDesktopOS: true,
      ),
      'http://localhost:3000',
    );
    expect(
      AuthRepositoryImpl.resolveOAuthRedirectTo(
        isWeb: true,
        isMobileOS: false,
        isDesktopOS: false,
      ),
      isNull,
    );
  });
}

