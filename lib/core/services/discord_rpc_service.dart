import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di/injection.dart';

typedef _CreateFileANative = ffi.IntPtr Function(
  ffi.Pointer<ffi.Uint8> lpFileName,
  ffi.Uint32 dwDesiredAccess,
  ffi.Uint32 dwShareMode,
  ffi.Pointer<ffi.Void> lpSecurityAttributes,
  ffi.Uint32 dwCreationDisposition,
  ffi.Uint32 dwFlagsAndAttributes,
  ffi.IntPtr hTemplateFile,
);
typedef _CreateFileADart = int Function(
  ffi.Pointer<ffi.Uint8> lpFileName,
  int dwDesiredAccess,
  int dwShareMode,
  ffi.Pointer<ffi.Void> lpSecurityAttributes,
  int dwCreationDisposition,
  int dwFlagsAndAttributes,
  int hTemplateFile,
);

typedef _WriteFileNative = ffi.Int32 Function(
  ffi.IntPtr hFile,
  ffi.Pointer<ffi.Uint8> lpBuffer,
  ffi.Uint32 nNumberOfBytesToWrite,
  ffi.Pointer<ffi.Uint32> lpNumberOfBytesWritten,
  ffi.Pointer<ffi.Void> lpOverlapped,
);
typedef _WriteFileDart = int Function(
  int hFile,
  ffi.Pointer<ffi.Uint8> lpBuffer,
  int nNumberOfBytesToWrite,
  ffi.Pointer<ffi.Uint32> lpNumberOfBytesWritten,
  ffi.Pointer<ffi.Void> lpOverlapped,
);

typedef _CloseHandleNative = ffi.Int32 Function(ffi.IntPtr hObject);
typedef _CloseHandleDart = int Function(int hObject);

/// Лёгкий Windows-сервис Discord Rich Presence через локальный Named Pipe (`discord-ipc-0..9`).
/// Работает без внешних DLL и безопасно отключается, если Discord не установлен или закрыт.
class DiscordRpcService extends ChangeNotifier {
  static final DiscordRpcService instance = DiscordRpcService._();
  DiscordRpcService._();

  static const String _prefEnabledKey = 'settings_discord_rpc_enabled';
  static const String _clientId = '1310000000000000000';
  static const int _invalidHandle = -1;

  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;

  int _pipeHandle = _invalidHandle;
  bool _handshakeSent = false;
  int _nonce = 0;

  ffi.DynamicLibrary? _kernel32;
  _CreateFileADart? _createFileA;
  _WriteFileDart? _writeFile;
  _CloseHandleDart? _closeHandle;

  bool get _isWindows => !kIsWeb && Platform.isWindows;

  Future<void> init() async {
    if (!_isWindows) return;
    try {
      final prefs = getIt.isRegistered<SharedPreferences>()
          ? getIt<SharedPreferences>()
          : await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefEnabledKey) ?? true;
      notifyListeners();
    } catch (_) {}

