import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/datasources/mangadex_datasource.dart';
import '../../domain/entities/manga_bridge.dart';
import '../screens/manga_details_screen.dart';

/// Встроенный браузер манги и манхвы внутри каталога SyncPai.
class MangaCatalogView extends StatefulWidget {
  final String searchQuery;

  const MangaCatalogView({
    super.key,
    this.searchQuery = '',
  });

  @override
  State<MangaCatalogView> createState() => _MangaCatalogViewState();
}

class _MangaCatalogViewState extends State<MangaCatalogView> {
  static const List<({String id, String label})> _tabs = [
    (id: 'all', label: 'Всё'),
    (id: 'manhwa', label: 'Манхва'),
    (id: 'manga', label: 'Манга'),
    (id: 'popular', label: 'Популярное'),
    (id: 'completed', label: 'Завершённые'),
  ];

  String _activeTab = 'all';
  bool _russianOnly = true;
  bool _isLoading = true;
  List<MangaDexManga> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadManga();
  }

  @override
  void didUpdateWidget(covariant MangaCatalogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery.trim() != widget.searchQuery.trim()) {
      _loadManga();
    }
  }

  Future<void> _loadManga() async {
    setState(() => _isLoading = true);
    final ds = getIt.isRegistered<MangaDexDataSource>()
        ? getIt<MangaDexDataSource>()
        : MangaDexDataSource();

    final origLang = _activeTab == 'manhwa'
        ? 'ko'
        : (_activeTab == 'manga' ? 'ja' : null);
    final order = _activeTab == 'popular' ? 'rating' : 'followedCount';
    final status = _activeTab == 'completed' ? 'completed' : null;
    final loaded = await ds.browseManga(
      originalLanguage: origLang,
      availableTranslatedLanguage: _russianOnly ? 'ru' : null,
      status: status,
      order: order,
      query: widget.searchQuery,
    );

    if (!mounted) return;
    setState(() {
      _items = loaded;
      _isLoading = false;
    });
  }

  void _openManga(MangaDexManga manga) {
    try {
      context.pushNamed(
        'manga_details',
        pathParameters: {'id': manga.id},
        extra: manga,
      );
    } catch (_) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsScreen(
            mangaId: manga.id,
            initialManga: manga,
          ),
        ),
      );
    }
  }

  Widget _buildLangPill({
    required Key key,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: isSelected ? const Color(0xFF35D9D5).withValues(alpha: 0.18) : const Color(0xFF151923),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF35D9D5) : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPad = screenWidth >= 900 ? 20.0 : (screenWidth < 390 ? 12.0 : 14.0);

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 8),
            child: Row(
              children: [
                _buildLangPill(
                  key: const ValueKey('manga_lang_ru'),
                  label: 'Русский',
                  isSelected: _russianOnly,
                  onTap: () {
                    if (!_russianOnly) {
                      setState(() => _russianOnly = true);
                      _loadManga();
                    }
                  },
                ),
                const SizedBox(width: 8),
                _buildLangPill(
                  key: const ValueKey('manga_lang_all'),
                  label: 'Все языки',
                  isSelected: !_russianOnly,
                  onTap: () {
                    if (_russianOnly) {
                      setState(() => _russianOnly = false);
                      _loadManga();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: horizontalPad),
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final isSelected = tab.id == _activeTab;
                return Material(
                  color: isSelected
                      ? const Color(0xFFFF6B4A)
                      : const Color(0xFF1A2030),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      if (_activeTab != tab.id) {
                        setState(() => _activeTab = tab.id);
                        _loadManga();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Center(
                        child: Text(
                          tab.label,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (_isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_items.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Center(
                child: Text(
                  _activeTab == 'lists'
                      ? 'Вы ещё не начали читать мангу'
                      : 'Ничего не найдено',
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horizontalPad, 0, horizontalPad, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: screenWidth >= 900 ? 210 : 170,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.56,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final manga = _items[index];
                  final typeLabel = manga.originalLanguage == 'ko'
                      ? 'Манхва'
                      : (manga.originalLanguage == 'zh' ? 'Маньхуа' : 'Манга');
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openManga(manga),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (manga.coverUrl.isNotEmpty)
                                    CachedNetworkImage(
                                      imageUrl: wrapCorsSafeUrl(manga.coverUrl),
                                      fit: BoxFit.cover,
                                      memCacheWidth: 360,
                                      errorWidget: (_, __, ___) => const ColoredBox(
                                        color: Color(0xFF161A22),
                                        child: Icon(Icons.menu_book_rounded, color: Colors.white38),
                                      ),
                                    )
                                  else
                                    const ColoredBox(
                                      color: Color(0xFF161A22),
                                      child: Icon(Icons.menu_book_rounded, color: Colors.white38),
                                    ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0B0E14).withValues(alpha: 0.85),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            typeLabel,
                                            style: const TextStyle(
                                              color: Color(0xFF35D9D5),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0B0E14).withValues(alpha: 0.85),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            (manga.hasRussianTranslation || _russianOnly) ? 'RU' : 'EN',
                                            style: TextStyle(
                                              color: (manga.hasRussianTranslation || _russianOnly)
                                                  ? const Color(0xFFFF6B4A)
                                                  : Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            manga.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: _items.length,
              ),
            ),
          ),
      ],
    );
  }
}

