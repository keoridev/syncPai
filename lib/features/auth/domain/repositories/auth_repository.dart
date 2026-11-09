import '../entities/user_profile.dart';

abstract class AuthRepository {
  /// Текущий профиль пользователя
  Future<UserProfile> getCurrentProfile();

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
    String? accentColor,
    String? showcaseType,
  });

  /// Выход из аккаунта
  Future<void> signOut();

  /// Стрим изменений состояния пользователя
  Stream<UserProfile?> get authStateChanges;
}
