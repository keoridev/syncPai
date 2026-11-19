import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/services/discord_rpc_service.dart';
import 'package:sync_pai/core/services/presence_service.dart';
import 'package:sync_pai/features/profile/domain/services/achievement_service.dart';
import 'package:sync_pai/core/widgets/sync_badge.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/domain/entities/translation_entity.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/catalog/domain/usecases/get_player_links_usecase.dart';
import 'package:sync_pai/features/downloads/domain/repositories/download_repository.dart';
import 'package:sync_pai/features/downloads/presentation/cubit/download_cubit.dart';
import 'package:sync_pai/features/kodik/domain/entities/kodik_translation.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_cubit.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/player/domain/entities/reaction_heatmap.dart';
import 'package:sync_pai/features/player/presentation/widgets/danmaku_overlay_layer.dart';
import 'package:sync_pai/features/player/services/episode_prefetch_service.dart';
import 'package:sync_pai/features/profile/presentation/cubit/profile_cubit.dart';
import 'package:sync_pai/features/profile/presentation/cubit/profile_state.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';
import 'package:sync_pai/features/sync_room/domain/repositories/sync_room_repository.dart';
import 'package:sync_pai/features/watch_history/presentation/cubit/watch_history_cubit.dart';
import 'package:sync_pai/features/anime_lists/presentation/cubit/anime_list_cubit.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_room.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'player_state.dart';

