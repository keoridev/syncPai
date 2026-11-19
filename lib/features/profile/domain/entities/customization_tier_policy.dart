import 'package:flutter/material.dart';

import '../../../support/domain/entities/supporter_tier.dart';

class FrameOptionMeta {
  final String id;
  final String label;
  final SupporterTier requiredTier;
  final List<Color> colors;
  final bool isAnimated;

  const FrameOptionMeta({
    required this.id,
    required this.label,
    required this.requiredTier,
    required this.colors,
    this.isAnimated = false,
  });
}

class HeaderBannerMeta {
  final String id;
  final String label;
  final SupporterTier requiredTier;
  final List<Color> gradient;
  final bool isAnimated;

  const HeaderBannerMeta({
    required this.id,
    required this.label,
    required this.requiredTier,
    required this.gradient,
    this.isAnimated = false,
  });
}

/// Единая политика кастомизации Free vs Plus vs Pro в SyncPai.
class CustomizationTierPolicy {
  static const List<FrameOptionMeta> frames = [
    // 4 бесплатных статичных рамки
    FrameOptionMeta(
      id: 'none',
      label: 'Без рамки',
      requiredTier: SupporterTier.free,
      colors: [Colors.transparent, Colors.transparent],
    ),
    FrameOptionMeta(
      id: 'minimal',
      label: 'Минимал',
      requiredTier: SupporterTier.free,
      colors: [Color(0x40FFFFFF), Color(0x20FFFFFF)],
    ),
    FrameOptionMeta(
      id: 'steel',
      label: 'Сталь',
      requiredTier: SupporterTier.free,
      colors: [Color(0xFF94A3B8), Color(0xFF475569)],
    ),
    FrameOptionMeta(
      id: 'neon_static',
      label: 'Неон',
      requiredTier: SupporterTier.free,
      colors: [Color(0xFF35D9D5), Color(0xFF0EA5E9)],
    ),
    // 3 анимированные рамки для Plus / Pro
    FrameOptionMeta(
      id: 'aurora',
      label: 'Северное сияние',
      requiredTier: SupporterTier.supporter,
      colors: [Color(0xFF35D9D5), Color(0xFF10B981), Color(0xFF8B5CF6)],
      isAnimated: true,
    ),
    FrameOptionMeta(
      id: 'cyber_pulse',
      label: 'Кибер-импульс',
      requiredTier: SupporterTier.supporter,
      colors: [Color(0xFF00E5FF), Color(0xFF3B82F6), Color(0xFFEC4899)],
      isAnimated: true,
    ),
    FrameOptionMeta(
      id: 'founders_gold',
      label: 'Золотой ореол',
      requiredTier: SupporterTier.vip,
      colors: [Color(0xFFFFD54F), Color(0xFFFF9800), Color(0xFFFFF176)],
      isAnimated: true,
    ),
  ];

  static const List<HeaderBannerMeta> banners = [
    // 4 спокойных тёмных градиента (Free)
    HeaderBannerMeta(
      id: 'midnight',
      label: 'Полночь',
      requiredTier: SupporterTier.free,
      gradient: [Color(0xFF0B0E14), Color(0xFF141B2D)],
    ),
    HeaderBannerMeta(
      id: 'graphite',
      label: 'Графит',
      requiredTier: SupporterTier.free,
      gradient: [Color(0xFF111318), Color(0xFF1E222B)],
    ),
    HeaderBannerMeta(
      id: 'deep_ocean',
      label: 'Глубокий океан',
      requiredTier: SupporterTier.free,
      gradient: [Color(0xFF0A1622), Color(0xFF132A3E)],
    ),
    HeaderBannerMeta(
      id: 'slate',
      label: 'Сланец',
      requiredTier: SupporterTier.free,
      gradient: [Color(0xFF12161F), Color(0xFF232938)],
    ),
    // 3 анимированных баннера (Plus / Pro)
    HeaderBannerMeta(
      id: 'animated_aurora',
      label: 'Сияние',
      requiredTier: SupporterTier.supporter,
      gradient: [Color(0xFF0B1F26), Color(0xFF163D42), Color(0xFF231942)],
      isAnimated: true,
    ),
    HeaderBannerMeta(
      id: 'starlight_drift',
      label: 'Звёздный дрейф',
      requiredTier: SupporterTier.supporter,
      gradient: [Color(0xFF0B0E18), Color(0xFF1A1F38), Color(0xFF0F172A)],
      isAnimated: true,
    ),
    HeaderBannerMeta(
      id: 'cyber_grid',
      label: 'Кибер-сетка',
      requiredTier: SupporterTier.vip,
      gradient: [Color(0xFF0D0B1A), Color(0xFF24133D), Color(0xFF0E2936)],
      isAnimated: true,
    ),
  ];

