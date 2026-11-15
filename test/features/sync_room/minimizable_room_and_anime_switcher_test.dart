import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/sync_room/data/repositories/sync_room_repository_impl.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_room.dart';
import 'package:sync_pai/features/sync_room/presentation/cubit/sync_room_cubit.dart';
import 'package:sync_pai/features/sync_room/presentation/cubit/sync_room_state.dart';
import 'package:sync_pai/features/sync_room/presentation/widgets/floating_room_overlay.dart';
import 'package:sync_pai/features/sync_room/presentation/widgets/in_room_anime_picker_sheet.dart';
import 'package:sync_pai/features/sync_room/services/active_room_service.dart';

class _DelayedSyncRoomRepository extends SyncRoomRepositoryImpl {
  final Completer<SyncRoom> createCompleter = Completer<SyncRoom>();

  @override
  Future<SyncRoom> createRoom({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality quality = PlayerQuality.hd,
    String hostName = 'Хост (Вы)',
  }) {
    return createCompleter.future;
  }
}

void main() {
  const initialAnime = AnimeTitle(
    id: 101,
    code: 'solo_leveling',
    russianTitle: 'Поднятие уровня в одиночку',
    englishTitle: 'Solo Leveling',
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    genres: ['Экшен', 'Фэнтези'],
    description: 'Охотник Сон Джин-Ву.',
    status: 'Онгоинг',
    episodes: [EpisodeItem(episode: 1, name: 'Серия 1')],
  );

  const secondAnime = AnimeTitle(
    id: 202,
    code: 'frieren',
    russianTitle: 'Провожающая в последний путь Фрирен',
    englishTitle: 'Sousou no Frieren',
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    genres: ['Приключения', 'Фэнтези'],
    description: 'Путешествие эльфийки Фрирен.',
    status: 'Онгоинг',
    episodes: [EpisodeItem(episode: 1, name: 'Конец приключения')],
  );

  tearDown(() async {
    await ActiveRoomService.instance.leaveActiveRoom();
    ActiveRoomService.instance.setRepositoryForTesting(null);
  });

  group('SyncRoomCubit close guard & in-room anime switching', () {
    test('does not throw StateError when closed before createRoom finishes', () async {
      final delayedRepo = _DelayedSyncRoomRepository();
      final cubit = SyncRoomCubit(repository: delayedRepo);

      final createFuture = cubit.createRoom(
        title: initialAnime,
        episode: const EpisodeItem(episode: 1),
      );

      // Закрываем кубик до завершения асинхронного createRoom
      await cubit.close();

      delayedRepo.createCompleter.complete(
        SyncRoom(
          code: 'SP-482100',
          title: initialAnime,
          episode: const EpisodeItem(episode: 1),
          quality: PlayerQuality.hd,
          hostName: 'Хост (Вы)',
          status: SyncRoomStatus.waiting,
          createdAt: DateTime.now(),
        ),
      );

      await expectLater(createFuture, completes);
    });

    test('changeRoomAnime updates title and episode while keeping same room code', () async {
      final repo = SyncRoomRepositoryImpl();
      final cubit = SyncRoomCubit(repository: repo);

      await cubit.createRoom(
        title: initialAnime,
        episode: const EpisodeItem(episode: 1),
      );

      expect(cubit.state, isA<SyncRoomHostWaiting>());
      final originalCode = (cubit.state as SyncRoomHostWaiting).room.code;

      await cubit.changeRoomAnime(secondAnime);

      expect(cubit.state, isA<SyncRoomHostWaiting>());
      final updatedState = cubit.state as SyncRoomHostWaiting;
      expect(updatedState.room.code, equals(originalCode));
      expect(updatedState.room.title.id, equals(secondAnime.id));
      expect(updatedState.room.title.displayTitle, equals('Провожающая в последний путь Фрирен'));

      await cubit.close();
    });
  });

  group('FloatingRoomOverlay & Pai-chan Friend Joined Notification', () {
    testWidgets('renders minimized room dock and shows Pai-chan banner when friend joins', (tester) async {
      final repo = SyncRoomRepositoryImpl();
      ActiveRoomService.instance.setRepositoryForTesting(repo);

      final room = SyncRoom(
        code: 'SP-482100',
        title: initialAnime,
        episode: const EpisodeItem(episode: 1, name: 'Серия 1'),
        quality: PlayerQuality.hd,
        hostName: 'Riku',
        status: SyncRoomStatus.waiting,
        createdAt: DateTime.now(),
      );

      bool expandCalled = false;
      ActiveRoomService.instance.minimizeRoom(
        room: room,
        isHost: true,
        isInPlayer: false,
        onExpandRoom: (_, __) {
          expandCalled = true;
        },
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: FloatingRoomOverlay(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // Проверяем отображение кода комнаты, счетчика 1/5 и текущего аниме
      expect(find.byKey(const ValueKey('floating_room_dock_card')), findsOneWidget);
      expect(find.text('SP-482100'), findsOneWidget);
      expect(find.text('👥 1/5'), findsOneWidget);
      expect(find.textContaining('Поднятие уровня в одиночку'), findsOneWidget);

      // Симулируем вход друга пока комната свернута
      ActiveRoomService.instance.simulateFriendJoin(peerName: 'Sakura');
      await tester.pump();

      // Счетчик участников должен обновиться на 2/5, и должен появиться баннер с Пай-чан
      expect(find.text('👥 2/5'), findsOneWidget);
      expect(find.byKey(const ValueKey('floating_room_friend_joined_banner')), findsOneWidget);
      expect(
        find.text('Друг зашёл в комнату SP-482100! Нажми, чтобы вернуться.'),
        findsOneWidget,
      );

      // Нажимаем «Развернуть»
      await tester.tap(find.byKey(const ValueKey('floating_room_expand_btn')));
      await tester.pump();

      expect(expandCalled, isTrue);
      expect(ActiveRoomService.instance.isMinimized, isFalse);
      expect(find.byKey(const ValueKey('floating_room_dock_card')), findsNothing);
    });
  });

  group('InRoomAnimePickerSheet', () {
    testWidgets('switches anime inside active room without closing or recreating room', (tester) async {
      final repo = SyncRoomRepositoryImpl();
      ActiveRoomService.instance.setRepositoryForTesting(repo);

      final room = SyncRoom(
        code: 'SP-482100',
        title: initialAnime,
        episode: const EpisodeItem(episode: 1),
        quality: PlayerQuality.hd,
        hostName: 'Riku',
        peerName: 'Sakura',
        status: SyncRoomStatus.connected,
        createdAt: DateTime.now(),
      );

      ActiveRoomService.instance.registerActiveRoom(
        room: room,
        isHost: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InRoomAnimePickerSheet(
              roomCode: 'SP-482100',
              currentTitle: initialAnime,
              initialCatalogTitles: [initialAnime, secondAnime],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Сменить аниме в комнате'), findsOneWidget);
      expect(find.text('SP-482100'), findsOneWidget);
      expect(find.text('Играет'), findsOneWidget);
      expect(find.text('Провожающая в последний путь Фрирен'), findsOneWidget);

      // Выбираем второе аниме
      await tester.tap(find.byKey(ValueKey('in_room_picker_item_${secondAnime.id}')));
      await tester.pump();

      // Проверяем, что тайтл комнаты сменился, а код комнаты и друг остались прежними
      final updatedRoom = ActiveRoomService.instance.activeRoom!;
      expect(updatedRoom.code, equals('SP-482100'));
      expect(updatedRoom.peerName, equals('Sakura'));
      expect(updatedRoom.title.id, equals(secondAnime.id));
      expect(updatedRoom.title.displayTitle, equals('Провожающая в последний путь Фрирен'));
    });
  });
}

