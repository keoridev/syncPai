import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/player/presentation/widgets/floating_pai_chan_reactions_overlay.dart';
import 'package:sync_pai/features/sync_room/data/repositories/sync_room_repository_impl.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';

void main() {
  const sampleAnime = AnimeTitle(
    id: 505,
    code: 'dandadan',
    russianTitle: 'Дандадан',
    englishTitle: 'Dandadan',
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    genres: ['Экшен', 'Комедия'],
    description: 'Мистика и пришельцы.',
    status: 'Онгоинг',
    episodes: [
      EpisodeItem(episode: 1, name: 'Серия 1'),
      EpisodeItem(episode: 2, name: 'Серия 2'),
    ],
  );

  group('Part 1 — Pai-chan Sticker Reactions Bar & Overlay', () {
    test('maps all 6 Pai-chan emotions to existing MascotState assets', () {
      expect(PaiChanSticker.values.length, equals(6));
      expect(PaiChanSticker.excited.mascotState, equals(MascotState.friendsJoined));
      expect(PaiChanSticker.happy.mascotState, equals(MascotState.happy));
      expect(PaiChanSticker.surprised.mascotState, equals(MascotState.serverError));
      expect(PaiChanSticker.sad.mascotState, equals(MascotState.emptyFavorites));
      expect(PaiChanSticker.love.mascotState, equals(MascotState.favoriteAdded));
      expect(PaiChanSticker.sleepy.mascotState, equals(MascotState.sleeping));

      expect(PaiChanSticker.fromIdOrEmoji('excited'), equals(PaiChanSticker.excited));
      expect(PaiChanSticker.fromIdOrEmoji('😂'), equals(PaiChanSticker.happy));
      expect(PaiChanSticker.fromIdOrEmoji('❤️'), equals(PaiChanSticker.love));
      expect(PaiChanSticker.fromIdOrEmoji('😭'), equals(PaiChanSticker.sad));
    });

    testWidgets('PaiChanStickerReactionBar renders 6 circular stickers and fires callback on tap', (tester) async {
      PaiChanSticker? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaiChanStickerReactionBar(
              onStickerSelected: (sticker) {
                selected = sticker;
              },
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('pai_chan_sticker_reaction_bar')), findsOneWidget);
      for (final sticker in PaiChanSticker.values) {
        expect(find.byKey(ValueKey('pai_sticker_btn_${sticker.id}')), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('pai_sticker_btn_excited')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(selected, equals(PaiChanSticker.excited));
    });

    testWidgets('FloatingPaiChanReactionsOverlay renders 76x76 sticker bubble with sender nickname badge', (tester) async {
      final reactions = [
        FloatingReaction(
          id: 'rx_1',
          emoji: '🔥',
          stickerId: 'excited',
          sender: 'Riku',
          senderId: 'user_riku',
          startXOffset: 0.45,
          timestamp: DateTime.now(),
        ),
        FloatingReaction(
          id: 'rx_2',
          emoji: '❤️',
          stickerId: 'love',
          sender: 'Sakura',
          senderId: 'user_sakura',
          startXOffset: 0.65,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FloatingPaiChanReactionsOverlay(reactions: reactions),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('floating_pai_chan_reactions_overlay')), findsOneWidget);
      expect(find.byKey(const ValueKey('floating_pai_sticker_rx_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('floating_pai_sticker_rx_2')), findsOneWidget);
      expect(find.text('Riku'), findsOneWidget);
      expect(find.text('Sakura'), findsOneWidget);
    });
  });

  group('Part 2 & 3 — Room Chat Delivery, Deduplication & Unified Sync Payloads', () {
    test('ChatMessage.fromRoomMessageRow parses both text and content columns and text/user types', () {
      final rowWithText = ChatMessage.fromRoomMessageRow({
        'id': 'msg_100',
        'sender_name': 'Riku',
        'text': 'Привет из комнаты!',
        'type': 'text',
        'created_at': '2026-11-15T12:00:00Z',
      });
      expect(rowWithText.id, equals('msg_100'));
      expect(rowWithText.sender, equals('Riku'));
      expect(rowWithText.text, equals('Привет из комнаты!'));
      expect(rowWithText.type, equals('user'));

      final rowWithContent = ChatMessage.fromRoomMessageRow({
        'id': 'msg_101',
        'sender_name': 'Sakura',
        'content': 'Готовлю рамен 🍜',
        'type': 'user',
        'created_at': '2026-11-15T12:01:00Z',
      });
      expect(rowWithContent.id, equals('msg_101'));
      expect(rowWithContent.sender, equals('Sakura'));
      expect(rowWithContent.text, equals('Готовлю рамен 🍜'));
      expect(rowWithContent.type, equals('user'));
    });

    test('SyncRoomRepositoryImpl delivers pai_sticker_reaction, chat_message, and unified playback_sync packets', () async {
      final repo = SyncRoomRepositoryImpl();
      final room = await repo.createRoom(
        title: sampleAnime,
        episode: const EpisodeItem(episode: 1),
        quality: PlayerQuality.fhd,
        hostName: 'Riku',
      );

      final receivedPackets = <SyncPacket>[];
      final sub = repo.subscribeToPackets(room.code).listen(receivedPackets.add);

      await repo.sendReaction(
        roomCode: room.code,
        emoji: '🔥',
        stickerId: 'excited',
        sender: 'Riku',
        senderId: 'uid_riku',
        reactionId: 'rx_test_1',
      );

      await repo.sendChatMessage(
        roomCode: room.code,
        text: 'Опенинг просто космос!',
        sender: 'Riku',
        isHost: true,
        messageId: 'msg_test_1',
      );

      await repo.broadcastPlayback(
        roomCode: room.code,
        time: 42.5,
        isPlaying: true,
        episode: 2,
        animeId: '${sampleAnime.id}',
        playbackRate: 2.0,
        updatedBy: 'uid_riku',
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        receivedPackets.any((p) =>
            (p.action == SyncActionTypes.paiStickerReaction ||
                p.action == SyncActionTypes.reaction) &&
            p.payload['sticker_id'] == 'excited' &&
            p.payload['sender_name'] == 'Riku' &&
            p.payload['sender_id'] == 'uid_riku'),
        isTrue,
      );

      expect(
        receivedPackets.any((p) =>
            p.action == SyncActionTypes.chatMessage &&
            p.payload['id'] == 'msg_test_1' &&
            p.payload['text'] == 'Опенинг просто космос!' &&
            p.payload['sender_name'] == 'Riku'),
        isTrue,
      );

      expect(
        receivedPackets.any((p) =>
            p.action == SyncActionTypes.controlAction &&
            p.payload['current_time_sec'] == 42.5 &&
            p.payload['episode_index'] == 2 &&
            p.payload['playback_rate'] == 2.0 &&
            p.payload['updated_by'] == 'uid_riku'),
        isTrue,
      );

      await sub.cancel();
    });
  });
}
