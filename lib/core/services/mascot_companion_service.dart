import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/profile/domain/services/achievement_service.dart';
import '../widgets/mascot/mascot_state.dart';

/// Данные всплывающей реакции Пай-тян.
class PaiCompanionReaction {
  final MascotExpression expression;
  final String message;
  final String? badgeId;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isAfk;
  final DateTime createdAt;

  const PaiCompanionReaction({
    required this.expression,
    required this.message,
    this.badgeId,
    this.actionLabel,
    this.onAction,
    this.isAfk = false,
    required this.createdAt,
  });
}

/// Централизованный сервис живых реакций Пай-тян и контроля активности (AFK 90s).
class MascotCompanionService extends ChangeNotifier {
  static final MascotCompanionService instance = MascotCompanionService._();

  MascotCompanionService._() {
    _achievementSub = AchievementService.instance.onUnlocked.listen(
      onAchievementUnlocked,
    );
  }

  static const String prefEnabledKey = 'pai_companion_reactions_enabled';
  static const Duration toastDuration = Duration(milliseconds: 3500);
  static const Duration afkTimeout = Duration(seconds: 90);

  StreamSubscription<AchievementBadge>? _achievementSub;
  Timer? _dismissTimer;
  Timer? _afkTimer;

  bool _enabled = true;
  bool _dailyGreetingShown = false;
  bool _isAfkActive = false;
  PaiCompanionReaction? _currentReaction;

  bool get enabled => _enabled;
  bool get isAfkActive => _isAfkActive;
  PaiCompanionReaction? get currentReaction => _currentReaction;

  bool get _isTestEnv {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(prefEnabledKey) ?? true;
    } catch (_) {}
    _restartAfkTimer();
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      dismiss();
    } else {
      _restartAfkTimer();
    }
    notifyListeners();
  }

  /// Фиксирует активность пользователя: сбрасывает 90-секундный AFK-таймер и
  /// мгновенно будит Пай-тян коротким приветствием, если она задремала.
  void reportUserActivity() {
    if (_isAfkActive) {
      _isAfkActive = false;
      if (_enabled) {
        showReaction(
          expression: MascotExpression.cheering,
          message: 'С возвращением! Готовы продолжить просмотр?',
        );
      } else {
        dismiss();
      }
    }
    _restartAfkTimer();
  }

  void _restartAfkTimer() {
    _afkTimer?.cancel();
    if (!_enabled || _isTestEnv) return;
    _afkTimer = Timer(afkTimeout, _triggerAfkDozing);
  }

  void _triggerAfkDozing() {
    if (!_enabled) return;
    _isAfkActive = true;
    _dismissTimer?.cancel();
    _currentReaction = PaiCompanionReaction(
      expression: MascotExpression.afkDozing,
      message: MascotExpression.afkDozing.defaultMessage,
      isAfk: true,
      createdAt: DateTime.now(),
    );
    notifyListeners();
  }

  void showReaction({
    required MascotExpression expression,
    required String message,
    String? badgeId,
    String? actionLabel,
    VoidCallback? onAction,
    bool autoDismiss = true,
  }) {
    if (!_enabled) return;
    _isAfkActive = false;
    _dismissTimer?.cancel();
    _currentReaction = PaiCompanionReaction(
      expression: expression,
      message: message,
      badgeId: badgeId,
      actionLabel: actionLabel,
      onAction: onAction,
      createdAt: DateTime.now(),
    );
    notifyListeners();

    if (autoDismiss) {
      _dismissTimer = Timer(toastDuration, dismiss);
    }
  }

  void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _isAfkActive = false;
    if (_currentReaction != null) {
      _currentReaction = null;
      notifyListeners();
    }
  }

  // --- Контекстные триггеры ---

  void onAchievementUnlocked(AchievementBadge badge) {
    showReaction(
      expression: MascotExpression.cheering,
      message: 'Новое достижение открыто: ${badge.title}. Отличный темп!',
      badgeId: badge.id,
    );
  }

  void onOpeningSkipped() {
    showReaction(
      expression: MascotExpression.speedster,
      message: 'Опенинг пропущен! Летим дальше к сюжету.',
    );
  }

  void onEpisodeNearEnd({
    required String animeTitle,
    int? nextEpisode,
    VoidCallback? onNextEpisode,
  }) {
    showReaction(
      expression: MascotExpression.cheering,
      message: nextEpisode != null
          ? 'Серия просмотрена! Переходим к $nextEpisode серии?'
          : 'Серия просмотрена! Переходим к следующей?',
      actionLabel: onNextEpisode != null ? 'След. серия' : null,
      onAction: onNextEpisode,
    );
  }

  void onWatchPartyFriendJoined(String friendName) {
    final clean = friendName.trim().isEmpty ? 'Друг' : friendName.trim();
    showReaction(
      expression: MascotExpression.popcornWatch,
      message: '$clean присоединился к просмотру!',
    );
  }

  void onWatchPartyJoined() {
    showReaction(
      expression: MascotExpression.popcornWatch,
      message: 'Комната готова. Приятного совместного просмотра!',
    );
  }

  void onCollectionAdded(String listLabel, String animeTitle) {
    showReaction(
      expression: MascotExpression.proudCollector,
      message: 'Добавлено в «$listLabel»: $animeTitle.',
    );
  }

  void onSearchOrFilterEmpty() {
    showReaction(
      expression: MascotExpression.curiousSearch,
      message: 'По этим фильтрам пока пусто. Попробуем другой жанр?',
    );
  }

  void showDailyGreeting({
    DateTime? now,
    String? lastAnimeTitle,
    int? lastEpisode,
    VoidCallback? onContinue,
  }) {
    if (_dailyGreetingShown || !_enabled) return;
    _dailyGreetingShown = true;

    final hour = (now ?? DateTime.now()).hour;
    final isLateNight = hour >= 0 && hour < 5;
    final expression =
        isLateNight ? MascotExpression.cozyNight : MascotExpression.cheering;

    final String message;
    if (lastAnimeTitle != null && lastAnimeTitle.trim().isNotEmpty) {
      final epPart = lastEpisode != null ? ' с $lastEpisode серии' : '';
      message = 'Продолжим «${lastAnimeTitle.trim()}»$epPart?';
    } else if (isLateNight) {
      message = 'Ночной марафон? Устраивайтесь поудобнее.';
    } else {
      message = 'Рада видеть вас в SyncPai! Что посмотрим сегодня?';
    }

    showReaction(
      expression: expression,
      message: message,
      actionLabel: (lastAnimeTitle != null && onContinue != null) ? 'Продолжить' : null,
      onAction: onContinue,
    );
  }

  @visibleForTesting
  void resetForTest() {
    _dismissTimer?.cancel();
    _afkTimer?.cancel();
    _enabled = true;
    _dailyGreetingShown = false;
    _isAfkActive = false;
    _currentReaction = null;
  }

  @override
  void dispose() {
    _achievementSub?.cancel();
    _dismissTimer?.cancel();
    _afkTimer?.cancel();
    super.dispose();
  }
}

