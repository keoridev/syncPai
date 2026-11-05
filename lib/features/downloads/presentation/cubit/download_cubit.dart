import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/repositories/download_repository.dart';
import 'download_state.dart';

class DownloadCubit extends Cubit<DownloadState> {
  final DownloadRepository _repository;
  StreamSubscription<DownloadTask>? _subscription;

  DownloadCubit(this._repository) : super(const DownloadState()) {
    _init();
  }

  Future<void> _init() async {
    emit(state.copyWith(isLoading: true));
    final tasksList = await _repository.getTasks();
    final tasksMap = {for (final t in tasksList) t.id: t};
    emit(state.copyWith(tasks: tasksMap, isLoading: false));

    _subscription = _repository.taskUpdates.listen((task) {
      final updatedMap = Map<String, DownloadTask>.from(state.tasks);
      if (task.status == DownloadStatus.idle && task.progress == 0.0) {
        updatedMap.remove(task.id);
      } else {
        updatedMap[task.id] = task;
      }
      emit(state.copyWith(tasks: updatedMap));
    });
  }

  Future<void> startDownload({
    required int titleId,
    required String titleName,
    required String posterUrl,
    required int episode,
    required String episodeName,
    required String quality,
    required String sourceUrl,
  }) async {
    final task = DownloadTask(
      id: DownloadTask.generateId(titleId, episode),
      titleId: titleId,
      titleName: titleName,
      posterUrl: posterUrl,
      episode: episode,
      episodeName: episodeName,
      quality: quality,
      sourceUrl: sourceUrl,
      localPath: '',
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
    );

    await _repository.startDownload(task);
  }

  Future<void> cancelDownload(String taskId) async {
    await _repository.cancelDownload(taskId);
  }

  Future<void> deleteDownload(String taskId) async {
    await _repository.deleteTask(taskId);
  }

  /// Включение / отключение умных загрузок
  void toggleSmartDownloads(bool enabled) {
    emit(state.copyWith(smartDownloadsEnabled: enabled));
  }

  /// Умная загрузка (Smart Downloads):
  /// Пользователь скачивает серию N -> приложение автоматически ставит в фоновую очередь серию N+1.
  Future<void> startSmartDownload({
    required AnimeTitle title,
    required EpisodeItem episode,
    required String quality,
  }) async {
    final videoUrl = episode.getUrlForQuality(quality);
    if (videoUrl.isNotEmpty) {
      await startDownload(
        titleId: title.id,
        titleName: title.displayTitle,
        posterUrl: title.posterMedium.isNotEmpty ? title.posterMedium : title.posterOriginal,
        episode: episode.episode,
        episodeName: episode.name ?? 'Серия ${episode.episode}',
        quality: quality,
        sourceUrl: videoUrl,
      );
    }

    // Если включены умные загрузки, кэшируем следующую серию в фоне
    if (state.smartDownloadsEnabled && title.episodes.isNotEmpty) {
      final nextEpIndex = title.episodes.indexWhere((e) => e.episode == episode.episode + 1);
      if (nextEpIndex != -1) {
        final nextEp = title.episodes[nextEpIndex];
        final nextTaskId = DownloadTask.generateId(title.id, nextEp.episode);
        if (!state.tasks.containsKey(nextTaskId)) {
          final nextUrl = nextEp.getUrlForQuality(quality);
          if (nextUrl.isNotEmpty) {
            await startDownload(
              titleId: title.id,
              titleName: title.displayTitle,
              posterUrl: title.posterMedium.isNotEmpty ? title.posterMedium : title.posterOriginal,
              episode: nextEp.episode,
              episodeName: nextEp.name ?? 'Серия ${nextEp.episode}',
              quality: quality,
              sourceUrl: nextUrl,
            );
          }
        }
      }
    }
  }

  /// Обработка завершения просмотра серии (Smart Cleanup & Auto-fetch):
  /// Когда 1-я серия досмотрена, она автоматически удаляется (освобождая память устройства),
  /// а приложение автоматически начинает загрузку 3-й серии.
  Future<void> onEpisodeFinished({
    required int titleId,
    required int finishedEpisode,
    AnimeTitle? title,
    String quality = '1080p FHD',
  }) async {
    if (!state.smartDownloadsEnabled) return;

    // 1. Освобождаем память: удаляем скачанный файл досмотренной серии
    final finishedTaskId = DownloadTask.generateId(titleId, finishedEpisode);
    if (state.tasks.containsKey(finishedTaskId)) {
      await deleteDownload(finishedTaskId);
    }

    // 2. Автоматически скачиваем следующую серию в очереди (например N+2)
    if (title != null && title.episodes.isNotEmpty) {
      final targetEpNum = finishedEpisode + 2;
      final targetIndex = title.episodes.indexWhere((e) => e.episode == targetEpNum);
      if (targetIndex != -1) {
        final targetEp = title.episodes[targetIndex];
        final targetTaskId = DownloadTask.generateId(titleId, targetEp.episode);
        if (!state.tasks.containsKey(targetTaskId)) {
          final targetUrl = targetEp.getUrlForQuality(quality);
          if (targetUrl.isNotEmpty) {
            await startDownload(
              titleId: title.id,
              titleName: title.displayTitle,
              posterUrl: title.posterMedium.isNotEmpty ? title.posterMedium : title.posterOriginal,
              episode: targetEp.episode,
              episodeName: targetEp.name ?? 'Серия ${targetEp.episode}',
              quality: quality,
              sourceUrl: targetUrl,
            );
          }
        }
      }
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}

