import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/watch_history_item.dart';
import '../../domain/repositories/watch_history_repository.dart';
import 'watch_history_state.dart';

class WatchHistoryCubit extends Cubit<WatchHistoryState> {
  final WatchHistoryRepository repository;

  WatchHistoryCubit({required this.repository}) : super(const WatchHistoryState()) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    emit(state.copyWith(isLoading: true));
    try {
      final list = await repository.getAllHistory();
      final map = {for (final item in list) item.titleId: item};
      emit(state.copyWith(
        history: list,
        historyMap: map,
        isLoading: false,
      ));
    } catch (_) {
      emit(state.copyWith(isLoading: false));
    }
  }

  Future<void> saveProgress({
    required int titleId,
    required String titleName,
    required String posterUrl,
    required int episode,
    String? episodeName,
    required Duration position,
    required Duration duration,
  }) async {
    if (titleId <= 0) return;

    final item = WatchHistoryItem(
      titleId: titleId,
      titleName: titleName,
      posterUrl: posterUrl,
      episode: episode,
      episodeName: episodeName,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds > 0 ? duration.inMilliseconds : 1440000,
      updatedAt: DateTime.now(),
    );

    await repository.saveProgress(item);

    final normName = titleName.trim().toLowerCase();
    final updatedMap = Map<int, WatchHistoryItem>.from(state.historyMap)..[titleId] = item;
    final updatedList = List<WatchHistoryItem>.from(state.history)
      ..removeWhere((e) =>
          e.titleId == titleId ||
          (normName.isNotEmpty && e.titleName.trim().toLowerCase() == normName))
      ..insert(0, item);

    emit(state.copyWith(
      history: updatedList,
      historyMap: updatedMap,
    ));
  }

  Future<void> removeProgress(int titleId) async {
    await repository.removeProgress(titleId);
    final updatedMap = Map<int, WatchHistoryItem>.from(state.historyMap)..remove(titleId);
    final updatedList = List<WatchHistoryItem>.from(state.history)
      ..removeWhere((e) => e.titleId == titleId);

    emit(state.copyWith(
      history: updatedList,
      historyMap: updatedMap,
    ));
  }

  Future<void> clearAllHistory() async {
    final ids = state.history.map((e) => e.titleId).toList();
    for (final id in ids) {
      await repository.removeProgress(id);
    }
    emit(state.copyWith(
      history: const [],
      historyMap: const {},
    ));
  }
}

