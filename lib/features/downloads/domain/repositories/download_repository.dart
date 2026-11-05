import '../entities/download_task.dart';

abstract class DownloadRepository {
  Future<List<DownloadTask>> getTasks();
  Future<void> startDownload(DownloadTask task);
  Future<void> cancelDownload(String taskId);
  Future<void> deleteTask(String taskId);
  bool isDownloaded(int titleId, int episode);
  DownloadTask? getTask(int titleId, int episode);
  Stream<DownloadTask> get taskUpdates;
  void dispose();
}

