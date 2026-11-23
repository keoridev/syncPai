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

/// Быстрые пресеты 2D-раскладки HUD плеера.
enum HudLayoutPresetType {
  classic('Классика'),
  rightThumb('Под правую руку');

  final String label;
  const HudLayoutPresetType(this.label);
}

/// Конфигурация свободной 2D-позиции, масштаба и видимости одной кнопки HUD.
/// Координаты `nx` (`0.06..0.94`) и `ny` (`0.08..0.88`) нормированы по SafeArea.
class PlayerHudButtonConfig extends Equatable {
  static const double minNx = 0.06;
  static const double maxNx = 0.94;
  static const double minNy = 0.08;
  static const double maxNy = 0.88;
  static const double minScale = 0.8;
  static const double maxScale = 1.4;

  final String id;
  final double nx;
  final double ny;
  final double scale;
  final bool visible;

  const PlayerHudButtonConfig({
    required this.id,
    required this.nx,
    required this.ny,
    this.scale = 1.0,
    this.visible = true,
  });

  PlayerHudButtonConfig clamped() => PlayerHudButtonConfig(
        id: id,
        nx: nx.clamp(minNx, maxNx).toDouble(),
        ny: ny.clamp(minNy, maxNy).toDouble(),
        scale: scale.clamp(minScale, maxScale).toDouble(),
        visible: visible,
      );

  PlayerHudButtonConfig copyWith({
    double? nx,
    double? ny,
    double? scale,
    bool? visible,
  }) {
    return PlayerHudButtonConfig(
      id: id,
      nx: (nx ?? this.nx).clamp(minNx, maxNx).toDouble(),
      ny: (ny ?? this.ny).clamp(minNy, maxNy).toDouble(),
      scale: (scale ?? this.scale).clamp(minScale, maxScale).toDouble(),
      visible: visible ?? this.visible,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nx': nx,
        'ny': ny,
        'scale': scale,
        'visible': visible,
      };

  factory PlayerHudButtonConfig.fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
    final rawNx = (json['nx'] as num?)?.toDouble() ?? 0.5;
    final rawNy = (json['ny'] as num?)?.toDouble() ?? 0.5;
    final rawScale = (json['scale'] as num?)?.toDouble() ?? 1.0;
    final rawVisible = json['visible'] as bool? ?? true;
    return PlayerHudButtonConfig(
      id: (json['id'] as String?) ?? fallbackId,
      nx: rawNx,
      ny: rawNy,
      scale: rawScale,
      visible: rawVisible,
    ).clamped();
  }

  @override
  List<Object?> get props => [id, nx, ny, scale, visible];
}

class PlayerHud2DButtonMeta {
  final String id;
  final String label;

  const PlayerHud2DButtonMeta({
    required this.id,
    required this.label,
  });
}

const List<PlayerHud2DButtonMeta> kPlayerHud2DButtons = [
  PlayerHud2DButtonMeta(id: 'play_pause', label: 'Пауза / Воспроизведение'),
  PlayerHud2DButtonMeta(id: 'seek_back', label: 'Назад 10 сек'),
  PlayerHud2DButtonMeta(id: 'seek_forward', label: 'Вперёд 10 сек'),
  PlayerHud2DButtonMeta(id: 'skip_intro', label: 'Пропустить опенинг'),
  PlayerHud2DButtonMeta(id: 'next_episode', label: 'Серии / Следующая'),
  PlayerHud2DButtonMeta(id: 'speed', label: 'Скорость'),
  PlayerHud2DButtonMeta(id: 'quality_dub', label: 'Качество и озвучка'),
  PlayerHud2DButtonMeta(id: 'lock_screen', label: 'Блокировка экрана'),
  PlayerHud2DButtonMeta(id: 'fullscreen', label: 'Полный экран'),
  PlayerHud2DButtonMeta(id: 'pip_mode', label: 'Картинка в картинке (PiP)'),
];

String hud2DButtonLabel(String id) {
  for (final meta in kPlayerHud2DButtons) {
    if (meta.id == id) return meta.label;
  }
  return id;
}

class PlayerHud2DPresets {
  static Map<String, PlayerHudButtonConfig> classicLayout() => const {
        'play_pause': PlayerHudButtonConfig(id: 'play_pause', nx: 0.50, ny: 0.50),
        'seek_back': PlayerHudButtonConfig(id: 'seek_back', nx: 0.30, ny: 0.50),
        'seek_forward': PlayerHudButtonConfig(id: 'seek_forward', nx: 0.70, ny: 0.50),
        'skip_intro': PlayerHudButtonConfig(id: 'skip_intro', nx: 0.85, ny: 0.72),
        'next_episode': PlayerHudButtonConfig(id: 'next_episode', nx: 0.15, ny: 0.74),
        'speed': PlayerHudButtonConfig(id: 'speed', nx: 0.76, ny: 0.32),
        'quality_dub': PlayerHudButtonConfig(id: 'quality_dub', nx: 0.90, ny: 0.32),
        'lock_screen': PlayerHudButtonConfig(id: 'lock_screen', nx: 0.09, ny: 0.32),
        'fullscreen': PlayerHudButtonConfig(id: 'fullscreen', nx: 0.92, ny: 0.84),
        'pip_mode': PlayerHudButtonConfig(id: 'pip_mode', nx: 0.91, ny: 0.48),
      };

