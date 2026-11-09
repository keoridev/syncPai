import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/domain/repositories/anime_list_repository.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import 'profile_state.dart';

class ProfileCubit extends Cubit<ProfileState> {
  final AuthRepository? authRepository;
  final AnimeListRepository? animeListRepository;
  StreamSubscription<UserProfile?>? _authSubscription;

  ProfileCubit({
    this.authRepository,
    this.animeListRepository,
  }) : super(ProfileState.initial());

  /// Загрузка данных профиля пользователя (своего или профиля друга по ID)
  Future<void> loadProfile({String? targetUserId}) async {
    emit(state.copyWith(status: ProfileStatus.loading));

    String? currentUserId;
    try {
      currentUserId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}

    if (currentUserId == null && authRepository != null) {
      try {
        final current = await authRepository!.getCurrentProfile();
        currentUserId = current.id;
      } catch (_) {}
    }

    final bool isCurrent = targetUserId == null ||
        targetUserId.trim().isEmpty ||
        targetUserId == currentUserId;

    if (isCurrent) {
      UserProfile profile = UserProfile.guest();
      if (authRepository != null) {
        try {
          profile = await authRepository!.getCurrentProfile();
        } catch (e) {
          debugPrint('Error getting current profile: $e');
        }
      }

      UserAnimeStats stats = const UserAnimeStats(
        totalTitles: 0,
        completedTitles: 0,
        watchingTitles: 0,
        plannedTitles: 0,
        droppedTitles: 0,
        totalEpisodesCompleted: 0,
        totalMinutesWatched: 0,
      );

      if (animeListRepository != null) {
        try {
          final entries = await animeListRepository!.getAllEntries();
          stats = UserAnimeStats.compute(entries);
        } catch (e) {
          debugPrint('Error getting anime list entries: $e');
        }
      }

      emit(state.copyWith(
        status: ProfileStatus.loaded,
        profile: profile,
        stats: stats,
        isCurrentUser: true,
      ));

      _authSubscription?.cancel();
      if (authRepository != null) {
        _authSubscription = authRepository!.authStateChanges.listen((updated) {
          if (updated != null && state.isCurrentUser) {
            emit(state.copyWith(profile: updated));
          }
        });
      }
    } else {
      try {
        SupabaseClient? client;
        try {
          client = Supabase.instance.client;
        } catch (_) {}

        if (client == null) {
          emit(state.copyWith(
            status: ProfileStatus.error,
            errorMessage: 'Supabase клиент недоступен',
          ));
          return;
        }

        final cloudRow = await client
            .from('profiles')
            .select()
            .eq('id', targetUserId)
            .maybeSingle();

        if (cloudRow == null) {
          emit(state.copyWith(
            status: ProfileStatus.error,
            errorMessage: 'Профиль пользователя не найден',
          ));
          return;
        }

        final friendProfile = UserProfile(
          id: targetUserId,
          username: (cloudRow['username'] as String?)?.isNotEmpty == true
              ? cloudRow['username'] as String
              : 'Пользователь #$targetUserId',
          avatarUrl: cloudRow['avatar_url'] as String?,
          frameId: (cloudRow['avatar_frame_id'] as String?) ??
              (cloudRow['frame_id'] as String?) ??
              'none',
          backgroundId: (cloudRow['background_url'] as String?) ??
              (cloudRow['background_id'] as String?) ??
              'none',
          customTitle: cloudRow['custom_title'] as String?,
          customStatus: (cloudRow['custom_status'] as String?) ?? 'Смотрю аниме...',
          bio: cloudRow['bio'] as String?,
          badgeId: cloudRow['badge_id'] as String? ?? 'sync_master',
          favoriteAnimeTitle: cloudRow['favorite_anime_title'] as String?,
          favoriteAnimeId: cloudRow['favorite_anime_id'] as String?,
          favoriteAnimePoster: cloudRow['favorite_anime_poster'] as String?,
          accentColor: cloudRow['accent_color'] as String? ?? '#E06C53',
          isAnonymous: false,
          createdAt: DateTime.tryParse(cloudRow['created_at'] as String? ?? '') ?? DateTime.now(),
        );

        UserAnimeStats friendStats = const UserAnimeStats(
          totalTitles: 0,
          completedTitles: 0,
          watchingTitles: 0,
          plannedTitles: 0,
          droppedTitles: 0,
          totalEpisodesCompleted: 0,
          totalMinutesWatched: 0,
        );

        try {
          final List<dynamic> listRows = await client
              .from('user_anime_lists')
              .select()
              .eq('user_id', targetUserId);
          final entries = listRows
              .map((e) => UserAnimeEntry.fromJson(e as Map<String, dynamic>))
              .toList();
          friendStats = UserAnimeStats.compute(entries);
        } catch (e) {
          debugPrint('Error getting friend anime lists: $e');
        }

        emit(state.copyWith(
          status: ProfileStatus.loaded,
          profile: friendProfile,
          stats: friendStats,
          isCurrentUser: false,
        ));
      } catch (e) {
        emit(state.copyWith(
          status: ProfileStatus.error,
          errorMessage: 'Ошибка загрузки профиля: $e',
        ));
      }
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}

