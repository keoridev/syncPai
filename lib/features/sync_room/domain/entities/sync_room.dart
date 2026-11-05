import 'package:equatable/equatable.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';

enum SyncRoomStatus {
  waiting,
  connected,
  closed,
}

/// Комната совместного просмотра SyncPai.
class SyncRoom extends Equatable {
  final String code;
  final AnimeTitle title;
  final EpisodeItem episode;
  final PlayerQuality quality;
  final String hostName;
  final String? peerName;
  final SyncRoomStatus status;
  final DateTime createdAt;

  const SyncRoom({
    required this.code,
    required this.title,
    required this.episode,
    this.quality = PlayerQuality.hd,
    this.hostName = 'Хост',
    this.peerName,
    this.status = SyncRoomStatus.waiting,
    required this.createdAt,
  });

  /// Универсальная ссылка быстрого подключения: https://syncpai.app/room/SP4821
  String get shareUrl => 'https://syncpai.app/room/${code.replaceAll(RegExp(r'[^A-Z0-9]'), '')}';

  /// Кастомная URI-схема для мобильных ОС: syncpai://room/SP4821
  String get deepLinkSchemeUrl => 'syncpai://room/${code.replaceAll(RegExp(r'[^A-Z0-9]'), '')}';

  SyncRoom copyWith({
    String? code,
    AnimeTitle? title,
    EpisodeItem? episode,
    PlayerQuality? quality,
    String? hostName,
    String? peerName,
    SyncRoomStatus? status,
    DateTime? createdAt,
  }) {
    return SyncRoom(
      code: code ?? this.code,
      title: title ?? this.title,
      episode: episode ?? this.episode,
      quality: quality ?? this.quality,
      hostName: hostName ?? this.hostName,
      peerName: peerName ?? this.peerName,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        code,
        title,
        episode,
        quality,
        hostName,
        peerName,
        status,
        createdAt,
      ];
}

