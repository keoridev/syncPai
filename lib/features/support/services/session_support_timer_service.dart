import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/supporter_tier.dart';

/// Отслеживает активное время пользователя в приложении и показывает ненавязчивое
/// напоминание о поддержке проекта спустя 30 минут (с паузой 72 часа после закрытия).
class SessionSupportTimerService extends ChangeNotifier with WidgetsBindingObserver {
  static const String snoozedUntilPrefsKey = 'support_prompt_snoozed_until_ms';
  static const Duration defaultThreshold = Duration(minutes: 30);
  static const Duration snoozeDuration = Duration(hours: 72);

  static final SessionSupportTimerService instance = SessionSupportTimerService._();

  final Duration threshold;
  final Future<SharedPreferences> Function()? _prefsProvider;
  final DateTime Function() _nowProvider;

  Timer? _ticker;
  bool _started = false;
  bool _isForeground = true;
  bool _shouldShowPrompt = false;
  bool _hasTriggeredThisSession = false;
  Duration _activeElapsed = Duration.zero;
  SupporterTier _supporterTier = SupporterTier.free;
  DateTime? _snoozedUntil;

  SessionSupportTimerService._({
    this.threshold = defaultThreshold,
    Future<SharedPreferences> Function()? prefsProvider,
    DateTime Function()? nowProvider,
  })  : _prefsProvider = prefsProvider,
        _nowProvider = nowProvider ?? DateTime.now;

  @visibleForTesting
  factory SessionSupportTimerService.forTest({
    Duration threshold = defaultThreshold,
    Future<SharedPreferences> Function()? prefsProvider,
    DateTime Function()? nowProvider,
  }) {
    return SessionSupportTimerService._(
      threshold: threshold,
      prefsProvider: prefsProvider,
      nowProvider: nowProvider,
    );
  }

  bool get shouldShowPrompt =>
      _shouldShowPrompt && _supporterTier == SupporterTier.free;
  Duration get activeElapsed => _activeElapsed;
  SupporterTier get supporterTier => _supporterTier;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _loadSnoozeState();

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isForeground) {
        tick(const Duration(seconds: 10));
      }
    });
  }

  Future<void> _loadSnoozeState() async {
    try {
      final loader = _prefsProvider;
      final prefs = await (loader != null
          ? loader()
          : SharedPreferences.getInstance());
      final ms = prefs.getInt(snoozedUntilPrefsKey);
      if (ms != null) {
        _snoozedUntil = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
  }

  void updateSupporterTier(SupporterTier tier) {
    if (_supporterTier == tier) return;
    _supporterTier = tier;
    if (tier != SupporterTier.free && _shouldShowPrompt) {
      _shouldShowPrompt = false;
    }
    notifyListeners();
  }

  void tick(Duration elapsed) {
    if (_supporterTier != SupporterTier.free) return;
    if (_hasTriggeredThisSession || _shouldShowPrompt) return;

    final now = _nowProvider();
    if (_snoozedUntil != null && now.isBefore(_snoozedUntil!)) {
      return;
    }

    _activeElapsed += elapsed;
    if (_activeElapsed >= threshold) {
      _hasTriggeredThisSession = true;
      _shouldShowPrompt = true;
      notifyListeners();
    }
  }

  Future<void> snoozeFor72Hours() async {
    _shouldShowPrompt = false;
    _hasTriggeredThisSession = true;
    final until = _nowProvider().add(snoozeDuration);
    _snoozedUntil = until;
    notifyListeners();

    try {
      final loader = _prefsProvider;
      final prefs = await (loader != null
          ? loader()
          : SharedPreferences.getInstance());
      await prefs.setInt(snoozedUntilPrefsKey, until.millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<void> markOpenedSupport() => snoozeFor72Hours();

  @override
  void dispose() {
    _ticker?.cancel();
    if (_started && !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
