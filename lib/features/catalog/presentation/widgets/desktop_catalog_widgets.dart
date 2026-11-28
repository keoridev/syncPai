import 'package:flutter/material.dart';

import '../../../../core/widgets/manga_panel_painter.dart';
import '../../../../core/widgets/poster_picker_dialog.dart';
import '../../../../core/widgets/safe_anime_poster.dart';
import '../../domain/entities/anime_title.dart';

/// Широкоформатный Hero Spotlight баннер (height: 280) для десктопного каталога.
class DesktopCatalogHeroBanner extends StatelessWidget {
  final AnimeTitle title;
  final VoidCallback onWatchTap;
  final VoidCallback onWatchTogetherTap;

  const DesktopCatalogHeroBanner({
    super.key,
    required this.title,
    required this.onWatchTap,
    required this.onWatchTogetherTap,
  });

  @override
  Widget build(BuildContext context) {
    final isManga = isMangaPrintTheme(context);
    final poster = title.posterOriginal.isNotEmpty
        ? title.posterOriginal
        : (title.posterMedium.isNotEmpty ? title.posterMedium : title.posterSmall);
    final score = title.score != null && title.score! > 0
        ? title.score!.toStringAsFixed(1)
        : null;

    final baseSurface =
        isManga ? const Color(0xFF161920) : const Color(0xFF131722);
    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: baseSurface,
        borderRadius: BorderRadius.circular(isManga ? 12 : 16),
        border: Border.all(
          color: isManga ? const Color(0x33F8FAFC) : const Color(0x18FFFFFF),
          width: isManga ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bannerWidth = constraints.maxWidth;
          final artworkWidth =
              bannerWidth.isFinite ? bannerWidth * 0.62 : 420.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: artworkWidth,
                child: SafeAnimePoster(
                  imageUrl: poster,
                  fallbackUrl: title.effectiveFallbackPoster,
                  title: title.displayTitle,
                  englishTitle: title.englishTitle,
                  malId: title.shikimoriId ?? (title.id > 0 ? title.id : null),
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.25),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: artworkWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: const [0.0, 0.35, 0.85, 1.0],
                      colors: [
                        baseSurface,
                        baseSurface.withValues(alpha: 0.53),
                        baseSurface.withValues(alpha: 0.07),
                        baseSurface.withValues(alpha: 0.80),
                      ],
                    ),
                  ),
                ),
              ),
          if (isManga)
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: MangaPanelPainter()),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (score != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isManga
                                    ? const Color(0xFFF1F5F9)
                                    : const Color(0xFF161920),
                                borderRadius: BorderRadius.circular(6),
                                border: isManga
                                    ? null
                                    : Border.all(color: const Color(0xFFFF6B4A)),
                              ),
                              child: Text(
                                '★ $score',
                                style: TextStyle(
                                  color: isManga
                                      ? const Color(0xFF0D0F12)
                                      : const Color(0xFFFF6B4A),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          for (final g in title.genres.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xCC161B26),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isManga
                                      ? const Color(0x33F8FAFC)
                                      : const Color(0x22FFFFFF),
                                ),
                              ),
                              child: Text(
                                g,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      if (title.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          title.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            height: 40,
                            child: FilledButton.icon(
                              onPressed: onWatchTap,
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(horizontal: 18),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 19),
                              label: const Text(
                                'Смотреть',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 40,
                            child: OutlinedButton.icon(
                              onPressed: onWatchTogetherTap,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: const Color(0xCC161920),
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: isManga
                                      ? const Color(0x4DF8FAFC)
                                      : const Color(0x28FFFFFF),
                                  width: isManga ? 1.5 : 1.0,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.group_add_rounded, size: 17),
                              label: const Text(
                                'Смотреть вместе',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
        },
      ),
    );
  }
}

/// Горизонтальная лента тайтлов со стрелками прокрутки для десктопа.
class DesktopCuratedRow extends StatefulWidget {
  final String heading;
  final List<AnimeTitle> titles;
  final ValueChanged<AnimeTitle> onTitleTap;
  final bool showRankBadges;

  const DesktopCuratedRow({
    super.key,
    required this.heading,
    required this.titles,
    required this.onTitleTap,
    this.showRankBadges = false,
  });

  @override
  State<DesktopCuratedRow> createState() => _DesktopCuratedRowState();
}

class _DesktopCuratedRowState extends State<DesktopCuratedRow> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  String _buildSubtitle(AnimeTitle t) {
    final parts = <String>[];
    if (t.year != null && t.year! > 0) {
      parts.add('${t.year}');
    }
    if (t.genres.isNotEmpty) {
      parts.add(t.genres.take(2).join(', '));
    }
    return parts.join(' • ');
  }

  Widget? _buildStatusOrScoreBadge(AnimeTitle t) {
    if (t.score != null && t.score! > 0) {
      return _buildOverlayPill(
        label: '★ ${t.score!.toStringAsFixed(1)}',
        textColor: const Color(0xFFFBBF24),
        fontSize: 11.5,
      );
    }
    final isAnons =
        t.isAnnounced || t.status.toLowerCase().contains('анонс');
    if (isAnons) {
      final text = t.year != null && t.year! > 0
          ? 'Анонс ${t.year}'
          : 'Анонс';
      return _buildOverlayPill(
        label: text,
        textColor: const Color(0xFF93C5FD),
        fontSize: 11,
      );
    }
    return null;
  }

  Widget _buildOverlayPill({
    required String label,
    required Color textColor,
    required double fontSize,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xE60D0F12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.titles.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isManga = isMangaPrintTheme(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.heading,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _scrollBy(-420),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.chevron_left_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              onPressed: () => _scrollBy(420),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 316,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.titles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final t = widget.titles[i];
              final subtitle = _buildSubtitle(t);
              final statusOrScoreBadge = _buildStatusOrScoreBadge(t);
              return SizedBox(
                width: 165,
                child: InkWell(
                  onTap: () => widget.onTitleTap(t),
                  onSecondaryTap: () => PosterPickerDialog.show(
                    context,
                    title: t,
                  ),
                  onLongPress: () => PosterPickerDialog.show(
                    context,
                    title: t,
                  ),
                  borderRadius: BorderRadius.circular(isManga ? 10 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(isManga ? 10 : 14),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                      isManga ? 10 : 14),
                                  border: Border.all(
                                    color: isManga
                                        ? const Color(0x33F8FAFC)
                                        : const Color(0x18FFFFFF),
                                    width: isManga ? 1.5 : 1.0,
                                  ),
                                ),
                                child: SafeAnimePoster(
                                  key: ValueKey(
                                      'poster_${t.id}_${t.displayTitle}'),
                                  imageUrl: t.posterUrl,
                                  fallbackUrl: t.effectiveFallbackPoster,
                                  title: t.displayTitle,
                                  englishTitle: t.englishTitle,
                                  malId: t.shikimoriId ??
                                      (t.id > 0 ? t.id : null),
                                  borderRadius: isManga ? 8 : 13,
                                  memCacheWidth: 340,
                                ),
                              ),
                              if (widget.showRankBadges)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: _buildOverlayPill(
                                    label: '#${i + 1}',
                                    textColor: i < 3
                                        ? const Color(0xFFFF6B4A)
                                        : const Color(0xFFF8FAFC),
                                    fontSize: 13,
                                  ),
                                ),
                              if (statusOrScoreBadge != null)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: statusOrScoreBadge,
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            t.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
