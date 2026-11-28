import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../network/image_cors_helper.dart';
import '../services/anime_poster_resolver.dart';

/// Безопасный виджет постера: фильтрует 404/placeholder URL-ы Shikimori,
/// заменяет обложки с водяным знаком AniLibria на чистые постеры Shikimori/AniList/Jikan,
/// ограничивает время загрузки 4 секундами и отображает матовую editorial-карточку при отсутствии обложки.
class SafeAnimePoster extends StatefulWidget {
  final String? imageUrl;
  final String? fallbackUrl;
  final String title;
  final String? englishTitle;
  final int? malId;
  final String? yearOrFormat;
  final ValueChanged<String>? onPosterResolved;
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
    this.englishTitle,
    this.malId,
    this.yearOrFormat,
    this.onPosterResolved,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.borderRadius = 0,
    this.memCacheWidth,
    this.monogramFontSize = 36,
  });

  @override
  State<SafeAnimePoster> createState() => _SafeAnimePosterState();
}

class _SafeAnimePosterState extends State<SafeAnimePoster> {
  String? _cleanPosterUrl;
  String? _lockedUrl;
  bool _primaryFailed = false;
  bool _timedOut = false;
  bool _resolveTriggered = false;
  bool _resolveFinishedNull = false;
  int _resolveGeneration = 0;
  Timer? _loadTimeoutTimer;

  @override
  void initState() {
    super.initState();
    AnimePosterResolver.overrideRevision.addListener(_onOverrideRevision);
    _resolveGeneration++;
    _resolveCleanIfNeeded();
    _armLoadTimeout();
  }

  void _onOverrideRevision() {
    if (!mounted) return;
    final cached = AnimePosterResolver.instance.getCachedSync(
      malId: widget.malId,
      title: widget.title,
      englishTitle: widget.englishTitle,
    );
    if (cached != null && cached != _lockedUrl) {
      _loadTimeoutTimer?.cancel();
      setState(() {
        _cleanPosterUrl = cached;
        _lockedUrl = cached;
        _timedOut = false;
        _primaryFailed = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant SafeAnimePoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    final itemChanged = oldWidget.malId != widget.malId ||
        oldWidget.title != widget.title;
    if (itemChanged) {
      _resolveGeneration++;
      _cleanPosterUrl = null;
      _lockedUrl = null;
      _primaryFailed = false;
      _timedOut = false;
      _resolveTriggered = false;
      _resolveFinishedNull = false;
      _resolveCleanIfNeeded();
      _armLoadTimeout();
      return;
    }
    if (oldWidget.imageUrl != widget.imageUrl && _lockedUrl == null) {
      _resolveGeneration++;
      _cleanPosterUrl = null;
      _primaryFailed = false;
      _timedOut = false;
      _resolveTriggered = false;
      _resolveFinishedNull = false;
      _resolveCleanIfNeeded();
      _armLoadTimeout();
    }
  }

  @override
  void dispose() {
    AnimePosterResolver.overrideRevision.removeListener(_onOverrideRevision);
    _loadTimeoutTimer?.cancel();
    super.dispose();
  }

  String? _effectiveUrl() {
    if (_lockedUrl != null) return _lockedUrl;
    if (_timedOut && _cleanPosterUrl == null) {
      return _resolveFinishedNull ? _anilibriaFallbackUrl() : null;
    }
    final rawPrimary =
        _primaryFailed ? null : AnimePosterResolver.sanitizeUrl(widget.imageUrl);
    final primaryIsWatermarked =
        AnimePosterResolver.isAniLibriaWatermarkedUrl(rawPrimary);
    final cleanPrimary =
        (rawPrimary != null && !primaryIsWatermarked) ? rawPrimary : null;

    final rawSecondary = AnimePosterResolver.sanitizeUrl(widget.fallbackUrl);
    final cleanSecondary = (rawSecondary != null &&
            !AnimePosterResolver.isAniLibriaWatermarkedUrl(rawSecondary))
        ? rawSecondary
        : null;

    final clean = _cleanPosterUrl ?? cleanPrimary ?? cleanSecondary;
    if (clean != null) return clean;
    return _resolveFinishedNull ? _anilibriaFallbackUrl() : null;
  }

  String? _anilibriaFallbackUrl() {
    final rawSecondary = AnimePosterResolver.sanitizeUrl(widget.fallbackUrl);
    if (rawSecondary != null && rawSecondary.isNotEmpty) return rawSecondary;
    final rawPrimary =
        _primaryFailed ? null : AnimePosterResolver.sanitizeUrl(widget.imageUrl);
    if (rawPrimary != null && rawPrimary.isNotEmpty) return rawPrimary;
    return null;
  }

  void _armLoadTimeout() {
    _loadTimeoutTimer?.cancel();
    final url = _effectiveUrl();
    if (url == null || url.isEmpty) return;
    _loadTimeoutTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _timedOut = true);
      _triggerFallbackResolve();
    });
  }

