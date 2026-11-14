import '../entities/download_task.dart';

abstract class DownloadRepository {
  Future<List<DownloadTask>> getTasks();
  Future<void> startDownload(DownloadTask task);
  Future<void> pauseDownload(String taskId);
  Future<void> resumeDownload(String taskId);
  Future<void> cancelDownload(String taskId);
  Future<void> deleteTask(String taskId);
  Future<void> deleteAllTasks();
  Future<int> getTotalStorageUsed();
  bool isDownloaded(int titleId, int episode);
  DownloadTask? getTask(int titleId, int episode);
  Stream<DownloadTask> get taskUpdates;
  void dispose();
}

