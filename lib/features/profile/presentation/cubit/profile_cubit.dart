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

        Map<String, dynamic>? cloudRow;
        if (client != null) {
          try {
            cloudRow = await client
                .from('profiles')
                .select()
                .eq('id', targetUserId)
                .maybeSingle();
          } catch (_) {}
        }

        final friendProfile = cloudRow != null
            ? UserProfile(
                id: targetUserId,
                username: (cloudRow['username'] as String?)?.isNotEmpty == true
                    ? cloudRow['username'] as String
                    : targetUserId,
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
                countryFlag: cloudRow['country_flag'] as String? ?? '🇰🇬',
                countryName: cloudRow['country_name'] as String? ?? 'Kyrgyzstan',
                avatarShape: cloudRow['avatar_shape'] as String? ?? 'square',
                isAnonymous: false,
                createdAt: DateTime.tryParse(cloudRow['created_at'] as String? ?? '') ?? DateTime.now(),
              )
            : _buildFallbackFriendProfile(targetUserId);

        UserAnimeStats friendStats = const UserAnimeStats(
          totalTitles: 42,
          completedTitles: 28,
          watchingTitles: 6,
          plannedTitles: 8,
          droppedTitles: 0,
          totalEpisodesCompleted: 348,
          totalMinutesWatched: 8352,
        );

        if (client != null) {
          try {
            final List<dynamic> listRows = await client
                .from('user_anime_lists')
                .select()
                .eq('user_id', targetUserId);
            if (listRows.isNotEmpty) {
              final entries = listRows
                  .map((e) => UserAnimeEntry.fromJson(e as Map<String, dynamic>))
                  .toList();
              friendStats = UserAnimeStats.compute(entries);
            }
          } catch (e) {
            debugPrint('Error getting friend anime lists: $e');
          }
        }

        emit(state.copyWith(
          status: ProfileStatus.loaded,
          profile: friendProfile,
          stats: friendStats,
          isCurrentUser: false,
        ));
      } catch (e) {
        emit(state.copyWith(
          status: ProfileStatus.loaded,
          profile: _buildFallbackFriendProfile(targetUserId),
          stats: const UserAnimeStats(
            totalTitles: 35,
            completedTitles: 22,
            watchingTitles: 5,
            plannedTitles: 8,
            droppedTitles: 0,
            totalEpisodesCompleted: 260,
            totalMinutesWatched: 6240,
          ),
          isCurrentUser: false,
        ));
      }
    }
  }

  UserProfile _buildFallbackFriendProfile(String targetUserId) {
    final lower = targetUserId.toLowerCase();
    String username = targetUserId;
    if (username.startsWith('fr_') || username.startsWith('guest_')) {
      username = 'Сенпай #${username.length > 5 ? username.substring(username.length - 4) : '777'}';
    }

    if (lower.contains('sakura')) {
      return UserProfile(
        id: targetUserId,
        username: 'SakuraChan',
        avatarUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=400&auto=format&fit=crop&q=80',
        frameId: 'sakura_blossom',
        backgroundId: 'falling_sakura_live',
        customTitle: 'Повелитель Сакуры',
        customStatus: 'Любуюсь лепестками сакуры 🌸',
        bio: '«Истинная красота мимолетна, как цветение сакуры весной»',
        badgeId: 'sync_master',
        accentColor: '#FF2A68',
        countryFlag: '🇯🇵',
        countryName: 'Japan',
        favoriteAnimeTitle: 'SAKURA BLADE // 桜刀 Твое Имя',
        favoriteAnimePoster: 'https://images.unsplash.com/photo-1528164344705-475426879c0d?w=1200&auto=format&fit=crop&q=80',
        showcaseType: 'favorite_anime',
        avatarShape: 'circle',
        createdAt: DateTime.now().subtract(const Duration(days: 120)),
      );
    } else if (lower.contains('kirit') || lower.contains('cyber') || lower.contains('blade')) {
      return UserProfile(
        id: targetUserId,
        username: 'Kirit0_Kun',
        avatarUrl: 'https://images.unsplash.com/photo-1563089145-599997674d42?w=400&auto=format&fit=crop&q=80',
        frameId: 'neon_cyber',
        backgroundId: 'cyberpunk_grid_3d',
        customTitle: 'Черный Мечник',
        customStatus: 'Марафоню аниме до утра ⚡',
        bio: '«Даже в виртуальном мире наши чувства реальны»',
        badgeId: 'marathon_100',
        accentColor: '#00E5FF',
        countryFlag: '🇰🇷',
        countryName: 'South Korea',
        favoriteAnimeTitle: 'SHADOW MONARCH // Мастера Меча Онлайн',
        favoriteAnimePoster: 'https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=1200&auto=format&fit=crop&q=80',
        showcaseType: 'favorite_anime',
        avatarShape: 'square',
        createdAt: DateTime.now().subtract(const Duration(days: 95)),
      );
    } else if (lower.contains('neko') || lower.contains('cat')) {
      return UserProfile(
        id: targetUserId,
        username: 'NekoSensei',
        avatarUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=400&auto=format&fit=crop&q=80',
        frameId: 'glacial_frost',
        backgroundId: 'frieren_magic_live',
        customTitle: 'Ночной Отаку',
        customStatus: 'Сплю днем, смотрю аниме ночью 🐱',
        bio: '«Мяу! Лучшие онгоинги смотрятся только в полночь»',
        badgeId: 'night_otaku',
        accentColor: '#B388FF',
        countryFlag: '🇰🇬',
        countryName: 'Kyrgyzstan',
        favoriteAnimeTitle: 'DOMAIN EXPANSION // Тетрадь Смерти',
        favoriteAnimePoster: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=1200&auto=format&fit=crop&q=80',
        showcaseType: 'favorite_anime',
        avatarShape: 'square',
        createdAt: DateTime.now().subtract(const Duration(days: 60)),
      );
    }

    return UserProfile(
      id: targetUserId,
      username: username,
      avatarUrl: 'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=400&auto=format&fit=crop&q=80',
      frameId: 'golden_dragon',
      backgroundId: 'uchiha_sharingan_live',
      customTitle: 'Отаку-Ветеран',
      customStatus: 'Смотрю аниме в SyncPai ✨',
      bio: '«Всегда готов к совместному просмотру шедевров!»',
      badgeId: 'sync_master',
      accentColor: '#FFD700',
      countryFlag: '🇰🇬',
      countryName: 'Kyrgyzstan',
      favoriteAnimeTitle: 'CYBERPUNK // Атака Титанов',
      favoriteAnimePoster: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=1200&auto=format&fit=crop&q=80',
      showcaseType: 'favorite_anime',
      avatarShape: 'square',
      createdAt: DateTime.now().subtract(const Duration(days: 45)),
    );
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}

