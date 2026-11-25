import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/profile/domain/services/achievement_service.dart';
import '../widgets/mascot/mascot_state.dart';

/// Данные всплывающей реакции Пай-тян.
class PaiCompanionReaction {
  final MascotExpression expression;
  final String? title;
  final String message;
  final String? badgeId;
  final String? actionLabel;
  final IconData? actionIcon;
  final Color? actionColor;
  final VoidCallback? onAction;
  final bool isAfk;
  final DateTime createdAt;

  const PaiCompanionReaction({
    required this.expression,
    this.title,
    required this.message,
    this.badgeId,
    this.actionLabel,
    this.actionIcon,
    this.actionColor,
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
  static const Duration toastDuration = Duration(seconds: 5);
  static const Duration afkTimeout = Duration(seconds: 90);
  static const Duration indecisionTimeout = Duration(seconds: 150);

  StreamSubscription<AchievementBadge>? _achievementSub;
  Timer? _autoHideTimer;
  Timer? _afkTimer;
  Timer? _indecisionTimer;

  bool _enabled = true;
  bool _dailyGreetingShown = false;
  bool _isAfkActive = false;
  bool _isPlayerActive = false;
  bool _indecisionHelperShownThisSession = false;
  VoidCallback? _onOpenForYouCallback;
  PaiCompanionReaction? _currentReaction;

  bool get enabled => _enabled;
  bool get isAfkActive => _isAfkActive;
  bool get isPlayerActive => _isPlayerActive;
  bool get indecisionHelperShownThisSession => _indecisionHelperShownThisSession;
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

  /// Паузит/возобновляет AFK-таймер и скрывает неактуальные тосты при активном плеере.
  void setPlayerActive(bool active) {
    if (_isPlayerActive == active) return;
    _isPlayerActive = active;
    if (active) {
      _afkTimer?.cancel();
      _afkTimer = null;
      stopCatalogBrowsingTimer();
      if (_isAfkActive || _currentReaction != null) {
        _isAfkActive = false;
        _currentReaction = null;
        _autoHideTimer?.cancel();
        _autoHideTimer = null;
        notifyListeners();
      }
    } else {
      _isAfkActive = false;
      _restartAfkTimer();
    }
  }

  /// Запускает 3-минутный таймер помощи при выборе аниме в каталоге (один раз за сессию).
  void startCatalogBrowsingTimer({
    VoidCallback? onOpenForYou,
    Duration timeout = indecisionTimeout,
  }) {
    if (onOpenForYou != null) {
      _onOpenForYouCallback = onOpenForYou;
    }
    if (!_enabled || _isPlayerActive || _indecisionHelperShownThisSession) {
      return;
    }
    if (_indecisionTimer?.isActive ?? false) return;
    _indecisionTimer = Timer(timeout, _triggerCatalogIndecisionHelper);
  }

  /// Фиксирует скролл или переключение вкладок в каталоге без запуска видео.
  void reportCatalogInteraction({VoidCallback? onOpenForYou}) {
    if (onOpenForYou != null) {
      _onOpenForYouCallback = onOpenForYou;
    }
    startCatalogBrowsingTimer(onOpenForYou: _onOpenForYouCallback);
  }

  /// Останавливает и сбрасывает таймер 3-минутного выбора (при выходе из каталога или запуске плеера).
  void stopCatalogBrowsingTimer() {
    _indecisionTimer?.cancel();
    _indecisionTimer = null;
  }

  void _triggerCatalogIndecisionHelper() {
    _indecisionTimer = null;
    if (!_enabled || _isPlayerActive || _indecisionHelperShownThisSession) {
      return;
    }
    _indecisionHelperShownThisSession = true;
    showReaction(
      expression: MascotExpression.curiousSearch,
      title: 'Нечего посмотреть?',
      message: 'Пай-тян подготовила подборку специально под твой вкус.',
      actionLabel: 'Смотреть подборку',
      onAction: _onOpenForYouCallback,
    );
  }

  /// Фиксирует активность пользователя: сбрасывает 90-секундный AFK-таймер и
  /// мгновенно будит Пай-тян коротким приветствием, если она задремала.
  void reportUserActivity() {
    if (_isPlayerActive) return;
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
    if (!_enabled || _isTestEnv || _isPlayerActive) return;
    _afkTimer = Timer(afkTimeout, _triggerAfkDozing);
  }

  void _triggerAfkDozing() {
    if (!_enabled || _isPlayerActive) return;
    _isAfkActive = true;
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
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
    String? title,
    required String message,
    String? badgeId,
    String? actionLabel,
    IconData? actionIcon,
    Color? actionColor,
    VoidCallback? onAction,
    bool autoDismiss = true,
    Duration? duration,
    bool isPlayerAction = false,
  }) {
    if (!_enabled || (_isPlayerActive && !isPlayerAction)) return;
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _isAfkActive = false;
    _currentReaction = PaiCompanionReaction(
      expression: expression,
      title: title,
      message: message,
      badgeId: badgeId,
      actionLabel: actionLabel,
      actionIcon: actionIcon,
      actionColor: actionColor,
      onAction: onAction,
      createdAt: DateTime.now(),
    );
    notifyListeners();

    if (autoDismiss) {
      _autoHideTimer = Timer(duration ?? toastDuration, dismissCurrentToast);
    }
  }

  void dismissCurrentToast() => dismiss();

  void dismiss() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
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
      isPlayerAction: true,
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
      isPlayerAction: true,
    );
  }

  /// Реакция Пай-тян на финал сезона с ветвлением по наличию продолжения или манги.
  void onSeasonFinale({
    String? nextSeasonName,
    required bool hasPlayableSequel,
    required bool hasAnnouncedSequel,
    String? mangaTitle,
    int? continueFromChapter,
    VoidCallback? onWatchSequel,
    VoidCallback? onAddPlanned,
    VoidCallback? onReadManga,
    VoidCallback? onFindSimilar,
  }) {
    final cleanName = nextSeasonName?.trim() ?? '';
    if (hasPlayableSequel && cleanName.isNotEmpty) {
      showReaction(
        expression: MascotExpression.cheering,
        title: 'Сезон завершён!',
        message: 'Дальше по хронологии: «$cleanName». Газ в продолжение?',
        actionLabel: 'Смотреть продолжение',
        actionIcon: Icons.play_arrow_rounded,
        actionColor: const Color(0xFFFF6B4A),
        onAction: onWatchSequel,
        duration: const Duration(seconds: 10),
        isPlayerAction: true,
      );
      return;
    }

    if (hasAnnouncedSequel && cleanName.isNotEmpty) {
      showReaction(
        expression: MascotExpression.proudCollector,
        title: 'Финал сезона!',
        message: 'Серий продолжения пока нет, но анонсирован «$cleanName».',
        actionLabel: 'В планах',
        actionIcon: Icons.bookmark_add_rounded,
        actionColor: const Color(0xFF35D9D5),
        onAction: onAddPlanned,
        duration: const Duration(seconds: 10),
        isPlayerAction: true,
      );
      return;
    }

    final cleanManga = mangaTitle?.trim() ?? '';
    if (cleanManga.isNotEmpty && onReadManga != null) {
      showReaction(
        expression: MascotExpression.curiousSearch,
        title: 'Сезон завершён!',
        message: continueFromChapter != null
            ? 'Продолжения аниме пока нет, но сюжет идёт дальше в манге — начать с $continueFromChapter главы?'
            : 'Продолжения аниме пока нет, но сюжет продолжается в манге — открыть для чтения?',
        actionLabel: continueFromChapter != null
            ? 'Читать с $continueFromChapter гл.'
            : 'Открыть мангу',
        actionIcon: Icons.menu_book_rounded,
        actionColor: const Color(0xFFFF6B4A),
        onAction: onReadManga,
        duration: const Duration(seconds: 11),
        isPlayerAction: true,
      );
      return;
    }

    showReaction(
      expression: MascotExpression.curiousSearch,
      title: 'Сезон пройден!',
      message:
          'Извини, продолжения у этого тайтла пока нет. Подобрать похожее по вайбу?',
      actionLabel: 'Похожие тайтлы',
      actionIcon: Icons.auto_awesome_rounded,
      actionColor: const Color(0xFF35D9D5),
      onAction: onFindSimilar,
      duration: const Duration(seconds: 10),
      isPlayerAction: true,
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
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _afkTimer?.cancel();
    _indecisionTimer?.cancel();
    _indecisionTimer = null;
    _enabled = true;
    _dailyGreetingShown = false;
    _isAfkActive = false;
    _isPlayerActive = false;
    _indecisionHelperShownThisSession = false;
    _onOpenForYouCallback = null;
    _currentReaction = null;
  }

  @override
  void dispose() {
    _achievementSub?.cancel();
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _afkTimer?.cancel();
    _indecisionTimer?.cancel();
    super.dispose();
  }
}

