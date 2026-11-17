import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/services/presence_service.dart';
import '../../../profile/domain/entities/steam_profile_customization.dart';
import '../../../profile/presentation/cubit/profile_cubit.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/auth_repository.dart';
import '../utils/auth_error_formatter.dart';
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
      unawaited(PresenceService.instance.startForUser(profile.id));
    } catch (e) {
      emit(AuthError(e.toString()));
    }

    _authSubscription = repository.authStateChanges.listen((profile) {
      if (profile != null) {
        emit(Authenticated(profile));
        unawaited(PresenceService.instance.startForUser(profile.id));
      }
    });
  }

  /// Тихое обновление профиля из Supabase (например, после возврата из Telegram-бота).
  Future<void> refreshProfile() async {
    try {
      final profile = await repository.getCurrentProfile();
      if (!isClosed) {
        emit(Authenticated(profile));
      }
      if (getIt.isRegistered<ProfileCubit>()) {
        getIt<ProfileCubit>().applyOptimisticProfile(profile);
      }
    } catch (_) {}
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
    final previousProfile =
        state is Authenticated ? (state as Authenticated).profile : null;

    if (previousProfile != null) {
      final optimistic = previousProfile.copyWith(
        username: username,
        avatarUrl: avatarUrl ?? previousProfile.avatarUrl,
        frameId: frameId ?? previousProfile.frameId,
        backgroundId: backgroundId ?? previousProfile.backgroundId,
        customTitle: customTitle ?? previousProfile.customTitle,
        customStatus: customStatus ?? previousProfile.customStatus,
        bio: bio ?? previousProfile.bio,
        badgeId: badgeId ?? previousProfile.badgeId,
        favoriteAnimeTitle: favoriteAnimeTitle != null
            ? (favoriteAnimeTitle.isEmpty ? null : favoriteAnimeTitle)
            : previousProfile.favoriteAnimeTitle,
        favoriteAnimeId: favoriteAnimeId != null
            ? (favoriteAnimeId.isEmpty ? null : favoriteAnimeId)
            : previousProfile.favoriteAnimeId,
        favoriteAnimePoster: favoriteAnimePoster != null
            ? (favoriteAnimePoster.isEmpty ? null : favoriteAnimePoster)
            : previousProfile.favoriteAnimePoster,
        artworkUrl: artworkUrl != null
            ? (artworkUrl.isEmpty ? null : artworkUrl)
            : previousProfile.artworkUrl,
        artworkTitle: artworkTitle != null
            ? (artworkTitle.isEmpty ? null : artworkTitle)
            : previousProfile.artworkTitle,
        accentColor: accentColor ?? previousProfile.accentColor,
        showcaseType: showcaseType ?? previousProfile.showcaseType,
        countryFlag: countryFlag ?? previousProfile.countryFlag,
        countryName: countryName ?? previousProfile.countryName,
        avatarShape: avatarShape ?? previousProfile.avatarShape,
      );

      // Мгновенное (0ms) оптимистичное обновление AuthCubit и ProfileCubit
      emit(Authenticated(optimistic));
      if (getIt.isRegistered<ProfileCubit>()) {
        getIt<ProfileCubit>().applyOptimisticProfile(optimistic);
      }
    }

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
      if (!isClosed) {
        emit(Authenticated(updated));
        if (getIt.isRegistered<ProfileCubit>()) {
          getIt<ProfileCubit>().applyOptimisticProfile(updated);
        }
      }
    } catch (e) {
      if (!isClosed) {
        if (previousProfile != null) {
          emit(Authenticated(previousProfile));
          if (getIt.isRegistered<ProfileCubit>()) {
            getIt<ProfileCubit>().applyOptimisticProfile(previousProfile);
          }
        } else {
          emit(AuthError('Ошибка обновления профиля: $e'));
        }
      }
    }
  }

  Future<void> updateCustomization(ProfileCustomization customization) async {
    final s = state;
    final previousProfile = s is Authenticated ? s.profile : null;

    if (previousProfile != null) {
      final optimistic = previousProfile.copyWith(
        backgroundId: customization.backgroundUrl,
        frameId: customization.avatarFrameUrl,
        accentColor: customization.themeColorHex,
        showcaseType: customization.showcaseType,
        bio: customization.customBio,
        countryFlag: customization.countryFlag,
        countryName: customization.countryName,
        avatarShape: customization.avatarShape,
      );
      emit(Authenticated(optimistic));
      if (getIt.isRegistered<ProfileCubit>()) {
        getIt<ProfileCubit>().applyOptimisticProfile(optimistic);
      }
    }

    try {
      final updated = await repository.updateCustomization(customization);
      if (!isClosed) {
        emit(Authenticated(updated));
        if (getIt.isRegistered<ProfileCubit>()) {
          getIt<ProfileCubit>().applyOptimisticProfile(updated);
        }
      }
    } catch (e) {
      if (!isClosed && previousProfile != null) {
        emit(Authenticated(previousProfile));
      }
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
      final friendly = AuthErrorFormatter.format(e);
      emit(AuthError(friendly));
      final current = await repository.getCurrentProfile();
      emit(Authenticated(current));
      rethrow;
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
      emit(AuthError(AuthErrorFormatter.format(e)));
      final current = await repository.getCurrentProfile();
      emit(Authenticated(current));
      rethrow;
    }
  }

  Future<void> signInWithIdentifier({
    required String identifier,
    required String password,
  }) async {
    emit(const AuthLoading());
    try {
      final profile = await repository.signInWithIdentifier(
        identifier: identifier,
        password: password,
      );
      emit(Authenticated(profile));
    } catch (e) {
      emit(AuthError(AuthErrorFormatter.format(e)));
      final current = await repository.getCurrentProfile();
      emit(Authenticated(current));
      rethrow;
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    return signInWithIdentifier(identifier: email, password: password);
  }

  Future<void> signOut() async {
    await PresenceService.instance.stop();
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
