import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/api_constants.dart';
import '../../../anime_lists/domain/repositories/anime_list_repository.dart';
import '../../../profile/domain/entities/steam_profile_customization.dart';
import '../../../profile/services/avatar_upload_service.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../presentation/utils/auth_error_formatter.dart';

class AuthRepositoryImpl implements AuthRepository {
  final SharedPreferences _prefs;
  final StreamController<UserProfile?> _authController =
      StreamController<UserProfile?>.broadcast();

  static const String _profileKey = 'sync_pai_user_profile';
  static const String _localGuestUuidKey = 'sync_pai_local_guest_uuid';

  /// В SyncPai гостевой режим работает исключительно локально без анонимных строк в Supabase.
  static const bool isAnonymousProviderDisabled = true;

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
          // 1. Мгновенная оптимистичная эмиссия сессии:
          // Если пользователь вошел, сразу создаем и эмитим профиль в поток (0ms UI unlock)
          final local = _loadLocalProfile();
          final fastProfile = local.copyWith(
            id: session.user.id,
            email: session.user.email ?? local.email,
            isAnonymous: session.user.isAnonymous,
            provider: session.user.appMetadata['provider'] as String? ??
                local.provider ??
                'google',
          );
          await _saveLocalProfile(fastProfile);
          _authController.add(fastProfile);

          // 2. Фоновая миграция данных и синхронизация списков (fire-and-forget в фоне)
          unawaited(() async {
            try {
              final fullProfile =
                  await _fetchAndMigrateCloudProfile(session.user);
              await _saveLocalProfile(fullProfile);
              _authController.add(fullProfile);
            } catch (e) {
              debugPrint('Background cloud profile migration error: $e');
            }
          }());
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
    String hex(int len) =>
        List.generate(len, (_) => rnd.nextInt(16).toRadixString(16)).join();
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
    final emailFromUser = user.email ?? metadata['email'] as String?;
    final emailPrefix = (emailFromUser != null && emailFromUser.contains('@'))
        ? emailFromUser.split('@').first.trim()
        : null;
    final googleName = metadata['full_name'] as String? ??
        metadata['name'] as String? ??
        (emailPrefix != null && emailPrefix.isNotEmpty ? emailPrefix : null);
    final googleAvatar =
        metadata['avatar_url'] as String? ?? metadata['picture'] as String?;

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

    // 1. Имя пользователя (без хардкода "Сенпай")
    final localHasCustomName =
        !UserProfile.isDefaultGeneratedNickname(local.username);
    final cloudUsername = cloudRow?['username'] as String?;
    final cloudHasCustomName =
        !UserProfile.isDefaultGeneratedNickname(cloudUsername);

    String effectiveUsername;
    if (explicitUsername != null && explicitUsername.trim().isNotEmpty) {
      effectiveUsername = explicitUsername.trim();
    } else if (cloudHasCustomName && cloudUsername != null) {
      effectiveUsername = cloudUsername;
    } else if (localHasCustomName) {
      effectiveUsername = local.username;
    } else if (googleName != null && googleName.trim().isNotEmpty) {
      effectiveUsername = googleName.trim();
    } else {
      effectiveUsername = UserProfile.generateAnimeNickname(user.id);
    }

    // 2. Аватарка
    String? effectiveAvatar = cloudRow?['avatar_url'] as String?;
    if (effectiveAvatar == null ||
        effectiveAvatar == 'cat' ||
        effectiveAvatar.isEmpty) {
      if (local.avatarUrl != null &&
          local.avatarUrl != 'cat' &&
          local.avatarUrl!.isNotEmpty) {
        effectiveAvatar = local.avatarUrl;
      } else {
        effectiveAvatar = googleAvatar ?? local.avatarUrl ?? 'cat';
      }
    }

    // 3. Рамка Steam (frameId) - если в облаке нет или 'none', сохраняем локально выбранную
    String effectiveFrame = (cloudRow?['avatar_frame_id'] as String?) ??
        (cloudRow?['frame_id'] as String?) ??
        'none';
    if (effectiveFrame == 'none' &&
        local.frameId != null &&
        local.frameId != 'none') {
      effectiveFrame = local.frameId!;
    }

