import 'package:equatable/equatable.dart';

enum PlayerHudPreset {
  standard('Стандартный', 'Сбалансированный HUD с перемоткой ±10с'),
  minimal('Минималистичный', 'Чистый экран, управление жестами'),
  advanced('Расширенный', 'Все инструменты вынесены на панель плеера'),
  custom('Пользовательский', 'Ручная настройка видимости и порядка кнопок');

  final String label;
  final String description;
  const PlayerHudPreset(this.label, this.description);

  static PlayerHudPreset fromString(String? val) {
    if (val == null) return PlayerHudPreset.standard;
    return PlayerHudPreset.values.firstWhere(
      (e) => e.name == val,
      orElse: () => PlayerHudPreset.standard,
    );
  }
}

class PlayerHudButtonMeta {
  final String id;
  final String label;
  final bool isCore;

  const PlayerHudButtonMeta({
    required this.id,
    required this.label,
    this.isCore = false,
  });
}

const List<PlayerHudButtonMeta> kDefaultPlayerHudButtons = [
  PlayerHudButtonMeta(id: 'back', label: 'Назад', isCore: true),
  PlayerHudButtonMeta(id: 'title', label: 'Название серии', isCore: true),
  PlayerHudButtonMeta(id: 'play_pause', label: 'Пауза / Воспроизведение', isCore: true),
  PlayerHudButtonMeta(id: 'seek_10s', label: 'Перемотка ±10 сек'),
  PlayerHudButtonMeta(id: 'skip_op_ed', label: 'Пропуск опенинга / эндинга', isCore: true),
  PlayerHudButtonMeta(id: 'timeline', label: 'Таймлайн', isCore: true),
  PlayerHudButtonMeta(id: 'quality', label: 'Качество видео', isCore: true),
  PlayerHudButtonMeta(id: 'next_episode', label: 'Следующая серия', isCore: true),
  PlayerHudButtonMeta(id: 'fullscreen', label: 'Полный экран', isCore: true),
  PlayerHudButtonMeta(id: 'settings_gear', label: 'Меню настроек (⚙️)', isCore: true),
  PlayerHudButtonMeta(id: 'speed', label: 'Скорость воспроизведения'),
  PlayerHudButtonMeta(id: 'aspect_ratio', label: 'Соотношение сторон'),
  PlayerHudButtonMeta(id: 'screenshot', label: 'Скриншот кадра'),
  PlayerHudButtonMeta(id: 'sleep_timer', label: 'Таймер сна'),
  PlayerHudButtonMeta(id: 'pip', label: 'Картинка в картинке (PiP)'),
];

class PlayerHudPresets {
  static List<String> defaultOrder() =>
      kDefaultPlayerHudButtons.map((b) => b.id).toList();

  static Map<String, bool> visibilityFor(PlayerHudPreset preset) {
    switch (preset) {
      case PlayerHudPreset.standard:
      case PlayerHudPreset.custom:
        return {
          'back': true,
          'title': true,
          'play_pause': true,
          'seek_10s': true,
          'skip_op_ed': true,
          'timeline': true,
          'quality': true,
          'next_episode': true,
          'fullscreen': true,
          'settings_gear': true,
          'speed': false,
          'aspect_ratio': false,
          'screenshot': false,
          'sleep_timer': false,
          'pip': false,
        };
      case PlayerHudPreset.minimal:
        return {
          'back': true,
          'title': true,
          'play_pause': true,
          'seek_10s': false,
          'skip_op_ed': true,
          'timeline': true,
          'quality': true,
          'next_episode': true,
          'fullscreen': true,
          'settings_gear': true,
          'speed': false,
          'aspect_ratio': false,
          'screenshot': false,
          'sleep_timer': false,
          'pip': false,
        };
      case PlayerHudPreset.advanced:
        return {
          for (final b in kDefaultPlayerHudButtons) b.id: true,
        };
    }
  }
}

class SettingsState extends Equatable {
  final int gridColumnCount; // 2 or 3
  final bool isListView; // false = grid, true = list
  final PlayerHudPreset playerHudPreset;
  final Map<String, bool> playerButtonVisibility;
  final List<String> playerButtonOrder;
  final bool autoSkipOpenings;
  final bool autoPauseOnLeave;
  final bool liquidGlassEffects;
  final String defaultQuality;
  final bool hasSeenPlayerOnboarding;
  final bool paiCompanionReactionsEnabled;

  const SettingsState({
    this.gridColumnCount = 3,
    this.isListView = false,
    this.playerHudPreset = PlayerHudPreset.standard,
    this.playerButtonVisibility = const {
      'back': true,
      'title': true,
      'play_pause': true,
      'seek_10s': true,
      'skip_op_ed': true,
      'timeline': true,
      'quality': true,
      'next_episode': true,
      'fullscreen': true,
      'settings_gear': true,
      'speed': false,
      'aspect_ratio': false,
      'screenshot': false,
      'sleep_timer': false,
      'pip': false,
    },
    this.playerButtonOrder = const [
      'back',
      'title',
      'play_pause',
      'seek_10s',
      'skip_op_ed',
      'timeline',
      'quality',
      'next_episode',
      'fullscreen',
      'settings_gear',
      'speed',
      'aspect_ratio',
      'screenshot',
      'sleep_timer',
      'pip',
    ],
    this.autoSkipOpenings = true,
    this.autoPauseOnLeave = true,
    this.liquidGlassEffects = true,
    this.defaultQuality = '1080p FHD',
    this.hasSeenPlayerOnboarding = false,
    this.paiCompanionReactionsEnabled = true,
  });

  bool isHudButtonVisible(String id) => playerButtonVisibility[id] ?? true;

  SettingsState copyWith({
    int? gridColumnCount,
    bool? isListView,
    PlayerHudPreset? playerHudPreset,
    Map<String, bool>? playerButtonVisibility,
    List<String>? playerButtonOrder,
    bool? autoSkipOpenings,
    bool? autoPauseOnLeave,
    bool? liquidGlassEffects,
    String? defaultQuality,
    bool? hasSeenPlayerOnboarding,
    bool? paiCompanionReactionsEnabled,
  }) {
    return SettingsState(
      gridColumnCount: gridColumnCount ?? this.gridColumnCount,
      isListView: isListView ?? this.isListView,
      playerHudPreset: playerHudPreset ?? this.playerHudPreset,
      playerButtonVisibility:
          playerButtonVisibility ?? this.playerButtonVisibility,
      playerButtonOrder: playerButtonOrder ?? this.playerButtonOrder,
      autoSkipOpenings: autoSkipOpenings ?? this.autoSkipOpenings,
      autoPauseOnLeave: autoPauseOnLeave ?? this.autoPauseOnLeave,
      liquidGlassEffects: liquidGlassEffects ?? this.liquidGlassEffects,
      defaultQuality: defaultQuality ?? this.defaultQuality,
      hasSeenPlayerOnboarding:
          hasSeenPlayerOnboarding ?? this.hasSeenPlayerOnboarding,
      paiCompanionReactionsEnabled:
          paiCompanionReactionsEnabled ?? this.paiCompanionReactionsEnabled,
    );
  }

  @override
  List<Object?> get props => [
        gridColumnCount,
        isListView,
        playerHudPreset,
        playerButtonVisibility,
        playerButtonOrder,
        autoSkipOpenings,
        autoPauseOnLeave,
        liquidGlassEffects,
        defaultQuality,
        hasSeenPlayerOnboarding,
        paiCompanionReactionsEnabled,
      ];
}
