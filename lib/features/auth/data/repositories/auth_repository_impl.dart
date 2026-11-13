import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/api_constants.dart';
import '../../../anime_lists/domain/repositories/anime_list_repository.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final SharedPreferences _prefs;
  final StreamController<UserProfile?> _authController = StreamController<UserProfile?>.broadcast();

  static const String _profileKey = 'sync_pai_user_profile';
  static const String _localGuestUuidKey = 'sync_pai_local_guest_uuid';

  /// Флаг: если в Supabase отключён Anonymous Sign-In (422 anonymous_provider_disabled),
  /// не повторяем сетевые запросы signInAnonymously и работаем в режиме LocalGuestUser.
  static bool _anonymousProviderDisabled = false;

  AuthRepositoryImpl(this._prefs) {
    _initSupabaseListener();
  }

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  void _initSupabaseListener() {
    final client = _supabase;
    if (client != null) {
      client.auth.onAuthStateChange.listen((data) async {
        final session = data.session;
        if (session != null) {
          final profile = await _fetchAndMigrateCloudProfile(session.user);
          await _saveLocalProfile(profile);
          _authController.add(profile);
        } else {
          final local = _loadLocalProfile();
          _authController.add(local);
        }
      });
    }
  }

  String _getOrCreateLocalGuestUuid() {
    final existing = _prefs.getString(_localGuestUuidKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }
    final rnd = Random();
    String hex(int len) => List.generate(len, (_) => rnd.nextInt(16).toRadixString(16)).join();
    final uuid = '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
    _prefs.setString(_localGuestUuidKey, uuid);
    return uuid;
  }

  UserProfile _loadLocalProfile() {
    final raw = _prefs.getString(_profileKey);
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final parsed = UserProfile.fromJson(map);
        if (parsed.id.isNotEmpty) {
          _prefs.setString(_localGuestUuidKey, parsed.id);
          return parsed;
        }
      } catch (_) {}
    }
    final localUuid = _getOrCreateLocalGuestUuid();
    final guest = UserProfile.guest(localUuid);
    _saveLocalProfile(guest);
    return guest;
  }

  Future<void> _saveLocalProfile(UserProfile profile) async {
    await _prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  /// КРИТИЧЕСКИЙ МЕХАНИЗМ БЕСШОВНОЙ МИГРАЦИИ:
  /// При авторизации (Google или Email/Password) данные пользователя, настроенные в гостевом режиме
  /// (кастомный арт, неоновая рамка, аватар, никнейм, статус, цитата, любимый тайтл, списки)
  /// НИ В КОЕМ СЛУЧАЕ НЕ СБРАСЫВАЮТСЯ, а бережно объединяются с аккаунтом и отправляются в облако!
  Future<UserProfile> _fetchAndMigrateCloudProfile(
    User user, {
    String? explicitUsername,
  }) async {
    final client = _supabase;
    final isAnon = user.isAnonymous;
    final metadata = user.userMetadata ?? {};
    final googleName = metadata['full_name'] as String? ?? metadata['name'] as String?;
    final googleAvatar = metadata['avatar_url'] as String? ?? metadata['picture'] as String?;

    // Считываем текущий локальный профиль (настройки гостя)
    final local = _loadLocalProfile();

    Map<String, dynamic>? cloudRow;
    if (client != null) {
      try {
        cloudRow = await client
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();
      } catch (e) {
        debugPrint('Error fetching cloud profile: $e');
      }
    }

    // 1. Имя пользователя
    final localHasCustomName = local.username.isNotEmpty &&
        !local.username.startsWith('Сенпай #') &&
        !local.username.startsWith('Гость #') &&
        local.username != 'Анимешник';

    String effectiveUsername;
    if (explicitUsername != null && explicitUsername.trim().isNotEmpty) {
      effectiveUsername = explicitUsername.trim();
    } else if (cloudRow != null &&
        (cloudRow['username'] as String?)?.isNotEmpty == true &&
        cloudRow['username'] != 'Анимешник' &&
        !(cloudRow['username'] as String).startsWith('Гость #')) {
      effectiveUsername = cloudRow['username'] as String;
    } else if (localHasCustomName) {
      effectiveUsername = local.username;
    } else {
      effectiveUsername = googleName ?? local.username;
    }

    // 2. Аватарка
    String? effectiveAvatar = cloudRow?['avatar_url'] as String?;
    if (effectiveAvatar == null || effectiveAvatar == 'cat' || effectiveAvatar.isEmpty) {
      if (local.avatarUrl != null && local.avatarUrl != 'cat' && local.avatarUrl!.isNotEmpty) {
        effectiveAvatar = local.avatarUrl;
      } else {
        effectiveAvatar = googleAvatar ?? local.avatarUrl ?? 'cat';
      }
    }

    // 3. Рамка Steam (frameId) - если в облаке нет или 'none', сохраняем локально выбранную
    String effectiveFrame = (cloudRow?['avatar_frame_id'] as String?) ??
        (cloudRow?['frame_id'] as String?) ??
        'none';
    if (effectiveFrame == 'none' && local.frameId != null && local.frameId != 'none') {
      effectiveFrame = local.frameId!;
    }

    // 4. Фон Steam (backgroundId) - если в облаке нет или 'none', переносим локальный арт/GIF
    String effectiveBg = (cloudRow?['background_url'] as String?) ??
        (cloudRow?['background_id'] as String?) ??
        'none';
    if (effectiveBg == 'none' && local.backgroundId != null && local.backgroundId != 'none') {
      effectiveBg = local.backgroundId!;
    }

    // 5. Кастомный титул
    String? effectiveTitle = cloudRow?['custom_title'] as String?;
    if ((effectiveTitle == null || effectiveTitle.isEmpty) &&
        local.customTitle != null &&
        local.customTitle!.isNotEmpty) {
      effectiveTitle = local.customTitle;
    }

    // 6. Кастомный статус
    String effectiveStatus = (cloudRow?['custom_status'] as String?) ?? 'Смотрю аниме...';
    if ((effectiveStatus == 'Смотрю аниме...' || effectiveStatus.isEmpty) &&
        local.customStatus != null &&
        local.customStatus != 'Смотрю аниме...' &&
        local.customStatus!.isNotEmpty) {
      effectiveStatus = local.customStatus!;
    }

    // 7. Цитата / О себе (Bio)
    String? effectiveBio = cloudRow?['bio'] as String?;
    if ((effectiveBio == null || effectiveBio.isEmpty) &&
        local.bio != null &&
        local.bio!.isNotEmpty) {
      effectiveBio = local.bio;
    }

    // 8. Значок Steam (Badge)
    String? effectiveBadge = cloudRow?['badge_id'] as String?;
    if ((effectiveBadge == null || effectiveBadge.isEmpty) && local.badgeId != null) {
      effectiveBadge = local.badgeId;
    }

    // 9. Любимый тайтл витрины
    String? effectiveFavAnimeTitle =
        cloudRow?['favorite_anime_title'] as String? ?? local.favoriteAnimeTitle;
    String? effectiveFavAnimeId =
        cloudRow?['favorite_anime_id'] as String? ?? local.favoriteAnimeId;
    String? effectiveFavAnimePoster =
        cloudRow?['favorite_anime_poster'] as String? ?? local.favoriteAnimePoster;
    String? effectiveArtworkUrl =
        cloudRow?['artwork_url'] as String? ?? local.artworkUrl;
    String? effectiveArtworkTitle =
        cloudRow?['artwork_title'] as String? ?? local.artworkTitle;

    // 10. Акцентный цвет
    String effectiveAccent =
        (cloudRow?['accent_color'] as String?) ?? local.accentColor ?? '#E06C53';

    final merged = UserProfile(
      id: user.id,
      username: effectiveUsername,
      avatarUrl: effectiveAvatar,
      frameId: effectiveFrame,
      backgroundId: effectiveBg,
      customTitle: effectiveTitle,
      customStatus: effectiveStatus,
      bio: effectiveBio,
      badgeId: effectiveBadge ?? 'sync_master',
      favoriteAnimeTitle: effectiveFavAnimeTitle,
      favoriteAnimeId: effectiveFavAnimeId,
      favoriteAnimePoster: effectiveFavAnimePoster,
      artworkUrl: effectiveArtworkUrl,
      artworkTitle: effectiveArtworkTitle,
      accentColor: effectiveAccent,
      isAnonymous: isAnon,
      createdAt: DateTime.tryParse(cloudRow?['created_at'] as String? ?? '') ?? DateTime.now(),
    );

    // Сохраняем объединенный профиль в Supabase и локальный кэш
    await _upsertCloudProfile(merged);
    await _saveLocalProfile(merged);

    // Фоновая синхронизация закладок/списков с новым аккаунтом
    try {
      if (getIt.isRegistered<AnimeListRepository>()) {
        unawaited(getIt<AnimeListRepository>().syncWithCloud(userId: user.id));
      }
    } catch (e) {
      debugPrint('Background anime list sync error on auth: $e');
    }

    return merged;
  }

  Future<void> _upsertCloudProfile(UserProfile profile) async {
    final client = _supabase;
    if (client != null) {
      try {
        await client.from('profiles').upsert({
          'id': profile.id,
          'username': profile.username,
          'avatar_url': profile.avatarUrl,
          'avatar_frame_id': profile.frameId,
          'background_url': profile.backgroundId,
          'custom_title': profile.customTitle,
          'custom_status': profile.customStatus,
          'bio': profile.bio,
          'badge_id': profile.badgeId,
          'favorite_anime_title': profile.favoriteAnimeTitle,
          'favorite_anime_id': profile.favoriteAnimeId,
          'favorite_anime_poster': profile.favoriteAnimePoster,
          'artwork_url': profile.artworkUrl,
          'artwork_title': profile.artworkTitle,
          'accent_color': profile.accentColor,
          'showcase_type': profile.showcaseType,
          'customization': profile.customization.toJson(),
          'created_at': profile.createdAt.toIso8601String(),
        });
      } catch (e) {
        debugPrint('Error upserting cloud profile: $e');
        // Fallback: запись со стандартным набором полей profiles (id, username, avatar_url, created_at)
        try {
          await client.from('profiles').upsert({
            'id': profile.id,
            'username': profile.username,
            'avatar_url': profile.avatarUrl ?? '🐱',
            'created_at': profile.createdAt.toIso8601String(),
          });
          debugPrint('[Auth] Успешная запись базового профиля в Supabase profiles: ${profile.id}');
        } catch (e2) {
          debugPrint('Error upserting minimal cloud profile: $e2');
        }
      }
    }
  }

  @override
  Future<UserProfile> getCurrentProfile() async {
    final client = _supabase;
    if (client != null && client.auth.currentUser != null) {
      final user = client.auth.currentUser!;
      final cloud = await _fetchAndMigrateCloudProfile(user);
      return cloud;
    }

    final local = _loadLocalProfile();
    // Если есть подключение к Supabase, сессии нет и анонимный провайдер не отключён — пробуем анонимный вход
    if (client != null && client.auth.currentUser == null && !_anonymousProviderDisabled) {
      try {
        return await signInAnonymously();
      } catch (_) {}
    }
    return local;
  }

  @override
  Future<UserProfile> signInAnonymously() async {
    final local = _loadLocalProfile();
    if (_anonymousProviderDisabled) {
      _authController.add(local);
      return local;
    }

    final client = _supabase;
    if (client != null) {
      try {
        final res = await client.auth.signInAnonymously();
        if (res.user != null) {
          final profile = await _fetchAndMigrateCloudProfile(res.user!);
          await _saveLocalProfile(profile);
          _authController.add(profile);
          return profile;
        }
      } on AuthException catch (authErr) {
        final isAnonDisabled = authErr.statusCode == '422' ||
            (authErr.code?.toLowerCase().contains('anonymous_provider_disabled') ?? false) ||
            authErr.message.toLowerCase().contains('anonymous');
        if (isAnonDisabled) {
          _anonymousProviderDisabled = true;
          debugPrint(
            '⚠️ [SyncPai Auth] Анонимная авторизация отключена на сервере Supabase (422: anonymous_provider_disabled).\n'
            '👉 Чтобы включить облачные сессии гостей, откройте Supabase Dashboard -> Authentication -> Providers -> Anonymous и включите тумблер "Allow anonymous sign-ins".\n'
            '✅ Приложение переключено в локальный гостевой режим (LocalGuestUser UUID: ${local.id}). Комнаты, списки и профиль работают штатно.',
          );
        } else {
          debugPrint('⚠️ [SyncPai Auth] Supabase AuthException (${authErr.statusCode}): ${authErr.message}. Используется LocalGuestUser (${local.id}).');
        }
      } catch (e) {
        debugPrint('⚠️ [SyncPai Auth] Сеть недоступна при анонимном входе ($e). Используется LocalGuestUser (${local.id}).');
      }
    }

    await _saveLocalProfile(local);
    _authController.add(local);
    return local;
  }

  @override
  Future<UserProfile?> signInWithGoogle() async {
    try {
      final client = _supabase;
      final bool isDesktopOS = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

      if (isDesktopOS && client != null) {
        try {
          await client.auth.signInWithOAuth(
            OAuthProvider.google,
            redirectTo: 'syncpai://login-callback',
          );
          final user = client.auth.currentUser;
          if (user != null) {
            final profile = await _fetchAndMigrateCloudProfile(user);
            await _saveLocalProfile(profile);
            _authController.add(profile);
            return profile;
          }
        } catch (oauthErr) {
          debugPrint('[Auth] Desktop signInWithOAuth warning: $oauthErr');
        }
      }

      GoogleSignInAccount? googleUser;
      try {
        final googleSignIn = GoogleSignIn(
          serverClientId: ApiConstants.googleServerClientId.isNotEmpty
              ? ApiConstants.googleServerClientId
              : null,
          scopes: ['email', 'profile'],
        );
        googleUser = await googleSignIn.signIn();
      } catch (nativeErr) {
        debugPrint('[Auth] Native GoogleSignIn error: $nativeErr. Falling back to Supabase OAuth...');
        if (client != null) {
          try {
            await client.auth.signInWithOAuth(
              OAuthProvider.google,
              redirectTo: 'syncpai://login-callback',
            );
            final user = client.auth.currentUser;
            if (user != null) {
              final profile = await _fetchAndMigrateCloudProfile(user);
              await _saveLocalProfile(profile);
              _authController.add(profile);
              return profile;
            }
          } catch (oauthErr) {
            debugPrint('[Auth] Supabase OAuth fallback failed: $oauthErr');
          }
        }
        rethrow;
      }

      if (googleUser == null) {
        // Пользователь отменил системный диалог выбора аккаунта
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (client != null && idToken != null) {
        try {
          await client.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: accessToken,
          );

          final user = client.auth.currentUser;
          if (user != null) {
            final profile = await _fetchAndMigrateCloudProfile(user);
            await _saveLocalProfile(profile);
            _authController.add(profile);
            return profile;
          }
        } catch (supabaseErr) {
          debugPrint('Supabase signInWithIdToken warning: $supabaseErr. Using local Google profile link.');
        }
      }

      // Бесшовный fallback: связываем полученный профиль Google локально и в облаке
      final local = await linkGoogleAccount(
        email: googleUser.email,
        displayName: googleUser.displayName,
        photoUrl: googleUser.photoUrl,
      );
      return local;
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      rethrow;
    }
  }

  @override
  Future<UserProfile> linkGoogleAccount({
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    final local = _loadLocalProfile();
    final client = _supabase;

    // Ни в коем случае не затираем кастомный арт, ник или оформление!
    final localHasCustomName = local.username.isNotEmpty &&
        !local.username.startsWith('Сенпай #') &&
        !local.username.startsWith('Гость #') &&
        local.username != 'Анимешник';

    final effectiveName = localHasCustomName
        ? local.username
        : (displayName != null && displayName.trim().isNotEmpty
            ? displayName.trim()
            : local.username);

    final effectiveAvatar = (local.avatarUrl != null &&
            local.avatarUrl != 'cat' &&
            local.avatarUrl!.isNotEmpty)
        ? local.avatarUrl
        : (photoUrl != null && photoUrl.isNotEmpty ? photoUrl : local.avatarUrl);

    final updated = local.copyWith(
      username: effectiveName,
      avatarUrl: effectiveAvatar,
      email: email.trim(),
      provider: 'google',
      isAnonymous: false,
    );

    await _saveLocalProfile(updated);
    if (client != null) {
      if (client.auth.currentSession == null) {
        try {
          await client.auth.signInAnonymously();
        } catch (_) {}
      }
      final currentUid = client.auth.currentUser?.id;
      final profileToSync = currentUid != null && currentUid.isNotEmpty
          ? updated.copyWith(id: currentUid)
          : updated;
      await _upsertCloudProfile(profileToSync);
    }
    _authController.add(updated);

    // Фоновая синхронизация списков
    try {
      if (getIt.isRegistered<AnimeListRepository>()) {
        unawaited(getIt<AnimeListRepository>().syncWithCloud(userId: updated.id));
      }
    } catch (e) {
      debugPrint('Background anime list sync error on linkGoogleAccount: $e');
    }

    return updated;
  }

  @override
  Future<UserProfile> signUpWithEmail({
    required String email,
    required String password,
    String? username,
  }) async {
    final client = _supabase;
    if (client != null) {
      try {
        final res = await client.auth.signUp(
          email: email.trim(),
          password: password,
          data: username != null && username.isNotEmpty
              ? {'full_name': username.trim(), 'name': username.trim()}
              : null,
        );

        if (res.user != null) {
          final profile = await _fetchAndMigrateCloudProfile(
            res.user!,
            explicitUsername: username,
          );
          await _saveLocalProfile(profile);
          _authController.add(profile);
          return profile;
        }
      } catch (e) {
        debugPrint('Supabase signUp error: $e');
        rethrow;
      }
    }

    // Офлайн/локальный фолбек для среды без Supabase
    final local = _loadLocalProfile();
    final migrated = local.copyWith(
      username: username != null && username.isNotEmpty ? username.trim() : local.username,
      isAnonymous: false,
    );
    await _saveLocalProfile(migrated);
    _authController.add(migrated);
    return migrated;
  }

  @override
  Future<UserProfile> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final client = _supabase;
    if (client != null) {
      try {
        final res = await client.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );

        if (res.user != null) {
          final profile = await _fetchAndMigrateCloudProfile(res.user!);
          await _saveLocalProfile(profile);
          _authController.add(profile);
          return profile;
        }
      } catch (e) {
        debugPrint('Supabase signIn error: $e');
        rethrow;
      }
    }

    // Офлайн/локальный фолбек
    final local = _loadLocalProfile();
    final migrated = local.copyWith(isAnonymous: false);
    await _saveLocalProfile(migrated);
    _authController.add(migrated);
    return migrated;
  }

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
    final current = await getCurrentProfile();
    final updated = current.copyWith(
      username: username,
      avatarUrl: avatarUrl ?? current.avatarUrl,
      frameId: frameId ?? current.frameId,
      backgroundId: backgroundId ?? current.backgroundId,
      customTitle: customTitle ?? current.customTitle,
      customStatus: customStatus ?? current.customStatus,
      bio: bio ?? current.bio,
      badgeId: badgeId ?? current.badgeId,
      favoriteAnimeTitle: favoriteAnimeTitle != null
          ? (favoriteAnimeTitle.isEmpty ? null : favoriteAnimeTitle)
          : current.favoriteAnimeTitle,
      favoriteAnimeId: favoriteAnimeId != null
          ? (favoriteAnimeId.isEmpty ? null : favoriteAnimeId)
          : current.favoriteAnimeId,
      favoriteAnimePoster: favoriteAnimePoster != null
          ? (favoriteAnimePoster.isEmpty ? null : favoriteAnimePoster)
          : current.favoriteAnimePoster,
      artworkUrl: artworkUrl != null
          ? (artworkUrl.isEmpty ? null : artworkUrl)
          : current.artworkUrl,
      artworkTitle: artworkTitle != null
          ? (artworkTitle.isEmpty ? null : artworkTitle)
          : current.artworkTitle,
      accentColor: accentColor ?? current.accentColor,
      showcaseType: showcaseType ?? current.showcaseType,
      countryFlag: countryFlag ?? current.countryFlag,
      countryName: countryName ?? current.countryName,
      avatarShape: avatarShape ?? current.avatarShape,
    );

    await _saveLocalProfile(updated);
    await _upsertCloudProfile(updated);
    _authController.add(updated);
    return updated;
  }

  @override
  Future<void> signOut() async {
    final client = _supabase;
    if (client != null) {
      try {
        await client.auth.signOut();
      } catch (_) {}
    }
    final guest = UserProfile.guest();
    await _saveLocalProfile(guest);
    _authController.add(guest);
  }

  @override
  Stream<UserProfile?> get authStateChanges => _authController.stream;
}
