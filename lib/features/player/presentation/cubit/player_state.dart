import 'package:equatable/equatable.dart';
import 'package:sync_pai/core/widgets/sync_badge.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/domain/entities/translation_entity.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/player/domain/entities/reaction_heatmap.dart';
import 'package:sync_pai/features/player/presentation/widgets/danmaku_overlay_layer.dart';
import 'package:sync_pai/features/sync_room/domain/entities/sync_protocol.dart';

class PlayerState extends Equatable {
  final AnimeTitle title;
  final EpisodeItem episode;
  final PlayerQuality selectedQuality;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final double playbackRate;
  final bool areControlsVisible;
  final String? errorMessage;

  // Supabase BFF агрегатор переводов и балансеров
  final List<TranslationEntity> translations;
  final TranslationEntity? currentTranslation;

  // Realtime Совместный просмотр (Sync Room)
  final String? roomCode;
  final bool isHost;
  final SyncStatus syncStatus;
  final String? peerName;
  final bool isPeerBuffering;
  final String? bufferNotice;
  final List<ChatMessage> chatMessages;
  final List<FloatingReaction> activeReactions;
  final bool isChatOverlayVisible;

  // Danmaku бегущие комментарии и телеметрия пинга
  final bool isDanmakuEnabled;
  final List<DanmakuItem> danmakuMessages;
  final int peerPingMs;

  // 1. Presence онлайн-радар
  final PeerPresence? peerPresence;
  final bool isPeerAway;

  // 2. Ламповые быстрые фразы (шорткаты)
  final QuickPhraseToast? activeQuickPhrase;

  // 3. Авто-переход на следующую серию
  final int? autoNextCountdown;
  final EpisodeItem? nextEpisode;

  // 4. Тепловая карта эмоций на таймлайне (SoundCloud-style)
  final ReactionHeatmap? heatmap;

  // 5. Голосовой шёпот (WebRTC / Voice Chat)
  final bool isVoiceMuted;
  final bool isPeerTalking;
  final bool isTalking;

  // 6. Ускорение 2X при удержании (Long Press Fast Forward)
  final bool is2xFastForwarding;

  // 7. Жесты: громкость и яркость
  final double volume;
  final double brightness;

  // 8. Психология, геймификация и анти-АФК
  final int awaySecondsCount;
  final bool isSpoilerShieldActive;
  final int coopSkipVotes;
  final bool hasVotedCoopSkip;
  final String? pokeNudgeMessage;
  final bool showWatchPartyStats;
  final int pauseCount;
  final int emojisSent;

  const PlayerState({
    required this.title,
    required this.episode,
    this.selectedQuality = PlayerQuality.fhd,
    this.isPlaying = false,
    this.isBuffering = true,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.playbackRate = 1.0,
    this.areControlsVisible = true,
    this.errorMessage,
    this.translations = const [],
    this.currentTranslation,
    this.roomCode,
    this.isHost = true,
    this.syncStatus = SyncStatus.active,
    this.peerName,
    this.isPeerBuffering = false,
    this.bufferNotice,
    this.chatMessages = const [],
    this.activeReactions = const [],
    this.isChatOverlayVisible = true,
    this.isDanmakuEnabled = true,
    this.danmakuMessages = const [],
    this.peerPingMs = 28,
    this.peerPresence,
    this.isPeerAway = false,
    this.activeQuickPhrase,
    this.autoNextCountdown,
    this.nextEpisode,
    this.heatmap,
    this.isVoiceMuted = true,
    this.isPeerTalking = false,
    this.isTalking = false,
    this.is2xFastForwarding = false,
    this.volume = 100.0,
    this.brightness = 1.0,
    this.awaySecondsCount = 0,
    this.isSpoilerShieldActive = false,
    this.coopSkipVotes = 0,
    this.hasVotedCoopSkip = false,
    this.pokeNudgeMessage,
    this.showWatchPartyStats = false,
    this.pauseCount = 0,
    this.emojisSent = 0,
  });

  bool get isSyncRoom => roomCode != null && roomCode!.isNotEmpty;

