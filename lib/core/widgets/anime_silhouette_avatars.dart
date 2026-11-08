import 'package:flutter/material.dart';

/// Премиальный арт-пресет аниме-силуэта в стиле Dark Cyberpunk
class AnimeSilhouettePreset {
  final String id;
  final String name;
  final String title;
  final Color eyeColor;
  final List<Color> backgroundGradient;
  final IconData silhouetteIcon;

  const AnimeSilhouettePreset({
    required this.id,
    required this.name,
    required this.title,
    required this.eyeColor,
    required this.backgroundGradient,
    required this.silhouetteIcon,
  });

  static const List<AnimeSilhouettePreset> presets = [
    AnimeSilhouettePreset(
      id: 'shadow_monarch',
      name: 'Теневой Монарх',
      title: 'Solo Leveling',
      eyeColor: Color(0xFF00E5FF),
      backgroundGradient: [Color(0xFF140326), Color(0xFF0B061A)],
      silhouetteIcon: Icons.shield_moon_rounded,
    ),
    AnimeSilhouettePreset(
      id: 'cyber_ronin',
      name: 'Кибер-Ронин',
      title: 'Cyberpunk 2077',
      eyeColor: Color(0xFFFF0055),
      backgroundGradient: [Color(0xFF051C3B), Color(0xFF1B072B)],
      silhouetteIcon: Icons.masks_rounded,
    ),
    AnimeSilhouettePreset(
      id: 'ghost_operative',
      name: 'Призрак в доспехах',
      title: 'Ghost Operative',
      eyeColor: Color(0xFF00FF88),
      backgroundGradient: [Color(0xFF071F1E), Color(0xFF061413)],
      silhouetteIcon: Icons.visibility_rounded,
    ),
    AnimeSilhouettePreset(
      id: 'blade_master',
      name: 'Мастер Двух Клинков',
      title: 'Sword Art',
      eyeColor: Color(0xFFFFD700),
      backgroundGradient: [Color(0xFF261005), Color(0xFF140A06)],
      silhouetteIcon: Icons.sports_martial_arts_rounded,
    ),
    AnimeSilhouettePreset(
      id: 'oni_assassin',
      name: 'Демонический Они',
      title: 'Demon Hunter',
      eyeColor: Color(0xFFFF1744),
      backgroundGradient: [Color(0xFF2B060C), Color(0xFF170407)],
      silhouetteIcon: Icons.whatshot_rounded,
    ),
    AnimeSilhouettePreset(
      id: 'void_sorceress',
      name: 'Чародейка Бездны',
      title: 'Void Arcana',
      eyeColor: Color(0xFFE040FB),
      backgroundGradient: [Color(0xFF1A0A2E), Color(0xFF0E051C)],
      silhouetteIcon: Icons.auto_awesome_rounded,
    ),
  ];

  static AnimeSilhouettePreset? find(String? id) {
    if (id == null) return null;
    try {
      return presets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}

