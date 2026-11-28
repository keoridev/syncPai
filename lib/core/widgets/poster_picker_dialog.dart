import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../features/catalog/domain/entities/anime_title.dart';
import '../network/image_cors_helper.dart';
import '../services/anime_poster_resolver.dart';

/// Компактный плоский матовый диалог выбора обложки из AniList, MAL (Jikan) и Shikimori.
class PosterPickerDialog extends StatefulWidget {
  final AnimeTitle title;
  final ValueChanged<String>? onPosterSelected;

  const PosterPickerDialog({
    super.key,
    required this.title,
    this.onPosterSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required AnimeTitle title,
    ValueChanged<String>? onPosterSelected,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => PosterPickerDialog(
        title: title,
        onPosterSelected: onPosterSelected,
      ),
    );
  }

  @override
  State<PosterPickerDialog> createState() => _PosterPickerDialogState();
}

class _PosterPickerDialogState extends State<PosterPickerDialog> {
  late Future<List<PosterCandidate>> _candidatesFuture;

  @override
  void initState() {
    super.initState();
    final malId = widget.title.shikimoriId ??
        (widget.title.id > 0 ? widget.title.id : null);
    _candidatesFuture = AnimePosterResolver.instance.fetchPosterCandidates(
      malId: malId,
      title: widget.title.displayTitle,
      englishTitle: widget.title.englishTitle,
    );
  }

  Future<void> _selectCandidate(PosterCandidate candidate) async {
    final malId = widget.title.shikimoriId ??
        (widget.title.id > 0 ? widget.title.id : null);
    await AnimePosterResolver.instance.setManualPosterOverride(
      malId: malId,
      title: widget.title.displayTitle,
      englishTitle: widget.title.englishTitle,
      url: candidate.url,
    );
    widget.onPosterSelected?.call(candidate.url);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF131722),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x26FFFFFF)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Выбрать обложку',
                      style: TextStyle(
                        color: Color(0xFFF8FAFC),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF94A3B8),
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                widget.title.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<PosterCandidate>>(
                future: _candidatesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  final items = snapshot.data ?? const <PosterCandidate>[];
                  if (items.isEmpty) {
                    return const SizedBox(
                      height: 120,
                      child: Center(
                        child: Text(
                          'Не удалось найти альтернативные обложки',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }
                  return Row(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectCandidate(items[i]),
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF151923),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0x26FFFFFF),
                                        ),
                                      ),
                                      child: CachedNetworkImage(
                                        imageUrl: wrapCorsSafeUrl(items[i].url),
                                        fit: BoxFit.cover,
                                        memCacheWidth: 320,
                                        placeholder: (_, __) => const ColoredBox(
                                          color: Color(0xFF151923),
                                        ),
                                        errorWidget: (_, __, ___) =>
                                            const ColoredBox(
                                          color: Color(0xFF151923),
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1C2230),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0x22FFFFFF),
                                    ),
                                  ),
                                  child: Text(
                                    items[i].source,
                                    style: const TextStyle(
                                      color: Color(0xFFE2E8F0),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