  PlayerState copyWith({
    AnimeTitle? title,
    EpisodeItem? episode,
    PlayerQuality? selectedQuality,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    Duration? buffer,
    double? playbackRate,
    bool? areControlsVisible,
    String? Function()? errorMessage,
    List<TranslationEntity>? translations,
    TranslationEntity? Function()? currentTranslation,
    String? roomCode,
    bool? isHost,
    SyncStatus? syncStatus,
    String? peerName,
    bool? isPeerBuffering,
    String? Function()? bufferNotice,
    List<ChatMessage>? chatMessages,
    List<FloatingReaction>? activeReactions,
    bool? isChatOverlayVisible,
    bool? isDanmakuEnabled,
    List<DanmakuItem>? danmakuMessages,
    int? peerPingMs,
    PeerPresence? Function()? peerPresence,
    bool? isPeerAway,
    QuickPhraseToast? Function()? activeQuickPhrase,
    int? Function()? autoNextCountdown,
    EpisodeItem? Function()? nextEpisode,
    ReactionHeatmap? Function()? heatmap,
    bool? isVoiceMuted,
    bool? isPeerTalking,
    bool? isTalking,
    bool? is2xFastForwarding,
    double? volume,
    double? brightness,
    int? awaySecondsCount,
    bool? isSpoilerShieldActive,
    int? coopSkipVotes,
    bool? hasVotedCoopSkip,
    String? Function()? pokeNudgeMessage,
    bool? showWatchPartyStats,
    int? pauseCount,
    int? emojisSent,
  }) {
    return PlayerState(
      title: title ?? this.title,
      episode: episode ?? this.episode,
      selectedQuality: selectedQuality ?? this.selectedQuality,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffer: buffer ?? this.buffer,
      playbackRate: playbackRate ?? this.playbackRate,
      areControlsVisible: areControlsVisible ?? this.areControlsVisible,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      translations: translations ?? this.translations,
      currentTranslation: currentTranslation != null ? currentTranslation() : this.currentTranslation,
      roomCode: roomCode ?? this.roomCode,
      isHost: isHost ?? this.isHost,
      syncStatus: syncStatus ?? this.syncStatus,
      peerName: peerName ?? this.peerName,
      isPeerBuffering: isPeerBuffering ?? this.isPeerBuffering,
      bufferNotice: bufferNotice != null ? bufferNotice() : this.bufferNotice,
      chatMessages: chatMessages ?? this.chatMessages,
      activeReactions: activeReactions ?? this.activeReactions,
      isChatOverlayVisible: isChatOverlayVisible ?? this.isChatOverlayVisible,
      isDanmakuEnabled: isDanmakuEnabled ?? this.isDanmakuEnabled,
      danmakuMessages: danmakuMessages ?? this.danmakuMessages,
      peerPingMs: peerPingMs ?? this.peerPingMs,
      peerPresence: peerPresence != null ? peerPresence() : this.peerPresence,
      isPeerAway: isPeerAway ?? this.isPeerAway,
      activeQuickPhrase: activeQuickPhrase != null ? activeQuickPhrase() : this.activeQuickPhrase,
      autoNextCountdown: autoNextCountdown != null ? autoNextCountdown() : this.autoNextCountdown,
      nextEpisode: nextEpisode != null ? nextEpisode() : this.nextEpisode,
      heatmap: heatmap != null ? heatmap() : this.heatmap,
      isVoiceMuted: isVoiceMuted ?? this.isVoiceMuted,
      isPeerTalking: isPeerTalking ?? this.isPeerTalking,
      isTalking: isTalking ?? this.isTalking,
      is2xFastForwarding: is2xFastForwarding ?? this.is2xFastForwarding,
      volume: volume ?? this.volume,
      brightness: brightness ?? this.brightness,
      awaySecondsCount: awaySecondsCount ?? this.awaySecondsCount,
      isSpoilerShieldActive: isSpoilerShieldActive ?? this.isSpoilerShieldActive,
      coopSkipVotes: coopSkipVotes ?? this.coopSkipVotes,
      hasVotedCoopSkip: hasVotedCoopSkip ?? this.hasVotedCoopSkip,
      pokeNudgeMessage: pokeNudgeMessage != null ? pokeNudgeMessage() : this.pokeNudgeMessage,
      showWatchPartyStats: showWatchPartyStats ?? this.showWatchPartyStats,
      pauseCount: pauseCount ?? this.pauseCount,
      emojisSent: emojisSent ?? this.emojisSent,
    );
  }

  @override
  List<Object?> get props => [
        title,
        episode,
        selectedQuality,
        isPlaying,
        isBuffering,
        position,
        duration,
        buffer,
        playbackRate,
        areControlsVisible,
        errorMessage,
        translations,
        currentTranslation,
        roomCode,
        isHost,
        syncStatus,
        peerName,
        isPeerBuffering,
        bufferNotice,
        chatMessages,
        activeReactions,
        isChatOverlayVisible,
        isDanmakuEnabled,
        danmakuMessages,
        peerPingMs,
        peerPresence,
        isPeerAway,
        activeQuickPhrase,
        autoNextCountdown,
        nextEpisode,
        heatmap,
        isVoiceMuted,
        isPeerTalking,
        isTalking,
        is2xFastForwarding,
        volume,
        brightness,
        awaySecondsCount,
        isSpoilerShieldActive,
        coopSkipVotes,
        hasVotedCoopSkip,
        pokeNudgeMessage,
        showWatchPartyStats,
        pauseCount,
        emojisSent,
      ];
}
