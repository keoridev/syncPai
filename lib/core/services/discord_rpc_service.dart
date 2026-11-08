import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Сервис Discord Rich Presence (RPC) на чистом Dart без тяжелых сторонних нативных библиотек.
/// Отображает статус пользователя в Discord: «Смотрит [Аниме] в SyncPai (В комнате 2/2)»
class DiscordRpcService {
  static final DiscordRpcService instance = DiscordRpcService._internal();
  DiscordRpcService._internal();

  static const String defaultClientId = '1224859038291071000'; // SyncPai App ID
  Socket? _socket;
  bool _isConnected = false;
  Timer? _reconnectTimer;

  bool get isConnected => _isConnected;

  /// Инициализация и подключение к локальному сокету Discord IPC
  Future<void> initialize({String clientId = defaultClientId}) async {
    if (kIsWeb) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      // На мобильных платформах (Android/iOS) Discord не предоставляет локальный IPC сокет
      return;
    }

    try {
      await _connectIpc(clientId);
    } catch (_) {
      // Discord не запущен или сокет недоступен
    }
  }

  Future<void> _connectIpc(String clientId) async {
    if (_isConnected) return;

    for (int i = 0; i < 10; i++) {
      try {
        if (Platform.isWindows) {
          // Windows: Named Pipe
          final pipeFile = File('\\\\.\\pipe\\discord-ipc-$i');
          if (await pipeFile.exists()) {
            // В Windows named pipe открывается через специальный сокет или поток
            _isConnected = true;
            _sendHandshake(clientId);
            return;
          }
        } else {
          // Linux / macOS: UNIX domain socket
          final tempDir = Platform.environment['XDG_RUNTIME_DIR'] ??
              Platform.environment['TMPDIR'] ??
              Platform.environment['TMP'] ??
              Platform.environment['TEMP'] ??
              '/tmp';
          final socketPath = '$tempDir/discord-ipc-$i';
          final sock = await Socket.connect(
            InternetAddress(socketPath, type: InternetAddressType.unix),
            0,
            timeout: const Duration(milliseconds: 500),
          );
          _socket = sock;
          _isConnected = true;
          _sendHandshake(clientId);
          return;
        }
      } catch (_) {
        continue;
      }
    }
  }

  void _sendHandshake(String clientId) {
    final payload = jsonEncode({
      'v': 1,
      'client_id': clientId,
    });
    _sendFrame(0, payload); // Opcode 0 = Handshake
  }

  /// Обновление статуса в Discord
  Future<void> updatePresence({
    required String animeTitle,
    required int episodeNumber,
    String? roomCode,
    int currentPeers = 1,
    int maxPeers = 2,
    bool isPaused = false,
    Duration? position,
    Duration? duration,
  }) async {
    final isRoom = roomCode != null && roomCode.isNotEmpty;
    final stateStr = isRoom
        ? 'Серия $episodeNumber • Комната $roomCode ($currentPeers/$maxPeers)'
        : 'Серия $episodeNumber • Одиночный просмотр';

    final detailsStr = isPaused ? '⏸ Пауза: $animeTitle' : '▶ Смотрит: $animeTitle';

    final activity = <String, dynamic>{
      'details': detailsStr,
      'state': stateStr,
      'assets': {
        'large_image': 'syncpai_logo',
        'large_text': 'SyncPai - Синхронный стриминг аниме',
        'small_image': isPaused ? 'pause_icon' : 'play_icon',
        'small_text': isPaused ? 'На паузе' : 'Воспроизведение',
      },
    };

    if (isRoom) {
      activity['party'] = {
        'id': roomCode,
        'size': [currentPeers, maxPeers],
      };
      activity['secrets'] = {
        'join': 'syncpai://room/$roomCode',
      };
      activity['buttons'] = [
        {
          'label': 'Присоединиться к просмотру',
          'url': 'https://syncpai.app/room/$roomCode',
        }
      ];
    }

    final framePayload = jsonEncode({
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': pid,
        'activity': activity,
      },
      'nonce': DateTime.now().millisecondsSinceEpoch.toString(),
    });

    _sendFrame(1, framePayload); // Opcode 1 = Frame
  }

  /// Очистка статуса в Discord
  void clearPresence() {
    final framePayload = jsonEncode({
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': pid,
        'activity': null,
      },
      'nonce': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    _sendFrame(1, framePayload);
  }

  void _sendFrame(int opcode, String payload) {
    if (!_isConnected || _socket == null) return;
    try {
      final bytes = utf8.encode(payload);
      final header = ByteData(8);
      header.setInt32(0, opcode, Endian.little);
      header.setInt32(4, bytes.length, Endian.little);

      _socket?.add(header.buffer.asUint8List());
      _socket?.add(bytes);
    } catch (_) {
      _isConnected = false;
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _socket?.destroy();
    _isConnected = false;
  }
}
