import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../profile/presentation/widgets/pai_chan_artwork_banner.dart';
import '../../../profile/presentation/widgets/steam_style_profile_header.dart';
import '../../data/repositories/manga_progress_repository.dart';
import '../../data/repositories/manga_repository.dart';
import '../../domain/entities/manga_bridge.dart';
import '../cubit/manga_read_history_cubit.dart';
import '../cubit/user_manga_list_cubit.dart';

/// Определяет нужный Referer-заголовок для CDN-изображений манги.
String? resolveMangaImageReferer(String url, {String? explicitReferer}) {
  if (explicitReferer != null && explicitReferer.trim().isNotEmpty) {
    return explicitReferer.trim();
  }
  final lower = url.toLowerCase();
  if (lower.contains('remanga.org') || lower.contains('reimg.org')) {
    return 'https://remanga.org/';
  }
  if (lower.contains('imglib.info') ||
      lower.contains('cdnlibs.org') ||
      lower.contains('cdnrulib.link') ||
      lower.contains('imgslib.link')) {
    return 'https://mangalib.me/';
  }
  if (lower.contains('senkuro.net') || lower.contains('senkuro.com')) {
    return 'https://senkuro.com/';
  }
  if (lower.contains('desu.')) {
    return 'https://desu.uno/';
  }
  return null;
}

/// Вычисляет нормализованный прямоугольник кадрирования (0.0..1.0) для InteractiveViewer.
({double cropX, double cropY, double cropWidth, double cropHeight})
    computeNormalizedCropRect({
  required Size viewportSize,
  required Size contentSize,
  required Matrix4 transform,
}) {
  if (viewportSize.width <= 0 ||
      viewportSize.height <= 0 ||
      contentSize.width <= 0 ||
      contentSize.height <= 0) {
    return (cropX: 0.0, cropY: 0.0, cropWidth: 1.0, cropHeight: 1.0);
  }

  final scale = transform.getMaxScaleOnAxis().clamp(1.0, 10.0);
  final translation = transform.getTranslation();
  final leftPx = (-translation.x) / scale;
  final topPx = (-translation.y) / scale;
  final visibleWidthPx = viewportSize.width / scale;
  final visibleHeightPx = viewportSize.height / scale;

  final cropWidth = (visibleWidthPx / contentSize.width).clamp(0.05, 1.0);
  final cropHeight = (visibleHeightPx / contentSize.height).clamp(0.05, 1.0);
  final maxX = (1.0 - cropWidth).clamp(0.0, 1.0);
  final maxY = (1.0 - cropHeight).clamp(0.0, 1.0);
  final cropX = (leftPx / contentSize.width).clamp(0.0, maxX);
  final cropY = (topPx / contentSize.height).clamp(0.0, maxY);

  return (
    cropX: cropX,
    cropY: cropY,
    cropWidth: cropWidth,
    cropHeight: cropHeight,
  );
}

/// Рендерит сохранённый кадр манги/манхвы по нормализованным координатам без хранения обрезанных файлов.
class MangaShowcasePanelBanner extends StatelessWidget {
  final MangaShowcasePanel panel;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const MangaShowcasePanelBanner({
    super.key,
    required this.panel,
    required this.width,
    required this.height,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final referer = resolveMangaImageReferer(
      panel.pageUrl,
      explicitReferer: panel.refererHeader,
    );
    final headers = <String, String>{
      if (referer != null) 'Referer': referer,
    };

    final safeCropW = panel.cropWidth.clamp(0.05, 1.0);
    final safeCropH = panel.cropHeight.clamp(0.05, 1.0);
    final imgWidth = width / safeCropW;
    final imgHeight = height / safeCropH;
    final leftOffset = -panel.cropX.clamp(0.0, 1.0 - safeCropW) * imgWidth;
    final topOffset = -panel.cropY.clamp(0.0, 1.0 - safeCropH) * imgHeight;

    final subtitle = panel.displayCaption;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: leftOffset,
                top: topOffset,
                width: imgWidth,
                height: imgHeight,
                child: CachedNetworkImage(
                  imageUrl: wrapCorsSafeUrl(panel.pageUrl),
                  httpHeaders: headers.isEmpty ? null : headers,
                  fit: BoxFit.fill,
                  placeholder: (_, __) => Container(
                    color: const Color(0xFF141821),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF141821),
                    child: const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white38,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.18),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.84),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141821).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0x14FFFFFF)),
                  ),
                  child: const Text(
                    'Вырезка из манги',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: const Color(0xFF131720).withValues(alpha: 0.88),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.crop_rounded,
                        size: 13,
                        color: Colors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Модальный лист интерактивного кадрирования кадра манги/манхвы в формат витрины 16:7.
class MangaPanelCropperSheet extends StatefulWidget {
  final String mangaId;
  final String mangaTitle;
  final String chapterLabel;
  final String pageUrl;
  final String? refererHeader;

  const MangaPanelCropperSheet({
    super.key,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterLabel,
    required this.pageUrl,
    this.refererHeader,
  });

  static Future<MangaShowcasePanel?> show(
    BuildContext context, {
    required String mangaId,
    required String mangaTitle,
    required String chapterLabel,
    required String pageUrl,
    String? refererHeader,
  }) {
    return showModalBottomSheet<MangaShowcasePanel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MangaPanelCropperSheet(
        mangaId: mangaId,
        mangaTitle: mangaTitle,
        chapterLabel: chapterLabel,
        pageUrl: pageUrl,
        refererHeader: refererHeader,
      ),
    );
  }

  @override
  State<MangaPanelCropperSheet> createState() => _MangaPanelCropperSheetState();
}

