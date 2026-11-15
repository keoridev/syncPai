import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../services/active_room_service.dart';

/// Модальное окно быстрого выбора и смены аниме внутри активной комнаты
/// без закрытия комнаты и без отключения подключенных друзей.
class InRoomAnimePickerSheet extends StatefulWidget {
  final String? roomCode;
  final AnimeTitle? currentTitle;
  final FutureOr<void> Function(AnimeTitle selectedTitle)? onAnimeSelected;
  final List<AnimeTitle>? initialCatalogTitles;

  const InRoomAnimePickerSheet({
    super.key,
    this.roomCode,
    this.currentTitle,
    this.onAnimeSelected,
    this.initialCatalogTitles,
  });

  static Future<AnimeTitle?> show(
    BuildContext context, {
    String? roomCode,
    AnimeTitle? currentTitle,
    FutureOr<void> Function(AnimeTitle selectedTitle)? onAnimeSelected,
    List<AnimeTitle>? initialCatalogTitles,
  }) {
    final isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        MediaQuery.sizeOf(context).width >= 700;

    if (isDesktop) {
      return showDialog<AnimeTitle>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 660),
            child: InRoomAnimePickerSheet(
              roomCode: roomCode,
              currentTitle: currentTitle,
              onAnimeSelected: onAnimeSelected,
              initialCatalogTitles: initialCatalogTitles,
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<AnimeTitle>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.84,
        child: InRoomAnimePickerSheet(
          roomCode: roomCode,
          currentTitle: currentTitle,
          onAnimeSelected: onAnimeSelected,
          initialCatalogTitles: initialCatalogTitles,
        ),
      ),
    );
  }

  @override
  State<InRoomAnimePickerSheet> createState() => _InRoomAnimePickerSheetState();
}

