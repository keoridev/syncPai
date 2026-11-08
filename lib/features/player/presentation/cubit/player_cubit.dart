import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/services/discord_rpc_service.dart';
import 'package:sync_pai/core/widgets/sync_badge.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/domain/entities/translation_entity.dart';
import 'package:sync_pai/features/catalog/domain/repositories/catalog_repository.dart';
import 'package:sync_pai/features/downloads/domain/repositories/download_repository.dart';
import 'package:sync_pai/features/downloads/presentation/cubit/download_cubit.dart';
import 'package:sync_pai/features/kodik/presentation/cubit/kodik_cubit.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/player/domain/entities/reaction_heatmap.dart';
import 'package:sync_pai/features/player/presentation/widgets/danmaku_overlay_layer.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';
import 'package:sync_pai/features/sync_room/domain/repositories/sync_room_repository.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'player_state.dart';

class PlayerCubit extends Cubit<PlayerState> {
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
  final Random _random = Random();

  bool isAutoSkipOpening = false;
  final Duration? _initialPosition;

  PlayerCubit({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality initialQuality = PlayerQuality.fhd,
    String? roomCode,
    bool isHost = true,
    this.syncRepository,
    Duration? initialPosition,
  })  : player = Player(),
        // ignore: prefer_initializing_formals
        _initialPosition = initialPosition,
        super(PlayerState(
          title: title,
          episode: episode,
          selectedQuality: initialQuality,
          roomCode: roomCode,
          isHost: isHost,
          peerName: isHost ? 'Друг' : 'Хост',
          heatmap: ReactionHeatmap.initial(titleId: title.id, episode: episode.episode),
        )) {
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

    // Слушатели медиаплеера libmpv
    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        emit(state.copyWith(isPlaying: playing));
        _updateDiscordPresence();
      }),
      player.stream.buffering.listen((buffering) {
        emit(state.copyWith(isBuffering: buffering));
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
        emit(state.copyWith(position: pos));
        _checkAutoNextEpisode(pos);
        _checkAutoSkipOpening(pos);
      }),
      player.stream.duration.listen((dur) {
        emit(state.copyWith(duration: dur));
        _updateDiscordPresence();
      }),
      player.stream.buffer.listen((buffer) {
        emit(state.copyWith(buffer: buffer));
      }),
      player.stream.rate.listen((rate) {
        emit(state.copyWith(playbackRate: rate));
      }),
      player.stream.error.listen((error) {
        if (error.isNotEmpty) {
          // Игнорируем нефатальные ошибки разрыва соединения и таймаута TCP-сокетов при паузе и чтении сегментов
          // (например tcp ffurl_read_returned 0xdfb9b0bb, failed reading, End of file, connection reset)
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
    final opening = state.episode.opening;
    if (isAutoSkipOpening && opening != null) {
      if (pos.inSeconds >= opening.start && pos.inSeconds < opening.start + 2) {
        seek(opening.stopDuration);
        emit(state.copyWith(
          errorMessage: () => 'Опенинг автоматически пропущен (+${opening.stop - opening.start}с)',
        ));
      }
    }
  }

  /// Включить / выключить умный авто-пропуск опенингов
  void toggleAutoSkipOpening() {
    isAutoSkipOpening = !isAutoSkipOpening;
    emit(state.copyWith(
      errorMessage: () => isAutoSkipOpening
          ? 'Включен авто-пропуск опенингов'
          : 'Авто-пропуск опенингов выключен',
    ));
  }

  /// Пропуск опенинга: по таймкодам или универсально на +90 сек
  void skipOpening() {
    if (state.isSyncRoom && !state.isHost) return;

    final opening = state.episode.opening;
    if (opening != null) {
      seek(opening.stopDuration);
    } else {
      seekRelative(90);
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
          ? () => '$friendName ждет вас. Плеер остановлен 🥺'
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

    final myName = state.isHost ? 'Хост' : (state.peerName ?? 'Гость');
    final isFromSelf = packet.sender == myName;

    // Измерение пинга между участниками комнаты
    final ping = (DateTime.now().millisecondsSinceEpoch - packet.timestampMs).abs().clamp(12, 380);
    if (!isFromSelf && (state.peerPingMs - ping).abs() > 4) {
      emit(state.copyWith(peerPingMs: ping));
    }

    switch (packet.action) {
      // HEARTBEAT от хоста (обработка ведомым клиентом с Drift Compensation)
      case SyncActionTypes.heartbeat:
        if (!state.isHost && !isFromSelf) {
          final hostPos = packet.payload['position_ms'] as int? ?? 0;
          final hostPlaying = packet.payload['is_playing'] as bool? ?? false;
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

          // Интеллектуальное сглаживание рассинхрона (Drift Compensation):
          if (delta.abs() < 400) {
            // Разница < 400 мс — синхрон идеален!
            if (state.playbackRate != 1.0) player.setRate(1.0);
            emit(state.copyWith(syncStatus: SyncStatus.active));
          } else if (delta.abs() <= 3000) {
            // Разница 400–3000 мс: плавная подгонка скорости без заиканий
            final newRate = delta > 0 ? 1.08 : 0.92;
            if (state.playbackRate != newRate) player.setRate(newRate);
            emit(state.copyWith(syncStatus: SyncStatus.aligning));
          } else {
            // Разница > 3000 мс (хост мотанул или нажал пропуск опенинга)
            // Спойлер-щит (Blur Mode при рассинхроне/прыжке вперед более 15 сек):
            if (delta > 15000) {
              _activateSpoilerShield();
            }
            player.seek(Duration(milliseconds: estimatedHostPos));
            if (state.playbackRate != 1.0) player.setRate(1.0);
            emit(state.copyWith(syncStatus: SyncStatus.active));
          }
        }
        break;

      // Управление хоста (Play, Pause, Seek)
      case SyncActionTypes.controlAction:
        if (!state.isHost && !isFromSelf) {
          final act = packet.payload['control_action'] as String?;
          final posMs = packet.payload['position_ms'] as int?;

          if (act == 'play') {
            player.play();
          } else if (act == 'pause') {
            player.pause();
          } else if (act == 'seek' && posMs != null) {
            final diff = posMs - state.position.inMilliseconds;
            if (diff > 15000) {
              _activateSpoilerShield();
            }
            player.seek(Duration(milliseconds: posMs));
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

      // Летящая реакция (Floating Reaction)
      case SyncActionTypes.reaction:
        final emoji = packet.payload['emoji'] as String? ?? '❤️';
        final reactionId = packet.payload['id'] as String? ??
            '${DateTime.now().microsecondsSinceEpoch}';

        final reaction = FloatingReaction(
          id: reactionId,
          emoji: emoji,
          sender: packet.sender,
          startXOffset: 0.65 + (_random.nextDouble() * 0.25),
          timestamp: DateTime.now(),
        );

        final current = List<FloatingReaction>.from(state.activeReactions)..add(reaction);
        emit(state.copyWith(activeReactions: current));

        // Обновляем тепловую карту таймлайна реакцией от друга
        if (state.heatmap != null && state.duration.inSeconds > 0) {
          final updatedHeatmap = state.heatmap!.addReaction(
            timestampSec: state.position.inSeconds.toDouble(),
            totalDurationSec: state.duration.inSeconds.toDouble(),
            emoji: emoji,
            sender: packet.sender,
          );
          emit(state.copyWith(heatmap: () => updatedHeatmap));
        }

        // Удаление реакции после завершения анимации (3.5 сек)
        Timer(const Duration(milliseconds: 3500), () {
          if (!isClosed) {
            final filtered = List<FloatingReaction>.from(state.activeReactions)
              ..removeWhere((r) => r.id == reactionId);
            emit(state.copyWith(activeReactions: filtered));
          }
        });
        break;

      // Сообщение в чат (Twitch overlay chat)
      case SyncActionTypes.chatMessage:
        final text = packet.payload['text'] as String? ?? '';
        final msgId = packet.payload['id'] as String? ??
            '${DateTime.now().microsecondsSinceEpoch}';
        final isHostMsg = packet.payload['is_host'] as bool? ?? false;

        final message = ChatMessage(
          id: msgId,
          sender: packet.sender,
          text: text,
          isHost: isHostMsg,
          timestamp: DateTime.now(),
        );

        final updated = List<ChatMessage>.from(state.chatMessages)..add(message);
        if (updated.length > 50) updated.removeAt(0);
        emit(state.copyWith(chatMessages: updated));
        _addDanmaku(text, packet.sender);
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
          _switchEpisodeInternal(nextEp);
        }
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

  void _broadcastControlAction(String action) {
    if (state.isSyncRoom && state.isHost) {
      syncRepository?.sendControlAction(
        roomCode: state.roomCode!,
        action: action,
        positionMs: state.position.inMilliseconds,
        sender: 'Хост',
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

  Future<void> _loadCurrentEpisodeStream({Duration? initialPosition}) async {
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

    String? streamUrl = localFilePath ?? _getUrlForQuality(state.episode, state.selectedQuality);

    // Защита: отсекаем dummy-ссылки sample.com, которые приводят к падению декодера c2.mtk.avc.decoder
    if (streamUrl != null && streamUrl.contains('sample.com')) {
      streamUrl = null;
    }

    // Если прямая ссылка отсутствует или тайтл не имеет серий — пробуем загрузить рабочий тайтл через CatalogRepository
    if ((streamUrl == null || streamUrl.isEmpty) && getIt.isRegistered<CatalogRepository>()) {
      try {
        final catalog = getIt<CatalogRepository>();
        AnimeTitle? resolvedTitle;

        if (state.title.id > 0) {
          resolvedTitle = await catalog.getTitleDetails(id: state.title.id, code: state.title.code);
        } else {
          // Для комнат совместного просмотра без указанного тайтла берём свежий популярный релиз
          final updates = await catalog.getUpdates();
          if (updates.isNotEmpty) {
            final first = updates.first;
            resolvedTitle = await catalog.getTitleDetails(id: first.id, code: first.code);
          }
        }

        if (resolvedTitle != null && resolvedTitle.episodes.isNotEmpty) {
          final targetEp = resolvedTitle.episodes.firstWhere(
            (e) => e.episode == state.episode.episode,
            orElse: () => resolvedTitle!.episodes.first,
          );
          streamUrl = _getUrlForQuality(targetEp, state.selectedQuality);
          if (streamUrl != null && !streamUrl.contains('sample.com')) {
            emit(state.copyWith(
              title: resolvedTitle,
              episode: targetEp,
            ));
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

    try {
      final shouldPlay = !state.isSyncRoom || state.isHost;
      emit(state.copyWith(
        isBuffering: true,
        isPlaying: shouldPlay,
        errorMessage: () => null,
      ));
      await player.open(
        Media(
          streamUrl,
          start: (initialPosition != null && initialPosition > Duration.zero)
              ? initialPosition
              : null,
        ),
        play: shouldPlay,
      );
    } catch (e) {
      emit(state.copyWith(
        errorMessage: () => 'Ошибка запуска видеопотока: $e',
        isBuffering: false,
        isPlaying: false,
      ));
    }
  }

  /// Переключение варианта озвучки или студии (AniLibria / Kodik / StudioBand)
  /// Обновляет источник воспроизведения без пересоздания всего экрана и с сохранением позиции
  Future<void> changeTranslation(TranslationEntity newTranslation) async {
    final currentPos = state.position;
    emit(state.copyWith(
      currentTranslation: () => newTranslation,
    ));

    if (newTranslation.isDirectStream) {
      final streamUrl = newTranslation.getStreamForEpisode(state.episode.episode);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        try {
          await player.open(
            Media(
              streamUrl,
              start: currentPos > Duration.zero ? currentPos : null,
            ),
            play: state.isPlaying,
          );
        } catch (e) {
          emit(state.copyWith(
            errorMessage: () => 'Ошибка переключения потока: $e',
          ));
        }
      }
    } else {
      // Для iframe плееров (Kodik) ставим нативный плеер на паузу
      await player.pause();
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

  void playOrPause() {
    if (state.isSyncRoom && !state.isHost) {
      // Для гостя: отправляем запрос на паузу хосту
      requestPauseFromHost();
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
    if (state.isSyncRoom && !state.isHost) return;
    player.play();
    _broadcastControlAction('play');
    _resetControlsTimer();
  }

  void pause() {
    if (state.isSyncRoom && !state.isHost) {
      requestPauseFromHost();
      return;
    }
    player.pause();
    emit(state.copyWith(pauseCount: state.pauseCount + 1));
    _broadcastControlAction('pause');
    _resetControlsTimer();
  }

  void seek(Duration position) {
    if (state.isSyncRoom && !state.isHost) {
      // Гостю таймлайн заблокирован для предотвращения рассинхрона
      return;
    }

    player.seek(position);
    _broadcastControlAction('seek');
    _resetControlsTimer();
  }

  void seekRelative(int seconds) {
    if (state.isSyncRoom && !state.isHost) return;

    final current = state.position.inSeconds;
    final target = (current + seconds).clamp(0, state.duration.inSeconds);
    seek(Duration(seconds: target));
  }

  double _preFastForwardRate = 1.0;

  void setPlaybackRate(double rate) {
    player.setRate(rate);
    _resetControlsTimer();
  }

  /// Ускорение 2X при удержании экрана (Long Press)
  void start2xFastForward() {
    if (state.is2xFastForwarding) return;
    _preFastForwardRate = state.playbackRate;
    player.setRate(2.0);
    emit(state.copyWith(is2xFastForwarding: true));
  }

  /// Возврат к обычной скорости при отпускании
  void stop2xFastForward() {
    if (!state.is2xFastForwarding) return;
    player.setRate(_preFastForwardRate);
    emit(state.copyWith(is2xFastForwarding: false));
  }

  /// Отправить реакцию (🔥, 😂, 😱, 😭, ❤️)
  void sendReaction(String emoji) {
    HapticFeedback.lightImpact();

    // 1. Немедленно отображаем реакцию локально на экране
    final reactionId = '${DateTime.now().microsecondsSinceEpoch}';
    final reaction = FloatingReaction(
      id: reactionId,
      emoji: emoji,
      sender: 'Вы',
      startXOffset: 0.60 + (_random.nextDouble() * 0.30),
      timestamp: DateTime.now(),
    );
    final current = List<FloatingReaction>.from(state.activeReactions)..add(reaction);
    emit(state.copyWith(activeReactions: current, emojisSent: state.emojisSent + 1));

    Timer(const Duration(milliseconds: 3500), () {
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
        emoji: emoji,
        sender: state.isHost ? 'Хост' : (state.peerName ?? 'Вы'),
      );
      emit(state.copyWith(heatmap: () => updatedHeatmap));
    }

    // 3. Отправляем в сокет комнаты
    if (state.isSyncRoom && state.roomCode != null) {
      syncRepository?.sendReaction(
        roomCode: state.roomCode!,
        emoji: emoji,
        sender: state.isHost ? 'Хост' : (state.peerName ?? 'Гость'),
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

  /// Отправить текстовое сообщение в чат и запустить бегущую строку (Danmaku)
  void sendChatMessage(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final sender = state.isHost ? 'Хост' : (state.peerName ?? 'Гость');
    _addDanmaku(clean, sender);

    if (state.isSyncRoom && state.roomCode != null) {
      syncRepository?.sendChatMessage(
        roomCode: state.roomCode!,
        text: clean,
        sender: sender,
        isHost: state.isHost,
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

  void _updateDiscordPresence() {
    try {
      DiscordRpcService.instance.updatePresence(
        animeTitle: state.title.displayTitle,
        episodeNumber: state.episode.episode,
        roomCode: state.roomCode,
        currentPeers: state.isSyncRoom ? 2 : 1,
        maxPeers: 2,
        isPaused: !state.isPlaying,
        position: state.position,
        duration: state.duration,
      );
    } catch (_) {}
  }

  /// Запрос паузы от ведомого гостя
  void requestPauseFromHost() {
    if (state.isSyncRoom && !state.isHost) {
      player.pause();
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

  /// Проверка окончания серии для авто-перехода (Auto Next Episode)
  void _checkAutoNextEpisode(Duration pos) {
    if (!state.isSyncRoom) return;

    final dur = state.duration;
    if (dur <= const Duration(seconds: 20)) return;

    final remaining = dur - pos;
    // Эффект Зейгарник: Автоплей стартует за 15 секунд до конца эндинга с обратным отсчетом
    if (remaining.inSeconds <= 15 && remaining.inSeconds >= 0 && state.autoNextCountdown == null) {
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
        if (state.isHost) {
          playNextEpisode(nextEp);
        }
      } else {
        emit(state.copyWith(autoNextCountdown: () => current - 1));
      }
    });
  }

  /// Отмена авто-перехода
  void cancelAutoNextCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
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
    if (state.isSyncRoom && !state.isHost) return;

    if (state.isSyncRoom && state.isHost) {
      syncRepository?.sendChangeEpisode(
        roomCode: state.roomCode!,
        episodeNumber: nextEpisode.episode,
        quality: state.selectedQuality.name,
        sender: 'Хост',
      );
    }

    await _switchEpisodeInternal(nextEpisode);
  }

  Future<void> _switchEpisodeInternal(EpisodeItem nextEpisode) async {
    cancelAutoNextCountdown();

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

  void _resetControlsTimer() {
    if (state.areControlsVisible) {
      _startControlsTimer();
    }
  }

  bool _isDisposing = false;

  @override
  Future<void> close() async {
    if (_isDisposing) return;
    _isDisposing = true;
    _controlsTimer?.cancel();
    _heartbeatTimer?.cancel();
    _countdownTimer?.cancel();
    _quickPhraseTimer?.cancel();
    await _presenceSubscription?.cancel();
    await _packetSubscription?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
    return super.close();
  }
}
