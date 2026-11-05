import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Модель цветового пресета оформления SyncPai
class ThemePreset extends Equatable {
  final String id;
  final String name;
  final String description;
  final Color primaryColor;
  final Color backgroundColor;
  final Color surfaceColor;
  final Color surfaceElevatedColor;
  final IconData icon;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.primaryColor,
    this.backgroundColor = const Color(0xFF121316),
    this.surfaceColor = const Color(0xFF1A1C22),
    this.surfaceElevatedColor = const Color(0xFF242730),
    this.icon = Icons.palette_outlined,
  });

  /// 8 дизайнерских кинотеатральных палитр для примерки
  static const List<ThemePreset> all = [
    ThemePreset(
      id: 'sunset_orange',
      name: 'Мандарин Сенпай',
      description: 'Фирменный теплый терракотово-оранжевый кинотеатр',
      primaryColor: Color(0xFFE06C53),
      backgroundColor: Color(0xFF121316),
      surfaceColor: Color(0xFF1A1C22),
      surfaceElevatedColor: Color(0xFF242730),
      icon: Icons.local_fire_department_rounded,
    ),
    ThemePreset(
      id: 'cyber_cyan',
      name: 'Кибер Неон',
      description: 'Футуристичный неоновый циан ночного Сибуи',
      primaryColor: Color(0xFF00E5FF),
      backgroundColor: Color(0xFF0B0F19),
      surfaceColor: Color(0xFF121826),
      surfaceElevatedColor: Color(0xFF1B2438),
      icon: Icons.electric_bolt_rounded,
    ),
    ThemePreset(
      id: 'eva_violet',
      name: 'Евангелион Фиолет',
      description: 'Мистический фиолетовый неоновый свет Токио-3',
      primaryColor: Color(0xFFB388FF),
      backgroundColor: Color(0xFF110E1C),
      surfaceColor: Color(0xFF1A152B),
      surfaceElevatedColor: Color(0xFF261F3E),
      icon: Icons.auto_awesome_rounded,
    ),
    ThemePreset(
      id: 'sakura_ruby',
      name: 'Розовая Сакура',
      description: 'Сочный неоновый рубин лепестков сакуры',
      primaryColor: Color(0xFFFF2A68),
      backgroundColor: Color(0xFF140D12),
      surfaceColor: Color(0xFF1E131B),
      surfaceElevatedColor: Color(0xFF2C1C28),
      icon: Icons.favorite_rounded,
    ),
    ThemePreset(
      id: 'emerald_glitch',
      name: 'Изумрудный Глитч',
      description: 'Сочный хакерский кибер-зеленый Матрицы',
      primaryColor: Color(0xFF00FF87),
      backgroundColor: Color(0xFF0B1410),
      surfaceColor: Color(0xFF111E18),
      surfaceElevatedColor: Color(0xFF192C23),
      icon: Icons.terminal_rounded,
    ),
    ThemePreset(
      id: 'solar_amber',
      name: 'Солнечное Пламя',
      description: 'Золотисто-янтарный солнечный акцент дракона',
      primaryColor: Color(0xFFFFB300),
      backgroundColor: Color(0xFF14120E),
      surfaceColor: Color(0xFF1F1B15),
      surfaceElevatedColor: Color(0xFF2D271E),
      icon: Icons.wb_sunny_rounded,
    ),
    ThemePreset(
      id: 'crimson_blade',
      name: 'Алый Клинок',
      description: 'Глубокий алый стиль самурайских битв',
      primaryColor: Color(0xFFFF1744),
      backgroundColor: Color(0xFF150B0D),
      surfaceColor: Color(0xFF201013),
      surfaceElevatedColor: Color(0xFF2E171C),
      icon: Icons.shield_rounded,
    ),
    ThemePreset(
      id: 'deep_indigo',
      name: 'Глубокий Индиго',
      description: 'Спокойный лавандово-синий ночной космос',
      primaryColor: Color(0xFF7C83FD),
      backgroundColor: Color(0xFF0E101D),
      surfaceColor: Color(0xFF15192C),
      surfaceElevatedColor: Color(0xFF1F2540),
      icon: Icons.nights_stay_rounded,
    ),
    ThemePreset(
      id: 'amoled_black',
      name: 'AMOLED Черный',
      description: 'Истинный глубокий черный #000000 для OLED экранов и батареи',
      primaryColor: Color(0xFFE2E8F0),
      backgroundColor: Color(0xFF000000),
      surfaceColor: Color(0xFF0A0A0A),
      surfaceElevatedColor: Color(0xFF141414),
      icon: Icons.dark_mode_rounded,
    ),
    ThemePreset(
      id: 'sapphire_blue',
      name: 'Сапфировый Синий',
      description: 'Благородный глубокий синий сапфир морской бездны',
      primaryColor: Color(0xFF2979FF),
      backgroundColor: Color(0xFF060B14),
      surfaceColor: Color(0xFF0D1726),
      surfaceElevatedColor: Color(0xFF142238),
      icon: Icons.water_drop_rounded,
    ),
    ThemePreset(
      id: 'midnight_navy',
      name: 'Полуночный Неви',
      description: 'Темно-синий ультрамарин ночного океана',
      primaryColor: Color(0xFF00B0FF),
      backgroundColor: Color(0xFF080D1A),
      surfaceColor: Color(0xFF101930),
      surfaceElevatedColor: Color(0xFF182442),
      icon: Icons.waves_rounded,
    ),
    ThemePreset(
      id: 'phantom_amethyst',
      name: 'Королевский Аметист',
      description: 'Роскошный глубокий темно-фиолетовый кристалл',
      primaryColor: Color(0xFFAB47BC),
      backgroundColor: Color(0xFF0E0714),
      surfaceColor: Color(0xFF190F24),
      surfaceElevatedColor: Color(0xFF261736),
      icon: Icons.diamond_rounded,
    ),
    ThemePreset(
      id: 'tokyo_blood_moon',
      name: 'Кровавая Луна',
      description: 'Мрачный бордово-кровавый готический неоновый стиль',
      primaryColor: Color(0xFFFF3366),
      backgroundColor: Color(0xFF0D0507),
      surfaceColor: Color(0xFF1A0A0E),
      surfaceElevatedColor: Color(0xFF281117),
      icon: Icons.nightlight_round,
    ),
  ];

  static ThemePreset fromId(String? id) {
    if (id == null || id.isEmpty) return all.first;
    return all.firstWhere((p) => p.id == id, orElse: () => all.first);
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        primaryColor,
        backgroundColor,
        surfaceColor,
        surfaceElevatedColor,
        icon,
      ];
}