class _InRoomAnimePickerSheetState extends State<InRoomAnimePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  int _selectedTab = 0; // 0 = Каталог и поиск, 1 = Мои закладки
  bool _isSearching = false;
  bool _isSwitching = false;
  List<AnimeTitle> _catalogTitles = const [];
  List<AnimeTitle> _searchResults = const [];
  List<AnimeTitle> _bookmarkedTitles = const [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    List<AnimeTitle> titles = widget.initialCatalogTitles ?? [];

    AnimeListCubit? listCubit;
    try {
      listCubit = context.read<AnimeListCubit>();
    } catch (_) {
      if (getIt.isRegistered<AnimeListCubit>()) {
        listCubit = getIt<AnimeListCubit>();
      }
    }

    if (titles.isEmpty) {
      try {
        final cubit = context.read<CatalogCubit>();
        final st = cubit.state;
        if (st is CatalogLoaded && st.titles.isNotEmpty) {
          titles = st.titles;
        }
      } catch (_) {}
    }

    if (titles.isEmpty && getIt.isRegistered<CatalogCubit>()) {
      try {
        final st = getIt<CatalogCubit>().state;
        if (st is CatalogLoaded && st.titles.isNotEmpty) {
          titles = st.titles;
        }
      } catch (_) {}
    }

    if (titles.isEmpty && getIt.isRegistered<CatalogRepository>()) {
      try {
        titles = await getIt<CatalogRepository>().getUpdates(page: 1, limit: 24);
      } catch (_) {}
    }

    final List<AnimeTitle> bookmarks = [];
    try {
      if (listCubit != null) {
        for (final UserAnimeEntry entry in listCubit.state.allEntries) {
          final safePoster = entry.posterUrl ?? '';
          bookmarks.add(
            AnimeTitle(
              id: entry.animeId,
              code: 'bookmark_${entry.animeId}',
              russianTitle: entry.titleRu,
              englishTitle: entry.titleRu,
              posterSmall: safePoster,
              posterMedium: safePoster,
              posterOriginal: safePoster,
              episodesTotal: entry.episodesTotal,
              genres: [entry.status.labelRu],
              description: '',
              status: entry.status.labelRu,
              episodes: [
                EpisodeItem(
                  episode: entry.lastEpisode > 0 ? entry.lastEpisode : 1,
                  name: 'Серия ${entry.lastEpisode > 0 ? entry.lastEpisode : 1}',
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _catalogTitles = titles;
        _bookmarkedTitles = bookmarks;
      });
    }
  }

  void _onSearchChanged(String rawQuery) {
    _debounce?.cancel();
    final query = rawQuery.trim();
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = const [];
      });
      return;
    }

    // Мгновенная локальная фильтрация уже загруженных тайтлов
    final lower = query.toLowerCase();
    final localMatches = _catalogTitles.where((t) {
      return t.russianTitle.toLowerCase().contains(lower) ||
          t.englishTitle.toLowerCase().contains(lower) ||
          t.genres.any((g) => g.toLowerCase().contains(lower));
    }).toList();

    setState(() {
      _searchResults = localMatches;
      _isSearching = getIt.isRegistered<CatalogRepository>();
    });

    if (!getIt.isRegistered<CatalogRepository>()) return;

    _debounce = Timer(const Duration(milliseconds: 320), () async {
      try {
        final remote = await getIt<CatalogRepository>().searchTitles(query, limit: 20);
        if (!mounted || _searchController.text.trim() != query) return;
        final combined = <int, AnimeTitle>{};
        for (final item in remote) {
          combined[item.id] = item;
        }
        for (final item in localMatches) {
          combined.putIfAbsent(item.id, () => item);
        }
        setState(() {
          _searchResults = combined.values.toList();
          _isSearching = false;
        });
      } catch (_) {
        if (mounted) {
          setState(() => _isSearching = false);
        }
      }
    });
  }

  Future<void> _selectAnime(AnimeTitle selected) async {
    if (_isSwitching) return;
    setState(() => _isSwitching = true);
    try {
      if (widget.onAnimeSelected != null) {
        await widget.onAnimeSelected!(selected);
      } else if (ActiveRoomService.instance.hasActiveRoom) {
        await ActiveRoomService.instance.switchAnimeInActiveRoom(selected);
      }
      if (!mounted) return;
      Navigator.of(context).pop(selected);
    } finally {
      if (mounted) {
        setState(() => _isSwitching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRoom = ActiveRoomService.instance.activeRoom;
    final effectiveRoomCode = widget.roomCode ??
        (activeRoom != null ? ActiveRoomService.instance.formattedRoomCode : 'Комната');
    final effectiveCurrentTitle = widget.currentTitle ?? activeRoom?.title;

    final query = _searchController.text.trim();
    final List<AnimeTitle> displayedList;
    if (query.isNotEmpty) {
      displayedList = _searchResults;
    } else if (_selectedTab == 1) {
      displayedList = _bookmarkedTitles;
    } else {
      displayedList = _catalogTitles;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF13151C),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.65),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок и бейдж комнаты
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Сменить аниме в комнате',
                              style: AppTypography.titleMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                effectiveRoomCode,
                                style: TextStyle(
                                  color: AppColors.primaryLight,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Друзья останутся в комнате и автоматически переключатся на новый тайтл',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    tooltip: 'Закрыть',
                  ),
                ],
              ),

              if (effectiveCurrentTitle != null && effectiveCurrentTitle.id > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_fill_rounded, color: AppColors.syncActive, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Сейчас в комнате: ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          effectiveCurrentTitle.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Поле поиска аниме
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Найти другое аниме по названию или жанру...',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.primary, width: 1.4),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Переключатель вкладок (Каталог / Мои списки)
              if (query.isEmpty)
                Row(
                  children: [
                    _buildFilterChip(
                      index: 0,
                      icon: Icons.explore_outlined,
                      label: 'Популярное в каталоге (${_catalogTitles.length})',
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      index: 1,
                      icon: Icons.bookmark_outline_rounded,
                      label: 'Мои списки (${_bookmarkedTitles.length})',
                    ),
                  ],
                ),

              const SizedBox(height: 12),

              // Список тайтлов
              Expanded(
                child: _isSearching && displayedList.isEmpty
                    ? Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    : displayedList.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.movie_filter_outlined,
                                  color: AppColors.textMuted,
                                  size: 42,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  query.isNotEmpty
                                      ? 'По запросу «$query» ничего не найдено'
                                      : (_selectedTab == 1
                                          ? 'В ваших списках пока нет сохранённых тайтлов'
                                          : 'Введите название аниме в поиск выше'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: displayedList.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = displayedList[index];
                              final isCurrent = effectiveCurrentTitle != null &&
                                  effectiveCurrentTitle.id == item.id &&
                                  item.id > 0;
                              return _buildAnimeItemTile(item, isCurrent: isCurrent);
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimeItemTile(AnimeTitle item, {required bool isCurrent}) {
    final poster = item.posterUrl;
    return InkWell(
      key: ValueKey('in_room_picker_item_${item.id}'),
      onTap: isCurrent ? null : () => _selectAnime(item),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isCurrent
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCurrent
                ? AppColors.primary.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 48,
                height: 66,
                child: poster.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: wrapCorsSafeUrl(poster),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.surfaceElevated,
                          child: const Icon(Icons.movie_outlined, color: Colors.white38, size: 20),
                        ),
                      )
                    : Container(
                        color: AppColors.surfaceElevated,
                        child: const Icon(Icons.movie_outlined, color: Colors.white38, size: 20),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.year != null) '${item.year}',
                      if (item.genres.isNotEmpty) item.genres.take(2).join(' • '),
                      item.episodesBadgeText,
                    ].where((s) => s.isNotEmpty).join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isCurrent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.syncActive.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.syncActive.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  'Играет',
                  style: TextStyle(
                    color: AppColors.syncActive,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _isSwitching ? null : () => _selectAnime(item),
                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                label: const Text(
                  'Включить',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