  static Map<String, PlayerHudButtonConfig> rightThumbLayout() => const {
        'play_pause': PlayerHudButtonConfig(
          id: 'play_pause',
          nx: 0.84,
          ny: 0.58,
          scale: 1.1,
        ),
        'seek_back': PlayerHudButtonConfig(id: 'seek_back', nx: 0.68, ny: 0.58),
        'seek_forward': PlayerHudButtonConfig(id: 'seek_forward', nx: 0.86, ny: 0.40),
        'skip_intro': PlayerHudButtonConfig(
          id: 'skip_intro',
          nx: 0.78,
          ny: 0.74,
          scale: 1.05,
        ),
        'next_episode': PlayerHudButtonConfig(
          id: 'next_episode',
          nx: 0.56,
          ny: 0.76,
          scale: 0.95,
        ),
        'speed': PlayerHudButtonConfig(
          id: 'speed',
          nx: 0.76,
          ny: 0.28,
          scale: 0.95,
        ),
        'quality_dub': PlayerHudButtonConfig(
          id: 'quality_dub',
          nx: 0.90,
          ny: 0.28,
          scale: 0.95,
        ),
        'lock_screen': PlayerHudButtonConfig(id: 'lock_screen', nx: 0.09, ny: 0.32),
        'fullscreen': PlayerHudButtonConfig(id: 'fullscreen', nx: 0.92, ny: 0.76),
        'pip_mode': PlayerHudButtonConfig(
          id: 'pip_mode',
          nx: 0.62,
          ny: 0.30,
          scale: 0.95,
        ),
      };

  static Map<String, PlayerHudButtonConfig> forPreset(HudLayoutPresetType type) {
    switch (type) {
      case HudLayoutPresetType.classic:
        return classicLayout();
      case HudLayoutPresetType.rightThumb:
        return rightThumbLayout();
    }
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
  PlayerHudButtonMeta(id: 'settings_gear', label: 'Меню настроек', isCore: true),
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
  final Map<String, PlayerHudButtonConfig> hudLayout;
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
    this.hudLayout = const {
      'play_pause': PlayerHudButtonConfig(id: 'play_pause', nx: 0.50, ny: 0.50),
      'seek_back': PlayerHudButtonConfig(id: 'seek_back', nx: 0.30, ny: 0.50),
      'seek_forward': PlayerHudButtonConfig(id: 'seek_forward', nx: 0.70, ny: 0.50),
      'skip_intro': PlayerHudButtonConfig(id: 'skip_intro', nx: 0.85, ny: 0.72),
      'next_episode': PlayerHudButtonConfig(id: 'next_episode', nx: 0.15, ny: 0.74),
      'speed': PlayerHudButtonConfig(id: 'speed', nx: 0.76, ny: 0.32),
      'quality_dub': PlayerHudButtonConfig(id: 'quality_dub', nx: 0.90, ny: 0.32),
      'lock_screen': PlayerHudButtonConfig(id: 'lock_screen', nx: 0.09, ny: 0.32),
      'fullscreen': PlayerHudButtonConfig(id: 'fullscreen', nx: 0.92, ny: 0.84),
      'pip_mode': PlayerHudButtonConfig(id: 'pip_mode', nx: 0.91, ny: 0.48),
    },
    this.autoSkipOpenings = true,
    this.autoPauseOnLeave = true,
    this.liquidGlassEffects = true,
    this.defaultQuality = '1080p FHD',
    this.hasSeenPlayerOnboarding = false,
    this.paiCompanionReactionsEnabled = true,
  });

  bool isHudButtonVisible(String id) => playerButtonVisibility[id] ?? true;

  PlayerHudButtonConfig hudConfigFor(String id) {
    return hudLayout[id] ??
        PlayerHud2DPresets.classicLayout()[id] ??
        PlayerHudButtonConfig(id: id, nx: 0.5, ny: 0.5);
  }

  List<PlayerHudButtonConfig> get hiddenHudButtons => [
        for (final meta in kPlayerHud2DButtons)
          if (!hudConfigFor(meta.id).visible) hudConfigFor(meta.id),
      ];

  SettingsState copyWith({
    int? gridColumnCount,
    bool? isListView,
    PlayerHudPreset? playerHudPreset,
    Map<String, bool>? playerButtonVisibility,
    List<String>? playerButtonOrder,
    Map<String, PlayerHudButtonConfig>? hudLayout,
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
      hudLayout: hudLayout ?? this.hudLayout,
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
        hudLayout,
        autoSkipOpenings,
        autoPauseOnLeave,
        liquidGlassEffects,
        defaultQuality,
        hasSeenPlayerOnboarding,
        paiCompanionReactionsEnabled,
      ];
}
