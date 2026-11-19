import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/di/injection.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/domain/repositories/anime_list_repository.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../domain/entities/customization_tier_policy.dart';
import '../../domain/services/taste_compatibility_calculator.dart';
import 'profile_state.dart';

class ProfileCubit extends Cubit<ProfileState> {
  final AuthRepository? authRepository;
  final AnimeListRepository? animeListRepository;
  StreamSubscription<UserProfile?>? _authSubscription;

  ProfileCubit({
    this.authRepository,
    this.animeListRepository,
  }) : super(ProfileState.initial());

  void _safeEmit(ProfileState newState) {
    if (!isClosed) {
      emit(newState);
    }
  }

  /// Мгновенное (0ms) оптимистичное обновление локального профиля в памяти.
  void applyOptimisticProfile(UserProfile updated) {
    if (isClosed || !state.isCurrentUser) return;
    _safeEmit(state.copyWith(
      status: ProfileStatus.loaded,
      profile: updated,
    ));
  }

  /// Финальная защита и применение кастомизации с проверкой уровня подписки.
  Future<UserProfile> applyCustomization({
    required String frameId,
    required String backgroundId,
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
    String? avatarUrl,
  }) async {
    final current = state.profile;
    final sanitized = CustomizationTierPolicy.sanitizePayload(
      tier: current.supporterTier,
      frameId: frameId,
      backgroundId: backgroundId,
      customTitle: customTitle,
      artworkUrl: artworkUrl,
      artworkTitle: artworkTitle,
    );

    final optimistic = current.copyWith(
      avatarUrl: avatarUrl ?? current.avatarUrl,
      frameId: sanitized.frameId,
      backgroundId: sanitized.backgroundId,
      customTitle: sanitized.customTitle,
      customStatus: customStatus,
      bio: bio,
      badgeId: badgeId,
      favoriteAnimeTitle: favoriteAnimeTitle,
      favoriteAnimeId: favoriteAnimeId,
      favoriteAnimePoster: favoriteAnimePoster,
      artworkUrl: sanitized.artworkUrl,
      artworkTitle: sanitized.artworkTitle,
      accentColor: accentColor,
      showcaseType: showcaseType ?? current.showcaseType,
      countryFlag: countryFlag,
      countryName: countryName,
      avatarShape: avatarShape ?? current.avatarShape,
    );

    applyOptimisticProfile(optimistic);

    if (authRepository != null) {
      try {
        final saved = await authRepository!.updateProfile(
          username: current.username,
          avatarUrl: avatarUrl ?? current.avatarUrl,
          frameId: sanitized.frameId,
          backgroundId: sanitized.backgroundId,
          customTitle: sanitized.customTitle,
          customStatus: customStatus,
          bio: bio,
          badgeId: badgeId,
          favoriteAnimeTitle: favoriteAnimeTitle,
          favoriteAnimeId: favoriteAnimeId,
          favoriteAnimePoster: favoriteAnimePoster,
          artworkUrl: sanitized.artworkUrl,
          artworkTitle: sanitized.artworkTitle,
          accentColor: accentColor,
          showcaseType: showcaseType,
          countryFlag: countryFlag,
          countryName: countryName,
          avatarShape: avatarShape,
        );
        applyOptimisticProfile(saved);
        return saved;
      } catch (e) {
        debugPrint('ProfileCubit.applyCustomization persist error: $e');
      }
    }

    return optimistic;
  }

  /// Загрузка данных профиля пользователя (своего или профиля друга по ID)
  Future<void> loadProfile({String? targetUserId}) async {
    if (isClosed) return;

    String? currentUserId;
    try {
      currentUserId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {}

    if (currentUserId == null && authRepository != null) {
      final cached = authRepository!.getCachedProfile();
      if (cached != null) {
        currentUserId = cached.id;
      }
    }

    final bool isCurrent = targetUserId == null ||
        targetUserId.trim().isEmpty ||
        targetUserId == currentUserId;

    if (isCurrent) {
      // 0ms SWR Disk Cache: если уже есть кэш или сохраненный локальный профиль —
      // мгновенно эмитим Loaded-состояние без мерцания и спиннеров!
      final cachedProfile = state.status == ProfileStatus.loaded
          ? state.profile
          : (authRepository?.getCachedProfile() ?? state.profile);

      if (state.status != ProfileStatus.loaded) {
        _safeEmit(state.copyWith(
          status: ProfileStatus.loaded,
          profile: cachedProfile,
          isCurrentUser: true,
        ));
      }

      // Фоновое обновление профиля и статистики из Supabase / репозитория
      UserProfile profile = cachedProfile;
      if (authRepository != null) {
        try {
          profile = await authRepository!.getCurrentProfile();
        } catch (e) {
          debugPrint('Error getting current profile: $e');
        }
      }
      if (isClosed) return;

      UserAnimeStats stats = state.stats;
      if (animeListRepository != null) {
        try {
          final entries = await animeListRepository!.getAllEntries();
          stats = UserAnimeStats.compute(entries);
        } catch (e) {
          debugPrint('Error getting anime list entries: $e');
        }
      }
      if (isClosed) return;

      _safeEmit(state.copyWith(
        status: ProfileStatus.loaded,
        profile: profile,
        stats: stats,
        isCurrentUser: true,
      ));

      _authSubscription?.cancel();
      if (authRepository != null) {
        _authSubscription = authRepository!.authStateChanges.listen((updated) {
          if (!isClosed && updated != null && state.isCurrentUser) {
            _safeEmit(state.copyWith(profile: updated));
          }
        });
      }
    } else {
      _safeEmit(state.copyWith(status: ProfileStatus.loading));
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
        if (isClosed) return;

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

        List<UserAnimeEntry> friendEntries = const [];
        if (client != null) {
          try {
            final List<dynamic> listRows = await client
                .from('user_anime_lists')
                .select('anime_id, status, score, title, poster_url')
                .eq('user_id', targetUserId);
            if (listRows.isNotEmpty) {
              friendEntries = listRows
                  .map((e) => UserAnimeEntry.fromJson(e as Map<String, dynamic>))
                  .toList();
              friendStats = UserAnimeStats.compute(friendEntries);
            }
          } catch (e) {
            debugPrint('Error getting friend anime lists: $e');
          }
        }
        if (isClosed) return;

        List<UserAnimeEntry> myEntries = const [];
        if (getIt.isRegistered<AnimeListCubit>()) {
          myEntries = getIt<AnimeListCubit>().state.allEntries;
        }
        if (myEntries.isEmpty && animeListRepository != null) {
          try {
            myEntries = await animeListRepository!.getAllEntries();
          } catch (_) {}
        }
        final compatibility = TasteCompatibilityCalculator.calculate(
          myEntries,
          friendEntries,
        );

        _safeEmit(state.copyWith(
          status: ProfileStatus.loaded,
          profile: friendProfile,
          stats: friendStats,
          isCurrentUser: false,
          tasteCompatibility: compatibility,
        ));
      } catch (e) {
        if (isClosed) return;
        _safeEmit(state.copyWith(
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
      username = UserProfile.generateAnimeNickname(targetUserId);
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
        favoriteAnimeTitle: 'Твое Имя',
        favoriteAnimePoster: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=1200&auto=format&fit=crop&q=80',
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
        favoriteAnimeTitle: 'Мастера Меча Онлайн',
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