class _MangaPanelCropperSheetState extends State<MangaPanelCropperSheet> {
  final TransformationController _transformController =
      TransformationController();
  final TextEditingController _captionController = TextEditingController();
  bool _isSaving = false;
  double _imageAspectRatio = 0.7;
  Size _lastViewportSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _resolveImageAspect();
  }

  void _resolveImageAspect() {
    final headers = _buildHeaders();
    final provider = CachedNetworkImageProvider(
      wrapCorsSafeUrl(widget.pageUrl),
      headers: headers.isEmpty ? null : headers,
    );
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (mounted && info.image.height > 0) {
          setState(() {
            _imageAspectRatio = info.image.width / info.image.height;
          });
        }
        stream.removeListener(listener);
      },
      onError: (_, __) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  Map<String, String> _buildHeaders() {
    final referer = resolveMangaImageReferer(
      widget.pageUrl,
      explicitReferer: widget.refererHeader,
    );
    return {
      if (referer != null) 'Referer': referer,
    };
  }

  @override
  void dispose() {
    _transformController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _saveCrop() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final viewport = _lastViewportSize.isEmpty
        ? const Size(320, 140)
        : _lastViewportSize;
    final contentWidth = viewport.width;
    final contentHeight =
        (contentWidth / _imageAspectRatio).clamp(viewport.height, 2000.0);

    final rect = computeNormalizedCropRect(
      viewportSize: viewport,
      contentSize: Size(contentWidth, contentHeight),
      transform: _transformController.value,
    );

    final customCaption = _captionController.text.trim();
    final panel = MangaShowcasePanel(
      mangaId: widget.mangaId,
      mangaTitle: widget.mangaTitle,
      chapterLabel: widget.chapterLabel,
      pageUrl: widget.pageUrl,
      refererHeader: widget.refererHeader,
      customCaption: customCaption.isNotEmpty ? customCaption : null,
      cropX: rect.cropX,
      cropY: rect.cropY,
      cropWidth: rect.cropWidth,
      cropHeight: rect.cropHeight,
    );

    await MangaProgressRepository().saveShowcasePanel(panel);
    if (!mounted) return;
    Navigator.of(context).pop(panel);
  }

  @override
  Widget build(BuildContext context) {
    final headers = _buildHeaders();

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 16, 10, 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1117),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.crop_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Кадрирование для витрины (16:7)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.mangaTitle} • ${widget.chapterLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: const Color(0xFF090B10),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _lastViewportSize = constraints.biggest;
                            final contentWidth = constraints.maxWidth;
                            final contentHeight =
                                (contentWidth / _imageAspectRatio)
                                    .clamp(constraints.maxHeight, 2000.0);

                            return InteractiveViewer(
                              transformationController: _transformController,
                              minScale: 1.0,
                              maxScale: 5.0,
                              constrained: false,
                              boundaryMargin: const EdgeInsets.all(80),
                              child: SizedBox(
                                width: contentWidth,
                                height: contentHeight,
                                child: CachedNetworkImage(
                                  imageUrl: wrapCorsSafeUrl(widget.pageUrl),
                                  httpHeaders:
                                      headers.isEmpty ? null : headers,
                                  fit: BoxFit.fill,
                                  placeholder: (_, __) => const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  errorWidget: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white38,
                                      size: 32,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.75),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _captionController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: 'Подпись / цитата (необязательно)',
                  hintStyle:
                      const TextStyle(color: Colors.white38, fontSize: 12.5),
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF141821),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _transformController.value = Matrix4.identity();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Color(0x1FFFFFFF)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Сбросить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveCrop,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 17),
                      label: const Text(
                        'Поставить в витрину',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Результат выбора оформления для «ВИТРИНА ИЛЛЮСТРАЦИЙ».
class MangaPanelPickerResult {
  final SteamArtworkPreset? preset;
  final MangaShowcasePanel? panel;

  const MangaPanelPickerResult._({this.preset, this.panel});

  factory MangaPanelPickerResult.preset(SteamArtworkPreset preset) =>
      MangaPanelPickerResult._(preset: preset);

  factory MangaPanelPickerResult.panel(MangaShowcasePanel panel) =>
      MangaPanelPickerResult._(panel: panel);
}

/// Модальный лист выбора витрины: «Арты Пай-тян» или «Кадр из манги / манхвы».
class MangaPanelPickerSheet extends StatefulWidget {
  final UserProfile profile;
  final Color accentColor;

  const MangaPanelPickerSheet({
    super.key,
    required this.profile,
    required this.accentColor,
  });

  static Future<MangaPanelPickerResult?> show(
    BuildContext context, {
    required UserProfile profile,
    required Color accentColor,
  }) {
    return showModalBottomSheet<MangaPanelPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MangaPanelPickerSheet(
        profile: profile,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<MangaPanelPickerSheet> createState() => _MangaPanelPickerSheetState();
}

class _MangaPanelPickerSheetState extends State<MangaPanelPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<MangaDexManga> _searchResults = const [];
  bool _isSearching = false;

  MangaDexManga? _selectedManga;
  List<MangaDexChapter> _chapters = const [];
  bool _isLoadingChapters = false;

  MangaDexChapter? _selectedChapter;
  List<String> _pages = const [];
  bool _isLoadingPages = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      final results = await MangaRepository.instance.searchManga(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    });
  }

  Future<void> _selectManga(MangaDexManga manga) async {
    setState(() {
      _selectedManga = manga;
      _selectedChapter = null;
      _chapters = const [];
      _pages = const [];
      _isLoadingChapters = true;
    });
    final chapters = await MangaRepository.instance.getChapters(manga);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _isLoadingChapters = false;
    });
  }

  Future<void> _selectChapter(MangaDexChapter chapter) async {
    final manga = _selectedManga;
    if (manga == null) return;
    setState(() {
      _selectedChapter = chapter;
      _pages = const [];
      _isLoadingPages = true;
    });
    final res = await MangaRepository.instance.getChapterPagesForChapter(
      chapter,
      mangaTitle: manga.title,
      originalTitle: manga.originalTitle,
    );
    if (!mounted) return;
    final urls = res.dataUrls.isNotEmpty ? res.dataUrls : res.dataSaverUrls;
    setState(() {
      _pages = urls;
      _isLoadingPages = false;
    });
  }

  Future<void> _openCropperForPage(String pageUrl) async {
    final manga = _selectedManga;
    final chapter = _selectedChapter;
    if (manga == null || chapter == null) return;

    final chNum = chapter.chapterLabel.trim();
    final chLabel = chNum.isNotEmpty ? 'Глава $chNum' : 'Глава';
    final referer = chapter.id.startsWith('remanga:')
        ? 'https://remanga.org/'
        : (chapter.id.startsWith('desu:') ? 'https://desu.uno/' : null);

    final panel = await MangaPanelCropperSheet.show(
      context,
      mangaId: manga.id,
      mangaTitle: manga.title,
      chapterLabel: chLabel,
      pageUrl: pageUrl,
      refererHeader: referer,
    );
    if (panel != null && mounted) {
      Navigator.of(context).pop(MangaPanelPickerResult.panel(panel));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.84;
    return SafeArea(
      child: Container(
        height: maxHeight,
        margin: const EdgeInsets.fromLTRB(10, 20, 10, 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF141821),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_mosaic_rounded,
                    color: widget.accentColor, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Настройка витрины иллюстраций',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabController,
              indicatorColor: widget.accentColor,
              labelColor: widget.accentColor,
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              tabs: const [
                Tab(text: 'Арты Пай-тян'),
                Tab(text: 'Кадр из манги / манхвы'),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPaiPresetsTab(),
                  _buildMangaPanelTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaiPresetsTab() {
    final presets = SteamStyleProfileHeader.curatedPresets;
    return ListView.separated(
      itemCount: presets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final preset = presets[index];
        final isSelected = widget.profile.artworkUrl == preset.imageUrl;
        final isPai = preset.imageUrl.startsWith('pai_');

        return InkWell(
          onTap: () async {
            await MangaProgressRepository().clearShowcasePanel();
            if (!context.mounted) return;
            Navigator.of(context).pop(MangaPanelPickerResult.preset(preset));
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0xFF1C212E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    isSelected ? widget.accentColor : const Color(0x14FFFFFF),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                SizedBox(
                  width: 132,
                  height: 86,
                  child: isPai
                      ? PaiChanArtworkBanner(
                          artworkId: preset.imageUrl,
                          width: 132,
                          height: 86,
                        )
                      : CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(preset.imageUrl),
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: const Color(0xFF141821),
                            child: const Icon(
                              Icons.image_outlined,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        preset.tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: widget.accentColor,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMangaPanelTab() {
    if (_selectedChapter != null) {
      return _buildPageSelector();
    }
    if (_selectedManga != null) {
      return _buildChapterSelector();
    }
    return _buildMangaSelector();
  }

  Widget _buildMangaSelector() {
    final historyEntries = getIt.isRegistered<MangaReadHistoryCubit>()
        ? getIt<MangaReadHistoryCubit>().state.entries
        : const <MangaHistoryEntry>[];
    final favEntries = getIt.isRegistered<UserMangaListCubit>()
        ? getIt<UserMangaListCubit>().state.entries
        : const <UserMangaEntry>[];

    final quickItems = <MangaDexManga>[];
    final seen = <String>{};
    for (final h in historyEntries) {
      if (seen.add(h.mangaId)) {
        quickItems.add(
          MangaDexManga(
            id: h.mangaId,
            title: h.title,
            coverUrl: h.coverUrl,
          ),
        );
      }
    }
    for (final f in favEntries) {
      if (seen.add(f.mangaId)) {
        quickItems.add(
          MangaDexManga(
            id: f.mangaId,
            title: f.mangaTitle,
            coverUrl: f.coverUrl,
          ),
        );
      }
    }

    final displayList =
        _searchController.text.trim().isNotEmpty ? _searchResults : quickItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Поиск манги или манхвы...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            prefixIcon:
                const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
            filled: true,
            fillColor: const Color(0xFF1C212E),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0x14FFFFFF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0x14FFFFFF)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (_isSearching)
          const Expanded(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (displayList.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'Начните ввод названия или откройте мангу из истории.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: displayList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final manga = displayList[index];
                return InkWell(
                  onTap: () => _selectManga(manga),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C212E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x14FFFFFF)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 42,
                            height: 58,
                            child: manga.coverUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: wrapCorsSafeUrl(manga.coverUrl),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => const Icon(
                                      Icons.menu_book_rounded,
                                      color: Colors.white38,
                                    ),
                                  )
                                : const Icon(
                                    Icons.menu_book_rounded,
                                    color: Colors.white38,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            manga.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white38,
                        ),
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

  Widget _buildChapterSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _selectedManga = null;
                  _chapters = const [];
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                _selectedManga?.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_isLoadingChapters)
          const Expanded(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_chapters.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'Главы не найдены.',
                style: TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _chapters.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final ch = _chapters[index];
                final label = ch.chapterLabel.trim().isNotEmpty
                    ? 'Глава ${ch.chapterLabel}'
                    : 'Глава ${index + 1}';
                return InkWell(
                  onTap: () => _selectChapter(ch),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C212E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x14FFFFFF)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            ch.title.trim().isNotEmpty
                                ? '$label — ${ch.title}'
                                : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white38,
                        ),
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

  Widget _buildPageSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _selectedChapter = null;
                  _pages = const [];
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                'Выберите страницу • Глава ${_selectedChapter?.chapterLabel ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingPages)
          const Expanded(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_pages.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                'Страницы недоступны.',
                style: TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ),
          )
        else
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.68,
              ),
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                final url = _pages[index];
                final headers = <String, String>{};
                if (url.contains('remanga.org') || url.contains('reimg.org')) {
                  headers['Referer'] = 'https://remanga.org/';
                } else if (url.contains('desu.')) {
                  headers['Referer'] = 'https://desu.uno/';
                }
                return InkWell(
                  onTap: () => _openCropperForPage(url),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C212E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x14FFFFFF)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: wrapCorsSafeUrl(url),
                          httpHeaders: headers.isEmpty ? null : headers,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white38,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC141821),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
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

