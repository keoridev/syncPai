import 'package:equatable/equatable.dart';
import '../../domain/entities/watch_history_item.dart';

class WatchHistoryState extends Equatable {
  final List<WatchHistoryItem> history;
  final Map<int, WatchHistoryItem> historyMap;
  final bool isLoading;

  const WatchHistoryState({
    this.history = const [],
    this.historyMap = const {},
    this.isLoading = false,
  });

  WatchHistoryItem? getForTitle(int titleId) => historyMap[titleId];

  /// Последний просмотренный тайтл
  WatchHistoryItem? get lastWatched => history.isNotEmpty ? history.first : null;

  WatchHistoryState copyWith({
    List<WatchHistoryItem>? history,
    Map<int, WatchHistoryItem>? historyMap,
    bool? isLoading,
  }) {
    return WatchHistoryState(
      history: history ?? this.history,
      historyMap: historyMap ?? this.historyMap,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [history, historyMap, isLoading];
}

