import '../../../profile/domain/entities/steam_profile_customization.dart';
import '../entities/user_profile.dart';

abstract class AuthRepository {
  /// Текущий профиль пользователя
  Future<UserProfile> getCurrentProfile();

  /// Мгновенное (0ms) чтение кэшированного профиля из локального дискового хранилища
  UserProfile? getCachedProfile() => null;

  /// Автоматический анонимный вход (при первом запуске без ввода паролей)
  Future<UserProfile> signInAnonymously();

  /// Вход через Google OAuth с безопасным переносом локального профиля
  Future<UserProfile?> signInWithGoogle();

  /// Прямая привязка Google-аккаунта (email) с 100% сохранением арта, никнейма и закладок
  Future<UserProfile> linkGoogleAccount({
    required String email,
    String? displayName,
    String? photoUrl,
  });

  /// Регистрация через Email и пароль с сохранением и переносом локального профиля
  Future<UserProfile> signUpWithEmail({
    required String email,
    required String password,
    String? username,
  });

  /// Авторизация через Email или логин (username) и пароль с сохранением и переносом локального профиля
  Future<UserProfile> signInWithIdentifier({
    required String identifier,
    required String password,
  });

  /// Авторизация через Email и пароль с сохранением и переносом локального профиля
  Future<UserProfile> signInWithEmail({
    required String email,
    required String password,
  });

  /// Обновление имени, аватарки и Steam-кастомизации профиля
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
    String? favoriteMangaTitle,
    String? favoriteMangaId,
    String? favoriteMangaPoster,
    String? showcaseMode,
    String? artworkUrl,
    String? artworkTitle,
    String? accentColor,
    String? showcaseType,
    String? countryFlag,
    String? countryName,
    String? avatarShape,
  });

  /// Обновление объекта кастомизации Steam Profile Customization
  Future<UserProfile> updateCustomization(ProfileCustomization customization);

  /// Выход из аккаунта
  Future<void> signOut();

  /// Стрим изменений состояния пользователя
  Stream<UserProfile?> get authStateChanges;
}
