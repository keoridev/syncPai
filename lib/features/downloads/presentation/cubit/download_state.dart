import 'package:equatable/equatable.dart';
import '../../domain/entities/download_task.dart';

class DownloadState extends Equatable {
  final Map<String, DownloadTask> tasks;
  final bool isLoading;
  final String? errorMessage;
  final bool smartDownloadsEnabled;

  const DownloadState({
    this.tasks = const {},
    this.isLoading = false,
    this.errorMessage,
    this.smartDownloadsEnabled = true,
  });

  bool isDownloaded(int titleId, int episode) {
    final task = tasks[DownloadTask.generateId(titleId, episode)];
    return task != null && task.status == DownloadStatus.completed;
  }

  DownloadTask? getTask(int titleId, int episode) {
    return tasks[DownloadTask.generateId(titleId, episode)];
  }

  List<DownloadTask> get completedTasks {
    final list = tasks.values
        .where((t) => t.status == DownloadStatus.completed)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<DownloadTask> get activeTasks {
    return tasks.values
        .where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.queued)
        .toList();
  }

  int get totalDownloadedCount => completedTasks.length;

  int get totalBytesUsed =>
      completedTasks.fold<int>(0, (sum, item) => sum + item.totalBytes);

  String get formattedTotalBytesUsed {
    final mb = totalBytesUsed / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} ГБ';
    }
    return '${mb.toStringAsFixed(0)} МБ';
  }

  DownloadState copyWith({
    Map<String, DownloadTask>? tasks,
    bool? isLoading,
    String? errorMessage,
    bool? smartDownloadsEnabled,
  }) {
    return DownloadState(
      tasks: tasks ?? this.tasks,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      smartDownloadsEnabled: smartDownloadsEnabled ?? this.smartDownloadsEnabled,
    );
  }

  @override
  List<Object?> get props => [tasks, isLoading, errorMessage, smartDownloadsEnabled];
}

