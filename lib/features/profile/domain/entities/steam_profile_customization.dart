import 'package:flutter/material.dart';

enum BadgeRarity { common, rare, epic, legendary }

enum BadgeGlowStyle { pulse, metallic, flame }

/// Значок профиля в стиле Steam Profile Badges с функциональными перками и кастомизацией
class SteamBadge {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int level;
  final BadgeRarity rarity;
  final String perkTitle;
  final String perkDescription;
  final String unlockCriteria;

  const SteamBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.level,
    this.rarity = BadgeRarity.rare,
    this.perkTitle = 'Эксклюзивный статус',
    this.perkDescription = 'Выделяет ваш профиль и сообщения среди зрителей',
    this.unlockCriteria = 'Активность в приложении SyncPai',
  });

  static const List<SteamBadge> all = [
    SteamBadge(
      id: 'sync_master',
      title: 'Синхронизатор',
      description: 'Мастер совместного просмотра без единого рассинхрона',
      icon: Icons.sync_alt_rounded,
      color: Color(0xFF00E5FF),
      level: 50,
      rarity: BadgeRarity.epic,
      perkTitle: 'Увеличение комнат до 12 человек',
      perkDescription: 'Позволяет хостить совместный просмотр в расширенных комнатах до 12 участников',
      unlockCriteria: '10 успешных сеансов совместного просмотра без десинхронизации',
    ),
    SteamBadge(
      id: 'marathon_100',
      title: 'Марафонец 100',
      description: 'Просмотрено более 100 серий аниме за один уикенд',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFF6B4A),
      level: 100,
      rarity: BadgeRarity.legendary,
      perkTitle: 'Особый звук входа в лобби',
      perkDescription: 'При вашем подключении к комнате друзья слышат фирменный эпический джингл',
      unlockCriteria: 'Просмотреть 100 серий аниме суммарно за 72 часа',
    ),
    SteamBadge(
      id: 'night_otaku',
      title: 'Ночной Отаку',
      description: 'Сеансы в 4 утра в темноте под шум дождя',
      icon: Icons.bedtime_rounded,
      color: Color(0xFFB388FF),
      level: 25,
      rarity: BadgeRarity.rare,
      perkTitle: 'Темная неоновая тема Danmaku',
      perkDescription: 'Открывает ультра-темный градиент для плавающих комментариев Danmaku',
      unlockCriteria: 'Просмотреть более 5 серий в ночное время (с 02:00 до 06:00)',
    ),
    SteamBadge(
      id: 'anixart_collector',
      title: 'Коллекционер Anixart',
      description: 'Импортировал легендарную библиотеку закладок',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFF00FF87),
      level: 30,
      rarity: BadgeRarity.rare,
      perkTitle: 'Мгновенный офлайн-экспорт списков',
      perkDescription: 'Быстрый экспорт и бэкап аниме-библиотеки в JSON и CSV в 1 клик',
      unlockCriteria: 'Импортировать профиль или CSV закладки из Anixart',
    ),
    SteamBadge(
      id: 'match_swiper',
      title: 'Аниме Matcher',
      description: 'Нашел соулмейта в совместном Anime Match',
      icon: Icons.favorite_rounded,
      color: Color(0xFFFF2A68),
      level: 20,
      rarity: BadgeRarity.rare,
      perkTitle: 'Неоновые сердечки в реакциях',
      perkDescription: 'Уникальный набор летающих реакций с сердечками для стрим-комнаты',
      unlockCriteria: 'Совершить 3 взаимных мэтча в режиме Anime Match с друзьями',
    ),
    SteamBadge(
      id: 'pioneer',
      title: 'Первопроходец SyncPai',
      description: 'Элитный участник ранней бета-версии',
      icon: Icons.military_tech_rounded,
      color: Color(0xFFFFD700),
      level: 99,
      rarity: BadgeRarity.legendary,
      perkTitle: 'Золотой никнейм и VIP значок',
      perkDescription: 'Отображает золотое свечение никнейма в списке участников комнаты',
      unlockCriteria: 'Участие в тестировании SyncPai на этапе закрытого альфа-релиза',
    ),
    SteamBadge(
      id: 'sakura_lord',
      title: 'Повелитель Сакуры',
      description: 'Открывается после 50 часов синхронного просмотра с друзьями',
      icon: Icons.filter_vintage_rounded,
      color: Color(0xFFFF76AC),
      level: 150,
      rarity: BadgeRarity.legendary,
      perkTitle: 'Эксклюзивный цвет текста в Danmaku',
      perkDescription: 'Ваши бегущие строки Danmaku подсвечиваются градиентом Сакуры',
      unlockCriteria: 'Провести 50 часов совместного просмотра в комнатах SyncPai',
    ),
    SteamBadge(
      id: 'fhd_expert',
      title: 'Full HD Эксперт',
      description: 'Смотрит только в 1080p с максимальным битрейтом',
      icon: Icons.high_quality_rounded,
      color: Color(0xFF4A90E2),
      level: 15,
      rarity: BadgeRarity.common,
      perkTitle: 'Приоритетный выбор 1080p 60fps',
      perkDescription: 'Автоматически подключает лучший доступный видеопоток без ожидания',
      unlockCriteria: 'Просмотреть 20 серий в максимальном качестве 1080p',
    ),
    SteamBadge(
      id: 'skip_legend',
      title: 'Скиппер Опенингов',
      description: 'Сэкономил более 24 часов жизни умным автопропуском',
      icon: Icons.fast_forward_rounded,
      color: Color(0xFFE06C53),
      level: 10,
      rarity: BadgeRarity.common,
      perkTitle: 'Мгновенный авто-скип без голосования',
      perkDescription: 'В соло-режиме пропускает опенинг за 0.1 секунды',
      unlockCriteria: 'Пропустить более 50 опенингов умным таймкодом',
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
  /// Тип анимации рамки (для AnimatedAvatarFrame)
  final SteamFrameAnimation animation;

  const SteamAvatarFrame({
    required this.id,
    required this.name,
    required this.colors,
    required this.previewIcon,
    this.animation = SteamFrameAnimation.none,
  });

  static const List<SteamAvatarFrame> all = [
    SteamAvatarFrame(
      id: 'none',
      name: 'Классическая',
      colors: [Color(0xFF2C303B), Color(0xFF1A1C22)],
      previewIcon: Icons.circle_outlined,
      animation: SteamFrameAnimation.none,
    ),
    SteamAvatarFrame(
      id: 'neon_ring',
      name: 'Неоновое кольцо',
      colors: [Color(0xFF00F0FF), Color(0xFF0072FF)],
      previewIcon: Icons.radio_button_checked_rounded,
      animation: SteamFrameAnimation.pulse,
    ),
    SteamAvatarFrame(
      id: 'demon_horns',
      name: 'Демонические рожки',
      colors: [Color(0xFFFF1744), Color(0xFFD50000), Color(0xFF880E4F)],
      previewIcon: Icons.warning_rounded,
      animation: SteamFrameAnimation.fire,
    ),
    SteamAvatarFrame(
      id: 'cyber_glitch',
      name: 'Кибер-глитч',
      colors: [Color(0xFF00FF87), Color(0xFF60EFFF)],
      previewIcon: Icons.grain_rounded,
      animation: SteamFrameAnimation.matrix,
    ),
    SteamAvatarFrame(
      id: 'golden_rank',
      name: 'Золотой ранг',
      colors: [Color(0xFFFFD700), Color(0xFFFFB300), Color(0xFFFFA000)],
      previewIcon: Icons.stars_rounded,
      animation: SteamFrameAnimation.shimmer,
    ),
    SteamAvatarFrame(
      id: 'neon_cyber',
      name: 'Неон Киберпанк',
      colors: [Color(0xFF00F0FF), Color(0xFFFF007F), Color(0xFF00F0FF)],
      previewIcon: Icons.bolt_rounded,
      animation: SteamFrameAnimation.pulse,
    ),
    SteamAvatarFrame(
      id: 'sakura_blossom',
      name: 'Цветение Сакуры',
      colors: [Color(0xFFFF9EB5), Color(0xFFE056FD), Color(0xFFFF9EB5)],
      previewIcon: Icons.local_florist_rounded,
      animation: SteamFrameAnimation.rotate,
    ),
    SteamAvatarFrame(
      id: 'cosmic_void',
      name: 'Космический Войд',
      colors: [Color(0xFF7C83FD), Color(0xFF8A2BE2), Color(0xFF00D2FF)],
      previewIcon: Icons.auto_awesome_rounded,
      animation: SteamFrameAnimation.shimmer,
    ),
    SteamAvatarFrame(
      id: 'golden_dragon',
      name: 'Золотой Дракон',
      colors: [Color(0xFFFFD700), Color(0xFFFF6B4A), Color(0xFFFFD700)],
      previewIcon: Icons.whatshot_rounded,
      animation: SteamFrameAnimation.fire,
    ),
    SteamAvatarFrame(
      id: 'glitch_aurora',
      name: 'Северное Сияние',
      colors: [Color(0xFF00FF87), Color(0xFF60EFFF), Color(0xFF00FF87)],
      previewIcon: Icons.waves_rounded,
      animation: SteamFrameAnimation.wave,
    ),
    SteamAvatarFrame(
      id: 'blood_moon',
      name: 'Кровавая Луна',
      colors: [Color(0xFFFF1744), Color(0xFFFF5252), Color(0xFF880E4F)],
      previewIcon: Icons.nights_stay_rounded,
      animation: SteamFrameAnimation.pulse,
    ),
    SteamAvatarFrame(
      id: 'sakura_lord_neon',
      name: 'Повелитель Сакуры (50ч+)',
      colors: [Color(0xFFFF76AC), Color(0xFFFFD700), Color(0xFFFF2A68)],
      previewIcon: Icons.workspace_premium_rounded,
      animation: SteamFrameAnimation.fire,
    ),
    SteamAvatarFrame(
      id: 'glacial_frost',
      name: 'Ледяной Клинок',
      colors: [Color(0xFF00E5FF), Color(0xFF80D8FF), Color(0xFF2979FF)],
      previewIcon: Icons.ac_unit_rounded,
      animation: SteamFrameAnimation.snow,
    ),
    SteamAvatarFrame(
      id: 'infernal_flame',
      name: 'Адское Пламя',
      colors: [Color(0xFFFF3D00), Color(0xFFFF9100), Color(0xFFFFD600)],
      previewIcon: Icons.local_fire_department_rounded,
      animation: SteamFrameAnimation.fire,
    ),
    SteamAvatarFrame(
      id: 'terminal_matrix',
      name: 'Матрица Hacker',
      colors: [Color(0xFF00FF66), Color(0xFF00E676), Color(0xFF1DE9B6)],
      previewIcon: Icons.terminal_rounded,
      animation: SteamFrameAnimation.matrix,
    ),
    SteamAvatarFrame(
      id: 'void_arcana',
      name: 'Бездна Арканы',
      colors: [Color(0xFFD500F9), Color(0xFF651FFF), Color(0xFF3D5AFE)],
      previewIcon: Icons.psychology_rounded,
      animation: SteamFrameAnimation.shimmer,
    ),
    SteamAvatarFrame(
      id: 'cyber_samurai',
      name: 'Кибер-Самурай',
      colors: [Color(0xFFFFD700), Color(0xFF00F0FF), Color(0xFFFF007F)],
      previewIcon: Icons.shield_rounded,
      animation: SteamFrameAnimation.pulse,
    ),
    // --- Новые рамки ---
    SteamAvatarFrame(
      id: 'rainbow_prism',
      name: 'Радужная Призма',
      colors: [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF)],
      previewIcon: Icons.blur_on_rounded,
      animation: SteamFrameAnimation.rainbow,
    ),
    SteamAvatarFrame(
      id: 'electric_storm',
      name: 'Электрический Шторм',
      colors: [Color(0xFFF5F500), Color(0xFF00BFFF), Color(0xFFF5F500)],
      previewIcon: Icons.flash_on_rounded,
      animation: SteamFrameAnimation.pulse,
    ),
    SteamAvatarFrame(
      id: 'shadow_oni',
      name: 'Тень Они',
      colors: [Color(0xFF4A0000), Color(0xFFCC0000), Color(0xFF4A0000)],
      previewIcon: Icons.sports_martial_arts_rounded,
      animation: SteamFrameAnimation.fire,
    ),
    SteamAvatarFrame(
      id: 'spirit_realm',
      name: 'Мир Духов',
      colors: [Color(0xFF80DEEA), Color(0xFFCE93D8), Color(0xFF80DEEA)],
      previewIcon: Icons.cloud_queue_rounded,
      animation: SteamFrameAnimation.wave,
    ),
    SteamAvatarFrame(
      id: 'mech_core',
      name: 'Ядро Меха',
      colors: [Color(0xFF455A64), Color(0xFF00BCD4), Color(0xFF455A64)],
      previewIcon: Icons.precision_manufacturing_rounded,
      animation: SteamFrameAnimation.rotate,
    ),
    SteamAvatarFrame(
      id: 'cursed_seal',
      name: 'Проклятая Печать',
      colors: [Color(0xFF1A0A2E), Color(0xFF7B1FA2), Color(0xFF1A0A2E)],
      previewIcon: Icons.hexagon_rounded,
      animation: SteamFrameAnimation.shimmer,
    ),
    SteamAvatarFrame(
      id: 'blizzard_snow',
      name: 'Снежная Метель',
      colors: [Color(0xFFE0F7FA), Color(0xFF80DEEA), Color(0xFF00E5FF)],
      previewIcon: Icons.ac_unit_rounded,
      animation: SteamFrameAnimation.snow,
    ),
    SteamAvatarFrame(
      id: 'matrix_hacker',
      name: 'Матрица Hacker',
      colors: [Color(0xFF00FF66), Color(0xFF00E676), Color(0xFF003311)],
      previewIcon: Icons.terminal_rounded,
      animation: SteamFrameAnimation.matrix,
    ),
    SteamAvatarFrame(
      id: 'sakura_drift',
      name: 'Парящая Сакура',
      colors: [Color(0xFFFFB7B2), Color(0xFFFF4081), Color(0xFFFF80AB)],
      previewIcon: Icons.local_florist_rounded,
      animation: SteamFrameAnimation.wave,
    ),
    SteamAvatarFrame(
      id: 'plasma_storm',
      name: 'Плазменный Разряд',
      colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF), Color(0xFFFF007F)],
      previewIcon: Icons.flash_on_rounded,
      animation: SteamFrameAnimation.pulse,
    ),
    SteamAvatarFrame(
      id: 'solar_flare',
      name: 'Солнечная Вспышка',
      colors: [Color(0xFFFF3D00), Color(0xFFFFD600), Color(0xFFFF6D00)],
      previewIcon: Icons.whatshot_rounded,
      animation: SteamFrameAnimation.fire,
    ),
  ];

  static SteamAvatarFrame fromId(String? id) {
    return all.firstWhere((f) => f.id == id, orElse: () => all.first);
  }
}