  void _resolveCleanIfNeeded() {
    if (_lockedUrl != null) return;
    final primary = AnimePosterResolver.sanitizeUrl(widget.imageUrl);
    if (primary != null &&
        primary.startsWith('http') &&
        !AnimePosterResolver.isAniLibriaWatermarkedUrl(primary)) {
      _lockedUrl = primary;
      return;
    }

    final cached = AnimePosterResolver.instance.getCachedSync(
      malId: widget.malId,
      title: widget.title,
      englishTitle: widget.englishTitle,
    );
    if (cached != null) {
      _cleanPosterUrl = cached;
      _lockedUrl = cached;
      return;
    }

    if (widget.title.trim().isEmpty &&
        (widget.malId == null || widget.malId! <= 0)) {
      _resolveFinishedNull = true;
      return;
    }

    _triggerFallbackResolve();
  }

  void _triggerFallbackResolve() {
    if (_resolveTriggered || _lockedUrl != null) return;
    if (widget.title.trim().isEmpty &&
        (widget.malId == null || widget.malId! <= 0)) {
      return;
    }
    _resolveTriggered = true;
    final gen = _resolveGeneration;
    AnimePosterResolver.instance
        .resolvePoster(
          malId: widget.malId,
          title: widget.title,
          fallbackTitle: widget.englishTitle,
        )
        .then((resolved) {
      if (!mounted || gen != _resolveGeneration || _lockedUrl != null) {
        return;
      }
      if (resolved != null && resolved.isNotEmpty) {
        _loadTimeoutTimer?.cancel();
        setState(() {
          _cleanPosterUrl = resolved;
          _lockedUrl = resolved;
          _timedOut = false;
          _primaryFailed = false;
        });
        widget.onPosterResolved?.call(resolved);
      } else {
        setState(() => _resolveFinishedNull = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final effectiveUrl = _effectiveUrl();
    final effectiveFallback =
        _resolveFinishedNull ? _anilibriaFallbackUrl() : null;

    final Widget inner;
    if (effectiveUrl == null || effectiveUrl.isEmpty) {
      inner = _buildEditorialFallback(key: const ValueKey('editorial'));
    } else {
      inner = CachedNetworkImage(
        key: ValueKey(effectiveUrl),
        imageUrl: wrapCorsSafeUrl(effectiveUrl),
        fit: BoxFit.cover,
        alignment: widget.alignment == Alignment.topCenter
            ? Alignment.center
            : widget.alignment,
        memCacheWidth: widget.memCacheWidth,
        imageBuilder: (context, imageProvider) {
          _loadTimeoutTimer?.cancel();
          _lockedUrl ??= effectiveUrl;
          return Image(
            image: imageProvider,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            alignment: widget.alignment == Alignment.topCenter
                ? Alignment.center
                : widget.alignment,
          );
        },
        placeholder: (_, __) => _buildEditorialFallback(),
        errorWidget: (_, __, ___) {
          _loadTimeoutTimer?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_lockedUrl == effectiveUrl) {
              _lockedUrl = null;
            }
            if (!_primaryFailed) {
              setState(() => _primaryFailed = true);
            }
            _triggerFallbackResolve();
          });
          if (effectiveFallback != null && effectiveFallback != effectiveUrl) {
            return CachedNetworkImage(
              imageUrl: wrapCorsSafeUrl(effectiveFallback),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              memCacheWidth: widget.memCacheWidth,
              placeholder: (_, __) => _buildEditorialFallback(),
              errorWidget: (_, __, ___) => _buildEditorialFallback(),
            );
          }
          return _buildEditorialFallback();
        },
      );
    }

    final content = SizedBox.expand(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child: inner,
      ),
    );

    if (widget.borderRadius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: content,
      );
    }
    return content;
  }

  Widget _buildEditorialFallback({Key? key}) {
    final isCompactThumb = widget.monogramFontSize < 26;
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: const Color(0xFF151923),
        borderRadius: widget.borderRadius > 0
            ? BorderRadius.circular(widget.borderRadius)
            : null,
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _EditorialGridPainter()),
          Center(
            child: Icon(
              Icons.movie_filter_outlined,
              color: const Color(0xFF475569),
              size: isCompactThumb ? 18 : 28,
            ),
          ),
          if (!isCompactThumb && widget.title.trim().isNotEmpty)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (widget.yearOrFormat != null &&
                      widget.yearOrFormat!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.yearOrFormat!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EditorialGridPainter extends CustomPainter {
  const _EditorialGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0AFFFFFF)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const step = 28.0;
    for (double x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height * 0.65, size.height),
        paint,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(8, 8, (size.width - 16).clamp(0, size.width),
          (size.height - 16).clamp(0, size.height)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

