import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../domain/entities/sync_protocol.dart';
import '../../domain/repositories/sync_room_repository.dart';
import 'coop_match_state.dart';

class CoopMatchCubit extends Cubit<CoopMatchState> {
  final String? roomCode;
  final String userName;
  final SyncRoomRepository? syncRepository;
  final Duration suspenseDuration;
  StreamSubscription<SyncPacket>? _packetSub;

  CoopMatchCubit({
    required List<AnimeTitle> initialDeck,
    this.roomCode,
    this.userName = 'Я',
    this.syncRepository,
    this.suspenseDuration = const Duration(milliseconds: 1200),
  }) : super(CoopMatchState(deck: initialDeck)) {
    _initNetwork();
  }

  void _initNetwork() {
    if (roomCode != null && syncRepository != null) {
      _packetSub = syncRepository!.subscribeToPackets(roomCode!).listen((packet) {
        if (packet.sender == userName) return;

        if (packet.action == SyncActionTypes.swipeVote) {
          final titleId = (packet.payload['title_id'] as num?)?.toInt();
          final liked = packet.payload['liked'] as bool? ?? false;
          if (titleId != null) {
            _handlePeerVote(titleId, liked, packet.sender);
          }
        } else if (packet.action == SyncActionTypes.matchFound) {
          final titleId = (packet.payload['title_id'] as num?)?.toInt();
          if (titleId != null) {
            final matched = state.deck.firstWhere(
              (t) => t.id == titleId,
              orElse: () => state.deck.first,
            );
            _triggerSuspenseMatch(matched);
          }
        } else if (packet.action == SyncActionTypes.startPlayback) {
          final titleId = (packet.payload['title_id'] as num?)?.toInt();
          AnimeTitle? matched = state.matchedTitle;
          if (titleId != null) {
            matched = state.deck.firstWhere(
              (t) => t.id == titleId,
              orElse: () => state.deck.first,
            );
          }
          if (matched != null) {
            emit(state.copyWith(
              matchedTitle: () => matched,
              isStartingPlayback: true,
            ));
          }
        }
      });
    }
  }

  void _handlePeerVote(int titleId, bool liked, String peer) {
    final updatedPeerVotes = Map<int, bool>.from(state.peerVotes)..[titleId] = liked;
    emit(state.copyWith(peerVotes: updatedPeerVotes, peerName: peer));

    // Проверяем, совпал ли лайк с моим уже поставленным
    if (liked && state.myVotes[titleId] == true) {
      final matched = state.deck.firstWhere(
        (t) => t.id == titleId,
        orElse: () => state.deck.first,
      );
      _triggerSuspenseMatch(matched);
    }
  }

  Future<void> _triggerSuspenseMatch(AnimeTitle match) async {
    // Эффект игрового автомата (Variable Reward): микро-пауза интриги
    emit(state.copyWith(isSuspenseReveal: true));
    if (suspenseDuration > Duration.zero) {
      await Future<void>.delayed(suspenseDuration);
    }
    if (!isClosed) {
      emit(state.copyWith(
        isSuspenseReveal: false,
        matchedTitle: () => match,
      ));
    }
  }

  Future<void> voteCurrent(bool isLike) async {
    final current = state.currentTitle;
    if (current == null) return;

    final updatedMyVotes = Map<int, bool>.from(state.myVotes)..[current.id] = isLike;
    final nextIndex = state.currentIndex + 1;

    // Проверяем совпадение (Match)
    AnimeTitle? match;
    if (isLike && state.peerVotes[current.id] == true) {
      match = current;
    }

    emit(state.copyWith(
      myVotes: updatedMyVotes,
      currentIndex: nextIndex,
    ));

    if (match != null) {
      await _triggerSuspenseMatch(match);
    }

    // Отправляем голос в комнату Supabase
    if (roomCode != null && syncRepository != null) {
      await syncRepository!.sendPacket(
        SyncPacket(
          action: SyncActionTypes.swipeVote,
          sender: userName,
          roomCode: roomCode!,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {
            'title_id': current.id,
            'liked': isLike,
          },
        ),
      );

      if (match != null) {
        await syncRepository!.sendPacket(
          SyncPacket(
            action: SyncActionTypes.matchFound,
            sender: userName,
            roomCode: roomCode!,
            timestampMs: DateTime.now().millisecondsSinceEpoch,
            payload: {'title_id': current.id},
          ),
        );
      }
    }
  }

  Future<void> startWatchingMatch() async {
    final matched = state.matchedTitle;
    if (matched == null) return;

    emit(state.copyWith(isStartingPlayback: true));

    if (roomCode != null && syncRepository != null) {
      await syncRepository!.sendPacket(
        SyncPacket(
          action: SyncActionTypes.startPlayback,
          sender: userName,
          roomCode: roomCode!,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {'title_id': matched.id},
        ),
      );
    }
  }

  void clearMatch() {
    emit(state.copyWith(matchedTitle: () => null, isStartingPlayback: false));
  }

  @override
  Future<void> close() {
    _packetSub?.cancel();
    return super.close();
  }
}