class PlayerCubit extends Cubit<PlayerState> {
  static const Map<String, String> defaultStreamingHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://anilibria.top/',
    'Origin': 'https://anilibria.top',
    'Accept': '*/*',
    'Connection': 'keep-alive',
  };

  final Player player;
  final SyncRoomRepository? syncRepository;
  final List<StreamSubscription> _subscriptions = [];
  StreamSubscription<SyncPacket>? _packetSubscription;
  StreamSubscription<List<PeerPresence>>? _presenceSubscription;
  Timer? _controlsTimer;
  Timer? _heartbeatTimer;
  Timer? _countdownTimer;
  Timer? _quickPhraseTimer;
  Timer? _awayDurationTimer;
  Timer? _spoilerShieldTimer;
  Timer? _bufferingFallbackTimer;
  Timer? _driftRateTimer;
  final List<DateTime> _recentBufferEvents = [];
  Duration _lastEmittedPos = Duration.zero;
  final Random _random = Random();

  bool isAutoSkipOpening = false;
  final Duration? _initialPosition;
  Duration? _pendingInitialSeek;
  String? _loadedMediaKey;

  DateTime? _lastPosSavedAt;
  String? _prefetchedEpisodeKey;

  void _savePlaybackPosition(Duration pos, Duration dur) {
    if (pos.inSeconds < 2) return;

    if (getIt.isRegistered<SharedPreferences>()) {
      final prefs = getIt<SharedPreferences>();
      final key = '${state.title.id}_${state.episode.episode}';
      if (dur > Duration.zero && (dur - pos).inSeconds <= 30) {
        prefs.remove(key);
      } else {
        prefs.setInt(key, pos.inMilliseconds);
      }
      if (state.title.shikimoriId != null && state.title.shikimoriId! > 0) {
        final shikiKey = '${state.title.shikimoriId}_${state.episode.episode}';
        if (dur > Duration.zero && (dur - pos).inSeconds <= 30) {
          prefs.remove(shikiKey);
        } else {
          prefs.setInt(shikiKey, pos.inMilliseconds);
        }
      }
    }

    if (dur.inSeconds > 0 && getIt.isRegistered<WatchHistoryCubit>()) {
      try {
        final hist = getIt<WatchHistoryCubit>();
        hist.saveProgress(
          titleId: state.title.id,
          titleName: state.title.displayTitle,
          posterUrl: state.title.posterMedium.isNotEmpty
              ? state.title.posterMedium
              : state.title.posterSmall,
          episode: state.episode.episode,
          episodeName: state.episode.name,
          position: pos,
          duration: dur,
        );
      } catch (_) {}
    }
  }

  static Duration? loadSavedPosition(AnimeTitle title, int epNum) {
    // 1. SharedPreferences по title.id и shikimoriId
    if (getIt.isRegistered<SharedPreferences>()) {
      final prefs = getIt<SharedPreferences>();
      final key = '${title.id}_$epNum';
      final ms = prefs.getInt(key);
      if (ms != null && ms > 3000) {
        return Duration(milliseconds: ms);
      }
      if (title.shikimoriId != null && title.shikimoriId! > 0) {
        final shikiKey = '${title.shikimoriId}_$epNum';
        final shikiMs = prefs.getInt(shikiKey);
        if (shikiMs != null && shikiMs > 3000) {
          return Duration(milliseconds: shikiMs);
        }
      }
    }

    // 2. WatchHistoryCubit
    if (getIt.isRegistered<WatchHistoryCubit>()) {
      final histState = getIt<WatchHistoryCubit>().state;
      var hist = histState.getForTitle(title.id);
      if (hist == null && title.shikimoriId != null && title.shikimoriId! > 0) {
        hist = histState.getForTitle(title.shikimoriId!);
      }
      if (hist != null && hist.episode == epNum && hist.positionMs > 3000) {
        return Duration(milliseconds: hist.positionMs);
      }
    }

    // 3. AnimeListCubit
    if (getIt.isRegistered<AnimeListCubit>()) {
      final listState = getIt<AnimeListCubit>().state;
      var entry = listState.getEntryFor(title.id);
      if (entry == null && title.shikimoriId != null && title.shikimoriId! > 0) {
        entry = listState.getEntryFor(title.shikimoriId!);
      }
      if (entry != null && entry.lastEpisode == epNum && entry.positionMs > 3000) {
        return Duration(milliseconds: entry.positionMs);
      }
    }

    return null;
  }

  late final String currentUserId;

  String get currentUserName {
    try {
      if (getIt.isRegistered<ProfileCubit>()) {
        final pState = getIt<ProfileCubit>().state;
        if (pState.status == ProfileStatus.loaded && pState.profile.username.trim().isNotEmpty) {
          return pState.profile.username.trim();
        }
      }
    } catch (_) {}
    try {
      final metaName = Supabase.instance.client.auth.currentUser?.userMetadata?['username'] as String?;
      if (metaName != null && metaName.trim().isNotEmpty) {
        return metaName.trim();
      }
    } catch (_) {}
    return state.isHost ? 'Хост' : (state.peerName ?? 'Гость');
  }

  PlayerCubit({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality initialQuality = PlayerQuality.fhd,
    String? roomCode,
    bool isHost = true,
    this.syncRepository,
    Duration? initialPosition,
    Player? existingPlayer,
    String? userIdOverride,
  })  : player = existingPlayer ??
            Player(
              configuration: const PlayerConfiguration(
                bufferSize: 128 * 1024 * 1024, // 128 МБ для стабильного 1080p HLS
                osc: false,
                logLevel: MPVLogLevel.warn,
              ),
            ),
        // ignore: prefer_initializing_formals
        _initialPosition = initialPosition,
        _pendingInitialSeek = initialPosition ?? loadSavedPosition(title, episode.episode),
        super(PlayerState(
          title: title,
          episode: episode,
          selectedQuality: initialQuality,
          roomCode: roomCode,
          isHost: isHost,
          peerName: isHost ? 'Друг' : 'Хост',
          heatmap: ReactionHeatmap.initial(titleId: title.id, episode: episode.episode),
        )) {
    String? resolvedUid = userIdOverride;
    if (resolvedUid == null || resolvedUid.isEmpty) {
      try {
        resolvedUid = Supabase.instance.client.auth.currentUser?.id;
      } catch (_) {}
    }
    currentUserId = (resolvedUid != null && resolvedUid.isNotEmpty)
        ? resolvedUid
        : '${isHost ? "host" : "guest"}_${_random.nextInt(999999)}';
    unawaited(PresenceService.instance.setWatchingActivity(title.russianTitle, episode.episode));

    _initPlayer();
    if (state.isSyncRoom) {
      _initSyncGateway();
    }
  }

  void _initPlayer() {
    if (!kIsWeb) {
      try {
        WakelockPlus.enable();
      } catch (_) {}
    }

    // 1. Аппаратное декодирование (GPU) и расширенные сетевые флаги libmpv
    try {
      final dynamic platform = player.platform;
      final isWindows = !kIsWeb && Platform.isWindows;
      platform.setProperty('hwdec', isWindows ? 'd3d11va-copy' : 'auto-safe');
      platform.setProperty('cache', 'yes');
      platform.setProperty('demuxer-max-bytes', '134217728'); // 128 МБ
      platform.setProperty('demuxer-max-back-bytes', '33554432'); // 32 МБ назад
      platform.setProperty('demuxer-readahead-secs', '45'); // 45 секунд вперед
      platform.setProperty('network-timeout', '15');
      platform.setProperty('tls-verify', 'no');
      platform.setProperty('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
    } catch (_) {}

    // Слушатели медиаплеера libmpv
    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        if (isClosed || _isDisposing) return;
        emit(state.copyWith(isPlaying: playing));
        _updateDiscordPresence();
      }),
      player.stream.buffering.listen((buffering) {
        if (isClosed || _isDisposing) return;
        emit(state.copyWith(isBuffering: buffering));
        _handleBufferingWatchdog(buffering);
        // При изменении буферизации уведомляем комнату
        if (state.isSyncRoom) {
          syncRepository?.sendBufferState(
            roomCode: state.roomCode!,
            isBuffering: buffering,
            sender: state.isHost ? 'Хост' : (state.peerName ?? 'Гость'),
          );
        }
      }),
      player.stream.position.listen((pos) {
        if (isClosed || _isDisposing) return;
        _checkAutoNextEpisode(pos);
        _checkAutoSkipOpening(pos);
        _checkNextEpisodePrefetch(pos);
        final now = DateTime.now();
        if (_lastPosSavedAt == null || now.difference(_lastPosSavedAt!).inSeconds >= 3) {
          if (_lastPosSavedAt != null && state.isPlaying && !state.isBuffering) {
            final elapsed = now.difference(_lastPosSavedAt!).inSeconds.clamp(1, 10);
            unawaited(AchievementService.instance.addWatchSeconds(elapsed));
          }
          _lastPosSavedAt = now;
          _savePlaybackPosition(pos, state.duration);
        }
        // Достижения за просмотр (Первый шаг / Ночной дозор) — строго при просмотре >= 80% серии
        if (state.duration.inSeconds > 10 &&
            pos.inSeconds >= (state.duration.inSeconds * 0.8)) {
          final epKey = '${state.title.id}_${state.episode.episode}';
          if (_completed80Episodes.add(epKey)) {
            unawaited(
              AchievementService.instance.recordEpisodeWatched(
                isWatchTogether: state.isSyncRoom,
              ),
            );
          }
        }
        // Троттлинг: обновляем позицию в Bloc не чаще чем раз в 250 мс для защиты FPS
        if ((pos - _lastEmittedPos).abs() >= const Duration(milliseconds: 250)) {
          _lastEmittedPos = pos;
          emit(state.copyWith(position: pos));
        }
      }),
      player.stream.duration.listen((dur) {
        if (isClosed || _isDisposing) return;
        emit(state.copyWith(duration: dur));
        _updateDiscordPresence();
        if (dur > Duration.zero && _pendingInitialSeek != null && _pendingInitialSeek! > Duration.zero) {
          final seekTarget = _pendingInitialSeek!;
          _pendingInitialSeek = null;
          // восстанавливаем сохраненную позицию
          if (seekTarget.inSeconds >= 3 && (dur - seekTarget).inSeconds >= 3) {
            player.seek(seekTarget);
            Future.delayed(const Duration(milliseconds: 400), () {
              if (!isClosed && !_isDisposing && (player.state.position < const Duration(seconds: 2) && seekTarget > const Duration(seconds: 3))) {
                player.seek(seekTarget);
              }
            });
          }
        }
      }),
      player.stream.buffer.listen((buffer) {
        if (isClosed || _isDisposing) return;
        emit(state.copyWith(buffer: buffer));
      }),
      player.stream.rate.listen((rate) {
        if (isClosed || _isDisposing) return;
        emit(state.copyWith(playbackRate: rate));
      }),
      player.stream.completed.listen((completed) {
        if (isClosed || _isDisposing) return;
        if (completed) {
          emit(state.copyWith(isPlaying: false));
          playNextEpisode();
        }
      }),
      player.stream.error.listen((error) {
        if (isClosed || _isDisposing) return;
        if (error.isNotEmpty) {
          // Игнорируем нефатальные ошибки разрыва соединения и таймаута TCP-сокетов при паузе и чтении сегментов
          final lower = error.toLowerCase();
          final isTransientSocketError = lower.contains('ffurl_read_returned') ||
              lower.contains('failed reading') ||
              lower.contains('0xdfb9b0bb') ||
              lower.contains('end of file') ||
              lower.contains('connection reset') ||
              lower.contains('broken pipe') ||
              lower.contains('software caused connection abort') ||
              lower.contains('operation not permitted') ||
              lower.contains('timed out') ||
              lower.contains('timeout');

          if (isTransientSocketError) {
            return;
          }

          // Если видео уже воспроизводится, не блокируем плеер фоновыми ворнингами
          if (state.isPlaying) {
            return;
          }

          emit(state.copyWith(
            errorMessage: () => error,
            isPlaying: false,
            isBuffering: false,
          ));
        }
      }),
    ]);

    _loadCurrentEpisodeStream(initialPosition: _initialPosition);
    _startControlsTimer();
  }

  void _checkAutoSkipOpening(Duration pos) {
    final opening = state.effectiveOpening;
    if (isAutoSkipOpening && opening != null) {
      if (pos.inSeconds >= opening.start && pos.inSeconds < opening.start + 2) {
        seek(opening.stopDuration);
      }
    }
  }

  /// Включить / выключить умный авто-пропуск опенингов
  void toggleAutoSkipOpening() {
    isAutoSkipOpening = !isAutoSkipOpening;
    emit(state.copyWith());
  }

  void setVideoFit(BoxFit fit) {
    emit(state.copyWith(videoFit: fit));
  }

  /// Пропуск опенинга: по таймкодам или универсально на +90 сек
  void skipOpening() {
    if (state.isSyncRoom && !state.isHost) return;

    unawaited(AchievementService.instance.recordOpeningSkipped());
    final opening = state.effectiveOpening;
    if (opening != null) {
      seek(opening.stopDuration);
    } else {
      seekRelative(90);
    }
  }

  /// Автоматический контроль буферизации (Watchdog):
  /// Если буферизация на 1080p длится > 4 сек или возникает чаще 3 раз за 15 сек — авто-фолбэк на 720p
  void _handleBufferingWatchdog(bool isBuffering) {
    if (!isBuffering) {
      _bufferingFallbackTimer?.cancel();
      _bufferingFallbackTimer = null;
      return;
    }

    if (!state.isPlaying || state.selectedQuality != PlayerQuality.fhd) return;

    final now = DateTime.now();
    _recentBufferEvents.add(now);
    _recentBufferEvents.removeWhere((t) => now.difference(t).inSeconds > 15);

    // Условие 1: если более 3 раз за 15 секунд сработала буферизация на 1080p
    if (_recentBufferEvents.length >= 3) {
      _recentBufferEvents.clear();
      _fallbackQualityToHd('Частая буферизация');
      return;
    }

    // Условие 2: буферизация длится дольше 4 секунд
    _bufferingFallbackTimer?.cancel();
    _bufferingFallbackTimer = Timer(const Duration(seconds: 4), () {
      if (!isClosed && !_isDisposing && state.isBuffering && state.isPlaying && state.selectedQuality == PlayerQuality.fhd) {
        _fallbackQualityToHd('Низкая скорость сети');
      }
    });
  }

  Future<void> _fallbackQualityToHd(String reason) async {
    final ep = state.episode;
    final hasHd = (ep.hdUrl != null && ep.hdUrl!.isNotEmpty) ||
        (state.title.episodes.isNotEmpty &&
            state.title.episodes
                .firstWhere((e) => e.episode == ep.episode, orElse: () => ep)
                .hdUrl !=
                null);

    if (hasHd && state.selectedQuality != PlayerQuality.hd) {
      final currentPos = state.position;
      emit(state.copyWith(
        selectedQuality: PlayerQuality.hd,
        bufferNotice: () => 'Качество автоматически переключено на 720p ($reason)',
      ));
      await _loadCurrentEpisodeStream(initialPosition: currentPos);
    }
  }

  void _initSyncGateway() {
    final code = state.roomCode;
    if (code == null || syncRepository == null) return;

    // 1. Подписка на поток сетевых пакетов комнаты (Supabase Broadcast / WS)
    _packetSubscription = syncRepository!.subscribeToPackets(code).listen(
      _handleIncomingPacket,
      onError: (_) {},
    );

    // 1.1. История чата комнаты из public.room_messages (для опоздавших участников)
    _loadChatHistory(code);

    // 1.2. Бесшовное восстановление сохраненного таймкода комнаты (24h Rejoin)
    syncRepository!.getRoomData(code).then((roomData) {
      if (!isClosed && roomData != null) {
        final posMs = (roomData['current_position_ms'] as num?)?.toInt() ??
            (((roomData['current_time_sec'] as num?)?.toDouble() ?? 0.0) * 1000).toInt();
        if (posMs > 1000 && state.position.inMilliseconds < 1000) {
          player.seek(Duration(milliseconds: posMs));
        }
      }
    }).catchError((_) {});

    // 2. Регистрация собственного присутствия (Presence)
    final myPresence = PeerPresence(
      userId: state.isHost ? 'host' : 'guest',
      name: state.isHost ? 'Хост' : (state.peerName ?? 'Гость'),
      avatar: state.isHost ? '👑' : '🐱',
      status: PresenceStatus.online,
      lastSeen: DateTime.now(),
      isHost: state.isHost,
    );
    syncRepository!.updatePresence(roomCode: code, presence: myPresence);

    // 3. Подписка на онлайн-радар присутствия (Presence)
    _presenceSubscription = syncRepository!.subscribeToPresence(code).listen(
      (presences) {
        final peer = presences.firstWhere(
          (p) => p.isHost != state.isHost,
          orElse: () => PeerPresence(
            userId: 'peer',
            name: state.peerName ?? 'Друг',
            avatar: '🐱',
            status: PresenceStatus.online,
            lastSeen: DateTime.now(),
          ),
        );
        _handlePeerPresence(peer);
      },
      onError: (_) {},
    );

    // 4. Если Я ХОСТ: запускаем периодический HEARTBEAT каждые 2.5 сек
    if (state.isHost) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        if (!isClosed && state.isSyncRoom) {
          syncRepository!.sendHeartbeat(
            roomCode: code,
            positionMs: state.position.inMilliseconds,
            isPlaying: state.isPlaying,
            rate: state.playbackRate,
            sender: 'Хост',
          );
        }
      });
    }
  }

  void _handlePeerPresence(PeerPresence peer) {
    if (isClosed) return;

    final wasAway = state.isPeerAway;
    final isAwayNow = peer.status == PresenceStatus.away;
    final friendName = peer.name.isNotEmpty ? peer.name : (state.peerName ?? 'Друг');

    // Таймер подсчета секунд АФК для анти-АФК кнопки «Кинуть тапок» (> 30 сек)
    if (isAwayNow && !wasAway) {
      _awayDurationTimer?.cancel();
      _awayDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!isClosed && state.isPeerAway) {
          emit(state.copyWith(awaySecondsCount: state.awaySecondsCount + 1));
        }
      });
    } else if (!isAwayNow) {
      _awayDurationTimer?.cancel();
      _awayDurationTimer = null;
    }

    emit(state.copyWith(
      peerPresence: () => peer,
      isPeerAway: isAwayNow,
      awaySecondsCount: isAwayNow ? state.awaySecondsCount : 0,
      bufferNotice: isAwayNow
          ? () => '$friendName ждет вас. Плеер приостановлен'
          : () => (wasAway ? null : state.bufferNotice),
      syncStatus: isAwayNow
          ? SyncStatus.buffering
          : (peer.status == PresenceStatus.online ? SyncStatus.active : SyncStatus.disconnected),
    ));

    // Если друг отошел — плавно ставим на паузу
    if (isAwayNow && state.isPlaying) {
      player.pause();
      if (state.isHost) {
        _broadcastControlAction('pause');
      }
    }
  }

  void _handleIncomingPacket(SyncPacket packet) {
    if (isClosed) return;

    final updatedBy = packet.payload['updated_by'] as String? ??
        packet.payload['sender_id'] as String?;
    final myName = currentUserName;
    final isFromSelf = (updatedBy != null && updatedBy == currentUserId) ||
        packet.sender == 'Self' ||
        packet.sender == myName;

    // Измерение пинга между участниками комнаты
    final ping = (DateTime.now().millisecondsSinceEpoch - packet.timestampMs).abs().clamp(12, 380);
    if (!isFromSelf && (state.peerPingMs - ping).abs() > 4) {
      emit(state.copyWith(peerPingMs: ping));
    }

    switch (packet.action) {
      // HEARTBEAT от хоста (обработка ведомым клиентом с Drift Compensation)
      case SyncActionTypes.heartbeat:
        if (!state.isHost && !isFromSelf) {
          final hostPos = (packet.payload['position_ms'] as num?)?.toInt() ?? 0;
          final hostPlaying = packet.payload['is_playing'] as bool? ?? false;
          final hostRate = (packet.payload['playback_rate'] as num?)?.toDouble() ??
              (packet.payload['rate'] as num?)?.toDouble();
          final now = DateTime.now().millisecondsSinceEpoch;
          final latency = (now - packet.timestampMs).clamp(0, 800);
          final estimatedHostPos = hostPos + (hostPlaying ? latency : 0);
          final currentPos = state.position.inMilliseconds;
          final delta = estimatedHostPos - currentPos;

          // Воспроизведение / Пауза
          if (hostPlaying && !state.isPlaying && !state.isBuffering && !state.isPeerAway) {
            player.play();
          } else if (!hostPlaying && state.isPlaying) {
            player.pause();
          }

          if (hostRate != null && hostRate >= 1.25) {
            if ((state.playbackRate - hostRate).abs() > 0.05) {
              player.setRate(hostRate);
              emit(state.copyWith(
                playbackRate: hostRate,
                is2xFastForwarding: hostRate >= 1.9,
              ));
            }
            break;
          }

          // Интеллектуальное сглаживание рассинхрона (Drift Compensation):
          // При расхождении < 1.5 сек НЕ вызываем seek во избежание сброса декодера и буфера
          if (delta.abs() < 1500) {
            if (delta.abs() < 300) {
              if (state.playbackRate != 1.0 && !state.is2xFastForwarding) {
                player.setRate(1.0);
              }
              emit(state.copyWith(syncStatus: SyncStatus.active));
            } else {
              // Разница 300–1500 мс: плавная временная подстройка скорости (1.05x / 0.95x) на 2 секунды
              final newRate = delta > 0 ? 1.05 : 0.95;
              if (state.playbackRate != newRate && !state.is2xFastForwarding) {
                player.setRate(newRate);
                _driftRateTimer?.cancel();
                _driftRateTimer = Timer(const Duration(seconds: 2), () {
                  if (!isClosed && !_isDisposing && state.playbackRate != 1.0 && !state.is2xFastForwarding) {
                    player.setRate(1.0);
                  }
                });
              }
              emit(state.copyWith(syncStatus: SyncStatus.aligning));
            }
          } else if (delta.abs() >= 1500) {
            // Разница >= 1.5 сек: вызываем синхронный seek
            if (delta > 15000) {
              _activateSpoilerShield();
            }
            player.seek(Duration(milliseconds: estimatedHostPos));
            if (state.playbackRate != 1.0 && !state.is2xFastForwarding) {
              player.setRate(1.0);
            }
            emit(state.copyWith(syncStatus: SyncStatus.active));
          }
        }
        break;

      // Двусторонняя синхронизация (Play, Pause, Seek > 1.5s, Episode, 2x Speed) между ПК и телефоном
      case SyncActionTypes.controlAction:
        if (!isFromSelf) {
          final remoteEp = (packet.payload['episode_index'] as num?)?.toInt() ??
              (packet.payload['episode'] as num?)?.toInt();
          if (remoteEp != null && remoteEp > 0 && remoteEp != state.episode.episode) {
            final nextEp = state.title.episodes.firstWhere(
              (e) => e.episode == remoteEp,
              orElse: () => state.episode,
            );
            if (nextEp.episode != state.episode.episode) {
              cancelAutoNextCountdown();
              _switchEpisodeInternal(nextEp);
            }
          }

          final remoteRate = (packet.payload['playback_rate'] as num?)?.toDouble();
          if (remoteRate != null && (state.playbackRate - remoteRate).abs() > 0.05) {
            player.setRate(remoteRate);
            emit(state.copyWith(
              playbackRate: remoteRate,
              is2xFastForwarding: remoteRate >= 1.9,
            ));
          }

          final act = packet.payload['control_action'] as String? ?? packet.payload['action'] as String?;
          final posMs = (packet.payload['position_ms'] as num?)?.toInt();
          final isPlayingVal = packet.payload['is_playing'] as bool?;
          final timeVal = packet.payload['current_time_sec'] ?? packet.payload['time'];
          final timeMs = timeVal is num ? (timeVal * 1000).toInt() : null;
          final effectivePosMs = posMs ?? timeMs;

          if (act == 'rate') {
            break;
          }

          if (act == 'play' || (act == null && isPlayingVal == true)) {
            if (effectivePosMs != null && (effectivePosMs - state.position.inMilliseconds).abs() >= 1500) {
              player.seek(Duration(milliseconds: effectivePosMs));
            }
            if (!state.isPlaying && packet.sender != 'Self') {
              _addSystemChatMessage('${packet.sender} продолжил просмотр');
            }
            player.play();
          } else if (act == 'pause' || (act == null && isPlayingVal == false)) {
            if (effectivePosMs != null && (effectivePosMs - state.position.inMilliseconds).abs() >= 1500) {
              player.seek(Duration(milliseconds: effectivePosMs));
            }
            if (state.isPlaying && packet.sender != 'Self') {
              _addSystemChatMessage('${packet.sender} поставил на паузу');
            }
            player.pause();
          } else if (act == 'seek' && effectivePosMs != null) {
            final diff = (effectivePosMs - state.position.inMilliseconds).abs();
            if (diff >= 1500) {
              if (effectivePosMs - state.position.inMilliseconds > 15000) {
                _activateSpoilerShield();
              }
              player.seek(Duration(milliseconds: effectivePosMs));
            }
          } else if (effectivePosMs != null) {
            final diff = (effectivePosMs - state.position.inMilliseconds).abs();
            if (diff >= 1500) {
              player.seek(Duration(milliseconds: effectivePosMs));
            }
          }
        }
        break;

      // Буферизация одного из участников
      case SyncActionTypes.bufferWait:
        if (!isFromSelf) {
          final user = packet.payload['user_name'] as String? ?? 'Друг';
          player.pause();
          emit(state.copyWith(
            isPeerBuffering: true,
            bufferNotice: () => 'У $user слабый сигнал, ждем…',
            syncStatus: SyncStatus.buffering,
          ));
        }
        break;

      case SyncActionTypes.bufferReady:
        if (!isFromSelf) {
          emit(state.copyWith(
            isPeerBuffering: false,
            bufferNotice: () => null,
            syncStatus: SyncStatus.active,
          ));
          if (state.isHost && !state.isPeerAway) {
            player.play();
          }
        }
        break;

      // Летящая стикер-реакция Пай-чан (Floating Pai-chan Sticker Reaction)
      case SyncActionTypes.reaction:
      case SyncActionTypes.paiStickerReaction:
        final reactionId = packet.payload['id'] as String? ??
            '${DateTime.now().microsecondsSinceEpoch}';
        if (isFromSelf || state.activeReactions.any((r) => r.id == reactionId)) {
          break;
        }

        final rawSticker = packet.payload['sticker_id'] as String? ??
            packet.payload['emoji'] as String? ??
            'love';
        final sticker = PaiChanSticker.fromIdOrEmoji(rawSticker);
        final senderName = (packet.payload['sender_name'] as String?)?.trim().isNotEmpty == true
            ? (packet.payload['sender_name'] as String).trim()
            : packet.sender;

        final reaction = FloatingReaction(
          id: reactionId,
          emoji: sticker.fallbackEmoji,
          stickerId: sticker.id,
          sender: senderName,
          senderId: updatedBy,
          startXOffset: 0.18 + (_random.nextDouble() * 0.64),
          timestamp: DateTime.now(),
        );

        final current = List<FloatingReaction>.from(state.activeReactions)..add(reaction);
        emit(state.copyWith(activeReactions: current));

        // Обновляем тепловую карту таймлайна реакцией от друга
        if (state.heatmap != null && state.duration.inSeconds > 0) {
          final updatedHeatmap = state.heatmap!.addReaction(
            timestampSec: state.position.inSeconds.toDouble(),
            totalDurationSec: state.duration.inSeconds.toDouble(),
            emoji: sticker.fallbackEmoji,
            sender: senderName,
          );
          emit(state.copyWith(heatmap: () => updatedHeatmap));
        }

        // Удаление стикера Пай-чан после завершения анимации (2.4 сек)
        Timer(const Duration(milliseconds: 2400), () {
          if (!isClosed) {
            final filtered = List<FloatingReaction>.from(state.activeReactions)
              ..removeWhere((r) => r.id == reactionId);
            emit(state.copyWith(activeReactions: filtered));
          }
        });
        break;

      // Сообщение в чат (Twitch overlay chat + чат сайдбара комнаты)
      case SyncActionTypes.chatMessage:
        final text = (packet.payload['text'] as String?) ??
            (packet.payload['content'] as String?) ??
            '';
        if (text.trim().isEmpty) break;
        final msgId = packet.payload['id'] as String? ??
            '${DateTime.now().microsecondsSinceEpoch}';
        final isHostMsg = packet.payload['is_host'] as bool? ?? false;
        final senderName = (packet.payload['sender_name'] as String?)?.trim().isNotEmpty == true
            ? (packet.payload['sender_name'] as String).trim()
            : packet.sender;

        final alreadyExists = state.chatMessages.any((m) => m.id == msgId);
        _pushChatMessage(ChatMessage(
          id: msgId,
          sender: senderName,
          text: text,
          isHost: isHostMsg,
          timestamp: DateTime.now(),
        ));
        if (!isFromSelf && !alreadyExists) {
          _addDanmaku(text, senderName);
        }
        break;

      // Запрос паузы от гостя
      case SyncActionTypes.requestPause:
        if (state.isHost) {
          player.pause();
          _broadcastControlAction('pause');
          emit(state.copyWith(
            errorMessage: () => 'Друг запросил паузу',
          ));
        }
        break;

      // Быстрая фраза (шорткат с авто-показом плашки на 3.5 секунды)
      case SyncActionTypes.quickPhrase:
        final toast = QuickPhraseToast.fromJson(packet.payload);
        emit(state.copyWith(activeQuickPhrase: () => toast));

        _quickPhraseTimer?.cancel();
        _quickPhraseTimer = Timer(const Duration(milliseconds: 3500), () {
          if (!isClosed) {
            emit(state.copyWith(activeQuickPhrase: () => null));
          }
        });

        // Если фраза с просьбой паузы:
        if (toast.phrase.toLowerCase().contains('останови') || toast.phrase.toLowerCase().contains('пауз')) {
          if (state.isHost) {
            player.pause();
            _broadcastControlAction('pause');
          }
        }
        break;

      // Авто-переход на следующую серию от хоста
      case SyncActionTypes.changeEpisode:
        final nextEpNum = packet.payload['episode'] as int?;
        if (nextEpNum != null) {
          final nextEp = state.title.episodes.firstWhere(
            (e) => e.episode == nextEpNum,
            orElse: () => state.episode,
          );
          cancelAutoNextCountdown();
          if (nextEp.episode != state.episode.episode) {
            _addSystemChatMessage('Серия переключена на ${nextEp.episode}');
          }
          _switchEpisodeInternal(nextEp);
        }
        break;

      // Хост закрыл комнату для всех
      case SyncActionTypes.roomClosed:
        _addSystemChatMessage('Хост закрыл комнату для всех');
        emit(state.copyWith(
          errorMessage: () => 'Хост закрыл комнату для всех',
        ));
        leaveRoom();
        break;

      // Обновление присутствия участника (Presence)
      case SyncActionTypes.presenceUpdate:
        final presence = PeerPresence.fromJson(packet.payload);
        if (presence.isHost != state.isHost) {
          _handlePeerPresence(presence);
        }
        break;

      // Голосовой статус участника (Audio Ducking)
      case SyncActionTypes.voiceTalking:
        final isTalking = packet.payload['is_talking'] as bool? ?? false;
        emit(state.copyWith(isPeerTalking: isTalking));
        _applyAudioDucking();
        break;

      // Анти-АФК «Кинуть тапок» (Poke Nudge)
      case SyncActionTypes.pokeNudge:
        if (!isFromSelf) {
          _handleIncomingPokeNudge(packet.sender);
        }
        break;

      // Кооперативный пропуск опенинга (Coop Skip Vote)
      case SyncActionTypes.coopSkipVote:
        final votes = packet.payload['votes'] as int? ?? 1;
        emit(state.copyWith(coopSkipVotes: votes));
        if (votes >= 2) {
          skipOpening();
        }
        break;

      // Смена аниме в активной комнате без пересоздания комнаты
      case SyncActionTypes.changeAnime:
        if (!isFromSelf) {
          final p = packet.payload;
          final animeId = (p['anime_id'] as num?)?.toInt() ??
              int.tryParse('${p['anime_id'] ?? 0}') ??
              0;
          final animeTitleStr = (p['anime_title'] as String?) ?? 'Аниме';
          final englishTitleStr = (p['english_title'] as String?) ?? animeTitleStr;
          final codeStr = (p['code'] as String?) ?? 'sync_anime_$animeId';
          final posterUrl = (p['poster_url'] as String?) ?? '';
          final epNum = (p['episode'] as num?)?.toInt() ?? 1;
          final epName = p['episode_name'] as String?;
          final fhdUrl = p['fhd_url'] as String?;
          final hdUrl = p['hd_url'] as String?;
          final sdUrl = p['sd_url'] as String?;

          final newEpisode = EpisodeItem(
            episode: epNum,
            name: epName ?? 'Серия $epNum',
            fhdUrl: fhdUrl,
            hdUrl: hdUrl,
            sdUrl: sdUrl,
          );

          final newTitle = AnimeTitle(
            id: animeId,
            code: codeStr,
            russianTitle: animeTitleStr,
            englishTitle: englishTitleStr,
            posterSmall: posterUrl,
            posterMedium: posterUrl,
            posterOriginal: posterUrl,
            genres: const ['Аниме'],
            description: '',
            status: 'Онгоинг',
            episodes: [newEpisode],
          );

          unawaited(switchAnimeInRoom(
            newTitle,
            episode: newEpisode,
            broadcast: false,
            senderLabel: packet.sender,
          ));
        }
        break;
    }
  }

  void _activateSpoilerShield() {
    emit(state.copyWith(isSpoilerShieldActive: true));
    _spoilerShieldTimer?.cancel();
    _spoilerShieldTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!isClosed) {
        emit(state.copyWith(isSpoilerShieldActive: false));
      }
    });
  }

  void _handleIncomingPokeNudge(String sender) {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.heavyImpact());
    Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.heavyImpact());

    emit(state.copyWith(
      pokeNudgeMessage: () => '🩴 $sender кинул в вас тапок! Возвращайтесь к просмотру!',
    ));

    Timer(const Duration(seconds: 4), () {
      if (!isClosed) {
        emit(state.copyWith(pokeNudgeMessage: () => null));
      }
    });
  }

  /// Отправить тапок АФК-другу
  void sendPokeNudge() {
    if (!state.isSyncRoom) return;
    HapticFeedback.mediumImpact();
    syncRepository?.sendPacket(
      SyncPacket(
        action: SyncActionTypes.pokeNudge,
        sender: state.isHost ? 'Хост' : (state.peerName ?? 'Гость'),
        roomCode: state.roomCode!,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        payload: {},
      ),
    );
  }

  /// Голосование за кооперативный пропуск опенинга
  void voteCoopSkip() {
    if (state.hasVotedCoopSkip) return;
    HapticFeedback.lightImpact();
    final newVotes = state.coopSkipVotes + 1;
    emit(state.copyWith(hasVotedCoopSkip: true, coopSkipVotes: newVotes));

    if (state.isSyncRoom) {
      syncRepository?.sendPacket(
        SyncPacket(
          action: SyncActionTypes.coopSkipVote,
          sender: state.isHost ? 'Хост' : (state.peerName ?? 'Гость'),
          roomCode: state.roomCode!,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {'votes': newVotes},
        ),
      );
    }

    if (newVotes >= 2 || !state.isSyncRoom) {
      skipOpening();
    }
  }

  void toggleWatchPartyStats() {
    emit(state.copyWith(showWatchPartyStats: !state.showWatchPartyStats));
  }

  void _broadcastControlAction(String action, {double? playbackRate, Duration? targetPosition}) {
    if (state.isSyncRoom && state.roomCode != null) {
      final posMs = (targetPosition ?? state.position).inMilliseconds;
      final isPlaying = action == 'play' ? true : (action == 'pause' ? false : state.isPlaying);
      final effectiveRate = playbackRate ?? state.playbackRate;

      syncRepository?.sendControlAction(
        roomCode: state.roomCode!,
        action: action,
        positionMs: posMs,
        sender: currentUserName,
        playbackRate: effectiveRate,
        updatedBy: currentUserId,
      );

      syncRepository?.broadcastPlayback(
        roomCode: state.roomCode!,
        time: posMs / 1000.0,
        isPlaying: isPlaying,
        episode: state.episode.episode,
        animeId: '${state.title.id}',
        playbackRate: effectiveRate,
        updatedBy: currentUserId,
      );
    }
  }

  String? _getUrlForQuality(EpisodeItem ep, PlayerQuality quality) {
    switch (quality) {
      case PlayerQuality.fhd:
        return ep.fhdUrl ?? ep.hdUrl ?? ep.sdUrl;
      case PlayerQuality.hd:
        return ep.hdUrl ?? ep.fhdUrl ?? ep.sdUrl;
      case PlayerQuality.sd:
        return ep.sdUrl ?? ep.hdUrl ?? ep.fhdUrl;
    }
  }

  final Set<String> _completed80Episodes = {};

  Future<void> _loadCurrentEpisodeStream({Duration? initialPosition}) async {
    final effectiveStart = initialPosition ?? _pendingInitialSeek;
    if (effectiveStart != null && effectiveStart > Duration.zero) {
      _pendingInitialSeek = effectiveStart;
    }
    // 1. Проверяем, скачана ли серия локально для офлайн-просмотра без интернета
    String? localFilePath;
    try {
      if (getIt.isRegistered<DownloadRepository>()) {
        final downloadRepo = getIt<DownloadRepository>();
        if (downloadRepo.isDownloaded(state.title.id, state.episode.episode)) {
          final task = downloadRepo.getTask(state.title.id, state.episode.episode);
          if (task != null && task.localPath.isNotEmpty && File(task.localPath).existsSync()) {
            localFilePath = task.localPath;
          }
        }
      }
    } catch (_) {}

    String? streamUrl = localFilePath;

    // 0. Проверяем предзагруженный кэш следующей серии для мгновенного старта (<200ms)
    if (streamUrl == null) {
      final prefetchedUrl = EpisodePrefetchService.instance.getPrefetchedStreamUrl(
        state.title.id,
        state.episode.episode,
        state.selectedQuality,
      );
      if (prefetchedUrl != null && prefetchedUrl.isNotEmpty && !prefetchedUrl.contains('sample.com')) {
        streamUrl = prefetchedUrl;
        debugPrint('[PlayerCubit] Мгновенный запуск из предзагруженного кэша для серии ${state.episode.episode}: $streamUrl');
      }
    }

    // Если активна сторонняя озвучка (Kodik, StudioBand, AniDUB и др.), загружаем её поток
    if (streamUrl == null && getIt.isRegistered<KodikCubit>()) {
      try {
        final kodik = getIt<KodikCubit>();
        if (!kodik.state.isAniLibriaActive) {
          final kodikStream = await kodik.getStreamForEpisode(state.episode.episode);
          if (kodikStream != null && kodikStream.isNotEmpty) {
            streamUrl = kodikStream;
          }
        }
      } catch (_) {}
    }

    streamUrl ??= _getUrlForQuality(state.episode, state.selectedQuality);

    // Защита: отсекаем dummy-ссылки sample.com, которые приводят к падению декодера c2.mtk.avc.decoder
    if (streamUrl != null && streamUrl.contains('sample.com')) {
      streamUrl = null;
    }

    // Если прямая ссылка отсутствует или тайтл не имеет серий — получаем видеопотоки через Supabase Edge Function
    if ((streamUrl == null || streamUrl.isEmpty) && getIt.isRegistered<GetPlayerLinksUseCase>() && state.title.id > 0) {
      try {
        final links = await getIt<GetPlayerLinksUseCase>().call(
          state.title.id,
          title: state.title.displayTitle,
        );
        if (links.isNotEmpty) {
          final direct = links.where((t) => t.isDirectStream && t.episodes.isNotEmpty);
          if (direct.isNotEmpty) {
            final directEps = direct.first.episodes.map((e) => e.toEpisodeItem()).toList();
            final updatedTitle = state.title.copyWith(episodes: directEps);
            final targetEp = directEps.firstWhere(
              (e) => e.episode == state.episode.episode,
              orElse: () => directEps.first,
            );
            streamUrl = _getUrlForQuality(targetEp, state.selectedQuality);
            if (streamUrl != null && !streamUrl.contains('sample.com')) {
              emit(state.copyWith(
                title: updatedTitle,
                episode: targetEp,
              ));
            }
          }
        }
      } catch (_) {}
    }

    // Если прямая ссылка отсутствует или пуста — пробуем разрешить через Kodik (если доступен)
    if ((streamUrl == null || streamUrl.isEmpty) && getIt.isRegistered<KodikCubit>()) {
      try {
        final kodik = getIt<KodikCubit>();
        final resolvedKodik = await kodik.getStreamForEpisode(state.episode.episode);
        if (resolvedKodik != null && resolvedKodik.isNotEmpty && !resolvedKodik.contains('sample.com')) {
          streamUrl = resolvedKodik;
        }
      } catch (_) {}
    }

    if (streamUrl != null && streamUrl.isNotEmpty) {
      final trimmed = streamUrl.trim();
      if (trimmed.startsWith('//')) {
        streamUrl = 'https:$trimmed';
      }
    }

    if (streamUrl == null || streamUrl.isEmpty || streamUrl.contains('sample.com')) {
      emit(state.copyWith(
        errorMessage: () => 'Серия недоступна для воспроизведения. Выберите другой тайтл или эпизод.',
        isBuffering: false,
        isPlaying: false,
      ));
      return;
    }

    final currentMediaKey = '${state.title.id}_${state.episode.episode}_${state.selectedQuality.name}_$streamUrl';
    if (_loadedMediaKey == currentMediaKey && player.state.playlist.medias.isNotEmpty) {
      // Медиа уже открыто в плеере — избегаем повторного player.open(), сброса D3D/MediaCodec и AudioTrack
      final shouldPlay = !state.isSyncRoom || state.isHost;
      if (shouldPlay && !state.isPlaying) {
        player.play();
      }
      return;
    }

    try {
      final shouldPlay = !state.isSyncRoom || state.isHost;
      emit(state.copyWith(
        isBuffering: true,
        isPlaying: shouldPlay,
        errorMessage: () => null,
      ));
      _updateDiscordPresence(isPaused: !shouldPlay);
      if (state.isSyncRoom && state.roomCode != null) {
        unawaited(
          AchievementService.instance.recordWatchTogetherJoined(state.roomCode),
        );
      }
      await player.open(
        Media(
          streamUrl,
          httpHeaders: defaultStreamingHeaders,
          start: (_pendingInitialSeek != null && _pendingInitialSeek! > Duration.zero)
              ? _pendingInitialSeek
              : null,
        ),
        play: shouldPlay,
      );
      _loadedMediaKey = currentMediaKey;
    } catch (e) {
      emit(state.copyWith(
        errorMessage: () => 'Ошибка запуска видеопотока: $e',
        isBuffering: false,
        isPlaying: false,
      ));
    }
  }

  /// Переключение студии озвучки Kodik / AniLibria прямо из плеера
  Future<void> switchVoiceoverStudio(KodikTranslation studio) async {
    final currentPos = state.position;
    final wasPlaying = state.isPlaying;

    if (getIt.isRegistered<KodikCubit>()) {
      try {
        final kodik = getIt<KodikCubit>();
        final qualityStr = state.selectedQuality == PlayerQuality.fhd
            ? '1080p'
            : (state.selectedQuality == PlayerQuality.hd ? '720p' : '480p');
        final streamUrl = await kodik.selectVoiceover(
          studio,
          episodeNumber: state.episode.episode,
          quality: qualityStr,
        );

        if (streamUrl != null && streamUrl.isNotEmpty && !streamUrl.contains('sample.com')) {
          _pendingInitialSeek = currentPos;
          await player.open(
            Media(
              streamUrl,
              httpHeaders: defaultStreamingHeaders,
              start: currentPos > Duration.zero ? currentPos : null,
            ),
            play: wasPlaying,
          );
          _loadedMediaKey = '${state.title.id}_${state.episode.episode}_${state.selectedQuality.name}_$streamUrl';
          return;
        }
      } catch (_) {}
    }

    // Если выбрана AniLibria или внешний поток Kodik вернул fallback — открываем основной поток с текущей позиции
    await _loadCurrentEpisodeStream(initialPosition: currentPos);
  }

  /// Переключение варианта озвучки или студии (AniLibria / Kodik / StudioBand)
  /// Обновляет источник воспроизведения без пересоздания всего экрана и с сохранением позиции
  Future<void> changeTranslation(TranslationEntity newTranslation) async {
    final currentPos = state.position;
    final wasPlaying = state.isPlaying;
    emit(state.copyWith(
      currentTranslation: () => newTranslation,
    ));

    if (newTranslation.isDirectStream) {
      final streamUrl = newTranslation.getStreamForEpisode(state.episode.episode);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        try {
          _pendingInitialSeek = currentPos;
          await player.open(
            Media(
              streamUrl,
              httpHeaders: defaultStreamingHeaders,
              start: currentPos > Duration.zero ? currentPos : null,
            ),
            play: wasPlaying,
          );
          _loadedMediaKey = '${state.title.id}_${state.episode.episode}_${state.selectedQuality.name}_$streamUrl';
          return;
        } catch (e) {
          emit(state.copyWith(
            errorMessage: () => 'Ошибка переключения потока: $e',
          ));
        }
      }
    } else {
      // Для сторонних озвучек (Kodik) извлекаем прямой поток через KodikCubit
      if (getIt.isRegistered<KodikCubit>()) {
        try {
          final kodik = getIt<KodikCubit>();
          final streamUrl = await kodik.getStreamForEpisode(state.episode.episode);
          if (streamUrl != null && streamUrl.isNotEmpty && !streamUrl.contains('sample.com')) {
            _pendingInitialSeek = currentPos;
            await player.open(
              Media(
                streamUrl,
                httpHeaders: defaultStreamingHeaders,
                start: currentPos > Duration.zero ? currentPos : null,
              ),
              play: wasPlaying,
            );
            _loadedMediaKey = '${state.title.id}_${state.episode.episode}_${state.selectedQuality.name}_$streamUrl';
            return;
          }
        } catch (_) {}
      }
    }

    // Fallback: поддерживаем непрерывное воспроизведение с текущей позиции
    final fallbackUrl = _getUrlForQuality(state.episode, state.selectedQuality);
    if (fallbackUrl != null && fallbackUrl.isNotEmpty && !fallbackUrl.contains('sample.com')) {
      try {
        _pendingInitialSeek = currentPos;
        await player.open(
          Media(
            fallbackUrl,
            httpHeaders: defaultStreamingHeaders,
            start: currentPos > Duration.zero ? currentPos : null,
          ),
          play: wasPlaying,
        );
        _loadedMediaKey = '${state.title.id}_${state.episode.episode}_${state.selectedQuality.name}_$fallbackUrl';
      } catch (_) {}
    }
  }

  /// Установка списка доступных переводов от Supabase Edge Function
  void setTranslations(List<TranslationEntity> translations) {
    if (translations.isEmpty) return;
    final current = state.currentTranslation ?? translations.first;
    emit(state.copyWith(
      translations: translations,
      currentTranslation: () => current,
    ));
  }

  /// Показ аккуратного всплывающего тоста гостю при попытке управлять воспроизведением
  void showGuestPlaybackLockedNotice() {
    final notice = QuickPhraseToast(
      id: 'guest_locked_${DateTime.now().microsecondsSinceEpoch}',
      sender: 'Комната',
      phrase: 'Воспроизведением управляет хост комнаты',
      emoji: '👑',
      timestamp: DateTime.now(),
    );
    emit(state.copyWith(activeQuickPhrase: () => notice));
    _quickPhraseTimer?.cancel();
    _quickPhraseTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!isClosed && state.activeQuickPhrase?.id.startsWith('guest_locked_') == true) {
        emit(state.copyWith(activeQuickPhrase: () => null));
      }
    });
  }

  void playOrPause() {
    if (state.isSyncRoom && !state.isHost) {
      showGuestPlaybackLockedNotice();
      return;
    }
    final willPlay = !state.isPlaying;
    if (willPlay && state.errorMessage != null) {
      emit(state.copyWith(errorMessage: () => null));
    }
    player.playOrPause();
    _broadcastControlAction(willPlay ? 'play' : 'pause');
    _resetControlsTimer();
  }

  void togglePlayPause() => playOrPause();

  void play() {
    if (state.isSyncRoom && !state.isHost) {
      showGuestPlaybackLockedNotice();
      return;
    }
    if (state.errorMessage != null) {
      emit(state.copyWith(errorMessage: () => null));
    }
    player.play();
    _broadcastControlAction('play');
    _updateDiscordPresence(isPaused: false);
    _resetControlsTimer();
  }

  void pause() {
    if (state.isSyncRoom && !state.isHost) {
      showGuestPlaybackLockedNotice();
      return;
    }
    player.pause();
    emit(state.copyWith(pauseCount: state.pauseCount + 1));
    _broadcastControlAction('pause');
    _updateDiscordPresence(isPaused: true);
    _resetControlsTimer();
  }

  void seek(Duration position) {
    if (state.isSyncRoom && !state.isHost) {
      showGuestPlaybackLockedNotice();
      return;
    }
    player.seek(position);
    emit(state.copyWith(position: position));
    _broadcastControlAction('seek', targetPosition: position);
    _resetControlsTimer();
  }

  void seekRelative(int seconds) {
    if (state.isSyncRoom && !state.isHost) {
      showGuestPlaybackLockedNotice();
      return;
    }
    final current = state.position.inSeconds;
    final maxSec = state.duration.inSeconds > 0 ? state.duration.inSeconds : 36000;
    final target = (current + seconds).clamp(0, maxSec);
    seek(Duration(seconds: target));
  }

  double _preFastForwardRate = 1.0;

  void setPlaybackRate(double rate) {
    player.setRate(rate);
    emit(state.copyWith(playbackRate: rate));
    _broadcastControlAction('rate', playbackRate: rate);
    _resetControlsTimer();
  }

  /// Ускорение при удержании экрана (Long Press) или зажатии Space (2x Speed)
  void start2xFastForward() {
    if (state.is2xFastForwarding) return;
    _preFastForwardRate = state.playbackRate >= 1.9 ? 1.0 : state.playbackRate;
    player.setRate(2.0);
    emit(state.copyWith(is2xFastForwarding: true, playbackRate: 2.0));
    _broadcastControlAction('rate', playbackRate: 2.0);
  }

  /// Плавное изменение скорости при свайпе во время зажатия (от 1.25x до 4.0x)
  void setFastForwardRate(double rate) {
    if (!state.is2xFastForwarding) return;
    final clamped = (rate * 4).round() / 4.0;
    final target = clamped.clamp(1.25, 4.0);
    if ((state.playbackRate - target).abs() > 0.01) {
      player.setRate(target);
      emit(state.copyWith(playbackRate: target));
      _broadcastControlAction('rate', playbackRate: target);
    }
  }

  /// Возврат к обычной скорости при отпускании
  void stop2xFastForward() {
    if (!state.is2xFastForwarding) return;
    final restoredRate = _preFastForwardRate > 0 ? _preFastForwardRate : 1.0;
    player.setRate(restoredRate);
    emit(state.copyWith(is2xFastForwarding: false, playbackRate: restoredRate));
    _broadcastControlAction('rate', playbackRate: restoredRate);
  }

  /// Отправить стикер-реакцию Пай-чан (excited, happy, surprised, sad, love, sleepy)
  void sendReaction(String emojiOrStickerId) {
    if (!kIsWeb && !Platform.isWindows) {
      try {
        HapticFeedback.lightImpact();
      } catch (_) {}
    }

    final sticker = PaiChanSticker.fromIdOrEmoji(emojiOrStickerId);
    final senderName = currentUserName;

    // 1. Немедленно спавним анимированный стикер Пай-чан локально поверх видео (2.4 сек)
    final reactionId = 'rx_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(9999)}';
    final reaction = FloatingReaction(
      id: reactionId,
      emoji: sticker.fallbackEmoji,
      stickerId: sticker.id,
      sender: senderName,
      senderId: currentUserId,
      startXOffset: 0.18 + (_random.nextDouble() * 0.64),
      timestamp: DateTime.now(),
    );
    final current = List<FloatingReaction>.from(state.activeReactions)..add(reaction);
    emit(state.copyWith(activeReactions: current, emojisSent: state.emojisSent + 1));

    Timer(const Duration(milliseconds: 2400), () {
      if (!isClosed) {
        final remaining = List<FloatingReaction>.from(state.activeReactions)
          ..removeWhere((r) => r.id == reactionId);
        emit(state.copyWith(activeReactions: remaining));
      }
    });

    // 2. Обновляем тепловую карту эмоций на таймлайне
    if (state.heatmap != null && state.duration.inSeconds > 0) {
      final updatedHeatmap = state.heatmap!.addReaction(
        timestampSec: state.position.inSeconds.toDouble(),
        totalDurationSec: state.duration.inSeconds.toDouble(),
        emoji: sticker.fallbackEmoji,
        sender: senderName,
      );
      emit(state.copyWith(heatmap: () => updatedHeatmap));
    }

    // 3. Транслируем pai_sticker_reaction в канал комнаты (room:$roomId) для друзей (Phone <-> PC)
    if (state.isSyncRoom && state.roomCode != null) {
      syncRepository?.sendReaction(
        roomCode: state.roomCode!,
        emoji: sticker.fallbackEmoji,
        stickerId: sticker.id,
        sender: senderName,
        senderId: currentUserId,
        reactionId: reactionId,
      );
    }
  }

  /// Включение / отключение микрофона (Push-to-Talk / Open Mic)
  void toggleVoiceMute() {
    final nextMute = !state.isVoiceMuted;
    emit(state.copyWith(isVoiceMuted: nextMute, isTalking: !nextMute));
    _applyAudioDucking();

    if (state.isSyncRoom) {
      syncRepository?.sendPacket(
        SyncPacket(
          action: SyncActionTypes.voiceTalking,
          sender: state.isHost ? 'Хост' : (state.peerName ?? 'Гость'),
          roomCode: state.roomCode!,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {'is_talking': !nextMute},
        ),
      );
    }
  }

  /// Зажать тангенту Push-to-Talk (говорит)
  void setTalking(bool talking) {
    if (state.isTalking == talking) return;
    emit(state.copyWith(isTalking: talking));
    _applyAudioDucking();

    if (state.isSyncRoom) {
      syncRepository?.sendPacket(
        SyncPacket(
          action: SyncActionTypes.voiceTalking,
          sender: state.isHost ? 'Хост' : (state.peerName ?? 'Гость'),
          roomCode: state.roomCode!,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          payload: {'is_talking': talking},
        ),
      );
    }
  }

  /// Умное приглушение звука серии (Audio Ducking):
  /// Снижаем громкость серии до 35%, когда говорит пользователь или друг
  void _applyAudioDucking() {
    final shouldDuck = state.isTalking || state.isPeerTalking;
    try {
      player.setVolume(shouldDuck ? 35.0 : 100.0);
    } catch (_) {}
  }

  /// Отправить быструю шорткат-фразу («Останови, отойду на минуту», «Что за трек?!»)
  void sendQuickPhrase(String phrase, {String? emoji}) {
    final senderName = state.isHost ? 'Хост' : (state.peerName ?? 'Вы');
    final effectiveEmoji = emoji ?? '💬';

    // 1. Показываем всплывающий тост локально у отправителя мгновенно
    final localToast = QuickPhraseToast(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      sender: senderName,
      phrase: phrase,
      emoji: effectiveEmoji,
      timestamp: DateTime.now(),
    );
    emit(state.copyWith(activeQuickPhrase: () => localToast));
    _quickPhraseTimer?.cancel();
    _quickPhraseTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!isClosed) {
        emit(state.copyWith(activeQuickPhrase: () => null));
      }
    });

    // 2. Добавляем в оверлей чата плеера, чтобы ник и текст появились в углу
    sendChatMessage('$effectiveEmoji $phrase');

    // 3. Отправляем сетевой пакет в комнату совместного просмотра
    if (state.isSyncRoom && state.roomCode != null) {
      syncRepository?.sendQuickPhrase(
        roomCode: state.roomCode!,
        phrase: phrase,
        emoji: effectiveEmoji,
        sender: senderName,
      );
    }

    // 4. Если фраза с просьбой паузы:
    if (phrase.toLowerCase().contains('останови') || phrase.toLowerCase().contains('пауз')) {
      if (state.isHost) {
        player.pause();
        _broadcastControlAction('pause');
      } else {
        requestPauseFromHost();
      }
    }
  }

  /// Отслеживание жизненного цикла приложения (свернул / вернулся)
  void setAppLifecycle({required bool isAway}) {
    if (!state.isSyncRoom) return;

    final myPresence = PeerPresence(
      userId: state.isHost ? 'host' : 'guest',
      name: state.isHost ? 'Хост' : (state.peerName ?? 'Гость'),
      avatar: state.isHost ? '👑' : '🐱',
      status: isAway ? PresenceStatus.away : PresenceStatus.online,
      lastSeen: DateTime.now(),
      isHost: state.isHost,
    );

    syncRepository?.updatePresence(
      roomCode: state.roomCode!,
      presence: myPresence,
    );
  }

  /// Добавить сообщение в ленту чата комнаты (дедупликация по id, лимит 100)
  void _pushChatMessage(ChatMessage message) {
    if (isClosed) return;
    if (state.chatMessages.any((m) => m.id == message.id)) return;
    final updated = List<ChatMessage>.from(state.chatMessages)..add(message);
    if (updated.length > 100) updated.removeRange(0, updated.length - 100);
    emit(state.copyWith(chatMessages: updated));
  }

  /// Системное событие комнаты («Хост поставил на паузу», «Серия переключена»)
  void _addSystemChatMessage(String text) {
    if (!state.isSyncRoom) return;
    _pushChatMessage(ChatMessage(
      id: 'sys_${DateTime.now().microsecondsSinceEpoch}',
      sender: 'SyncPai',
      text: text,
      timestamp: DateTime.now(),
      type: 'system',
    ));
  }

  Future<void> _loadChatHistory(String code) async {
    try {
      final history = await syncRepository?.fetchChatHistory(code) ?? const <ChatMessage>[];
      if (isClosed || history.isEmpty) return;
      final existingIds = state.chatMessages.map((m) => m.id).toSet();
      final merged = <ChatMessage>[
        ...history.where((m) => !existingIds.contains(m.id)),
        ...state.chatMessages,
      ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      emit(state.copyWith(
        chatMessages: merged.length > 100 ? merged.sublist(merged.length - 100) : merged,
      ));
    } catch (_) {}
  }

  /// Отправить текстовое сообщение в чат и запустить бегущую строку (Danmaku)
  void sendChatMessage(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final sender = currentUserName;
    final msgId = 'msg_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(9999)}';

    // 1. Оптимистичное добавление сообщения в локальный стейт чата мгновенно по нажатию Enter / Send
    _pushChatMessage(ChatMessage(
      id: msgId,
      sender: sender,
      text: clean,
      isHost: state.isHost,
      timestamp: DateTime.now(),
    ));
    _addDanmaku(clean, sender);

    // 2. Вставка в public.room_messages и мгновенная трансляция в канал комнаты (room:$roomId)
    if (state.isSyncRoom && state.roomCode != null) {
      unawaited(
        (syncRepository?.sendChatMessage(
                  roomCode: state.roomCode!,
                  text: clean,
                  sender: sender,
                  isHost: state.isHost,
                  messageId: msgId,
                ) ??
                Future.value())
            .catchError((Object error) {
          if (!isClosed) {
            emit(state.copyWith(
              errorMessage: () => 'Не удалось доставить сообщение: $error',
            ));
          }
        }),
      );
    }
  }

  void toggleDanmaku() {
    emit(state.copyWith(isDanmakuEnabled: !state.isDanmakuEnabled));
  }

  void _addDanmaku(String text, String sender) {
    if (!state.isDanmakuEnabled || text.trim().isEmpty) return;
    final item = DanmakuItem(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(9999)}',
      text: text.trim(),
      sender: sender,
      lane: _random.nextInt(4),
      color: sender == 'Хост' ? const Color(0xFF00CEC9) : const Color(0xFFFF7675),
    );
    final updated = List<DanmakuItem>.from(state.danmakuMessages)..add(item);
    if (updated.length > 30) {
      updated.removeRange(0, updated.length - 30);
    }
    emit(state.copyWith(danmakuMessages: updated));
  }

  void _updateDiscordPresence({bool? isPaused}) {
    final paused = isPaused ?? !state.isPlaying;
    try {
      if (state.isSyncRoom && state.roomCode != null) {
        unawaited(
          DiscordRpcService.instance.setWatchingTogether(
            title: state.title.displayTitle,
            episodeNumber: state.episode.episode,
            roomCode: state.roomCode!,
            roomId: 'room_${state.roomCode}',
            participantsCount: 2,
            posterUrl: state.title.posterMedium,
          ),
        );
      } else {
        unawaited(
          DiscordRpcService.instance.setWatchingSolo(
            title: state.title.displayTitle,
            episodeNumber: state.episode.episode,
            totalEpisodes: state.title.episodesTotal,
            posterUrl: state.title.posterMedium,
            isPaused: paused,
            position: state.position,
            duration: state.duration,
          ),
        );
      }
    } catch (_) {}
  }

  /// Динамически подключить сессию совместной комнаты к текущему плееру
  void attachRoomSession(SyncRoom room, {required bool isHost}) {
    if (isClosed) return;
    _heartbeatTimer?.cancel();
    _presenceSubscription?.cancel();
    _packetSubscription?.cancel();

    emit(state.copyWith(
      roomCode: room.code,
      isHost: isHost,
      peerName: isHost ? room.peerName : room.hostName,
      syncStatus: SyncStatus.active,
      chatMessages: const [],
    ));

    _initSyncGateway();
    _addSystemChatMessage(isHost ? 'Вы создали комнату ${room.code}' : 'Вы присоединились к комнате ${room.code}');
  }

  /// Покинуть комнату совместного просмотра и вернуться в соло-режим
  Future<void> leaveRoom() async {
    final code = state.roomCode;
    _heartbeatTimer?.cancel();
    _presenceSubscription?.cancel();
    _packetSubscription?.cancel();

    if (code != null && syncRepository != null) {
      try {
        await syncRepository!.leaveRoom(code);
      } catch (_) {}
    }

    if (!isClosed) {
      emit(state.copyWith(
        clearRoom: true,
        syncStatus: SyncStatus.disconnected,
        peerPresence: () => null,
        bufferNotice: () => null,
      ));
    }
  }

  /// Полное закрытие комнаты хостом для всех участников
  Future<void> closeRoomForAll() async {
    final code = state.roomCode;
    _heartbeatTimer?.cancel();
    _presenceSubscription?.cancel();
    _packetSubscription?.cancel();

    if (code != null && syncRepository != null) {
      try {
        await syncRepository!.closeRoomForAll(code);
      } catch (_) {}
    }

    if (!isClosed) {
      emit(state.copyWith(
        clearRoom: true,
        syncStatus: SyncStatus.disconnected,
        peerPresence: () => null,
        bufferNotice: () => null,
      ));
    }
  }

  /// Запрос паузы от ведомого гостя
  void requestPauseFromHost() {
    if (state.isSyncRoom && !state.isHost) {
      player.pause();
      emit(state.copyWith(
        errorMessage: () => 'Запрос на паузу отправлен хосту',
      ));
      Timer(const Duration(seconds: 3), () {
        if (!isClosed && state.errorMessage == 'Запрос на паузу отправлен хосту') {
          emit(state.copyWith(errorMessage: () => null));
        }
      });
      syncRepository?.sendRequestPause(
        roomCode: state.roomCode!,
        sender: state.peerName ?? 'Гость',
      );
    }
  }

  /// Переключение видимости оверлея чата (скрыть / показать)
  void toggleChatOverlay() {
    emit(state.copyWith(isChatOverlayVisible: !state.isChatOverlayVisible));
  }

  Future<void> changeQuality(PlayerQuality newQuality) async {
    if (newQuality == state.selectedQuality) return;

    final currentPosition = state.position;
    emit(state.copyWith(selectedQuality: newQuality));
    await _loadCurrentEpisodeStream(initialPosition: currentPosition);
  }

  int? _autoNextCancelledForEpisode;

  /// Упреждающая предзагрузка следующей серии (Smart Next-Episode Prefetch)
  /// Запускается перед финальными титрами (ending.start или duration - 120s)
  void _checkNextEpisodePrefetch(Duration pos) {
    final dur = state.duration;
    if (dur <= const Duration(seconds: 30)) return;

    final all = state.title.episodes;
    final curIdx = all.indexWhere((e) => e.episode == state.episode.episode);
    if (curIdx < 0 || curIdx + 1 >= all.length) return;

    final nextEp = all[curIdx + 1];
    final currentKey = '${state.title.id}_${state.episode.episode}_${nextEp.episode}_${state.selectedQuality.name}';
    if (_prefetchedEpisodeKey == currentKey) return;

    // Условие триггера: ending.start таймкод (или duration - const Duration(seconds: 120), если ending отсутствует)
    final ending = state.effectiveEnding;
    final Duration triggerPoint;
    if (ending != null && ending.start > 0) {
      triggerPoint = Duration(seconds: ending.start);
    } else if (dur > const Duration(seconds: 120)) {
      triggerPoint = dur - const Duration(seconds: 120);
    } else {
      triggerPoint = dur - const Duration(seconds: 30);
    }

    if (pos >= triggerPoint) {
      _prefetchedEpisodeKey = currentKey;
      unawaited(
        EpisodePrefetchService.instance.prefetchNext(
          title: state.title,
          currentEpisode: state.episode,
          nextEpisode: nextEp,
          quality: state.selectedQuality,
        ),
      );
    }
  }

  /// Проверка окончания серии для авто-перехода (Auto Next Episode)
  void _checkAutoNextEpisode(Duration pos) {
    final dur = state.duration;
    if (dur <= const Duration(seconds: 20)) return;
    if (_autoNextCancelledForEpisode == state.episode.episode) return;

    final remaining = dur - pos;
    // Автоплей стартует за 10 секунд до конца серии с 10-секундным обратным отсчетом
    if (remaining.inSeconds <= 10 && remaining.inSeconds > 0 && state.autoNextCountdown == null) {
      final all = state.title.episodes;
      final curIdx = all.indexWhere((e) => e.episode == state.episode.episode);
      if (curIdx >= 0 && curIdx < all.length - 1) {
        startAutoNextCountdown(all[curIdx + 1]);
      }
    }
  }

  /// Запуск обратного отсчета следующей серии
  void startAutoNextCountdown(EpisodeItem nextEp) {
    if (state.autoNextCountdown != null) return;

    emit(state.copyWith(
      autoNextCountdown: () => 10,
      nextEpisode: () => nextEp,
    ));

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (isClosed) {
        timer.cancel();
        return;
      }
      final current = state.autoNextCountdown ?? 0;
      if (current <= 1) {
        timer.cancel();
        emit(state.copyWith(autoNextCountdown: () => null));
        if (!state.isSyncRoom || state.isHost) {
          playNextEpisode(nextEp);
        }
      } else {
        emit(state.copyWith(autoNextCountdown: () => current - 1));
      }
    });
  }

  /// Отмена авто-перехода
  void cancelAutoNextCountdown({bool markCancelledForEpisode = true}) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (markCancelledForEpisode) {
      _autoNextCancelledForEpisode = state.episode.episode;
    }
    emit(state.copyWith(
      autoNextCountdown: () => null,
      nextEpisode: () => null,
    ));
  }

  /// Немедленный переход на следующую серию
  void playNextEpisode([EpisodeItem? nextEp]) {
    cancelAutoNextCountdown();
    final target = nextEp ?? state.nextEpisode;
    if (target != null) {
      switchEpisode(target);
      return;
    }

    final all = state.title.episodes;
    final curIdx = all.indexWhere((e) => e.episode == state.episode.episode);
    if (curIdx >= 0 && curIdx < all.length - 1) {
      switchEpisode(all[curIdx + 1]);
    }
  }

  Future<void> switchEpisode(EpisodeItem nextEpisode) async {
    if (nextEpisode.episode == state.episode.episode) return;

    if (state.isSyncRoom && state.roomCode != null) {
      syncRepository?.sendChangeEpisode(
        roomCode: state.roomCode!,
        episodeNumber: nextEpisode.episode,
        quality: state.selectedQuality.name,
        sender: currentUserName,
      );
      syncRepository?.broadcastPlayback(
        roomCode: state.roomCode!,
        time: 0.0,
        isPlaying: true,
        episode: nextEpisode.episode,
        animeId: '${state.title.id}',
        playbackRate: state.playbackRate,
        updatedBy: currentUserId,
      );
    }

    await _switchEpisodeInternal(nextEpisode);
  }

  /// Смена аниме прямо внутри активной комнаты без пересоздания комнаты и без разрыва чата
  Future<void> switchAnimeInRoom(
    AnimeTitle newTitle, {
    EpisodeItem? episode,
    bool broadcast = true,
    String? senderLabel,
  }) async {
    if (isClosed) return;

    _savePlaybackPosition(state.position, state.duration);
    _pendingInitialSeek = Duration.zero;
    _autoNextCancelledForEpisode = null;
    _prefetchedEpisodeKey = null;
    cancelAutoNextCountdown(markCancelledForEpisode: false);

    AnimeTitle resolvedTitle = newTitle;
    if (resolvedTitle.episodes.length <= 1 &&
        resolvedTitle.id > 0 &&
        getIt.isRegistered<CatalogRepository>()) {
      try {
        final full = await getIt<CatalogRepository>().getTitleDetails(
          id: resolvedTitle.id,
          code: resolvedTitle.code,
        );
        if (full.episodes.isNotEmpty) {
          resolvedTitle = resolvedTitle.copyWith(
            episodes: full.episodes,
            episodesTotal: full.episodesTotal ?? full.episodes.length,
            description: resolvedTitle.description.isNotEmpty
                ? resolvedTitle.description
                : full.description,
            genres: resolvedTitle.genres.isNotEmpty
                ? resolvedTitle.genres
                : full.genres,
          );
        }
      } catch (_) {}
    }

    if (isClosed) return;

    EpisodeItem targetEpisode = episode ??
        (resolvedTitle.episodes.isNotEmpty
            ? resolvedTitle.episodes.first
            : const EpisodeItem(episode: 1, name: 'Серия 1'));

    if (resolvedTitle.episodes.isNotEmpty && targetEpisode.bestAvailableUrl == null) {
      targetEpisode = resolvedTitle.episodes.firstWhere(
        (e) => e.episode == targetEpisode.episode,
        orElse: () => resolvedTitle.episodes.first,
      );
    }

    _loadedMediaKey = null;
    emit(state.copyWith(
      title: resolvedTitle,
      episode: targetEpisode,
      position: Duration.zero,
      duration: Duration.zero,
      buffer: Duration.zero,
      isBuffering: true,
      bufferNotice: () => null,
      errorMessage: () => null,
    ));

    final actor = senderLabel ?? (state.isHost ? 'Хост' : (state.peerName ?? 'Участник'));
    _addSystemChatMessage(
      broadcast
          ? 'Вы сменили аниме на «${resolvedTitle.displayTitle}» (Серия ${targetEpisode.episode})'
          : '$actor сменил аниме на «${resolvedTitle.displayTitle}» (Серия ${targetEpisode.episode})',
    );

    if (broadcast && state.isSyncRoom && state.roomCode != null) {
      unawaited(
        syncRepository?.changeRoomAnime(
              roomCode: state.roomCode!,
              title: resolvedTitle,
              episode: targetEpisode,
              sender: actor,
            ) ??
            Future.value(),
      );
    }

    await _loadCurrentEpisodeStream(initialPosition: Duration.zero);
  }

  Future<void> _switchEpisodeInternal(EpisodeItem nextEpisode) async {
    _savePlaybackPosition(state.position, state.duration);
    _pendingInitialSeek = loadSavedPosition(state.title, nextEpisode.episode);
    _autoNextCancelledForEpisode = null;
    _prefetchedEpisodeKey = null;
    cancelAutoNextCountdown(markCancelledForEpisode: false);

    final prevEpisode = state.episode.episode;
    try {
      if (getIt.isRegistered<DownloadCubit>()) {
        getIt<DownloadCubit>().onEpisodeFinished(
          titleId: state.title.id,
          finishedEpisode: prevEpisode,
          title: state.title,
          quality: state.selectedQuality.label,
        );
      }
    } catch (_) {}

    emit(state.copyWith(
      episode: nextEpisode,
      position: Duration.zero,
      duration: Duration.zero,
      buffer: Duration.zero,
      isBuffering: true,
      bufferNotice: () => null,
    ));

    await _loadCurrentEpisodeStream();
  }

  void setVolume(double volume) {
    final v = volume.clamp(0.0, 100.0);
    player.setVolume(v);
    emit(state.copyWith(volume: v));
  }

  void setBrightness(double brightness) {
    final b = brightness.clamp(0.05, 1.0);
    emit(state.copyWith(brightness: b));
  }

  void toggleScreenLock() {
    final nextLocked = !state.isScreenLocked;
    emit(state.copyWith(
      isScreenLocked: nextLocked,
      areControlsVisible: !nextLocked,
    ));
    if (nextLocked) {
      _controlsTimer?.cancel();
    }
  }

  void setScreenLocked(bool locked) {
    emit(state.copyWith(
      isScreenLocked: locked,
      areControlsVisible: !locked,
    ));
    if (locked) {
      _controlsTimer?.cancel();
    }
  }

  void toggleControls() {
    final nextVisible = !state.areControlsVisible;
    emit(state.copyWith(areControlsVisible: nextVisible));
    if (nextVisible) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  void showControls() {
    emit(state.copyWith(areControlsVisible: true));
    _startControlsTimer();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    final delay = state.isPlaying
        ? const Duration(milliseconds: 2600)
        : const Duration(milliseconds: 4500);
    _controlsTimer = Timer(delay, () {
      if (!isClosed) {
        emit(state.copyWith(areControlsVisible: false));
      }
    });
  }

  void setHudEditMode(bool enabled) {
    if (enabled) {
      _controlsTimer?.cancel();
      emit(state.copyWith(isHudEditMode: true, areControlsVisible: true));
    } else {
      emit(state.copyWith(isHudEditMode: false, areControlsVisible: true));
      _resetControlsTimer();
    }
  }

  void _resetControlsTimer() {
    if (state.isHudEditMode) {
      _controlsTimer?.cancel();
      return;
    }
    if (state.areControlsVisible) {
      _startControlsTimer();
    }
  }

  bool _isDisposing = false;
  bool _playerDisposed = false;

  @override
  Future<void> close() async {
    if (_isDisposing) return;
    _isDisposing = true;
    unawaited(PresenceService.instance.clearWatchingActivity());
    unawaited(DiscordRpcService.instance.setBrowsing());

    // 1. Сначала отменяем все подписки на стримы
    for (final s in _subscriptions) {
      try {
        await s.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();

    // 2. Отменяем фоновые таймеры и сетевые подписки
    _controlsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _countdownTimer?.cancel();
    _quickPhraseTimer?.cancel();
    _bufferingFallbackTimer?.cancel();
    _driftRateTimer?.cancel();
    try {
      await _presenceSubscription?.cancel();
    } catch (_) {}
    try {
      await _packetSubscription?.cancel();
    } catch (_) {}

    _savePlaybackPosition(state.position, state.duration);

    // 3. Безопасное однократное завершение нативного медиаплеера (stop -> dispose)
    if (!_playerDisposed) {
      _playerDisposed = true;
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.dispose();
      } catch (_) {}
    }

    if (!kIsWeb) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
    return super.close();
  }
}
