import 'package:equatable/equatable.dart';

enum PlayerHudPreset {
  standard('Стандартный', 'Сбалансированный интерфейс со всеми быстрыми кнопками'),
  minimal('Минималистичный (Жесты)', 'Чистый кинематографичный вид — управление жестами'),
  advanced('Расширенный', 'Все инструменты вынесены на главный экран плеера');

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

class SettingsState extends Equatable {
  final int gridColumnCount; // 2 or 3
  final bool isListView; // false = grid, true = list
  final PlayerHudPreset playerHudPreset;
  final bool autoSkipOpenings;
  final bool autoPauseOnLeave;
  final bool liquidGlassEffects;
  final String defaultQuality;

  const SettingsState({
    this.gridColumnCount = 3,
    this.isListView = false,
    this.playerHudPreset = PlayerHudPreset.standard,
    this.autoSkipOpenings = true,
    this.autoPauseOnLeave = true,
    this.liquidGlassEffects = true,
    this.defaultQuality = '1080p FHD',
  });

  SettingsState copyWith({
    int? gridColumnCount,
    bool? isListView,
    PlayerHudPreset? playerHudPreset,
    bool? autoSkipOpenings,
    bool? autoPauseOnLeave,
    bool? liquidGlassEffects,
    String? defaultQuality,
  }) {
    return SettingsState(
      gridColumnCount: gridColumnCount ?? this.gridColumnCount,
      isListView: isListView ?? this.isListView,
      playerHudPreset: playerHudPreset ?? this.playerHudPreset,
      autoSkipOpenings: autoSkipOpenings ?? this.autoSkipOpenings,
      autoPauseOnLeave: autoPauseOnLeave ?? this.autoPauseOnLeave,
      liquidGlassEffects: liquidGlassEffects ?? this.liquidGlassEffects,
      defaultQuality: defaultQuality ?? this.defaultQuality,
    );
  }

  @override
  List<Object?> get props => [
        gridColumnCount,
        isListView,
        playerHudPreset,
        autoSkipOpenings,
        autoPauseOnLeave,
        liquidGlassEffects,
        defaultQuality,
      ];
}
