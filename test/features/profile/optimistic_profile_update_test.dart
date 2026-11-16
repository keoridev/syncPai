import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sync_pai/features/auth/domain/entities/user_profile.dart';
import 'package:sync_pai/features/auth/domain/repositories/auth_repository.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:sync_pai/features/auth/presentation/cubit/auth_state.dart';
import 'package:sync_pai/features/profile/presentation/cubit/profile_cubit.dart';

class _SlowFakeAuthRepo implements AuthRepository {
  final Completer<UserProfile> completer;
  final _ctrl = StreamController<UserProfile?>.broadcast();
  final UserProfile initial;

  _SlowFakeAuthRepo(this.initial, this.completer);

  @override
  Stream<UserProfile?> get authStateChanges => _ctrl.stream;

  @override
  Future<UserProfile> getCurrentProfile() async => initial;

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
  }) =>
      completer.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<ProfileCubit>()) {
      await getIt<ProfileCubit>().close();
      await getIt.unregister<ProfileCubit>();
    }
  });

  test('AuthCubit.updateProfile emits 0ms optimistic state and syncs ProfileCubit before network completes', () async {
    final initial = UserProfile.guest('u1').copyWith(username: 'keori', bio: 'old bio');
    final completer = Completer<UserProfile>();
    final repo = _SlowFakeAuthRepo(initial, completer);

    final profileCubit = ProfileCubit();
    await profileCubit.loadProfile();
    GetIt.instance.registerSingleton<ProfileCubit>(profileCubit);

    final authCubit = AuthCubit(repository: repo);
    await Future<void>.delayed(Duration.zero);
    expect(authCubit.state, isA<Authenticated>());

    // Trigger update without awaiting the slow 3s network call
    final future = authCubit.updateProfile(
      username: 'keori_new',
      bio: 'new instant bio',
      accentColor: '#22D3EE',
    );

    // 0ms synchronous check: AuthCubit and ProfileCubit are ALREADY updated!
    expect((authCubit.state as Authenticated).profile.username, 'keori_new');
    expect((authCubit.state as Authenticated).profile.bio, 'new instant bio');
    expect((authCubit.state as Authenticated).profile.accentColor, '#22D3EE');
    expect(profileCubit.state.profile.username, 'keori_new');

    completer.complete(initial.copyWith(username: 'keori_new', bio: 'new instant bio', accentColor: '#22D3EE'));
    await future;
    await authCubit.close();
  });

  test('AuthCubit.updateProfile rolls back to previousProfile on network error', () async {
    final initial = UserProfile.guest('u1').copyWith(username: 'keori', bio: 'old bio');
    final completer = Completer<UserProfile>();
    final repo = _SlowFakeAuthRepo(initial, completer);

    final authCubit = AuthCubit(repository: repo);
    await Future<void>.delayed(Duration.zero);

    final future = authCubit.updateProfile(username: 'broken_name');
    expect((authCubit.state as Authenticated).profile.username, 'broken_name');

    completer.completeError(Exception('Network timeout'));
    await future;

    // Rolled back cleanly without wiping Authenticated state
    expect((authCubit.state as Authenticated).profile.username, 'keori');
    await authCubit.close();
  });
}
