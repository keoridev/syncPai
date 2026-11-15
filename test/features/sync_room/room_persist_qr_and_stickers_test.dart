import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sync_pai/core/utils/qr_payload_router.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/player/presentation/widgets/floating_pai_chan_reactions_overlay.dart';
import 'package:sync_pai/features/sync_room/data/repositories/sync_room_repository_impl.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_room.dart';
import 'package:sync_pai/features/sync_room/presentation/cubit/sync_room_cubit.dart';
import 'package:sync_pai/features/sync_room/presentation/cubit/sync_room_state.dart';

class _FailingCreateRoomRepository extends SyncRoomRepositoryImpl {
  @override
  Future<SyncRoom> createRoom({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality quality = PlayerQuality.hd,
    String hostName = '',
  }) async {
    throw const PostgrestException(message: 'RLS policy violation on rooms');
  }
}

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
    ],
  );

  group('Pai-chan distinct sticker assets, glow colors & animations', () {
    test('each PaiChanSticker uses distinct assets/stickers/pai_*.png and glowColor', () {
      expect(PaiChanSticker.excited.assetPath, 'assets/stickers/pai_hype.png');
      expect(PaiChanSticker.happy.assetPath, 'assets/stickers/pai_laugh.png');
      expect(PaiChanSticker.surprised.assetPath, 'assets/stickers/pai_shock.png');
      expect(PaiChanSticker.sad.assetPath, 'assets/stickers/pai_cry.png');
      expect(PaiChanSticker.love.assetPath, 'assets/stickers/pai_love.png');
      expect(PaiChanSticker.sleepy.assetPath, 'assets/stickers/pai_sleepy.png');

      expect(PaiChanSticker.excited.glowColor, Colors.amber);
      expect(PaiChanSticker.happy.glowColor, Colors.cyan);
      expect(PaiChanSticker.surprised.glowColor, Colors.purple);
      expect(PaiChanSticker.sad.glowColor, Colors.blue);
      expect(PaiChanSticker.love.glowColor, Colors.pink);
      expect(PaiChanSticker.sleepy.glowColor, Colors.indigo);

      expect(PaiChanSticker.fromIdOrEmoji('hype'), PaiChanSticker.excited);
      expect(PaiChanSticker.fromIdOrEmoji('laugh'), PaiChanSticker.happy);
      expect(PaiChanSticker.fromIdOrEmoji('shock'), PaiChanSticker.surprised);
      expect(PaiChanSticker.fromIdOrEmoji('cry'), PaiChanSticker.sad);
      expect(PaiChanSticker.fromIdOrEmoji('heart'), PaiChanSticker.love);
      expect(PaiChanSticker.fromIdOrEmoji('chill'), PaiChanSticker.sleepy);
    });

    testWidgets('PaiChanStickerReactionBar renders 44x44 pills in non-compact mode', (tester) async {
      PaiChanSticker? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaiChanStickerReactionBar(
              onStickerSelected: (s) => selected = s,
            ),
          ),
        ),
      );

      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(const ValueKey('pai_sticker_btn_excited')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(container.constraints?.maxWidth, 44.0);
      expect(container.constraints?.maxHeight, 44.0);

      await tester.tap(find.byKey(const ValueKey('pai_sticker_btn_love')));
      await tester.pump();
      expect(selected, PaiChanSticker.love);
    });

    testWidgets('FloatingPaiChanReactionsOverlay renders all 6 distinct sticker choreographies & particles', (tester) async {
      final reactions = PaiChanSticker.values.asMap().entries.map((entry) {
        return FloatingReaction(
          id: 'r_${entry.key}',
          emoji: entry.value.fallbackEmoji,
          stickerId: entry.value.id,
          sender: 'User${entry.key}',
          senderId: 'user_${entry.key}',
          startXOffset: 0.2 + entry.key * 0.1,
          timestamp: DateTime.now(),
        );
      }).toList();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: FloatingPaiChanReactionsOverlay(reactions: reactions),
            ),
          ),
        ),
      );

      // Pump halfway through the 2600ms animation and then to completion
      await tester.pump(const Duration(milliseconds: 900));
      for (var i = 0; i < PaiChanSticker.values.length; i++) {
        expect(
          find.byKey(ValueKey('floating_pai_sticker_r_$i')),
          findsOneWidget,
        );
      }
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.pump(const Duration(milliseconds: 1800));
    });
  });

  group('Room persistence & QR payload parsing', () {
    test('RoomCodeParser & QrPayloadRouter normalize syncpai://room/ and SP- codes to clean 6-digit ID', () {
      expect(RoomCodeParser.extractCleanRoomId('syncpai://room/639245'), '639245');
      expect(RoomCodeParser.extractCleanRoomId('SP-639245'), '639245');
      expect(RoomCodeParser.extractCleanRoomId('639245'), '639245');

      final parsed = QrPayloadRouter.parse('syncpai://room/639245');
      expect(parsed.type, QrPayloadType.room);
      expect(parsed.cleanCode, '639245');
    });

    test('SyncRoomCubit.createRoom emits SyncRoomError on PostgrestException instead of unpersisted room', () async {
      final cubit = SyncRoomCubit(repository: _FailingCreateRoomRepository());
      addTearDown(cubit.close);

      await cubit.createRoom(
        title: sampleAnime,
        episode: sampleAnime.episodes.first,
        quality: PlayerQuality.hd,
      );

      expect(cubit.state, isA<SyncRoomError>());
      expect(
        (cubit.state as SyncRoomError).message,
        contains('RLS policy violation on rooms'),
      );
    });
  });
}
