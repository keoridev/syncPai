import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository repository;
  StreamSubscription<UserProfile?>? _authSubscription;

  AuthCubit({required this.repository}) : super(const AuthInitial()) {
    _init();
  }

  Future<void> _init() async {
    emit(const AuthLoading());
    try {
      final profile = await repository.getCurrentProfile();
      emit(Authenticated(profile));
    } catch (e) {
      emit(AuthError(e.toString()));
    }

    _authSubscription = repository.authStateChanges.listen((profile) {
      if (profile != null) {
        emit(Authenticated(profile));
      }
    });
  }

  Future<void> updateProfile({
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
    try {
      final updated = await repository.updateProfile(
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
      emit(Authenticated(updated));
    } catch (e) {
      emit(AuthError('Ошибка обновления профиля: $e'));
    }
  }

  Future<void> signInWithGoogle() async {
    emit(const AuthLoading());
    try {
      final profile = await repository.signInWithGoogle();
      if (profile != null) {
        emit(Authenticated(profile));
      } else {
        final current = await repository.getCurrentProfile();
        emit(Authenticated(current));
      }
    } catch (e) {
      emit(AuthError('Ошибка входа через Google: $e'));
      final current = await repository.getCurrentProfile();
      emit(Authenticated(current));
    }
  }

  Future<void> linkGoogleAccount({
    required String email,
    String? displayName,
    String? photoUrl,
  }) async {
    emit(const AuthLoading());
    try {
      final profile = await repository.linkGoogleAccount(
        email: email,
        displayName: displayName,
        photoUrl: photoUrl,
      );
      emit(Authenticated(profile));
    } catch (e) {
      emit(AuthError('Ошибка привязки Google: $e'));
      final current = await repository.getCurrentProfile();
      emit(Authenticated(current));
    }
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? username,
  }) async {
    emit(const AuthLoading());
    try {
      final profile = await repository.signUpWithEmail(
        email: email,
        password: password,
        username: username,
      );
      emit(Authenticated(profile));
    } catch (e) {
      emit(AuthError('Ошибка регистрации: $e'));
      final current = await repository.getCurrentProfile();
      emit(Authenticated(current));
      rethrow;
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    emit(const AuthLoading());
    try {
      final profile = await repository.signInWithEmail(
        email: email,
        password: password,
      );
      emit(Authenticated(profile));
    } catch (e) {
      emit(AuthError('Ошибка авторизации: $e'));
      final current = await repository.getCurrentProfile();
      emit(Authenticated(current));
      rethrow;
    }
  }

  Future<void> signOut() async {
    await repository.signOut();
    final guest = await repository.getCurrentProfile();
    emit(Authenticated(guest));
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
