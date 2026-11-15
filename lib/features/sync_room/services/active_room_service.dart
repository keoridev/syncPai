import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../../app/di/injection.dart';
import '../../catalog/domain/entities/anime_title.dart';
import '../../catalog/domain/entities/episode_item.dart';
import '../data/repositories/sync_room_repository_impl.dart';
import '../domain/entities/sync_event.dart';
import '../domain/entities/sync_protocol.dart';
import '../domain/entities/sync_room.dart';
import '../domain/repositories/sync_room_repository.dart';

/// Глобальный реактивный менеджер активной комнаты совместного просмотра.
/// Позволяет сворачивать комнату в плавающий мини-док (PiP / Lobby Dock)
/// во время ожидания друзей или поиска другого аниме в каталоге,
/// не разрывая соединение Supabase Realtime и не пересоздавая плеер.
class ActiveRoomService extends ChangeNotifier {
  static final ActiveRoomService instance = ActiveRoomService._();

  ActiveRoomService._();

  @override
  void notifyListeners() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks ||
        binding.schedulerPhase == SchedulerPhase.midFrameMicrotasks) {
      binding.addPostFrameCallback((_) {
        if (hasListeners) {
          super.notifyListeners();
        }
      });
      return;
    }
    super.notifyListeners();
  }

  SyncRoomRepository? _customRepository;
  SyncRoom? _activeRoom;
  bool _isHost = true;
  bool _isMinimized = false;
  bool _isInPlayer = false;
  int _maxPeers = 5;
  List<PeerPresence> _participants = const [];
  String? _friendJoinedBannerText;
  String? _lastJoinedPeerName;
  bool _pulseParticipantBadge = false;

  void Function(SyncRoom room, bool isHost)? _onExpandRoomCallback;
  Future<void> Function(AnimeTitle title, {EpisodeItem? episode})? _onSwitchAnimeCallback;

  StreamSubscription<List<PeerPresence>>? _presenceSub;
  StreamSubscription<SyncEvent>? _eventSub;
  Timer? _bannerAutoHideTimer;
  Timer? _pulseResetTimer;

  SyncRoom? get activeRoom => _activeRoom;
  bool get hasActiveRoom => _activeRoom != null;
  bool get isHost => _isHost;
  bool get isMinimized => _isMinimized;
  bool get isInPlayer => _isInPlayer;
  int get maxPeers => _maxPeers;
  List<PeerPresence> get participants => _participants;
  String? get friendJoinedBannerText => _friendJoinedBannerText;
  String? get lastJoinedPeerName => _lastJoinedPeerName;
  bool get pulseParticipantBadge => _pulseParticipantBadge;

  int get participantCount {
    if (_participants.isNotEmpty) {
      return _participants.length;
    }
    if (_activeRoom != null &&
        _activeRoom!.peerName != null &&
        _activeRoom!.peerName!.trim().isNotEmpty) {
      return 2;
    }
    return _activeRoom != null ? 1 : 0;
  }

  /// Форматированный код комнаты вида `SP-XXXXXX`
  String get formattedRoomCode {
    final raw = _activeRoom?.code ?? '';
    if (raw.isEmpty) return '';
    final pin = SyncRoomRepositoryImpl.extractPinCode(raw);
    return 'SP-$pin';
  }

  SyncRoomRepository? get _repository {
    if (_customRepository != null) return _customRepository;
    if (getIt.isRegistered<SyncRoomRepository>()) {
      return getIt<SyncRoomRepository>();
    }
    return null;
  }

  @visibleForTesting
  void setRepositoryForTesting(SyncRoomRepository? repo) {
    _customRepository = repo;
  }

  /// Регистрация или обновление активной комнаты
  void registerActiveRoom({
    required SyncRoom room,
    required bool isHost,
    bool isInPlayer = false,
    int maxPeers = 5,
    List<PeerPresence>? initialParticipants,
    void Function(SyncRoom room, bool isHost)? onExpandRoom,
    Future<void> Function(AnimeTitle title, {EpisodeItem? episode})? onSwitchAnime,
  }) {
    final prevCode = _activeRoom?.code;
    _activeRoom = room;
    _isHost = isHost;
    _isInPlayer = isInPlayer;
    _maxPeers = maxPeers;

    if (onExpandRoom != null) {
      _onExpandRoomCallback = onExpandRoom;
    }
    if (onSwitchAnime != null) {
      _onSwitchAnimeCallback = onSwitchAnime;
    }
    if (initialParticipants != null && initialParticipants.isNotEmpty) {
      _participants = List<PeerPresence>.from(initialParticipants);
    } else if (_participants.isEmpty) {
      _participants = [
        PeerPresence(
          userId: 'host_${room.code}',
          name: room.hostName,
          avatar: '👑',
          status: PresenceStatus.online,
          lastSeen: DateTime.now(),
          isHost: true,
        ),
        if (room.peerName != null && room.peerName!.isNotEmpty)
          PeerPresence(
            userId: 'peer_${room.code}',
            name: room.peerName!,
            avatar: '🐱',
            status: PresenceStatus.online,
            lastSeen: DateTime.now(),
            isHost: false,
          ),
      ];
    }

    if (prevCode != room.code) {
      _subscribeToRoomStreams(room.code);
    }

    notifyListeners();
  }

  void _subscribeToRoomStreams(String roomCode) {
    _presenceSub?.cancel();
    _eventSub?.cancel();

    final repo = _repository;
    if (repo == null) return;

    _presenceSub = repo.subscribeToPresence(roomCode).listen((presences) {
      if (_activeRoom == null) return;
      final prevCount = participantCount;
      _participants = List<PeerPresence>.from(presences);

      final guest = presences.where((p) => !p.isHost).firstOrNull;
      if (guest != null && _activeRoom!.peerName != guest.name) {
        _activeRoom = _activeRoom!.copyWith(
          peerName: guest.name,
          status: SyncRoomStatus.connected,
        );
      }

      if (participantCount > prevCount) {
        _onPeerJoinedNotification(guest?.name ?? 'Друг');
      }
      notifyListeners();
    });

    _eventSub = repo.subscribeToRoom(roomCode).listen((event) {
      if (_activeRoom == null) return;

      if (event.type == SyncEventType.peerJoined) {
        _activeRoom = _activeRoom!.copyWith(
          peerName: event.senderName,
          status: SyncRoomStatus.connected,
        );
        final hasGuestInList = _participants.any((p) => !p.isHost && p.name == event.senderName);
        if (!hasGuestInList) {
          _participants = [
            ..._participants,
            PeerPresence(
              userId: 'peer_${event.senderName}',
              name: event.senderName,
              avatar: '🐱',
              status: PresenceStatus.online,
              lastSeen: DateTime.now(),
              isHost: false,
            ),
          ];
        }
        _onPeerJoinedNotification(event.senderName);
        notifyListeners();
      } else if (event.type == SyncEventType.animeChanged && event.newTitle != null) {
        final ep = event.newEpisode ??
            (event.newTitle!.episodes.isNotEmpty
                ? event.newTitle!.episodes.first
                : const EpisodeItem(episode: 1, name: 'Серия 1'));
        _activeRoom = _activeRoom!.copyWith(
          title: event.newTitle,
          episode: ep,
        );
        notifyListeners();
      }
    });
  }

  void _onPeerJoinedNotification(String peerName) {
    _lastJoinedPeerName = peerName;
    _pulseParticipantBadge = true;
    _pulseResetTimer?.cancel();
    _pulseResetTimer = Timer(const Duration(seconds: 6), () {
      _pulseParticipantBadge = false;
      notifyListeners();
    });

    if (_isMinimized && _activeRoom != null) {
      _friendJoinedBannerText =
          'Друг зашёл в комнату $formattedRoomCode! Нажми, чтобы вернуться.';
      _bannerAutoHideTimer?.cancel();
      _bannerAutoHideTimer = Timer(const Duration(seconds: 8), () {
        if (_friendJoinedBannerText != null) {
          _friendJoinedBannerText = null;
          notifyListeners();
        }
      });
    }
  }

  /// Свернуть активную комнату в плавающий мини-док
  void minimizeRoom({
    SyncRoom? room,
    bool? isHost,
    bool? isInPlayer,
    List<PeerPresence>? participants,
    void Function(SyncRoom room, bool isHost)? onExpandRoom,
    Future<void> Function(AnimeTitle title, {EpisodeItem? episode})? onSwitchAnime,
  }) {
    if (room != null) {
      registerActiveRoom(
        room: room,
        isHost: isHost ?? _isHost,
        isInPlayer: isInPlayer ?? _isInPlayer,
        initialParticipants: participants,
        onExpandRoom: onExpandRoom,
        onSwitchAnime: onSwitchAnime,
      );
    } else {
      if (isHost != null) _isHost = isHost;
      if (isInPlayer != null) _isInPlayer = isInPlayer;
      if (participants != null && participants.isNotEmpty) {
        _participants = List<PeerPresence>.from(participants);
      }
      if (onExpandRoom != null) _onExpandRoomCallback = onExpandRoom;
      if (onSwitchAnime != null) _onSwitchAnimeCallback = onSwitchAnime;
    }

    _isMinimized = true;
    notifyListeners();
  }

  /// Развернуть свернутую комнату обратно в полный экран / модальное окно
  void expandRoom() {
    _isMinimized = false;
    _friendJoinedBannerText = null;
    _pulseParticipantBadge = false;
    _bannerAutoHideTimer?.cancel();
    _pulseResetTimer?.cancel();
    notifyListeners();

    final room = _activeRoom;
    final callback = _onExpandRoomCallback;
    if (room != null && callback != null) {
      callback(room, _isHost);
    }
  }

  void dismissFriendJoinedBanner() {
    if (_friendJoinedBannerText != null) {
      _friendJoinedBannerText = null;
      _bannerAutoHideTimer?.cancel();
      notifyListeners();
    }
  }

  /// Сменить аниме внутри активной комнаты (без пересоздания комнаты и без кика друзей)
  Future<void> switchAnimeInActiveRoom(
    AnimeTitle newTitle, {
    EpisodeItem? episode,
  }) async {
    if (_activeRoom == null) return;

    final targetEp = episode ??
        (newTitle.episodes.isNotEmpty
            ? newTitle.episodes.first
            : const EpisodeItem(episode: 1, name: 'Серия 1'));

    _activeRoom = _activeRoom!.copyWith(
      title: newTitle,
      episode: targetEp,
    );
    notifyListeners();

    if (_onSwitchAnimeCallback != null) {
      await _onSwitchAnimeCallback!(newTitle, episode: targetEp);
    } else {
      final repo = _repository;
      if (repo != null) {
        await repo.changeRoomAnime(
          roomCode: _activeRoom!.code,
          title: newTitle,
          episode: targetEp,
          sender: _isHost ? _activeRoom!.hostName : (_activeRoom!.peerName ?? 'Участник'),
        );
      }
    }
  }

  /// Симуляция входа друга (для тестирования уведомления Pai-chan в свернутом режиме)
  void simulateFriendJoin({String peerName = 'Ren'}) {
    if (_activeRoom == null) return;
    _activeRoom = _activeRoom!.copyWith(
      peerName: peerName,
      status: SyncRoomStatus.connected,
    );
    _participants = [
      ..._participants.where((p) => p.isHost),
      PeerPresence(
        userId: 'peer_$peerName',
        name: peerName,
        avatar: '🐱',
        status: PresenceStatus.online,
        lastSeen: DateTime.now(),
        isHost: false,
      ),
    ];
    _onPeerJoinedNotification(peerName);
    notifyListeners();

    final repo = _repository;
    if (repo != null) {
      repo.simulatePeerJoin(_activeRoom!.code, peerName: peerName);
    }
  }

  /// Полный выход из активной комнаты
  Future<void> leaveActiveRoom() async {
    final code = _activeRoom?.code;
    await _presenceSub?.cancel();
    await _eventSub?.cancel();
    _presenceSub = null;
    _eventSub = null;
    _bannerAutoHideTimer?.cancel();
    _pulseResetTimer?.cancel();

    _activeRoom = null;
    _isMinimized = false;
    _isInPlayer = false;
    _participants = const [];
    _friendJoinedBannerText = null;
    _lastJoinedPeerName = null;
    _pulseParticipantBadge = false;
    _onExpandRoomCallback = null;
    _onSwitchAnimeCallback = null;
    notifyListeners();

    if (code != null) {
      try {
        await _repository?.leaveRoom(code);
      } catch (_) {}
    }
  }
}