/// Типы анимаций рамок аватара
enum SteamFrameAnimation {
  none,     // статичная
  pulse,    // пульсирующее свечение
  rotate,   // вращение градиента
  shimmer,  // мерцание
  fire,     // пламя (быстрый pulse + оранжевый glow)
  wave,     // волна (плавный shift)
  snow,     // снежинки вокруг
  matrix,   // зелёные буквы (пульс + зелёный glow)
  rainbow,  // плавная смена цветов
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
      id: 'matrix_digital_rain',
      name: 'Матрица (Живой код)',
      gradient: [Color(0xFF030D06), Color(0xFF003311)],
      assetOrUrl: 'matrix',
      icon: Icons.terminal_rounded,
    ),
    SteamBackgroundTheme(
      id: 'falling_sakura_live',
      name: 'Цветение Сакуры (Live)',
      gradient: [Color(0xFF260D1E), Color(0xFF160914)],
      assetOrUrl: 'sakura',
      icon: Icons.filter_vintage_rounded,
    ),
    SteamBackgroundTheme(
      id: 'cyberpunk_grid_3d',
      name: 'Киберпанк 3D Сетка (Live)',
      gradient: [Color(0xFF090614), Color(0xFF1B072B)],
      assetOrUrl: 'cyberpunk',
      icon: Icons.view_in_ar_rounded,
    ),
    SteamBackgroundTheme(
      id: 'deep_starfield_cosmos',
      name: 'Глубокий Космос (Live)',
      gradient: [Color(0xFF06060F), Color(0xFF140D2B)],
      assetOrUrl: 'starfield',
      icon: Icons.auto_awesome_rounded,
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
      name: 'Solo Leveling (Монарх Live)',
      gradient: [Color(0xFF16062E), Color(0xFF0D142E), Color(0xFF121316)],
      assetOrUrl: 'solo_leveling',
      icon: Icons.flash_on_rounded,
    ),
    SteamBackgroundTheme(
      id: 'attack_on_titan',
      name: 'Атака Титанов (Молния Live)',
      gradient: [Color(0xFF38140B), Color(0xFF211310), Color(0xFF121316)],
      assetOrUrl: 'titan_lightning',
      icon: Icons.electric_bolt_rounded,
    ),
    SteamBackgroundTheme(
      id: 'jujutsu_kaisen',
      name: 'Магическая Битва (Black Flash Live)',
      gradient: [Color(0xFF061838), Color(0xFF1C0838), Color(0xFF121316)],
      assetOrUrl: 'black_flash',
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
      name: 'Блич: Банкай (Рэйацу Live)',
      gradient: [Color(0xFF1C1D24), Color(0xFF2E0911), Color(0xFF121316)],
      assetOrUrl: 'bleach_bankai',
      icon: Icons.colorize_rounded,
    ),
    SteamBackgroundTheme(
      id: 'evangelion',
      name: 'Евангелион (A.T. Field Live)',
      gradient: [Color(0xFF260D38), Color(0xFF142419), Color(0xFF121316)],
      assetOrUrl: 'evangelion_at',
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
    // --- Новые фоны ---
    SteamBackgroundTheme(
      id: 'cyberpunk_city',
      name: 'Киберпанк 2077 Неон',
      gradient: [Color(0xFF0D0221), Color(0xFF0F084B), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1519501025264-65ba15a82390?w=1200&q=80',
      icon: Icons.location_city_rounded,
    ),
    SteamBackgroundTheme(
      id: 'snowy_mountain',
      name: 'Падающий Снег (Зимняя Фудзи)',
      gradient: [Color(0xFF0D1B2A), Color(0xFF1B263B), Color(0xFF121316)],
      assetOrUrl: 'snow',
      icon: Icons.ac_unit_rounded,
    ),
    SteamBackgroundTheme(
      id: 'neon_samurai',
      name: 'Неоновый Самурай',
      gradient: [Color(0xFF2B0938), Color(0xFF1C0A35), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?w=1200&q=80',
      icon: Icons.sports_martial_arts_rounded,
    ),
    SteamBackgroundTheme(
      id: 'retro_synthwave',
      name: 'Ретро Синтвейв 80s',
      gradient: [Color(0xFF370617), Color(0xFF6A040F), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?w=1200&q=80',
      icon: Icons.radio_rounded,
    ),
    SteamBackgroundTheme(
      id: 'bamboo_forest',
      name: 'Бамбуковый Лес Киото',
      gradient: [Color(0xFF0A2312), Color(0xFF133C1E), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1503899036084-c55cdd92da26?w=1200&q=80',
      icon: Icons.forest_rounded,
    ),
    SteamBackgroundTheme(
      id: 'deep_ocean',
      name: 'Бездна Океана',
      gradient: [Color(0xFF03045E), Color(0xFF023E8A), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1682687220063-4742bd7fd538?w=1200&q=80',
      icon: Icons.water_rounded,
    ),
    SteamBackgroundTheme(
      id: 'cherry_blossom_night',
      name: 'Ночная Сакура',
      gradient: [Color(0xFF2C0B1E), Color(0xFF1F0D24), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1522383225653-ed111181a951?w=1200&q=80',
      icon: Icons.local_florist_rounded,
    ),
    SteamBackgroundTheme(
      id: 'pixel_art_room',
      name: 'Уютная Pixel Комната',
      gradient: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1511512578047-dfb367046420?w=1200&q=80',
      icon: Icons.videogame_asset_rounded,
    ),
    SteamBackgroundTheme(
      id: 'snowy_village',
      name: 'Снежная Деревня (Live Снегопад)',
      gradient: [Color(0xFF0F1E36), Color(0xFF182848), Color(0xFF121316)],
      assetOrUrl: 'snow',
      icon: Icons.ac_unit_rounded,
    ),
    SteamBackgroundTheme(
      id: 'matrix_cyberspace',
      name: 'Матрица: Зеленый Код',
      gradient: [Color(0xFF001F0B), Color(0xFF003814), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=1200&q=80',
      icon: Icons.terminal_rounded,
    ),
    SteamBackgroundTheme(
      id: 'ghibli_sunset',
      name: 'Ghibli Закатный Поезд',
      gradient: [Color(0xFF381D2A), Color(0xFF1D283E), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1506703719100-a0f3a48c0f86?w=1200&q=80',
      icon: Icons.train_rounded,
    ),
    SteamBackgroundTheme(
      id: 'cyber_highway',
      name: 'Кибертрасса Под Дождем',
      gradient: [Color(0xFF120324), Color(0xFF07193F), Color(0xFF121316)],
      assetOrUrl: 'https://images.unsplash.com/photo-1519501025264-65ba15a82390?w=1200&q=80',
      icon: Icons.speed_rounded,
    ),
  ];

  static SteamBackgroundTheme fromId(String? idOrUrl) {
    if (idOrUrl == null || idOrUrl.isEmpty || idOrUrl == 'none') {
      return all.first;
    }
    for (final bg in all) {
      if (bg.id == idOrUrl) return bg;
    }
    String effective = idOrUrl.trim();
    if (!effective.startsWith('http://') &&
        !effective.startsWith('https://') &&
        !effective.startsWith('/') &&
        !effective.startsWith('file://') &&
        !effective.contains(':\\') &&
        !effective.contains(':/')) {
      effective = 'https://$effective';
    }
    return SteamBackgroundTheme(
      id: idOrUrl,
      name: 'Пользовательский арт / GIF',
      gradient: const [Color(0xFF2A2B32), Color(0xFF16181F)],
      assetOrUrl: effective,
      icon: Icons.image_outlined,
    );
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

class SteamCountry {
  final String flag;
  final String name;

  const SteamCountry({required this.flag, required this.name});

  static const List<SteamCountry> popular = [
    SteamCountry(flag: '🇰🇬', name: 'Kyrgyzstan'),
    SteamCountry(flag: '🇷🇺', name: 'Russia'),
    SteamCountry(flag: '🇰🇿', name: 'Kazakhstan'),
    SteamCountry(flag: '🇧🇾', name: 'Belarus'),
    SteamCountry(flag: '🇺🇦', name: 'Ukraine'),
    SteamCountry(flag: '🇯🇵', name: 'Japan'),
    SteamCountry(flag: '🇰🇷', name: 'South Korea'),
    SteamCountry(flag: '🇺🇸', name: 'United States'),
    SteamCountry(flag: '🇩🇪', name: 'Germany'),
    SteamCountry(flag: '🇬🇧', name: 'United Kingdom'),
    SteamCountry(flag: '🇫🇷', name: 'France'),
    SteamCountry(flag: '🇨🇦', name: 'Canada'),
    SteamCountry(flag: '🇺🇿', name: 'Uzbekistan'),
    SteamCountry(flag: '🇹🇯', name: 'Tajikistan'),
  ];
}

/// Настройки кастомизации профиля пользователя (Steam Point Shop Live Customization)
class ProfileCustomization {
  final String backgroundType; // 'video', 'image', 'color'
  final String backgroundUrl; // Ссылка на mp4, webp или id процедурного фона
  final String? avatarFrameUrl; // Ссылка на прозрачный PNG/WebP или id рамки
  final String themeColorHex; // Акцентный цвет профиля (#8A2BE2)
  final String showcaseType; // 'favorite_anime', 'stats_badges', 'custom_text'
  final String? customBio; // Текст цитаты профиля
  final String? countryFlag; // Флаг страны (🇰🇬)
  final String? countryName; // Название страны (Kyrgyzstan)
  final String avatarShape; // 'square' или 'circle'

  const ProfileCustomization({
    required this.backgroundType,
    required this.backgroundUrl,
    this.avatarFrameUrl,
    this.themeColorHex = '#8A2BE2',
    this.showcaseType = 'favorite_anime',
    this.customBio,
    this.countryFlag = '🇰🇬',
    this.countryName = 'Kyrgyzstan',
    this.avatarShape = 'square',
  });

  factory ProfileCustomization.defaultSettings() => const ProfileCustomization(
        backgroundType: 'color',
        backgroundUrl: 'none',
        themeColorHex: '#8A2BE2',
        showcaseType: 'favorite_anime',
        countryFlag: '🇰🇬',
        countryName: 'Kyrgyzstan',
        avatarShape: 'square',
      );

  factory ProfileCustomization.fromJson(Map<String, dynamic> json) {
    return ProfileCustomization(
      backgroundType: json['background_type'] as String? ?? 'video',
      backgroundUrl: json['background_url'] as String? ?? json['backgroundId'] as String? ?? 'none',
      avatarFrameUrl: json['avatar_frame_url'] as String? ?? json['frame_id'] as String?,
      themeColorHex: json['theme_color_hex'] as String? ?? json['accent_color'] as String? ?? '#8A2BE2',
      showcaseType: json['showcase_type'] as String? ?? 'favorite_anime',
      customBio: json['custom_bio'] as String? ?? json['bio'] as String?,
      countryFlag: json['country_flag'] as String? ?? json['countryFlag'] as String? ?? '🇰🇬',
      countryName: json['country_name'] as String? ?? json['countryName'] as String? ?? 'Kyrgyzstan',
      avatarShape: json['avatar_shape'] as String? ?? json['avatarShape'] as String? ?? 'square',
    );
  }

  Map<String, dynamic> toJson() => {
        'background_type': backgroundType,
        'background_url': backgroundUrl,
        if (avatarFrameUrl != null) 'avatar_frame_url': avatarFrameUrl,
        'theme_color_hex': themeColorHex,
        'showcase_type': showcaseType,
        if (customBio != null) 'custom_bio': customBio,
        if (countryFlag != null) 'country_flag': countryFlag,
        if (countryName != null) 'country_name': countryName,
        'avatar_shape': avatarShape,
      };

  ProfileCustomization copyWith({
    String? backgroundType,
    String? backgroundUrl,
    String? avatarFrameUrl,
    String? themeColorHex,
    String? showcaseType,
    String? customBio,
    String? countryFlag,
    String? countryName,
    String? avatarShape,
  }) {
    return ProfileCustomization(
      backgroundType: backgroundType ?? this.backgroundType,
      backgroundUrl: backgroundUrl ?? this.backgroundUrl,
      avatarFrameUrl: avatarFrameUrl ?? this.avatarFrameUrl,
      themeColorHex: themeColorHex ?? this.themeColorHex,
      showcaseType: showcaseType ?? this.showcaseType,
      customBio: customBio ?? this.customBio,
      countryFlag: countryFlag ?? this.countryFlag,
      countryName: countryName ?? this.countryName,
      avatarShape: avatarShape ?? this.avatarShape,
    );
  }
}
