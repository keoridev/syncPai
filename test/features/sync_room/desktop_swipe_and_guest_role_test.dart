import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_cubit.dart';
import 'package:sync_pai/features/player/presentation/cubit/player_state.dart';
import 'package:sync_pai/features/player/presentation/widgets/player_controls_overlay.dart';
import 'package:sync_pai/features/player/presentation/widgets/twitch_chat_overlay.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';
import 'package:sync_pai/features/sync_room/presentation/cubit/coop_match_cubit.dart';
import 'package:sync_pai/features/sync_room/presentation/screens/coop_match_screen.dart';

AnimeTitle _fakeAnime(int id, String title) => AnimeTitle(
      id: id,
      code: 'code_$id',
      russianTitle: title,
      englishTitle: title,
      posterSmall: '',
      posterMedium: '',
      posterOriginal: '',
      description: 'desc $id',
      genres: const ['Экшен'],
      year: 2025,
      status: 'Вышел',
      episodes: const [EpisodeItem(episode: 1)],
    );

class _FakePlayerCubit extends Fake implements PlayerCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Desktop Swipe Deck — opens currently active card, not initial card', () {
    testWidgets('after swiping past 3 cards, info button opens 4th card', (tester) async {
      final deck = [
        _fakeAnime(101, 'First Anime'),
        _fakeAnime(102, 'Second Anime'),
        _fakeAnime(103, 'Third Anime'),
        _fakeAnime(104, 'Fourth Anime'),
      ];
      final cubit = CoopMatchCubit(
        initialDeck: deck,
        suspenseDuration: Duration.zero,
      );

      AnimeTitle? openedAnime;
      String? openedLocation;

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => CoopMatchScreen(cubit: cubit),
          ),
          GoRoute(
            path: '/anime/:id',
            builder: (context, state) {
              openedLocation = state.uri.toString();
              openedAnime = state.extra as AnimeTitle?;
              return Scaffold(
                body: Text('DETAILS: ${openedAnime?.russianTitle}'),
              );
            },
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('First Anime'), findsOneWidget);

      // Swipe / skip past 3 cards
      await cubit.voteCurrent(false);
      await tester.pump();
      await cubit.voteCurrent(false);
      await tester.pump();
      await cubit.voteCurrent(false);
      await tester.pumpAndSettle();

      expect(find.text('Fourth Anime'), findsOneWidget);
      expect(cubit.state.currentIndex, 3);

      // Click info button on 4th card
      await tester.tap(find.byKey(const ValueKey('coop_match_open_details_btn')));
      await tester.pumpAndSettle();

      expect(openedLocation, '/anime/104');
      expect(openedAnime?.id, 104);
      expect(openedAnime?.russianTitle, 'Fourth Anime');
      expect(find.text('DETAILS: Fourth Anime'), findsOneWidget);
    });

    testWidgets('Enter key opens the currently active card after swiping', (tester) async {
      final deck = [
        _fakeAnime(201, 'Card One'),
        _fakeAnime(202, 'Card Two'),
      ];
      final cubit = CoopMatchCubit(
        initialDeck: deck,
        suspenseDuration: Duration.zero,
      );

      AnimeTitle? openedAnime;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => CoopMatchScreen(cubit: cubit),
          ),
          GoRoute(
            path: '/anime/:id',
            builder: (context, state) {
              openedAnime = state.extra as AnimeTitle?;
              return const Scaffold(body: Text('DETAILS'));
            },
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // ArrowRight likes Card One -> Card Two becomes active
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Card Two'), findsOneWidget);

      // Enter opens Card Two (not Card One!)
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(openedAnime?.id, 202);
      expect(openedAnime?.russianTitle, 'Card Two');
    });
  });

  group('Watch-Together Role Pill & Chat — strict session isHost check', () {
    testWidgets('PlayerControlsOverlay shows Участник when isHost == false and Хост комнаты when isHost == true',
        (tester) async {
      final fakeCubit = _FakePlayerCubit();

      Widget buildOverlay(bool isHost) => MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 450,
                child: PlayerControlsOverlay(
                  cubit: fakeCubit,
                  state: PlayerState(
                    title: _fakeAnime(1, 'Test Anime'),
                    episode: const EpisodeItem(episode: 1),
                    isHost: isHost,
                    roomCode: 'SP-123456',
                  ),
                  onBack: () {},
                ),
              ),
            ),
          );

      // Guest session (even on same account) -> Участник
      await tester.pumpWidget(buildOverlay(false));
      await tester.pump();
      expect(find.text('Участник'), findsOneWidget);
      expect(find.text('Хост комнаты'), findsNothing);

      // Host session -> Хост комнаты
      await tester.pumpWidget(buildOverlay(true));
      await tester.pump();
      expect(find.text('Хост комнаты'), findsOneWidget);
      expect(find.text('Участник'), findsNothing);
    });

    testWidgets('TwitchChatOverlay does not attach Хост crown badge when isHost == false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TwitchChatOverlay(
              isVisible: true,
              onToggleVisibility: () {},
              messages: [
                ChatMessage(
                  id: 'm1',
                  sender: 'keori_phone',
                  text: 'Привет с телефона',
                  isHost: false,
                  timestamp: DateTime.now(),
                ),
                ChatMessage(
                  id: 'm2',
                  sender: 'keori_pc',
                  text: 'Привет с ПК',
                  isHost: true,
                  timestamp: DateTime.now(),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.textContaining('keori_phone:'), findsOneWidget);
      expect(find.textContaining('👑 keori_phone'), findsNothing);
      expect(find.textContaining('👑 keori_pc:'), findsOneWidget);
    });
  });
}
