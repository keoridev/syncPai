import 'package:equatable/equatable.dart';
import '../../../catalog/domain/entities/anime_title.dart';

class CoopMatchState extends Equatable {
  final List<AnimeTitle> deck;
  final int currentIndex;
  final Map<int, bool> myVotes;
  final Map<int, bool> peerVotes;
  final AnimeTitle? matchedTitle;
  final bool isSearching;
  final String? peerName;

  const CoopMatchState({
    this.deck = const [],
    this.currentIndex = 0,
    this.myVotes = const {},
    this.peerVotes = const {},
    this.matchedTitle,
    this.isSearching = false,
    this.peerName,
  });

  AnimeTitle? get currentTitle =>
      (deck.isNotEmpty && currentIndex < deck.length) ? deck[currentIndex] : null;

  bool get hasFinishedDeck => currentIndex >= deck.length;

  int get remainingCount => deck.length - currentIndex;

  CoopMatchState copyWith({
    List<AnimeTitle>? deck,
    int? currentIndex,
    Map<int, bool>? myVotes,
    Map<int, bool>? peerVotes,
    AnimeTitle? Function()? matchedTitle,
    bool? isSearching,
    String? peerName,
  }) {
    return CoopMatchState(
      deck: deck ?? this.deck,
      currentIndex: currentIndex ?? this.currentIndex,
      myVotes: myVotes ?? this.myVotes,
      peerVotes: peerVotes ?? this.peerVotes,
      matchedTitle: matchedTitle != null ? matchedTitle() : this.matchedTitle,
      isSearching: isSearching ?? this.isSearching,
      peerName: peerName ?? this.peerName,
    );
  }

  @override
  List<Object?> get props => [
        deck,
        currentIndex,
        myVotes,
        peerVotes,
        matchedTitle,
        isSearching,
        peerName,
      ];
}