    if (_isEnabled) {
      await setBrowsing();
    }
  }

  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    notifyListeners();
    try {
      final prefs = getIt.isRegistered<SharedPreferences>()
          ? getIt<SharedPreferences>()
          : await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabledKey, value);
    } catch (_) {}

    if (!value) {
      await clear();
    } else {
      await setBrowsing();
    }
  }

  Future<void> setBrowsing() async {
    await _sendActivity({
      'details': 'Выбирает аниме в SyncPai',
      'state': 'Каталог • Windows Desktop',
      'assets': {
        'large_image': 'syncpai_logo',
        'large_text': 'SyncPai',
      },
    });
  }

  Future<void> setWatchingSolo({
    required String title,
    required int episodeNumber,
    int? totalEpisodes,
    String? posterUrl,
    bool isPaused = false,
    Duration? position,
    Duration? duration,
  }) async {
    final epState = isPaused
        ? 'На паузе • Серия $episodeNumber'
        : (totalEpisodes != null && totalEpisodes > 0
            ? 'Серия $episodeNumber из $totalEpisodes'
            : 'Серия $episodeNumber');

    final activity = <String, dynamic>{
      'details': title,
      'state': epState,
      'assets': {
        'large_image': (posterUrl != null && posterUrl.startsWith('https://'))
            ? posterUrl
            : 'syncpai_logo',
        'large_text': title,
      },
    };

    if (!isPaused &&
        duration != null &&
        duration > Duration.zero &&
        position != null) {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remainingSec = (duration - position).inSeconds.clamp(0, 86400);
      activity['timestamps'] = {
        'start': nowSec - position.inSeconds.clamp(0, 86400),
        'end': nowSec + remainingSec,
      };
    }

    await _sendActivity(activity);
  }

  Future<void> setWatchingTogether({
    required String title,
    required int episodeNumber,
    required String roomCode,
    required String roomId,
    required int participantsCount,
    String? posterUrl,
  }) async {
    await _sendActivity({
      'details': title,
      'state': 'Смотрит вместе • Серия $episodeNumber (Код: $roomCode)',
      'assets': {
        'large_image': (posterUrl != null && posterUrl.startsWith('https://'))
            ? posterUrl
            : 'syncpai_logo',
        'large_text': title,
      },
      'party': {
        'id': roomId,
        'size': [participantsCount.clamp(1, 10), 10],
      },
    });
  }

  Future<void> clear() async {
    if (!_isWindows || _pipeHandle == _invalidHandle) return;
    _writeIpcFrame(1, {
      'cmd': 'SET_ACTIVITY',
      'args': {'pid': pid, 'activity': null},
      'nonce': '${++_nonce}',
    });
    _closePipe();
  }

  void disposeService() {
    _closePipe();
  }

  Future<void> _sendActivity(Map<String, dynamic> activity) async {
    if (!_isWindows || !_isEnabled) return;
    try {
      if (!_ensureConnected()) return;
      final ok = _writeIpcFrame(1, {
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': pid,
          'activity': activity,
        },
        'nonce': '${++_nonce}',
      });
      if (!ok) {
        _closePipe();
      }
    } catch (_) {
      _closePipe();
    }
  }

  bool _ensureConnected() {
    if (_pipeHandle != _invalidHandle && _handshakeSent) return true;
    _initWin32();
    if (_createFileA == null || _writeFile == null || _closeHandle == null) {
      return false;
    }

    for (int i = 0; i < 10; i++) {
      final pathBytes = utf8.encode('\\\\.\\pipe\\discord-ipc-$i\x00');
      final ptr = _allocBytes(pathBytes);
      if (ptr == null) return false;
      final handle = _createFileA!(
        ptr,
        0xC0000000, // GENERIC_READ | GENERIC_WRITE
        0,
        ffi.nullptr,
        3, // OPEN_EXISTING
        0,
        0,
      );
      _freeBytes(ptr);
      if (handle != _invalidHandle && handle != 0) {
        _pipeHandle = handle;
        _handshakeSent = _writeIpcFrame(0, {'v': 1, 'client_id': _clientId});
        if (_handshakeSent) return true;
        _closePipe();
      }
    }
    return false;
  }

  void _initWin32() {
    if (_kernel32 != null) return;
    try {
      _kernel32 = ffi.DynamicLibrary.open('kernel32.dll');
      _createFileA = _kernel32!
          .lookupFunction<_CreateFileANative, _CreateFileADart>('CreateFileA');
      _writeFile = _kernel32!
          .lookupFunction<_WriteFileNative, _WriteFileDart>('WriteFile');
      _closeHandle = _kernel32!
          .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
    } catch (_) {}
  }

  bool _writeIpcFrame(int opcode, Map<String, dynamic> payload) {
    if (_pipeHandle == _invalidHandle || _writeFile == null) return false;
    final body = utf8.encode(jsonEncode(payload));
    final packet = ByteData(8 + body.length);
    packet.setUint32(0, opcode, Endian.little);
    packet.setUint32(4, body.length, Endian.little);
    final bytes = packet.buffer.asUint8List();
    bytes.setRange(8, 8 + body.length, body);

    final ptr = _allocBytes(bytes);
    final writtenPtr = _allocUint32();
    if (ptr == null || writtenPtr == null) {
      if (ptr != null) _freeBytes(ptr);
      if (writtenPtr != null) _freeBytes(writtenPtr);
      return false;
    }
    try {
      final res = _writeFile!(
        _pipeHandle,
        ptr,
        bytes.length,
        writtenPtr,
        ffi.nullptr,
      );
      return res != 0;
    } finally {
      _freeBytes(ptr);
      _freeBytes(writtenPtr);
    }
  }

  void _closePipe() {
    if (_pipeHandle != _invalidHandle && _closeHandle != null) {
      try {
        _closeHandle!(_pipeHandle);
      } catch (_) {}
    }
    _pipeHandle = _invalidHandle;
    _handshakeSent = false;
  }

  // Простой выделятель через HeapAlloc / HeapFree из kernel32 (без пакета package:ffi)
  ffi.Pointer<ffi.Uint8>? _allocBytes(List<int> data) {
    final k32 = _kernel32;
    if (k32 == null) return null;
    try {
      final getProcessHeap =
          k32.lookupFunction<ffi.IntPtr Function(), int Function()>('GetProcessHeap');
      final heapAlloc = k32.lookupFunction<
          ffi.Pointer<ffi.Uint8> Function(ffi.IntPtr, ffi.Uint32, ffi.IntPtr),
          ffi.Pointer<ffi.Uint8> Function(int, int, int)>('HeapAlloc');
      final heap = getProcessHeap();
      final ptr = heapAlloc(heap, 0x08, data.length);
      if (ptr == ffi.nullptr) return null;
      ptr.asTypedList(data.length).setAll(0, data);
      return ptr;
    } catch (_) {
      return null;
    }
  }

  ffi.Pointer<ffi.Uint32>? _allocUint32() {
    final ptr = _allocBytes(const [0, 0, 0, 0]);
    return ptr?.cast<ffi.Uint32>();
  }

  void _freeBytes(ffi.Pointer<ffi.NativeType> ptr) {
    final k32 = _kernel32;
    if (k32 == null || ptr == ffi.nullptr) return;
    try {
      final getProcessHeap =
          k32.lookupFunction<ffi.IntPtr Function(), int Function()>('GetProcessHeap');
      final heapFree = k32.lookupFunction<
          ffi.Int32 Function(ffi.IntPtr, ffi.Uint32, ffi.Pointer<ffi.Void>),
          int Function(int, int, ffi.Pointer<ffi.Void>)>('HeapFree');
      heapFree(getProcessHeap(), 0, ptr.cast<ffi.Void>());
    } catch (_) {}
  }
}
