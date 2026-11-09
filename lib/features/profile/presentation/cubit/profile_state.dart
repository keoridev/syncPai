import 'package:equatable/equatable.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../auth/domain/entities/user_profile.dart';

enum ProfileStatus { initial, loading, loaded, error }

class ProfileState extends Equatable {
  final ProfileStatus status;
  final UserProfile profile;
  final UserAnimeStats stats;
  final bool isCurrentUser;
  final String? errorMessage;

  const ProfileState({
    this.status = ProfileStatus.initial,
    required this.profile,
    required this.stats,
    this.isCurrentUser = true,
    this.errorMessage,
  });

  factory ProfileState.initial() => ProfileState(
        status: ProfileStatus.initial,
        profile: UserProfile.guest(),
        stats: const UserAnimeStats(
          totalTitles: 0,
          completedTitles: 0,
          watchingTitles: 0,
          plannedTitles: 0,
          droppedTitles: 0,
          totalEpisodesCompleted: 0,
          totalMinutesWatched: 0,
        ),
        isCurrentUser: true,
      );

  bool get isLoading => status == ProfileStatus.loading;
  bool get hasError => status == ProfileStatus.error;

  ProfileState copyWith({
    ProfileStatus? status,
    UserProfile? profile,
    UserAnimeStats? stats,
    bool? isCurrentUser,
    String? errorMessage,
  }) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      stats: stats ?? this.stats,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        status,
        profile,
        stats,
        isCurrentUser,
        errorMessage,
      ];
}

