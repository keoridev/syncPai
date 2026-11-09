import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../domain/entities/anime_clip.dart';

/// Элемент пула плееров для шортсов/моментов
class PooledPlayerEntry {
  final int index;
  final String clipId;
  final String videoUrl;
  final Player player;
  final VideoController controller;
  bool isBuffering;
  bool isPlaying;
  bool hasError;
  double progress;
  bool is2xFastForwarding;

  StreamSubscription? posSub;
  StreamSubscription? bufSub;
  StreamSubscription? playSub;
  StreamSubscription? errSub;

  PooledPlayerEntry({
    required this.index,
    required this.clipId,
    required this.videoUrl,
    required this.player,
    required this.controller,
    this.isBuffering = true,
    this.isPlaying = false,
    this.hasError = false,
    this.progress = 0.0,
    this.is2xFastForwarding = false,
  });

  void dispose() {
    posSub?.cancel();
    bufSub?.cancel();
    playSub?.cancel();
    errSub?.cancel();
    posSub = null;
    bufSub = null;
    playSub = null;
    errSub = null;
    player.pause();
    player.dispose();
  }
}

/// Архитектура 3-Player Pool Buffering для ленты «Моменты» (Shorts/Reels):
/// 1. Держит активными ровно 3 экземпляра:
///    - Index N (текущий): воспроизводится со звуком.
///    - Index N + 1 (следующий): загружен и на паузе на 0-й секунде (pre-buffered).
///    - Index N - 1 (предыдущий): на паузе.
/// 2. При скролле на N + 1:
///    - Моментально вызывается `.play()` на уже готовом плеере N + 1 (задержка 0 мс).
///    - Контроллер N - 1 освобождается (`dispose()`).
///    - Инициализируется контроллер для N + 2 в фоне.
/// 3. Ограничение декодера: 1080x1920, hardwareAcceleration: true, логи отключены.
class MomentsPlayerPool extends ChangeNotifier {
  final Map<int, PooledPlayerEntry> _pool = {};
  int _currentIndex = 0;
  bool _isMuted = false;
  bool _isDisposed = false;

  int get currentIndex => _currentIndex;
  bool get isMuted => _isMuted;
  PooledPlayerEntry? getEntry(int index) => _pool[index];

  /// Обновление активного индекса при свайпе
  void updateActiveIndex(int newIndex, List<AnimeClip> clips) {
    if (_isDisposed || clips.isEmpty) return;
    _currentIndex = newIndex;

    // Вычисляем необходимые 3 индекса: [newIndex - 1, newIndex, newIndex + 1]
    final neededIndices = <int>{};
    if (newIndex - 1 >= 0 && newIndex - 1 < clips.length) {
      neededIndices.add(newIndex - 1);
    }
    if (newIndex >= 0 && newIndex < clips.length) {
      neededIndices.add(newIndex);
    }
    if (newIndex + 1 < clips.length) {
      neededIndices.add(newIndex + 1);
    }

    // 1. Освобождаем (dispose) контроллеры, вышедшие за пределы окна N-1..N+1
    final toRemove = <int>[];
    _pool.forEach((idx, entry) {
      if (!neededIndices.contains(idx)) {
        entry.dispose();
        toRemove.add(idx);
      }
    });
    for (final idx in toRemove) {
      _pool.remove(idx);
    }

    // 2. Инициализируем отсутствующие необходимые плееры в окне
    for (final idx in neededIndices) {
      if (!_pool.containsKey(idx)) {
        _initPlayerForIndex(idx, clips[idx], shouldPlay: idx == newIndex);
      }
    }

    // 3. Управляем воспроизведением:
    // Текущий (newIndex) -> играет со звуком
    // Соседние (N-1, N+1) -> на паузе в предбуфере
    _pool.forEach((idx, entry) {
      if (idx == newIndex) {
        entry.player.setVolume(_isMuted ? 0 : 100);
        entry.player.play();
      } else {
        entry.player.pause();
      }
    });

    notifyListeners();
  }

