import 'package:flutter/material.dart';

/// Значок профиля в стиле Steam Profile Badges
class SteamBadge {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int level;

  const SteamBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.level,
  });

  static const List<SteamBadge> all = [
    SteamBadge(
      id: 'sync_master',
      title: 'Синхронизатор',
      description: 'Мастер совместного просмотра без единого рассинхрона',
      icon: Icons.sync_alt_rounded,
      color: Color(0xFF00E5FF),
      level: 50,
    ),
    SteamBadge(
      id: 'marathon_100',
      title: 'Марафонец 100',
      description: 'Просмотрено более 100 серий аниме за один уикенд',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFF6B4A),
      level: 100,
    ),
    SteamBadge(
      id: 'night_otaku',
      title: 'Ночной Отаку',
      description: 'Сеансы в 4 утра в темноте под шум дождя',
      icon: Icons.bedtime_rounded,
      color: Color(0xFFB388FF),
      level: 25,
    ),
    SteamBadge(
      id: 'anixart_collector',
      title: 'Коллекционер Anixart',
      description: 'Импортировал легендарную библиотеку закладок',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFF00FF87),
      level: 30,
    ),
    SteamBadge(
      id: 'match_swiper',
      title: 'Аниме Matcher',
      description: 'Нашел соулмейта в совместном Anime Tinder',
      icon: Icons.favorite_rounded,
      color: Color(0xFFFF2A68),
      level: 20,
    ),
    SteamBadge(
      id: 'pioneer',
      title: 'Первопроходец SyncPai',
      description: 'Элитный участник ранней бета-версии',
      icon: Icons.military_tech_rounded,
      color: Color(0xFFFFD700),
      level: 99,
    ),
    SteamBadge(
      id: 'fhd_expert',
      title: 'Full HD Эксперт',
      description: 'Смотрит только в 1080p с максимальным битрейтом',
      icon: Icons.high_quality_rounded,
      color: Color(0xFF4A90E2),
      level: 15,
    ),
    SteamBadge(
      id: 'skip_legend',
      title: 'Скиппер Опенингов',
      description: 'Сэкономил более 24 часов жизни умным автопропуском',
      icon: Icons.fast_forward_rounded,
      color: Color(0xFFE06C53),
      level: 10,
    ),
  ];

  static SteamBadge fromId(String? id) {
    if (id == null || id.isEmpty) return all.first;
    return all.firstWhere((b) => b.id == id, orElse: () => all.first);
  }
}

/// Модели тем оформления профиля в стиле Steam Community / Points Shop
class SteamAvatarFrame {
  final String id;
  final String name;
  final List<Color> colors;
  final IconData previewIcon;

  const SteamAvatarFrame({
    required this.id,
    required this.name,
    required this.colors,
    required this.previewIcon,
  });

  static const List<SteamAvatarFrame> all = [
    SteamAvatarFrame(
      id: 'none',
      name: 'Классическая',
      colors: [Color(0xFF2C303B), Color(0xFF1A1C22)],
      previewIcon: Icons.circle_outlined,
    ),
    SteamAvatarFrame(
      id: 'neon_cyber',
      name: 'Неон Киберпанк',
      colors: [Color(0xFF00F0FF), Color(0xFFFF007F), Color(0xFF00F0FF)],
      previewIcon: Icons.bolt_rounded,
    ),
    SteamAvatarFrame(
      id: 'sakura_blossom',
      name: 'Цветение Сакуры',
      colors: [Color(0xFFFF9EB5), Color(0xFFE056FD), Color(0xFFFF9EB5)],
      previewIcon: Icons.local_florist_rounded,
    ),
    SteamAvatarFrame(
      id: 'cosmic_void',
      name: 'Космический Войд',
      colors: [Color(0xFF7C83FD), Color(0xFF8A2BE2), Color(0xFF00D2FF)],
      previewIcon: Icons.auto_awesome_rounded,
    ),
    SteamAvatarFrame(
      id: 'golden_dragon',
      name: 'Золотой Дракон',
      colors: [Color(0xFFFFD700), Color(0xFFFF6B4A), Color(0xFFFFD700)],
      previewIcon: Icons.whatshot_rounded,
    ),
    SteamAvatarFrame(
      id: 'glitch_aurora',
      name: 'Северное Сияние',
      colors: [Color(0xFF00FF87), Color(0xFF60EFFF), Color(0xFF00FF87)],
      previewIcon: Icons.waves_rounded,
    ),
    SteamAvatarFrame(
      id: 'blood_moon',
      name: 'Кровавая Луна',
      colors: [Color(0xFFFF1744), Color(0xFFFF5252), Color(0xFF880E4F)],
      previewIcon: Icons.nights_stay_rounded,
    ),
    SteamAvatarFrame(
      id: 'glacial_frost',
      name: 'Ледяной Клинок',
      colors: [Color(0xFF00E5FF), Color(0xFF80D8FF), Color(0xFF2979FF)],
      previewIcon: Icons.ac_unit_rounded,
    ),
    SteamAvatarFrame(
      id: 'infernal_flame',
      name: 'Адское Пламя',
      colors: [Color(0xFFFF3D00), Color(0xFFFF9100), Color(0xFFFFD600)],
      previewIcon: Icons.local_fire_department_rounded,
    ),
    SteamAvatarFrame(
      id: 'terminal_matrix',
      name: 'Матрица Hacker',
      colors: [Color(0xFF00FF66), Color(0xFF00E676), Color(0xFF1DE9B6)],
      previewIcon: Icons.terminal_rounded,
    ),
    SteamAvatarFrame(
      id: 'void_arcana',
      name: 'Бездна Арканы',
      colors: [Color(0xFFD500F9), Color(0xFF651FFF), Color(0xFF3D5AFE)],
      previewIcon: Icons.psychology_rounded,
    ),
    SteamAvatarFrame(
      id: 'cyber_samurai',
      name: 'Кибер-Самурай',
      colors: [Color(0xFFFFD700), Color(0xFF00F0FF), Color(0xFFFF007F)],
      previewIcon: Icons.shield_rounded,
    ),
  ];

