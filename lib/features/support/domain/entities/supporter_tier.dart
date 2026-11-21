import 'package:flutter/material.dart';

/// Уровни поддержки SyncPai и связанные с ними возможности.
enum SupporterTier {
  free(
    id: 'free',
    title: 'Базовый аккаунт',
    priceLabel: '0 сом',
    badgeLabel: null,
    icon: Icons.person_outline_rounded,
    accentColor: Color(0xFF9CA3AF),
    perks: [
      'Базовый каталог и синхронный просмотр до 5 друзей',
      'Стандартные стикеры и чат комнаты',
    ],
  ),
  supporter(
    id: 'supporter',
    title: 'SyncPai Plus',
    priceLabel: '99 сом / мес (55 ⭐)',
    badgeLabel: 'Plus',
    icon: Icons.bolt_rounded,
    accentColor: Color(0xFF22D3EE),
    perks: [
      'Живые анимированные рамки («Северное сияние», «Кибер-импульс») и анимированные шапки',
      'Расширенная палитра акцентных цветов интерфейса',
      'Расширенные комнаты Watch Together до 10 друзей + приоритетная синхронизация',
      'Значок саппортера в профиле',
    ],
  ),
  vip(
    id: 'vip',
    title: 'SyncPai Pro',
    priceLabel: '199 сом / мес (110 ⭐)',
    badgeLabel: 'Pro',
    icon: Icons.auto_awesome_rounded,
    accentColor: Color(0xFFA855F7),
    perks: [
      'Всё из SyncPai Plus',
      'Топ-3 любимых тайтла на полке в профиле (вместо 1)',
      'Главная иллюстрация (Steam Artwork / GIF) — загрузка своего арта в витрину',
      'Кастомный титул профиля под никнеймом',
      'Экспорт карточки SyncPai Wrapped без водяного знака',
    ],
  ),
  producer(
    id: 'producer',
    title: 'Founders Club',
    priceLabel: '490 сом навсегда (270 ⭐)',
    badgeLabel: 'Founder',
    icon: Icons.verified_rounded,
    accentColor: Color(0xFFFBBF24),
    perks: [
      'Все возможности SyncPai Pro навсегда без ежемесячных списаний',
      'Эксклюзивная золотая рамка «Золотой ореол» и значок первопроходца Founders Club',
      'Имя в титрах благодарности в разделе «О приложении»',
    ],
  );

  final String id;
  final String title;
  final String priceLabel;
  final String? badgeLabel;
  final IconData icon;
  final Color accentColor;
  final List<String> perks;

  const SupporterTier({
    required this.id,
    required this.title,
    required this.priceLabel,
    required this.badgeLabel,
    required this.icon,
    required this.accentColor,
    required this.perks,
  });

  bool get isSupporterOrAbove => index >= SupporterTier.supporter.index;
  bool get isVipOrAbove => index >= SupporterTier.vip.index;
  bool get isProducer => this == SupporterTier.producer;

  int get starsPrice => switch (this) {
        SupporterTier.supporter => 55,
        SupporterTier.vip => 110,
        SupporterTier.producer => 270,
        SupporterTier.free => 0,
      };

  String get botBuyKey => switch (this) {
        SupporterTier.supporter => 'plus',
        SupporterTier.vip => 'pro',
        SupporterTier.producer => 'founders',
        SupporterTier.free => 'free',
      };

  int get maxRoomParticipants => isSupporterOrAbove ? 10 : 5;
  bool get unlocksRamenFrame => isSupporterOrAbove;
  bool get unlocksAnimatedFrames => isSupporterOrAbove;
  bool get unlocksCyberSticker => isSupporterOrAbove;
  bool get unlocksCustomArtworkUpload => isVipOrAbove;
  bool get unlocksCustomProfileTitle => isVipOrAbove;

  String? get chatBadgeLabel => badgeLabel;

  static List<SupporterTier> get paidTiers => const [
        SupporterTier.supporter,
        SupporterTier.vip,
        SupporterTier.producer,
      ];

  static SupporterTier fromId(String? raw) {
    final cleaned = raw?.trim().toLowerCase() ?? '';
    for (final t in SupporterTier.values) {
      if (t.id == cleaned) return t;
    }
    return SupporterTier.free;
  }
}
