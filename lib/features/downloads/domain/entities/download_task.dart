import 'package:equatable/equatable.dart';

enum DownloadStatus {
  idle,
  queued,
  downloading,
  completed,
  failed,
  paused,
}

class DownloadTask extends Equatable {
  final String id;
  final int titleId;
  final String titleName;
  final String posterUrl;
  final int episode;
  final String episodeName;
  final String quality;
  final String sourceUrl;
  final String localPath;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final DownloadStatus status;
  final String? errorMessage;
  final DateTime createdAt;

  const DownloadTask({
    required this.id,
    required this.titleId,
    required this.titleName,
    required this.posterUrl,
    required this.episode,
    required this.episodeName,
    required this.quality,
    required this.sourceUrl,
    required this.localPath,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.status = DownloadStatus.idle,
    this.errorMessage,
    required this.createdAt,
  });

  static String generateId(int titleId, int episode) => '${titleId}_$episode';

  DownloadTask copyWith({
    String? id,
    int? titleId,
    String? titleName,
    String? posterUrl,
    int? episode,
    String? episodeName,
    String? quality,
    String? sourceUrl,
    String? localPath,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    DownloadStatus? status,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      titleId: titleId ?? this.titleId,
      titleName: titleName ?? this.titleName,
      posterUrl: posterUrl ?? this.posterUrl,
      episode: episode ?? this.episode,
      episodeName: episodeName ?? this.episodeName,
      quality: quality ?? this.quality,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      localPath: localPath ?? this.localPath,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      errorMessage: errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title_id': titleId,
      'title_name': titleName,
      'poster_url': posterUrl,
      'episode': episode,
      'episode_name': episodeName,
      'quality': quality,
      'source_url': sourceUrl,
      'local_path': localPath,
      'progress': progress,
      'downloaded_bytes': downloadedBytes,
      'total_bytes': totalBytes,
      'status': status.name,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String? ?? generateId(json['title_id'] as int? ?? 0, json['episode'] as int? ?? 1),
      titleId: json['title_id'] as int? ?? 0,
      titleName: json['title_name'] as String? ?? '',
      posterUrl: json['poster_url'] as String? ?? '',
      episode: json['episode'] as int? ?? 1,
      episodeName: json['episode_name'] as String? ?? '',
      quality: json['quality'] as String? ?? '1080p',
      sourceUrl: json['source_url'] as String? ?? '',
      localPath: json['local_path'] as String? ?? '',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      downloadedBytes: json['downloaded_bytes'] as int? ?? 0,
      totalBytes: json['total_bytes'] as int? ?? 0,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.idle,
      ),
      errorMessage: json['error_message'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String get formattedSize {
    if (totalBytes <= 0) return '';
    final mb = totalBytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} ГБ';
    }
    return '${mb.toStringAsFixed(0)} МБ';
  }

  @override
  List<Object?> get props => [
        id,
        titleId,
        episode,
        quality,
        progress,
        status,
        downloadedBytes,
        totalBytes,
        localPath,
      ];
}