  static SteamAvatarFrame fromId(String? id) {
    return all.firstWhere((f) => f.id == id, orElse: () => all.first);
  }
}

class SteamBackgroundTheme {
  final String id;
  final String name;
  final List<Color> gradient;
  final String? assetOrUrl;
  final IconData icon;

  const SteamBackgroundTheme({
    required this.id,
    required this.name,
    required this.gradient,
    this.assetOrUrl,
    required this.icon,
  });

  static const List<SteamBackgroundTheme> all = [
    SteamBackgroundTheme(
      id: 'none',
      name: 'Cinema Dark',
      gradient: [Color(0xFF1E1F24), Color(0xFF121316)],
      icon: Icons.dark_mode_rounded,
    ),
    SteamBackgroundTheme(
      id: 'cyberpunk_edgerunners',
      name: 'Cyberpunk: Edgerunners',
      gradient: [Color(0xFF1B072B), Color(0xFF051C3B), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=1200&q=80',
      icon: Icons.electric_bolt_rounded,
    ),
    SteamBackgroundTheme(
      id: 'solo_leveling',
      name: 'Solo Leveling (Монарх)',
      gradient: [Color(0xFF16062E), Color(0xFF0D142E), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=1200&q=80',
      icon: Icons.flash_on_rounded,
    ),
    SteamBackgroundTheme(
      id: 'attack_on_titan',
      name: 'Атака Титанов (Стена)',
      gradient: [Color(0xFF38140B), Color(0xFF211310), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=1200&q=80',
      icon: Icons.fort_rounded,
    ),
    SteamBackgroundTheme(
      id: 'jujutsu_kaisen',
      name: 'Магическая Битва (Gojo)',
      gradient: [Color(0xFF061838), Color(0xFF1C0838), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=1200&q=80',
      icon: Icons.all_inclusive_rounded,
    ),
    SteamBackgroundTheme(
      id: 'demon_slayer',
      name: 'Клинок Рассекающий (Хиноками)',
      gradient: [Color(0xFF3E120A), Color(0xFF2A0F1E), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=1200&q=80',
      icon: Icons.whatshot_rounded,
    ),
    SteamBackgroundTheme(
      id: 'bleach',
      name: 'Блич: Кровавая Война',
      gradient: [Color(0xFF1C1D24), Color(0xFF2E0911), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=1200&q=80',
      icon: Icons.colorize_rounded,
    ),
    SteamBackgroundTheme(
      id: 'evangelion',
      name: 'Евангелион: Tokyo-3',
      gradient: [Color(0xFF260D38), Color(0xFF142419), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=1200&q=80',
      icon: Icons.warning_amber_rounded,
    ),
    SteamBackgroundTheme(
      id: 'your_name',
      name: 'Твоё Имя: Комета',
      gradient: [Color(0xFF28134F), Color(0xFF162D4A), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=1200&q=80',
      icon: Icons.star_border_purple500_rounded,
    ),
    SteamBackgroundTheme(
      id: 'tokyo_neon',
      name: 'Tokyo Neon Night',
      gradient: [Color(0xFF1D063A), Color(0xFF0B1936), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=1200&q=80',
      icon: Icons.nightlife_rounded,
    ),
    SteamBackgroundTheme(
      id: 'lofi_sunset',
      name: 'Lofi Sunset Chill',
      gradient: [Color(0xFF4A192C), Color(0xFF261835), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=1200&q=80',
      icon: Icons.wb_twilight_rounded,
    ),
    SteamBackgroundTheme(
      id: 'shinjuku_rain',
      name: 'Shinjuku Rain',
      gradient: [Color(0xFF0E2238), Color(0xFF151E2B), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1503899036084-c55cdd92da26?w=1200&q=80',
      icon: Icons.water_drop_rounded,
    ),
    SteamBackgroundTheme(
      id: 'fantasy_sky',
      name: 'Twilight Sky',
      gradient: [Color(0xFF2C1654), Color(0xFF1F2B47), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=1200&q=80',
      icon: Icons.cloud_rounded,
    ),
    SteamBackgroundTheme(
      id: 'sakura_shrine',
      name: 'Sakura Shrine',
      gradient: [Color(0xFF3B152B), Color(0xFF261228), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1528164344705-475426879c0d?w=1200&q=80',
      icon: Icons.local_florist_rounded,
    ),
    SteamBackgroundTheme(
      id: 'cosmic_nebula',
      name: 'Cosmic Nebula',
      gradient: [Color(0xFF1E0A3C), Color(0xFF0B1936), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=1200&q=80',
      icon: Icons.auto_awesome_rounded,
    ),
  ];

  static SteamBackgroundTheme fromId(String? idOrUrl) {
    if (idOrUrl == null || idOrUrl.isEmpty || idOrUrl == 'none') {
      return all.first;
    }
    if (idOrUrl.startsWith('http://') || idOrUrl.startsWith('https://')) {
      return SteamBackgroundTheme(
        id: idOrUrl,
        name: 'Пользовательский арт / GIF',
        gradient: const [Color(0xFF2A2B32), Color(0xFF121316)],
        assetOrUrl: idOrUrl,
        icon: Icons.image_outlined,
      );
    }
    return all.firstWhere((b) => b.id == idOrUrl, orElse: () => all.first);
  }
}

class SteamProfileThemeAccent {
  final String hex;
  final String name;
  final Color color;

  const SteamProfileThemeAccent({
    required this.hex,
    required this.name,
    required this.color,
  });

  static const List<SteamProfileThemeAccent> all = [
    SteamProfileThemeAccent(hex: '#E06C53', name: 'SyncPai Orange', color: Color(0xFFE06C53)),
    SteamProfileThemeAccent(hex: '#00E5FF', name: 'Cyber Cyan', color: Color(0xFF00E5FF)),
    SteamProfileThemeAccent(hex: '#B388FF', name: 'EVA Neon Violet', color: Color(0xFFB388FF)),
    SteamProfileThemeAccent(hex: '#FF2A68', name: 'Ruby Sakura', color: Color(0xFFFF2A68)),
    SteamProfileThemeAccent(hex: '#00FF87', name: 'Emerald Glitch', color: Color(0xFF00FF87)),
    SteamProfileThemeAccent(hex: '#FFD700', name: 'Solar Dragon', color: Color(0xFFFFD700)),
    SteamProfileThemeAccent(hex: '#FF1744', name: 'Blood Crimson', color: Color(0xFFFF1744)),
    SteamProfileThemeAccent(hex: '#9D4EDD', name: 'Deep Void', color: Color(0xFF9D4EDD)),
  ];

  static SteamProfileThemeAccent fromHex(String? hex) {
    return all.firstWhere(
      (a) => a.hex.toLowerCase() == hex?.toLowerCase(),
      orElse: () => all.first,
    );
  }
}

class SteamCustomTitle {
  static const List<String> titles = [
    '',
    'Сенпай в сети',
    'Архимаг Синхрона',
    'Король Пиратов',
    'Тень Монарха',
    'Lofi Ночной Отаку',
    'Кибер-Шиноби',
    'Хранитель Аниме',
    'Спидраннер Сезонов',
    'Повелитель Сакуры',
    'Шинигами из Общества Душ',
  ];
}
