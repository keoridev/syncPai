import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_colors.dart';
import '../app_theme.dart';
import '../theme_preset.dart';

class ThemeState extends Equatable {
  final ThemePreset currentPreset;
  final ThemeData themeData;

  const ThemeState({
    required this.currentPreset,
    required this.themeData,
  });

  @override
  List<Object?> get props => [currentPreset, themeData];
}

class ThemeCubit extends Cubit<ThemeState> {
  final SharedPreferences _prefs;
  static const _themePrefKey = 'syncpai_theme_preset_id';

  ThemeCubit(this._prefs)
      : super(
          _buildInitialState(_prefs),
        );

  static ThemeState _buildInitialState(SharedPreferences prefs) {
    final savedId = prefs.getString(_themePrefKey);
    final preset = ThemePreset.fromId(savedId);
    AppColors.updatePrimaryColor(preset.primaryColor);
    return ThemeState(
      currentPreset: preset,
      themeData: AppTheme.fromPreset(preset),
    );
  }

  /// Установить и сохранить цветовую тему
  Future<void> setPreset(ThemePreset preset) async {
    AppColors.updatePrimaryColor(preset.primaryColor);
    await _prefs.setString(_themePrefKey, preset.id);
    emit(ThemeState(
      currentPreset: preset,
      themeData: AppTheme.fromPreset(preset),
    ));
  }

  /// Установить кастомный акцентный цвет
  Future<void> setCustomAccent(Color color, {String name = 'Пользовательский'}) async {
    AppColors.updatePrimaryColor(color);
    final customPreset = ThemePreset(
      id: 'custom_${color.toARGB32().toRadixString(16)}',
      name: name,
      description: 'Индивидуальная палитра',
      primaryColor: color,
    );
    await _prefs.setString(_themePrefKey, customPreset.id);
    emit(ThemeState(
      currentPreset: customPreset,
      themeData: AppTheme.fromPreset(customPreset),
    ));
  }
}

