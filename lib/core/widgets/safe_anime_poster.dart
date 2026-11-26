import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../network/image_cors_helper.dart';
import '../services/anime_poster_resolver.dart';

/// Безопасный виджет постера: фильтрует 404/placeholder URL-ы Shikimori
/// и отображает плоскую матовую монограмму при отсутствии валидного изображения.
class SafeAnimePoster extends StatelessWidget {
  final String? imageUrl;
  final String? fallbackUrl;
  final String title;
  final BoxFit fit;
  final Alignment alignment;
  final double borderRadius;
  final int? memCacheWidth;
  final double monogramFontSize;

  const SafeAnimePoster({
    super.key,
    required this.imageUrl,
    this.fallbackUrl,
    required this.title,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.borderRadius = 0,
    this.memCacheWidth,
    this.monogramFontSize = 36,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AnimePosterResolver.sanitizeUrl(imageUrl);
    final secondary = AnimePosterResolver.sanitizeUrl(fallbackUrl);
    final effectiveUrl = primary ?? secondary;

    Widget content;
    if (effectiveUrl == null || effectiveUrl.isEmpty) {
      content = _buildMonogram();
    } else {
      content = CachedNetworkImage(
        imageUrl: wrapCorsSafeUrl(effectiveUrl),
        fit: fit,
        alignment: alignment,
        memCacheWidth: memCacheWidth,
        placeholder: (_, __) => _buildMonogram(),
        errorWidget: (_, __, ___) {
          if (primary != null && secondary != null && secondary != primary) {
            return CachedNetworkImage(
              imageUrl: wrapCorsSafeUrl(secondary),
              fit: fit,
              alignment: alignment,
              memCacheWidth: memCacheWidth,
              placeholder: (_, __) => _buildMonogram(),
              errorWidget: (_, __, ___) => _buildMonogram(),
            );
          }
          return _buildMonogram();
        },
      );
    }

    if (borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      );
    }
    return content;
  }

  Widget _buildMonogram() {
    final letter = RegExp(r'[А-Яа-яЁёA-Za-z]')
            .firstMatch(title.trim())
            ?.group(0)
            ?.toUpperCase() ??
        'A';
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius:
            borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white70,
            fontSize: monogramFontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

