import 'package:flutter/material.dart';

/// Уровни поддержки SyncPai и связанные с ними возможности.
enum SupporterTier {
  free(
    id: 'free',
    title: 'Базовый аккаунт',
    priceLabel: '0 ₽',
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
    priceLabel: '149 ₽ / \$1.5',
    badgeLabel: 'Plus',
    icon: Icons.bolt_rounded,
    accentColor: Color(0xFF22D3EE),
    perks: [
      'Неоновая рамка аватара',
      'Значок саппортера в профиле и чате комнаты',
      'Доступ в закрытый канал бета-тестеров',
    ],
  ),
  vip(
    id: 'vip',
    title: 'SyncPai Pro',
    priceLabel: '349 ₽ / \$4',
    badgeLabel: 'Pro',
    icon: Icons.auto_awesome_rounded,
    accentColor: Color(0xFFA855F7),
    perks: [
      'Все возможности SyncPai Plus',
      'Анимированные рамки и эксклюзивный стикер Пай-тян',
      'Загрузка собственного GIF / арта в витрину профиля',
      'Кастомный титул над ником и комнаты до 10 человек',
    ],
  ),
  producer(
    id: 'producer',
    title: 'Founders Club',
    priceLabel: '990 ₽ / \$12',
    badgeLabel: 'Founder',
    icon: Icons.verified_rounded,
    accentColor: Color(0xFFFBBF24),
    perks: [
      'Все возможности SyncPai Pro',
      'Упоминание в списке основателей проекта',
      'Приоритетный запрос новой фичи или скина',
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

  int get maxRoomParticipants => isVipOrAbove ? 10 : 5;
  bool get unlocksRamenFrame => isSupporterOrAbove;
  bool get unlocksAnimatedFrames => isVipOrAbove;
  bool get unlocksCyberSticker => isVipOrAbove;
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