  /// 3 бесплатных базовых акцентных темы
  static const Set<String> freeThemeIds = {
    'winter_2026',
    'cyber_cyan',
    'sunset_orange',
  };

  /// 4 бесплатных статичных рамки
  static const Set<String> freeFrameIds = {
    'none',
    'minimal',
    'steel',
    'neon_static',
  };

  /// 4 бесплатных тёмных градиентных баннера (+ 'none')
  static const Set<String> freeBannerIds = {
    'none',
    'midnight',
    'graphite',
    'deep_ocean',
    'slate',
  };

  static bool hasTier(SupporterTier userTier, SupporterTier requiredTier) {
    return userTier.index >= requiredTier.index;
  }

  static bool isThemeUnlocked(SupporterTier userTier, String presetId) {
    if (freeThemeIds.contains(presetId)) return true;
    return hasTier(userTier, SupporterTier.supporter);
  }

  static SupporterTier requiredTierForFrame(String frameId) {
    for (final f in frames) {
      if (f.id == frameId) return f.requiredTier;
    }
    if (freeFrameIds.contains(frameId)) return SupporterTier.free;
    if (frameId.contains('gold') || frameId.contains('pro') || frameId.contains('founders')) {
      return SupporterTier.vip;
    }
    return SupporterTier.supporter;
  }

  static bool isFrameUnlocked(SupporterTier userTier, String frameId) {
    return hasTier(userTier, requiredTierForFrame(frameId));
  }

  static SupporterTier requiredTierForBanner(String bannerId) {
    if (bannerId.isEmpty || freeBannerIds.contains(bannerId)) {
      return SupporterTier.free;
    }
    if (bannerId.startsWith('http') || bannerId.contains('/') || bannerId.contains('\\')) {
      return SupporterTier.vip;
    }
    for (final b in banners) {
      if (b.id == bannerId) return b.requiredTier;
    }
    if (bannerId.contains('cyber') || bannerId.contains('pro') || bannerId.contains('live')) {
      return SupporterTier.vip;
    }
    return SupporterTier.supporter;
  }

  static bool isBannerUnlocked(SupporterTier userTier, String bannerId) {
    return hasTier(userTier, requiredTierForBanner(bannerId));
  }

  static bool canEditCustomTitle(SupporterTier userTier) =>
      hasTier(userTier, SupporterTier.vip);

  static bool canUseHeroArtwork(SupporterTier userTier) =>
      hasTier(userTier, SupporterTier.vip);

  static int maxFavoriteAnimeCount(SupporterTier userTier) =>
      hasTier(userTier, SupporterTier.vip) ? 3 : 1;

  /// Финальная санитизация кастомизации перед сохранением в Supabase / ProfileState.
  static ({
    String frameId,
    String backgroundId,
    String? customTitle,
    String? artworkUrl,
    String? artworkTitle,
  }) sanitizePayload({
    required SupporterTier tier,
    required String frameId,
    required String backgroundId,
    String? customTitle,
    String? artworkUrl,
    String? artworkTitle,
  }) {
    final safeFrameId = isFrameUnlocked(tier, frameId) ? frameId : 'none';
    final safeBackgroundId = isBannerUnlocked(tier, backgroundId) ? backgroundId : 'none';
    final safeCustomTitle = canEditCustomTitle(tier) ? customTitle : null;

    String? safeArtworkUrl = artworkUrl;
    String? safeArtworkTitle = artworkTitle;
    if (!canUseHeroArtwork(tier) && safeArtworkUrl != null && safeArtworkUrl.isNotEmpty) {
      final isCustomOrLive = safeArtworkUrl.startsWith('live:') ||
          (!safeArtworkUrl.startsWith('http') && !safeArtworkUrl.startsWith('assets/'));
      if (isCustomOrLive) {
        safeArtworkUrl = null;
        safeArtworkTitle = null;
      }
    }

    return (
      frameId: safeFrameId,
      backgroundId: safeBackgroundId,
      customTitle: safeCustomTitle,
      artworkUrl: safeArtworkUrl,
      artworkTitle: safeArtworkTitle,
    );
  }
}

