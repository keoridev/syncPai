import '../entities/sync_event.dart';
import '../entities/sync_protocol.dart';
import '../entities/sync_room.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../player/domain/entities/player_quality.dart';

abstract class SyncRoomRepository {
  /// Создать новую комнату совместного просмотра (Я хост)
  Future<SyncRoom> createRoom({
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality quality = PlayerQuality.hd,
    String hostName = 'Хост (Вы)',
  });

  /// Получить информацию о комнате по ее 6-значному коду
  Future<SyncRoom?> getRoom(String code);

  /// Валидация существования комнаты перед входом (предотвращение входа в призрачные комнаты)
  Future<bool> validateRoomExists(String code);

  /// Присоединиться к существующей комнате (Я гость)
  Future<SyncRoom> joinRoom({
    required String code,
    String peerName = 'Друг',
  });

  /// Подписка на высокоуровневые события состояния комнаты (PEER_JOINED, PEER_LEFT...)
  Stream<SyncEvent> subscribeToRoom(String roomCode);

  /// Подписка на поток сетевых пакетов реального времени (Supabase Broadcast / WebSocket)
  Stream<SyncPacket> subscribeToPackets(String roomCode);

  /// Отправка произвольного пакета
  Future<void> sendPacket(SyncPacket packet);

  /// HEARTBEAT: хост каждые 2.5 секунды транслирует позицию и статус
  Future<void> sendHeartbeat({
    required String roomCode,
    required int positionMs,
    required bool isPlaying,
    required double rate,
    required String sender,
  });

  /// CONTROL_ACTION: хост нажал Play / Pause / Seek
  Future<void> sendControlAction({
    required String roomCode,
    required String action,
    required int positionMs,
    required String sender,
  });

  /// Отправка быстрого Broadcast-события синхронизации плеера по WebSockets (sync_player)
  Future<void> sendSyncEvent({
    required String roomCode,
    required double time,
    required bool isPlaying,
  });

  /// Отправка события синхронизации плеера (playback_sync) по PIN-коду комнаты
  Future<void> broadcastPlayback({
    required String roomCode,
    required double time,
    required bool isPlaying,
    required int episode,
  }) async {
    await sendSyncEvent(roomCode: roomCode, time: time, isPlaying: isPlaying);
  }

  /// Подписка на Realtime-канал синхронизации плеера (playback_sync) по PIN-коду
  void subscribeToPlaybackSync(
    String pinCode, {
    required void Function(double time, bool isPlaying, int episode) onSyncReceived,
  }) {}

  /// BUFFER_WAIT / BUFFER_READY: состояние буферизации
  Future<void> sendBufferState({
    required String roomCode,
    required bool isBuffering,
    required String sender,
  });

  /// REACTION: отправка летящих эмодзи
  Future<void> sendReaction({
    required String roomCode,
    required String emoji,
    required String sender,
  });

  /// CHAT_MESSAGE: отправка сообщения в Twitch-чат
  Future<void> sendChatMessage({
    required String roomCode,
    required String text,
    required String sender,
    bool isHost = false,
  });

  /// REQUEST_PAUSE: запрос гостя на паузу
  Future<void> sendRequestPause({
    required String roomCode,
    required String sender,
  });

  /// CHANGE_EPISODE: синхронная смена серии в комнате (Auto Next Episode)
  Future<void> sendChangeEpisode({
    required String roomCode,
    required int episodeNumber,
    required String quality,
    required String sender,
  });

  /// QUICK_PHRASE: отправка шортката быстрой фразы (с авто-показом плашки на 3 секунды)
  Future<void> sendQuickPhrase({
    required String roomCode,
    required String phrase,
    String? emoji,
    required String sender,
  });

  /// Подписка на онлайн-радар присутствия участников (Supabase Presence)
  Stream<List<PeerPresence>> subscribeToPresence(String roomCode);

  /// Обновление статуса присутствия участника (В сети / Отошел)
  Future<void> updatePresence({
    required String roomCode,
    required PeerPresence presence,
  });

  /// Отправка события в комнату
  void emitEvent(SyncEvent event);

  /// Отправка команды немедленного одновременного старта воспроизведения для всех участников лобби
  Future<void> startPlayback(String roomCode);

  /// Выход из комнаты / закрытие
  Future<void> leaveRoom(String roomCode);

  /// Симуляция подключения друга (для быстрого тестирования)
  void simulatePeerJoin(String roomCode, {String peerName = 'Сенпай'});
}
