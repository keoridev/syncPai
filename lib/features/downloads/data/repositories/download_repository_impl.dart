import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/repositories/download_repository.dart';

class DownloadRepositoryImpl implements DownloadRepository {
  final SharedPreferences _prefs;
  final Dio _dio;

  static const String _storageKey = 'sync_pai_offline_downloads';

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final StreamController<DownloadTask> _updateController =
      StreamController<DownloadTask>.broadcast();

  DownloadRepositoryImpl(
    this._prefs, {
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _loadFromPreferences();
  }

  void _loadFromPreferences() {
    final raw = _prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          final task = DownloadTask.fromJson(item as Map<String, dynamic>);
          // Проверяем, существует ли физический файл на диске
          if (task.status == DownloadStatus.completed) {
            final file = File(task.localPath);
            if (file.existsSync()) {
              _tasks[task.id] = task;
            }
          } else {
            // Если загрузка была оборвана при выходе из приложения
            _tasks[task.id] = task.copyWith(status: DownloadStatus.failed);
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    final list = _tasks.values.map((t) => t.toJson()).toList();
    await _prefs.setString(_storageKey, jsonEncode(list));
  }

  @override
  Stream<DownloadTask> get taskUpdates => _updateController.stream;

  @override
  Future<List<DownloadTask>> getTasks() async {
    return _tasks.values.toList();
  }

  @override
  bool isDownloaded(int titleId, int episode) {
    final id = DownloadTask.generateId(titleId, episode);
    final task = _tasks[id];
    if (task == null || task.status != DownloadStatus.completed) {
      return false;
    }
    return File(task.localPath).existsSync();
  }

  @override
  DownloadTask? getTask(int titleId, int episode) {
    final id = DownloadTask.generateId(titleId, episode);
    return _tasks[id];
  }

  @override
  Future<void> startDownload(DownloadTask task) async {
    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    // Определяем локальный путь сохранения видео
    String finalPath = task.localPath;
    if (finalPath.isEmpty) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final downloadsDir = Directory('${appDir.path}/anime_downloads');
        if (!downloadsDir.existsSync()) {
          downloadsDir.createSync(recursive: true);
        }
        final cleanQuality = task.quality.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
        finalPath = '${downloadsDir.path}/title_${task.titleId}_ep_${task.episode}_$cleanQuality.mp4';
      } catch (_) {
        finalPath = 'download_${task.id}.mp4';
      }
    }

    var currentTask = task.copyWith(
      localPath: finalPath,
      status: DownloadStatus.downloading,
      progress: 0.01,
      errorMessage: null,
    );
    _tasks[task.id] = currentTask;
    _updateController.add(currentTask);
    await _persist();

    try {
      int lastReportedProgress = 0;

      await _dio.download(
        task.sourceUrl,
        finalPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final percent = (progress * 100).toInt();
            if (percent > lastReportedProgress) {
              lastReportedProgress = percent;
              currentTask = currentTask.copyWith(
                progress: progress,
                downloadedBytes: received,
                totalBytes: total,
              );
              _tasks[task.id] = currentTask;
              _updateController.add(currentTask);
            }
          }
        },
      );

      // Загрузка завершена успешно
      currentTask = currentTask.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
      );
      _tasks[task.id] = currentTask;
      _updateController.add(currentTask);
      await _persist();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        currentTask = currentTask.copyWith(
          status: DownloadStatus.idle,
          progress: 0.0,
        );
      } else {
        currentTask = currentTask.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.message ?? 'Ошибка загрузки',
        );
      }
      _tasks[task.id] = currentTask;
      _updateController.add(currentTask);
      await _persist();
    } catch (e) {
      currentTask = currentTask.copyWith(
        status: DownloadStatus.failed,
        errorMessage: e.toString(),
      );
      _tasks[task.id] = currentTask;
      _updateController.add(currentTask);
      await _persist();
    } finally {
      _cancelTokens.remove(task.id);
    }
  }

  @override
  Future<void> cancelDownload(String taskId) async {
    final token = _cancelTokens[taskId];
    token?.cancel('Отменено пользователем');
    _cancelTokens.remove(taskId);

    final task = _tasks[taskId];
    if (task != null) {
      final updated = task.copyWith(
        status: DownloadStatus.idle,
        progress: 0.0,
      );
      _tasks[taskId] = updated;
      _updateController.add(updated);
      await _persist();
    }
  }

  @override
  Future<void> deleteTask(String taskId) async {
    cancelDownload(taskId);
    final task = _tasks[taskId];
    if (task != null) {
      try {
        final file = File(task.localPath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
      _tasks.remove(taskId);
      final cleared = task.copyWith(
        status: DownloadStatus.idle,
        progress: 0.0,
      );
      _updateController.add(cleared);
      await _persist();
    }
  }

  @override
  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();
    _updateController.close();
  }
}

