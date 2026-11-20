import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnlinePresenceInfo {
  final String userId;
  final String status;
  final String activity;
  final DateTime updatedAt;

  const OnlinePresenceInfo({
    required this.userId,
    required this.status,
    required this.activity,
    required this.updatedAt,
  });
}

/// Сервис мгновенного Realtime-присутствия (Supabase Presence) и режима «Инкогнито».
class PresenceService extends ChangeNotifier with WidgetsBindingObserver {
  static const String incognitoPrefsKey = 'syncpai_incognito_mode';
  static const String defaultActivity = 'В приложении';
  static const String channelName = 'syncpai:presence';

  static final PresenceService instance = PresenceService._();

  void _safeNotifyListeners() {
    try {
      final phase = SchedulerBinding.instance.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (hasListeners) {
            super.notifyListeners();
          }
        });
        return;
      }
    } catch (_) {}
    super.notifyListeners();
  }

  final StreamController<Map<String, OnlinePresenceInfo>> _onlineController =
      StreamController<Map<String, OnlinePresenceInfo>>.broadcast();

  RealtimeChannel? _channel;
  String? _currentUserId;
  bool _isIncognito = false;
  bool _observerAttached = false;
  String _currentActivity = defaultActivity;
  Map<String, OnlinePresenceInfo> _onlineUsers = const {};

  PresenceService._();

  @visibleForTesting
  factory PresenceService.forTest() => PresenceService._();

  bool get isIncognito => _isIncognito;
  String get currentActivity => _currentActivity;
  Map<String, OnlinePresenceInfo> get onlineUsers => _onlineUsers;
  Stream<Map<String, OnlinePresenceInfo>> get onlineUsersStream => _onlineController.stream;

  bool isUserOnline(String userId) {
    if (userId.isEmpty) return false;
    return _onlineUsers.containsKey(userId);
  }

  String? activityForUser(String userId) {
    return _onlineUsers[userId]?.activity;
  }

  Future<void> initPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(incognitoPrefsKey);
      if (saved != null && saved != _isIncognito) {
        _isIncognito = saved;
        _safeNotifyListeners();
      }
    } catch (_) {}
  }

  Future<void> startForUser(String userId) async {
    if (userId.isEmpty) return;
    await initPreferences();

    if (!_observerAttached && !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    }

    if (_currentUserId == userId && _channel != null) {
      if (!_isIncognito) {
        await _trackCurrentState();
      }
      return;
    }

    await stop();
    _currentUserId = userId;

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    final client = _supabase;
    if (client == null) return;

    try {
      final ch = client.channel(channelName);
      _channel = ch;
      ch.onPresenceSync((_) => _syncPresenceState());
      ch.onPresenceJoin((_) => _syncPresenceState());
      ch.onPresenceLeave((_) => _syncPresenceState());
      ch.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (_isIncognito) {
            await _untrackCurrentState();
          } else {
            await _trackCurrentState();
          }
        }
      });
    } catch (e) {
      debugPrint('[PresenceService] subscribe error: $e');
    }
  }

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  void _syncPresenceState() {
    final ch = _channel;
    if (ch == null) return;
    try {
      final next = <String, OnlinePresenceInfo>{};
      final states = ch.presenceState();
      for (final single in states) {
        for (final presence in single.presences) {
          final payload = presence.payload;
          final uid = payload['user_id']?.toString() ?? '';
          if (uid.isEmpty) continue;
          final status = payload['status']?.toString() ?? 'online';
          final activity = payload['activity']?.toString() ?? defaultActivity;
          final updatedAt = DateTime.tryParse(payload['updated_at']?.toString() ?? '') ??
              DateTime.now();
          next[uid] = OnlinePresenceInfo(
            userId: uid,
            status: status,
            activity: activity,
            updatedAt: updatedAt,
          );
        }
      }
      _onlineUsers = Map.unmodifiable(next);
      _onlineController.add(_onlineUsers);
      _safeNotifyListeners();
    } catch (e) {
      debugPrint('[PresenceService] presenceState parse error: $e');
    }
  }

  Future<void> _trackCurrentState() async {
    final ch = _channel;
    final uid = _currentUserId;
    if (ch == null || uid == null || _isIncognito) return;
    try {
      await ch.track({
        'user_id': uid,
        'status': 'online',
        'activity': _currentActivity,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _untrackCurrentState() async {
    final ch = _channel;
    if (ch == null) return;
    try {
      await ch.untrack();
    } catch (_) {}
  }

  Future<void> setWatchingActivity(String animeTitle, int episodeNumber) async {
    final cleanTitle = animeTitle.trim();
    _currentActivity = cleanTitle.isEmpty
        ? defaultActivity
        : 'Смотрит: $cleanTitle • $episodeNumber сер.';
    _safeNotifyListeners();
    if (!_isIncognito) {
      await _trackCurrentState();
    }
  }

  Future<void> clearWatchingActivity() async {
    if (_currentActivity == defaultActivity) return;
    _currentActivity = defaultActivity;
    _safeNotifyListeners();
    if (!_isIncognito) {
      await _trackCurrentState();
    }
  }

  Future<void> setIncognito(bool enabled) async {
    if (_isIncognito == enabled) return;
    _isIncognito = enabled;
    _safeNotifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(incognitoPrefsKey, enabled);
    } catch (_) {}

    if (enabled) {
      await _untrackCurrentState();
    } else {
      await _trackCurrentState();
    }

    // Best-effort обновление public.profiles (не блокирует UI)
    final client = _supabase;
    final uid = _currentUserId ?? client?.auth.currentUser?.id;
    if (client != null && uid != null) {
      try {
        await client.from('profiles').update({
          'is_incognito': enabled,
          if (enabled) 'current_activity': null,
        }).eq('id', uid);
      } catch (_) {}
    }
  }

  Future<void> toggleIncognito() => setIncognito(!_isIncognito);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_isIncognito) {
        unawaited(_trackCurrentState());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_untrackCurrentState());
    }
  }

  Future<void> stop() async {
    await _untrackCurrentState();
    final ch = _channel;
    _channel = null;
    _currentUserId = null;
    if (ch != null) {
      try {
        await _supabase?.removeChannel(ch);
      } catch (_) {}
    }
    _onlineUsers = const {};
    _safeNotifyListeners();
  }

  @visibleForTesting
  void setTestOnlineUsers(Map<String, OnlinePresenceInfo> users) {
    _onlineUsers = Map.unmodifiable(users);
    _onlineController.add(_onlineUsers);
    _safeNotifyListeners();
  }
}