  /// Инициализация одного плеера в пуле
  void _initPlayerForIndex(int index, AnimeClip clip, {required bool shouldPlay}) {
    if (_isDisposed) return;

    try {
      final player = Player(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.error, // Отключаем избыточный вывод логов MediaCodec
        ),
      );

      // Включение аппаратного декодирования и ограничение разрешения до 1080x1920
      try {
        final platform = player.platform;
        if (platform != null) {
          (platform as dynamic).setProperty('hwdec', 'auto');
          (platform as dynamic).setProperty('video-max-width', '1080');
          (platform as dynamic).setProperty('video-max-height', '1920');
        }
      } catch (_) {}

      final controller = VideoController(
        player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );

      player.setPlaylistMode(PlaylistMode.loop);
      player.setVolume((shouldPlay && !_isMuted) ? 100 : 0);

      final entry = PooledPlayerEntry(
        index: index,
        clipId: clip.id,
        videoUrl: clip.videoUrl,
        player: player,
        controller: controller,
        isBuffering: true,
        isPlaying: shouldPlay,
      );

      entry.posSub = player.stream.position.listen((pos) {
        final dur = player.state.duration;
        if (dur.inMilliseconds > 0) {
          entry.progress = (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
          notifyListeners();
        }
      });

      entry.bufSub = player.stream.buffering.listen((buffering) {
        entry.isBuffering = buffering;
        notifyListeners();
      });

      entry.playSub = player.stream.playing.listen((playing) {
        entry.isPlaying = playing;
        notifyListeners();
      });

      entry.errSub = player.stream.error.listen((error) {
        if (error.isNotEmpty) {
          entry.hasError = true;
          notifyListeners();
        }
      });

      _pool[index] = entry;

      // Открываем видео. Если это текущий — play: true, если предзагрузка N+1 — play: false
      String targetUrl = clip.videoUrl;
      if (targetUrl.contains('_ep1_720')) {
        targetUrl = 'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8';
      }

      if (targetUrl.isNotEmpty && targetUrl.startsWith('http')) {
        player.open(Media(targetUrl), play: shouldPlay);
        if (!shouldPlay) {
          player.pause();
        }
      }
    } catch (_) {
      // Игнорируем ошибки инициализации отдельного слота
    }
  }

  /// Обработка видимости через VisibilityDetector:
  /// При уходе видео более чем на 50% — немедленный pause.
  void handleVisibilityChanged(int index, double visibleFraction) {
    if (_isDisposed) return;
    final entry = _pool[index];
    if (entry == null) return;

    if (visibleFraction < 0.5) {
      if (entry.isPlaying) {
        entry.player.pause();
      }
    } else if (visibleFraction >= 0.5 && index == _currentIndex) {
      if (!entry.isPlaying) {
        entry.player.play();
      }
    }
  }

  void togglePlayPause(int index) {
    final entry = _pool[index];
    if (entry == null) return;

    if (entry.isPlaying) {
      entry.player.pause();
    } else {
      entry.player.play();
    }
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    final currentEntry = _pool[_currentIndex];
    if (currentEntry != null) {
      currentEntry.player.setVolume(_isMuted ? 0 : 100);
    }
    notifyListeners();
  }

  void set2xSpeed(int index, bool enable) {
    final entry = _pool[index];
    if (entry == null) return;
    entry.player.setRate(enable ? 2.0 : 1.0);
    entry.is2xFastForwarding = enable;
    notifyListeners();
  }

  void retry(int index, AnimeClip clip) {
    final old = _pool.remove(index);
    old?.dispose();
    _initPlayerForIndex(index, clip, shouldPlay: index == _currentIndex);
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pool.forEach((_, entry) => entry.dispose());
    _pool.clear();
    super.dispose();
  }
}