    // 4. Фон Steam (backgroundId) - если в облаке нет или 'none', переносим локальный арт/GIF
    String effectiveBg = (cloudRow?['background_url'] as String?) ??
        (cloudRow?['background_id'] as String?) ??
        'none';
    if (effectiveBg == 'none' &&
        local.backgroundId != null &&
        local.backgroundId != 'none') {
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
    String effectiveStatus =
        (cloudRow?['custom_status'] as String?) ?? 'Смотрю аниме...';
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
    if ((effectiveBadge == null || effectiveBadge.isEmpty) &&
        local.badgeId != null) {
      effectiveBadge = local.badgeId;
    }

    // 9. Любимый тайтл витрины
    String? effectiveFavAnimeTitle =
        cloudRow?['favorite_anime_title'] as String? ??
            local.favoriteAnimeTitle;
    String? effectiveFavAnimeId =
        cloudRow?['favorite_anime_id'] as String? ?? local.favoriteAnimeId;
    String? effectiveFavAnimePoster =
        cloudRow?['favorite_anime_poster'] as String? ??
            local.favoriteAnimePoster;
    String? effectiveArtworkUrl =
        cloudRow?['artwork_url'] as String? ?? local.artworkUrl;
    String? effectiveArtworkTitle =
        cloudRow?['artwork_title'] as String? ?? local.artworkTitle;

    // 10. Акцентный цвет, провайдер, email и тег
    String effectiveAccent = (cloudRow?['accent_color'] as String?) ??
        local.accentColor ??
        '#E06C53';
    final rawTag = (cloudRow?['tag'] as String?) ?? local.tag;
    final effectiveTag = (rawTag.isNotEmpty && rawTag != '#0001')
        ? rawTag
        : UserProfile.generateTag(user.id);
    final effectiveProvider = user.appMetadata['provider'] as String? ??
        (googleName != null || googleAvatar != null
            ? 'google'
            : (isAnon ? 'anonymous' : (local.provider ?? 'email')));

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
      email: emailFromUser ?? local.email,
      provider: effectiveProvider,
      isAnonymous: isAnon,
      tag: effectiveTag,
      friendCode: (cloudRow?['friend_code'] as String?) ??
          local.friendCode ??
          'SP-${user.id.length >= 6 ? user.id.substring(0, 6).toUpperCase() : '777AAA'}',
      telegramId: (cloudRow?['telegram_id'] as num?)?.toInt() ?? local.telegramId,
      telegramUsername: (cloudRow?['telegram_username'] as String?)
                  ?.trim()
                  .isNotEmpty ==
              true
          ? cloudRow!['telegram_username'] as String
          : local.telegramUsername,
      unlockedBadges: (cloudRow?['unlocked_badges'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          local.unlockedBadges,
      createdAt: DateTime.tryParse(cloudRow?['created_at'] as String? ?? '') ??
          DateTime.now(),
    );

    // Сохраняем объединенный профиль в Supabase и локальный кэш
    if (cloudRow != null) {
      await _updateCloudProfile(merged);
    } else {
      await _insertInitialCloudProfile(merged);
    }
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

  /// Строгое обновление СУЩЕСТВУЮЩЕГО профиля в public.profiles по auth.currentUser.id.
  /// НИКОГДА не генерирует новые UUID, tag или friend_code.
  /// Исключает создание дублирующих строк (использует .update(), а не .upsert()).
  Future<void> _updateCloudProfile(UserProfile profile) async {
    final client = _supabase;
    if (client == null) return;

    final activeUser =
        client.auth.currentSession?.user ?? client.auth.currentUser;
    if (activeUser == null) {
      // Гостевой режим: данные хранятся исключительно локально!
      return;
    }

    final cloudUserId = activeUser.id;
    String? cloudAvatarUrl = profile.avatarUrl;
    if (AvatarUploadService.isLocalFilePath(cloudAvatarUrl)) {
      final uploaded = await AvatarUploadService.uploadLocalAvatarFile(
        cloudAvatarUrl!,
        clientOverride: client,
        userIdOverride: cloudUserId,
      );
      if (uploaded != null && uploaded.isNotEmpty) {
        cloudAvatarUrl = uploaded;
        await _saveLocalProfile(profile.copyWith(avatarUrl: uploaded));
      } else {
        // Не сохраняем локальные файловые пути устройства (/data/user/0/...) в облачный profiles.avatar_url
        cloudAvatarUrl = null;
      }
    }

    final payload = <String, dynamic>{
      'username': profile.username,
      if (cloudAvatarUrl != null) 'avatar_url': cloudAvatarUrl,
      'avatar_frame_id': profile.frameId ?? 'none',
      'background_url': profile.backgroundId ?? 'none',
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
      'customization': profile.customization.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await client.from('profiles').update(payload).eq('id', cloudUserId);
    } catch (e) {
      debugPrint('[Auth] Error updating profile: $e');
      try {
        await client.from('profiles').update({
          'username': profile.username,
          if (cloudAvatarUrl != null) 'avatar_url': cloudAvatarUrl,
          'avatar_frame_id': profile.frameId ?? 'none',
          'background_url': profile.backgroundId ?? 'none',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', cloudUserId);
      } catch (e2) {
        debugPrint('[Auth] Error in fallback profile update: $e2');
      }
    }
  }

  /// Начальное создание профиля нового пользователя в Supabase при первой регистрации
  Future<void> _insertInitialCloudProfile(UserProfile profile) async {
    final client = _supabase;
    if (client == null) return;

    final activeUser =
        client.auth.currentSession?.user ?? client.auth.currentUser;
    if (activeUser == null) return;

    final cloudUserId = activeUser.id;
    final effectiveEmail =
        (activeUser.email != null && activeUser.email!.trim().isNotEmpty)
            ? activeUser.email!.trim()
            : (profile.email != null && profile.email!.trim().isNotEmpty
                ? profile.email!.trim()
                : null);

    final payload = <String, dynamic>{
      'id': cloudUserId,
      'username': profile.username,
      if (effectiveEmail != null) 'email': effectiveEmail,
      'avatar_url': profile.avatarUrl,
      'avatar_frame_id': profile.frameId ?? 'none',
      'background_url': profile.backgroundId ?? 'none',
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
      'customization': profile.customization.toJson(),
      'tag': profile.tag,
      if (profile.friendCode != null) 'friend_code': profile.friendCode,
      'created_at': profile.createdAt.toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await client.from('profiles').upsert(payload);
    } catch (e) {
      debugPrint('[Auth] Error inserting initial cloud profile: $e');
      try {
        await client.from('profiles').upsert({
          'id': cloudUserId,
          'username': profile.username,
          if (effectiveEmail != null) 'email': effectiveEmail,
          'avatar_url': profile.avatarUrl ?? '🐱',
          'avatar_frame_id': profile.frameId ?? 'none',
          'background_url': profile.backgroundId ?? 'none',
          'created_at': profile.createdAt.toIso8601String(),
        });
      } catch (e2) {
        debugPrint('[Auth] Minimal initial cloud profile error: $e2');
      }
    }
  }

  /// Удаляет осиротевший временный профиль анонимного гостя после переноса данных на постоянный аккаунт
  Future<void> _cleanupOrphanedAnonymousProfile(
    String? oldAnonId,
    String newUserId,
  ) async {
    final client = _supabase;
    if (client == null ||
        oldAnonId == null ||
        oldAnonId.isEmpty ||
        oldAnonId == newUserId) {
      return;
    }
    try {
      await client.from('profiles').delete().eq('id', oldAnonId);
    } catch (e) {
      debugPrint('[Auth] Orphaned anonymous profile cleanup skipped: $e');
    }
  }

  @override
  UserProfile? getCachedProfile() {
    return _loadLocalProfile();
  }

  @override
  Future<UserProfile> getCurrentProfile() async {
    final client = _supabase;
    final activeUser =
        client?.auth.currentSession?.user ?? client?.auth.currentUser;
    if (activeUser != null) {
      return _fetchAndMigrateCloudProfile(activeUser);
    }

    // Не вызываем signInAnonymously() на холодном старте, чтобы не плодить дубликаты профилей.
    return _loadLocalProfile();
  }

  @override
  Future<UserProfile> signInAnonymously() async {
    final client = _supabase;

    // Если реальная сессия уже существует — переиспользуем её без создания анонимных дубликатов
    final existingUser =
        client?.auth.currentSession?.user ?? client?.auth.currentUser;
    if (existingUser != null) {
      final profile = await _fetchAndMigrateCloudProfile(existingUser);
      await _saveLocalProfile(profile);
      _authController.add(profile);
      return profile;
    }

    // Zero Anonymous Auth Rows: гостевой режим строго локальный (SharedPreferences/Hive).
    // Никаких вызовов signInAnonymously() на сервере Supabase, чтобы не плодить пустые строки в profiles!
    final local = _loadLocalProfile();
    await _saveLocalProfile(local);
    _authController.add(local);
    return local;
  }

  static const String _desktopOAuthSuccessHtml = '''
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SyncPai — Авторизация</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      background: #0B0E14;
      color: #F3F4F6;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Inter, sans-serif;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }
    .card {
      width: 100%;
      max-width: 400px;
      background: #12161F;
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 20px;
      padding: 36px 32px;
      text-align: center;
      box-shadow: 0 24px 48px rgba(0, 0, 0, 0.55);
    }
    .badge {
      width: 56px;
      height: 56px;
      margin: 0 auto 20px;
      border-radius: 16px;
      background: rgba(34, 211, 238, 0.12);
      border: 1px solid rgba(34, 211, 238, 0.25);
      display: flex;
      align-items: center;
      justify-content: center;
      color: #22D3EE;
    }
    h1 {
      margin: 0 0 8px;
      font-size: 20px;
      font-weight: 600;
      letter-spacing: -0.01em;
      color: #F9FAFB;
    }
    p {
      margin: 0 0 24px;
      font-size: 14px;
      line-height: 1.5;
      color: #9CA3AF;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 44px;
      border-radius: 12px;
      background: #22D3EE;
      color: #090D16;
      font-size: 14px;
      font-weight: 600;
      text-decoration: none;
      transition: transform 0.12s ease, background 0.15s ease;
    }
    .btn:hover { background: #38E1FB; }
    .btn:active { transform: scale(0.98); }
    .hint {
      margin-top: 14px;
      font-size: 12px;
      color: #6B7280;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">
      <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
        <polyline points="20 6 9 17 4 12"></polyline>
      </svg>
    </div>
    <h1>Вход выполнен</h1>
    <p>Аккаунт успешно привязан. Нажмите кнопку ниже, чтобы вернуться в SyncPai.</p>
    <a class="btn" href="syncpai://auth-success" id="openAppBtn">Вернуться в SyncPai</a>
    <div class="hint">После перехода эту вкладку можно закрыть</div>
  </div>
  <script>
    setTimeout(function () {
      window.location.href = 'syncpai://auth-success';
    }, 350);
  </script>
</body>
</html>
''';

  @visibleForTesting
  static Future<Uri> awaitDesktopOAuthCallback(HttpServer server) async {
    await for (final request in server.timeout(const Duration(minutes: 2))) {
      if (request.uri.path == '/favicon.ico') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        continue;
      }
      final callbackUri = request.uri;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('text', 'html', charset: 'utf-8')
        ..write(_desktopOAuthSuccessHtml);
      await request.response.close();
      return callbackUri;
    }
    throw TimeoutException(
        'OAuth callback server closed before receiving redirect');
  }

  /// Возвращает платформенно-зависимый OAuth redirect URL:
  /// - Android / iOS: `syncpai://login-callback` (deep link)
  /// - Windows / macOS / Linux: `http://localhost:3000` (loopback)
  static String? resolveOAuthRedirectTo({
    required bool isWeb,
    required bool isMobileOS,
    required bool isDesktopOS,
  }) {
    if (isWeb) return null;
    if (isMobileOS) return 'syncpai://login-callback';
    if (isDesktopOS) return 'http://localhost:3000';
    return null;
  }

  @override
  Future<UserProfile?> signInWithGoogle() async {
    try {
      final client = _supabase;
      final oldAnonId = (client?.auth.currentUser?.isAnonymous == true)
          ? client?.auth.currentUser?.id
          : null;
      final bool isDesktopOS = !kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
      final bool isMobileOS = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      final String? oauthRedirectTo = resolveOAuthRedirectTo(
        isWeb: kIsWeb,
        isMobileOS: isMobileOS,
        isDesktopOS: isDesktopOS,
      );

      Future<UserProfile?> launchSupabaseGoogleOAuth() async {
        if (client == null) return null;
        HttpServer? server;
        try {
          if (isDesktopOS) {
            try {
              server =
                  await HttpServer.bind(InternetAddress.loopbackIPv4, 3000);
            } catch (_) {
              server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
            }
            final desktopRedirectTo = 'http://localhost:${server.port}';
            final callbackFuture = awaitDesktopOAuthCallback(server);
            await client.auth.signInWithOAuth(
              OAuthProvider.google,
              redirectTo: desktopRedirectTo,
              authScreenLaunchMode: LaunchMode.externalApplication,
            );
            final callbackUri = await callbackFuture;
            if (callbackUri.queryParameters.containsKey('error')) {
              final errDesc =
                  callbackUri.queryParameters['error_description'] ??
                      callbackUri.queryParameters['error'] ??
                      'OAuth error';
              throw AuthException(errDesc);
            }
            await client.auth.getSessionFromUrl(callbackUri);
          } else {
            await client.auth.signInWithOAuth(
              OAuthProvider.google,
              redirectTo: oauthRedirectTo,
              authScreenLaunchMode: LaunchMode.externalApplication,
            );
          }

          final user = client.auth.currentUser;
          if (user != null && !user.isAnonymous) {
            final profile = await _fetchAndMigrateCloudProfile(user);
            await _cleanupOrphanedAnonymousProfile(oldAnonId, user.id);
            await _saveLocalProfile(profile);
            _authController.add(profile);
            return profile;
          }
        } catch (oauthErr) {
          debugPrint('[Auth] Supabase signInWithOAuth warning: $oauthErr');
          if (AuthErrorFormatter.isProviderDisabledError(oauthErr)) {
            throw AuthException(
              AuthErrorFormatter.format(oauthErr),
              code: 'validation_failed',
            );
          }
        } finally {
          await server?.close(force: true);
        }
        return null;
      }

      // На Windows / macOS / Linux полностью обходим нативный GoogleSignIn (он даёт MissingPluginException)
      if (isDesktopOS) {
        return await launchSupabaseGoogleOAuth();
      }

      // На Android / iOS сначала пробуем нативный GoogleSignIn
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
        debugPrint(
            '[Auth] Native GoogleSignIn unavailable ($nativeErr). Falling back to Supabase OAuth...');
        return await launchSupabaseGoogleOAuth();
      }

      if (googleUser == null) {
        // Пользователь отменил системный диалог выбора аккаунта
        return null;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        debugPrint(
            '[Auth] Google idToken is null. Falling back to Supabase OAuth...');
        return await launchSupabaseGoogleOAuth();
      }

      if (client != null) {
        try {
          await client.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: accessToken,
          );

          final user = client.auth.currentUser;
          if (user != null) {
            final profile = await _fetchAndMigrateCloudProfile(user);
            await _cleanupOrphanedAnonymousProfile(oldAnonId, user.id);
            await _saveLocalProfile(profile);
            _authController.add(profile);
            return profile;
          }
        } catch (supabaseErr) {
          if (AuthErrorFormatter.isProviderDisabledError(supabaseErr)) {
            throw AuthException(
              AuthErrorFormatter.format(supabaseErr),
              code: 'validation_failed',
            );
          }
          debugPrint(
              'Supabase signInWithIdToken warning ($supabaseErr). Falling back to OAuth...');
          final oauthProfile = await launchSupabaseGoogleOAuth();
          if (oauthProfile != null) return oauthProfile;
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
    final localHasCustomName =
        !UserProfile.isDefaultGeneratedNickname(local.username);
    final emailPrefix =
        email.contains('@') ? email.split('@').first.trim() : email.trim();

    final effectiveName = localHasCustomName
        ? local.username
        : (displayName != null &&
                displayName.trim().isNotEmpty &&
                !UserProfile.isDefaultGeneratedNickname(displayName)
            ? displayName.trim()
            : (emailPrefix.isNotEmpty ? emailPrefix : local.username));

    final effectiveAvatar = (local.avatarUrl != null &&
            local.avatarUrl != 'cat' &&
            local.avatarUrl!.isNotEmpty)
        ? local.avatarUrl
        : (photoUrl != null && photoUrl.isNotEmpty
            ? photoUrl
            : local.avatarUrl);

    final effectiveTag = (local.tag.isNotEmpty && local.tag != '#0001')
        ? local.tag
        : UserProfile.generateTag(email);

    final updated = local.copyWith(
      username: effectiveName,
      avatarUrl: effectiveAvatar,
      email: email.trim(),
      provider: 'google',
      isAnonymous: false,
      tag: effectiveTag,
    );

    await _saveLocalProfile(updated);
    if (client != null && client.auth.currentSession != null) {
      final currentUid = client.auth.currentUser?.id;
      final profileToSync = currentUid != null && currentUid.isNotEmpty
          ? updated.copyWith(id: currentUid)
          : updated;
      await _updateCloudProfile(profileToSync);
    }
    _authController.add(updated);

    // Фоновая синхронизация списков
    try {
      if (getIt.isRegistered<AnimeListRepository>()) {
        unawaited(
            getIt<AnimeListRepository>().syncWithCloud(userId: updated.id));
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
    final oldAnonId = (client?.auth.currentUser?.isAnonymous == true)
        ? client?.auth.currentUser?.id
        : null;
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
          await _cleanupOrphanedAnonymousProfile(oldAnonId, res.user!.id);
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
      username: username != null && username.isNotEmpty
          ? username.trim()
          : local.username,
      isAnonymous: false,
    );
    await _saveLocalProfile(migrated);
    _authController.add(migrated);
    return migrated;
  }

  @override
  Future<UserProfile> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    final trimmed = identifier.trim();
    final client = _supabase;
    final oldAnonId = (client?.auth.currentUser?.isAnonymous == true)
        ? client?.auth.currentUser?.id
        : null;
    if (client != null) {
      try {
        String resolvedEmail = trimmed;
        if (!trimmed.contains('@')) {
          final rpcResult = await client.rpc(
            'get_email_by_username',
            params: {'p_username': trimmed},
          );
          final candidate = rpcResult?.toString().trim() ?? '';
          if (candidate.isEmpty) {
            throw const AuthException('Пользователь с таким логином не найден');
          }
          resolvedEmail = candidate;
        }

        final res = await client.auth.signInWithPassword(
          email: resolvedEmail,
          password: password,
        );

        if (res.user != null) {
          final profile = await _fetchAndMigrateCloudProfile(res.user!);
          await _cleanupOrphanedAnonymousProfile(oldAnonId, res.user!.id);
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
  Future<UserProfile> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return signInWithIdentifier(identifier: email, password: password);
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
    await _updateCloudProfile(updated);
    _authController.add(updated);
    return updated;
  }

  @override
  Future<UserProfile> updateCustomization(ProfileCustomization customization) async {
    final current = await getCurrentProfile();
    final updated = current.copyWith(
      backgroundId: customization.backgroundUrl,
      frameId: customization.avatarFrameUrl,
      accentColor: customization.themeColorHex,
      showcaseType: customization.showcaseType,
      bio: customization.customBio,
      countryFlag: customization.countryFlag,
      countryName: customization.countryName,
      avatarShape: customization.avatarShape,
    );

    await _saveLocalProfile(updated);
    await _updateCloudProfile(updated);
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
