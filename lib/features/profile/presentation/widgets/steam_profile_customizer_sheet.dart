import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/cubit/theme_cubit.dart';
import '../../../../core/theme/theme_preset.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/steam_avatar_frame.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../domain/entities/steam_profile_customization.dart';
import '../../../../core/widgets/anime_silhouette_avatars.dart';
import '../../../../core/widgets/holographic_monogram_avatar.dart';
import 'badge_details_sheet.dart';
import 'live_backgrounds/live_background_widget.dart';
import 'media_crop_editor_modal.dart';

/// Интерактивное меню кастомизации профиля в стиле Steam Community & Points Shop
/// Вкладки:
/// 1. Фон (Backdrop) - 15 легендарных аниме артов + ввод любого URL / GIF
/// 2. Рамка (Avatar Frame) - 12 анимированных неоновых/киберпанк рамок
/// 3. Аватар (Avatar) - векторные пресеты + ввод прямого URL / GIF
/// 4. Значки (Steam Badges) - коллекционные значки с уровнями
/// 5. Витрина & О себе - произвольный титул, статус, цитата/био, любимый тайтл
/// 6. Акцент (Theme Accent) - палитра неонового свечения
class SteamProfileCustomizerSheet extends StatefulWidget {
  final UserProfile profile;
  final int initialTabIndex;

  const SteamProfileCustomizerSheet({
    super.key,
    required this.profile,
    this.initialTabIndex = 0,
  });

  static void show(BuildContext context, UserProfile profile, {int initialTabIndex = 0}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: MultiBlocProvider(
          providers: [
            if (getIt.isRegistered<ThemeCubit>())
              BlocProvider.value(value: getIt<ThemeCubit>()),
            if (getIt.isRegistered<AuthCubit>())
              BlocProvider.value(value: getIt<AuthCubit>()),
            if (getIt.isRegistered<CatalogCubit>())
              BlocProvider.value(value: getIt<CatalogCubit>()),
            if (getIt.isRegistered<AnimeListCubit>())
              BlocProvider.value(value: getIt<AnimeListCubit>()),
          ],
          child: SteamProfileCustomizerSheet(
            profile: profile,
            initialTabIndex: initialTabIndex,
          ),
        ),
      ),
    );
  }

  @override
  State<SteamProfileCustomizerSheet> createState() => _SteamProfileCustomizerSheetState();
}

class _SteamProfileCustomizerSheetState extends State<SteamProfileCustomizerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _selectedFrameId;
  late String _selectedBgId;
  late String _selectedAccentHex;
  late String _selectedBadgeId;
  late String _selectedAvatar;
  String? _selectedFavAnimeId;
  String? _selectedFavAnimePoster;

  late TextEditingController _customUrlController;
  late TextEditingController _customAvatarUrlController;
  late TextEditingController _statusController;
  late TextEditingController _titleController;
  late TextEditingController _bioController;
  late TextEditingController _favAnimeController;

  late FocusNode _titleFocusNode;
  late FocusNode _statusFocusNode;
  late FocusNode _bioFocusNode;
  late FocusNode _favAnimeFocusNode;

  static const List<String> _quickStatuses = [
    'Смотрю аниме...',
    'В поиске годноты',
    'Осторожно: спойлеры!',
    'Не спать, смотреть онгоинги',
    'Синхронный вайб',
    'Жду новый сезон',
  ];

  // Живой поиск любимого тайтла для витрины
  Timer? _searchDebounceTimer;
  List<AnimeTitle> _searchedCatalogTitles = [];
  bool _isSearchingTitles = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 5),
    );
    _selectedFrameId = widget.profile.frameId ?? 'none';
    _selectedBgId = widget.profile.backgroundId ?? 'none';
    _selectedAccentHex = widget.profile.accentColor ??
        (getIt.isRegistered<ThemeCubit>()
            ? '#${getIt<ThemeCubit>().state.currentPreset.primaryColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
            : '#E06C53');
    _selectedBadgeId = widget.profile.badgeId ?? 'sync_master';
    _selectedAvatar = widget.profile.avatarUrl ?? 'cat';
    _selectedFavAnimeId = widget.profile.favoriteAnimeId;
    _selectedFavAnimePoster = widget.profile.favoriteAnimePoster;

    _customUrlController = TextEditingController(
      text: _selectedBgId.startsWith('http') ? _selectedBgId : '',
    );
    _customAvatarUrlController = TextEditingController(
      text: _selectedAvatar.startsWith('http') ? _selectedAvatar : '',
    );
    _statusController = TextEditingController(
      text: widget.profile.customStatus ?? 'Смотрю аниме...',
    );
    _titleController = TextEditingController(
      text: widget.profile.customTitle ?? '',
    );
    _bioController = TextEditingController(
      text: widget.profile.bio ?? '',
    );
    _favAnimeController = TextEditingController(
      text: widget.profile.favoriteAnimeTitle ?? '',
    );

    _titleFocusNode = FocusNode()..addListener(() => _ensureFocusVisible(_titleFocusNode));
    _statusFocusNode = FocusNode()..addListener(() => _ensureFocusVisible(_statusFocusNode));
    _bioFocusNode = FocusNode()..addListener(() => _ensureFocusVisible(_bioFocusNode));
    _favAnimeFocusNode = FocusNode()..addListener(() => _ensureFocusVisible(_favAnimeFocusNode));
  }

  void _ensureFocusVisible(FocusNode node) {
    if (node.hasFocus) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (node.context != null) {
          Scrollable.ensureVisible(
            node.context!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: 0.5,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _tabController.dispose();
    _customUrlController.dispose();
    _customAvatarUrlController.dispose();
    _statusController.dispose();
    _titleController.dispose();
    _bioController.dispose();
    _favAnimeController.dispose();
    _titleFocusNode.dispose();
    _statusFocusNode.dispose();
    _bioFocusNode.dispose();
    _favAnimeFocusNode.dispose();
    super.dispose();
  }

  void _onFavSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    final q = query.trim();
    if (q.length < 2) {
      setState(() {
        _searchedCatalogTitles = [];
        _isSearchingTitles = false;
      });
      return;
    }

    setState(() {
      _isSearchingTitles = true;
    });

    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        if (getIt.isRegistered<CatalogRepository>()) {
          final results = await getIt<CatalogRepository>().searchTitles(q, limit: 10);
          if (mounted) {
            setState(() {
              _searchedCatalogTitles = results;
              _isSearchingTitles = false;
            });
          }
        } else {
          if (mounted) setState(() => _isSearchingTitles = false);
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingTitles = false);
      }
    });
  }

  void _applyChanges() {
    HapticFeedback.heavyImpact();
    final newStatus = _statusController.text.trim();
    final newFavAnime = _favAnimeController.text.trim();
    final newTitle = _titleController.text.trim();
    final newBio = _bioController.text.trim();

    // Если введен кастомный URL аватара — берем его
    final effectiveAvatar = _customAvatarUrlController.text.trim().isNotEmpty
        ? _customAvatarUrlController.text.trim()
        : _selectedAvatar;

    final customBgUrl = _customUrlController.text.trim();
    final effectiveBg = (customBgUrl.isNotEmpty && customBgUrl != 'none')
        ? customBgUrl
        : _selectedBgId;

    String? effectiveFavPoster = _selectedFavAnimePoster;
    String? effectiveFavId = _selectedFavAnimeId;

    if (newFavAnime.isNotEmpty && (effectiveFavPoster == null || effectiveFavPoster.isEmpty)) {
      if (_searchedCatalogTitles.isNotEmpty) {
        final searchMatch = _searchedCatalogTitles.first;
        effectiveFavPoster = searchMatch.posterUrl.isNotEmpty
            ? searchMatch.posterUrl
            : searchMatch.effectiveFallbackPoster;
        effectiveFavId = searchMatch.id.toString();
      } else {
        try {
          if (getIt.isRegistered<CatalogCubit>()) {
            final catState = getIt<CatalogCubit>().state;
            if (catState is CatalogLoaded) {
              final m = catState.titles.firstWhere(
                (t) => t.russianTitle.toLowerCase().contains(newFavAnime.toLowerCase()) ||
                       t.englishTitle.toLowerCase().contains(newFavAnime.toLowerCase()),
              );
              effectiveFavPoster = m.posterUrl.isNotEmpty ? m.posterUrl : m.effectiveFallbackPoster;
              effectiveFavId = m.id.toString();
            }
          }
        } catch (_) {}
      }
    }

    // 1. Сохраняем в AuthCubit
    context.read<AuthCubit>().updateProfile(
          username: widget.profile.username,
          avatarUrl: effectiveAvatar,
          frameId: _selectedFrameId,
          backgroundId: effectiveBg,
          customTitle: newTitle.isNotEmpty ? newTitle : null,
          customStatus: newStatus.isNotEmpty ? newStatus : null,
          bio: newBio.isNotEmpty ? newBio : null,
          badgeId: _selectedBadgeId,
          favoriteAnimeTitle: newFavAnime.isNotEmpty ? newFavAnime : null,
          favoriteAnimeId: newFavAnime.isNotEmpty ? effectiveFavId : null,
          favoriteAnimePoster: newFavAnime.isNotEmpty ? effectiveFavPoster : null,
          accentColor: _selectedAccentHex,
        );

    // 2. СИНХРОНИЗАЦИЯ С ТЕМОЙ ПРИЛОЖЕНИЯ:
    // Динамически применяем выбранный цвет ко всему приложению!
    if (getIt.isRegistered<ThemeCubit>()) {
      final accent = SteamProfileThemeAccent.fromHex(_selectedAccentHex);
      final matchingPreset = ThemePreset.all.firstWhere(
        (p) => p.primaryColor.toARGB32() == accent.color.toARGB32(),
        orElse: () => ThemePreset(
          id: 'accent_${accent.hex.replaceAll('#', '')}',
          name: accent.name,
          description: 'Индивидуальная тема профиля',
          primaryColor: accent.color,
        ),
      );
      getIt<ThemeCubit>().setPreset(matchingPreset);
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✨ Кастомизация профиля и тема оформления успешно применены!'),
        backgroundColor: AppColors.syncActive,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgTheme = SteamBackgroundTheme.fromId(_selectedBgId);
    final accent = SteamProfileThemeAccent.fromHex(_selectedAccentHex).color;
    final badge = SteamBadge.fromId(_selectedBadgeId);
    final effectiveAvatar = _customAvatarUrlController.text.trim().isNotEmpty
        ? _customAvatarUrlController.text.trim()
        : _selectedAvatar;

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Полоска handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.strokeMedium,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),

          // Заголовок
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.palette_outlined, color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Кастомизация Steam',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Интерактивный живой предпросмотр профиля
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.5),
              child: Stack(
                children: [
                  // Арт на фоне (сеть или файл из галереи)
                  Positioned.fill(
                    child: _buildPreviewBg(bgTheme),
                  ),

                  // Градиентная маска
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.25),
                            Colors.black.withValues(alpha: 0.8),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),

                  // Инфо поверх
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        SteamAvatarFrameWidget(
                          frameId: _selectedFrameId,
                          size: 56,
                          child: AppAvatar(
                            avatarUrl: effectiveAvatar,
                            username: widget.profile.username,
                            size: 56,
                            borderColor: accent,
                            borderWidth: 1.5,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.profile.username,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        shadows: [
                                          Shadow(color: Colors.black, blurRadius: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Значок Steam
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: badge.color.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: badge.color, width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(badge.icon, size: 10, color: badge.color),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${badge.level}',
                                          style: TextStyle(
                                            color: badge.color,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _statusController.text.isNotEmpty
                                    ? _statusController.text
                                    : 'Смотрю аниме...',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  shadows: const [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ],
                                ),
                              ),
                              if (_titleController.text.trim().isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.7),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    _titleController.text.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Вкладки кастомизации
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: accent,
            labelColor: accent,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              Tab(text: 'Фон (${SteamBackgroundTheme.all.length})'),
              Tab(text: 'Рамка (${SteamAvatarFrame.all.length})'),
              const Tab(text: 'Аватар'),
              const Tab(text: 'Значки'),
              const Tab(text: 'Витрина'),
              const Tab(text: 'Цвета'),
            ],
          ),

          // Содержимое вкладок
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBackgroundTab(accent),
                _buildFramesTab(accent),
                _buildAvatarTab(accent),
                _buildBadgesTab(accent),
                _buildShowcaseTab(accent),
                _buildColorsTab(accent),
              ],
            ),
          ),

          // Кнопка применить
          Padding(
            padding: const EdgeInsets.all(AppDimensions.spacingXl),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                onPressed: _applyChanges,
                child: const Text(
                  'Применить кастомизацию',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBg(SteamBackgroundTheme bgTheme) {
    return LiveBackgroundWidget(
      backgroundId: _selectedBgId,
      assetOrUrl: _customUrlController.text.trim().isNotEmpty
          ? _customUrlController.text.trim()
          : (bgTheme.assetOrUrl ?? _selectedBgId),
      fallbackGradient: bgTheme.gradient,
    );
  }

  // --- 1. ВКЛАДКА «ФОН» ---
  Widget _buildBackgroundTab(Color accent) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl, vertical: 12),
      children: [
        // Выбор из галереи устройства (фото, GIF или зацикленное видео MP4/WebM)
        OutlinedButton.icon(
          icon: const Icon(Icons.video_library_rounded, size: 20),
          label: const Text('Загрузить фото, GIF или видео (MP4)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: accent.withValues(alpha: 0.6), width: 1.2),
            backgroundColor: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () async {
            try {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'webm'],
                withData: true,
              );
              if (result != null && result.files.isNotEmpty) {
                final file = result.files.first;
                final appDir = await getApplicationDocumentsDirectory();
                final ext = file.extension ?? 'jpg';
                final targetPath = '${appDir.path}/custom_bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
                final targetFile = File(targetPath);

                if (file.bytes != null) {
                  await targetFile.writeAsBytes(file.bytes!);
                } else if (file.path != null) {
                  await File(file.path!).copy(targetPath);
                }

                if (mounted && targetFile.existsSync()) {
                  final isVideo = ext == 'mp4' || ext == 'webm';
                  if (!isVideo && context.mounted) {
                    await MediaCropEditorModal.show(
                      context,
                      imagePathOrUrl: targetFile.path,
                      shape: CropShape.banner,
                    );
                  }
                  setState(() {
                    _selectedBgId = targetFile.path;
                    _customUrlController.text = targetFile.path;
                  });
                }
              }
            } catch (e) {
              debugPrint('Custom bg pick error: $e');
            }
          },
        ),
        const SizedBox(height: 14),

        // Ввод произвольного URL или GIF
        Text('Или вставьте прямую ссылку на арт/GIF:',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customUrlController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://example.com/art.jpg или .gif',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.strokeMedium),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.strokeMedium),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    setState(() => _selectedBgId = val.trim());
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent.withValues(alpha: 0.2),
                foregroundColor: accent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final url = _customUrlController.text.trim();
                if (url.isNotEmpty) {
                  setState(() => _selectedBgId = url);
                }
              },
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),

        const SizedBox(height: 18),
        Text('Коллекция легендарных аниме фонов:',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 10),

        // Сетка предзагруженных фонов
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
          ),
          itemCount: SteamBackgroundTheme.all.length,
          itemBuilder: (context, index) {
            final bg = SteamBackgroundTheme.all[index];
            final isSelected = _selectedBgId == bg.id;

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedBgId = bg.id;
                  _customUrlController.clear();
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? accent : AppColors.strokeMedium,
                    width: isSelected ? 2.5 : 1.0,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.5),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (bg.assetOrUrl != null)
                        CachedNetworkImage(
                          imageUrl: bg.assetOrUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: bg.gradient),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: bg.gradient),
                          ),
                        ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            bg.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, size: 12, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // --- 2. ВКЛАДКА «РАМКА» ---
  Widget _buildFramesTab(Color accent) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth <= 360;
        final isWide = constraints.maxWidth >= 600;
        final crossCount = isNarrow ? 2 : (isWide ? 4 : 3);
        final ratio = isNarrow ? 0.72 : (isWide ? 0.85 : 0.68);

        return GridView.builder(
          padding: EdgeInsets.symmetric(
            horizontal: isNarrow ? 8 : AppDimensions.spacingXl,
            vertical: 12,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossCount,
            crossAxisSpacing: isNarrow ? 8 : 10,
            mainAxisSpacing: isNarrow ? 8 : 10,
            childAspectRatio: ratio,
          ),
          itemCount: SteamAvatarFrame.all.length,
          itemBuilder: (context, index) {
            final frame = SteamAvatarFrame.all[index];
            final isSelected = _selectedFrameId == frame.id;

            return InkWell(
              onTap: () => setState(() => _selectedFrameId = frame.id),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? accent.withValues(alpha: 0.12) : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? accent : AppColors.strokeMedium,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: SteamAvatarFrameWidget(
                          frameId: frame.id,
                          size: 30,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF1E2028),
                            ),
                            child: Icon(frame.previewIcon, size: 15, color: frame.colors.first),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              frame.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isNarrow ? 9.5 : 10.5,
                                height: 1.15,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- 3. ВКЛАДКА «АВАТАР» ---
  Widget _buildAvatarTab(Color accent) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl, vertical: 14),
      children: [
        // Загрузка своего аватара из галереи в оригинальном разрешении
        OutlinedButton.icon(
          icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
          label: const Text('Загрузить свой аватар из галереи'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: accent.withValues(alpha: 0.6), width: 1.2),
            backgroundColor: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () async {
            try {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.image,
                withData: true,
              );
              if (result != null && result.files.isNotEmpty) {
                final file = result.files.first;
                final appDir = await getApplicationDocumentsDirectory();
                final ext = file.extension ?? 'jpg';
                final targetPath = '${appDir.path}/custom_avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
                final targetFile = File(targetPath);

                if (file.bytes != null) {
                  await targetFile.writeAsBytes(file.bytes!);
                } else if (file.path != null) {
                  await File(file.path!).copy(targetPath);
                }

                if (mounted && targetFile.existsSync()) {
                  if (context.mounted) {
                    await MediaCropEditorModal.show(
                      context,
                      imagePathOrUrl: targetFile.path,
                      shape: CropShape.circle,
                    );
                  }
                  setState(() {
                    _selectedAvatar = targetFile.path;
                    _customAvatarUrlController.text = targetFile.path;
                  });
                }
              }
            } catch (e) {
              debugPrint('Custom avatar pick error: $e');
            }
          },
        ),
        const SizedBox(height: 14),

        Text('Или вставьте прямую ссылку на аватар/GIF:',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customAvatarUrlController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://example.com/avatar.gif или .png',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.strokeMedium),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.strokeMedium),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                ),
                onChanged: (val) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            if (_customAvatarUrlController.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.clear_rounded, color: AppColors.textSecondary),
                onPressed: () {
                  setState(() {
                    _customAvatarUrlController.clear();
                  });
                },
              ),
          ],
        ),

        const SizedBox(height: 18),
        Text('Премиальные арт-пресеты (Anime Silhouettes & Hologram):',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 10),

        // Голографическая монограмма из матового стекла
        InkWell(
          onTap: () {
            setState(() {
              _selectedAvatar = '';
              _customAvatarUrlController.clear();
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: (_selectedAvatar.isEmpty && _customAvatarUrlController.text.isEmpty)
                  ? accent.withValues(alpha: 0.16)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (_selectedAvatar.isEmpty && _customAvatarUrlController.text.isEmpty)
                    ? accent
                    : AppColors.strokeMedium,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                HolographicMonogramAvatar(
                  text: widget.profile.username,
                  size: 48,
                  accentColor: accent,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Голографическая монограмма',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Стеклянный Glassmorphism с радужным переливом и инициалом',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_selectedAvatar.isEmpty && _customAvatarUrlController.text.isEmpty)
                  Icon(Icons.check_circle_rounded, color: accent, size: 20),
              ],
            ),
          ),
        ),

        // Сетка Dark Cyberpunk аниме-силуэтов
        ...AnimeSilhouettePreset.presets.map((preset) {
          final isSelected = _selectedAvatar == preset.id && _customAvatarUrlController.text.isEmpty;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedAvatar = preset.id;
                  _customAvatarUrlController.clear();
                });
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected ? preset.eyeColor.withValues(alpha: 0.15) : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? preset.eyeColor : AppColors.strokeMedium,
                    width: isSelected ? 1.8 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    AppAvatar(
                      avatarUrl: preset.id,
                      size: 46,
                      borderColor: isSelected ? preset.eyeColor : AppColors.strokeMedium,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            preset.title,
                            style: TextStyle(color: preset.eyeColor, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: preset.eyeColor, size: 20),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // --- 4. ВКЛАДКА «ЗНАЧКИ STEAM» ---
  Widget _buildBadgesTab(Color accent) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl, vertical: 14),
      itemCount: SteamBadge.all.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final b = SteamBadge.all[index];
        final isSelected = _selectedBadgeId == b.id;

        return InkWell(
          onTap: () => setState(() => _selectedBadgeId = b.id),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected ? b.color.withValues(alpha: 0.12) : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? b.color : AppColors.strokeMedium,
                width: isSelected ? 1.8 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: b.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: b.color.withValues(alpha: 0.6)),
                  ),
                  child: Icon(b.icon, color: b.color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            b.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: b.color.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'LVL ${b.level}',
                              style: TextStyle(
                                color: b.color,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        b.description,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.info_outline_rounded,
                    color: b.color.withValues(alpha: 0.8),
                    size: 20,
                  ),
                  tooltip: 'Перки и детали значка',
                  onPressed: () {
                    BadgeDetailsSheet.show(
                      context,
                      badge: b,
                      onSelectBadge: () {
                        setState(() => _selectedBadgeId = b.id);
                      },
                    );
                  },
                ),
                if (isSelected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle_rounded, color: b.color, size: 20),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // --- 5. ВКЛАДКА «ВИТРИНА & О СЕБЕ» ---
  Widget _buildShowcaseTab(Color accent) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: AppDimensions.spacingXl,
        right: AppDimensions.spacingXl,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 36,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Живой интерактивный предпросмотр Витрины (Live Preview)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.15),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.visibility_rounded, color: accent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'ПРЕДПРОСМОТР ВИТРИНЫ',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_titleController.text.trim().isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accent, width: 0.8),
                    ),
                    child: Text(
                      _titleController.text.trim(),
                      style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  '«${_statusController.text.isNotEmpty ? _statusController.text : 'Смотрю аниме...'}»',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                if (_bioController.text.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _bioController.text.trim(),
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),

          // Произвольный кастомный титул
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Кастомный титул профиля:',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
              Text('${_titleController.text.length}/30',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            maxLength: 30,
            cursorColor: accent,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Например: Тень Монарха, Верховный Архимаг...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: SteamCustomTitle.titles.where((t) => t.isNotEmpty).map((t) {
              return InkWell(
                onTap: () {
                  setState(() {
                    _titleController.text = t;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: Text(t, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // Статус
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Статус в профиле:',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
              Text('${_statusController.text.length}/50',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _statusController,
            focusNode: _statusFocusNode,
            maxLength: 50,
            cursorColor: accent,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Что сейчас делаете?',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
            onChanged: (val) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _quickStatuses.map((s) {
              return InkWell(
                onTap: () {
                  setState(() {
                    _statusController.text = s;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: Text(s, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // О себе / Цитата
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('О себе / Цитата:',
                  style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
              Text('${_bioController.text.length}/150',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _bioController,
            focusNode: _bioFocusNode,
            maxLines: 2,
            maxLength: 150,
            cursorColor: accent,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Любимая цитата из аниме или пара слов о себе...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
            onChanged: (val) => setState(() {}),
          ),

          const SizedBox(height: 14),

          // Любимый тайтл на витрине с живым автодополнением
          Text('Любимый тайтл на витрине:',
              style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          if (_selectedFavAnimePoster != null && _selectedFavAnimePoster!.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: wrapCorsSafeUrl(_selectedFavAnimePoster!),
                      width: 40,
                      height: 56,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 24),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _favAnimeController.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Постер выбран для витрины',
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                    onPressed: () {
                      setState(() {
                        _favAnimeController.clear();
                        _selectedFavAnimeId = null;
                        _selectedFavAnimePoster = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
          TextField(
            controller: _favAnimeController,
            focusNode: _favAnimeFocusNode,
            cursorColor: accent,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Начните вводить название (например: Восхождение в тени)...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface,
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
              suffixIcon: _favAnimeController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textMuted),
                      onPressed: () {
                        setState(() {
                          _favAnimeController.clear();
                          _selectedFavAnimeId = null;
                          _selectedFavAnimePoster = null;
                        });
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.strokeMedium),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
            onChanged: (val) {
              setState(() {});
              _onFavSearchChanged(val);
            },
          ),

        // Выпадающий список совпадений из каталога и живого поиска для мгновенного выбора
        if (_favAnimeController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Builder(
            builder: (context) {
              final q = _favAnimeController.text.toLowerCase().trim();
              final catalogState = getIt.isRegistered<CatalogCubit>()
                  ? getIt<CatalogCubit>().state
                  : null;
              final savedEntries = getIt.isRegistered<AnimeListCubit>()
                  ? getIt<AnimeListCubit>().state.allEntries
                  : const <UserAnimeEntry>[];

              // Объединяем результаты: живой поиск API AniLibria, сохраненные списки, кэш каталога
              final Map<int, AnimeTitle> combined = {};

              // 1. Результаты живого поиска по API
              for (final t in _searchedCatalogTitles) {
                combined[t.id] = t;
              }

              // 2. Результаты из загруженного каталога
              if (catalogState is CatalogLoaded) {
                for (final t in catalogState.titles) {
                  if (t.russianTitle.toLowerCase().contains(q) ||
                      t.englishTitle.toLowerCase().contains(q)) {
                    combined[t.id] = t;
                  }
                }
              }

              // 3. Результаты из сохраненных закладок пользователя
              for (final e in savedEntries) {
                if (e.cleanTitleRu.toLowerCase().contains(q) ||
                    e.titleRu.toLowerCase().contains(q)) {
                  combined[e.animeId] = AnimeTitle(
                    id: e.animeId,
                    code: 'saved_${e.animeId}',
                    russianTitle: e.cleanTitleRu,
                    englishTitle: e.cleanTitleRu,
                    posterSmall: e.posterUrl ?? '',
                    posterMedium: e.posterUrl ?? '',
                    posterOriginal: e.posterUrl ?? '',
                    genres: const [],
                    description: '',
                    status: e.status.labelRu,
                  );
                }
              }

              final matches = combined.values.take(8).toList();

              if (matches.isEmpty && !_isSearchingTitles) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.textMuted, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Название «${_favAnimeController.text.trim()}» будет сохранено как произвольный текст',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (_isSearchingTitles)
                        const LinearProgressIndicator(minHeight: 2),
                      ...matches.map((t) {
                        final isChosen = _selectedFavAnimeId == t.id.toString() ||
                            _favAnimeController.text.trim().toLowerCase() == t.russianTitle.toLowerCase();

                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 32,
                              height: 44,
                              child: t.posterUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: wrapCorsSafeUrl(t.posterUrl),
                                      memCacheWidth: 150,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.high,
                                      httpHeaders: const {
                                        'User-Agent': 'SyncPai-App/1.0',
                                        'Referer': 'https://shikimori.io/',
                                      },
                                      placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                                      errorWidget: (_, __, ___) => t.effectiveFallbackPoster.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: wrapCorsSafeUrl(t.effectiveFallbackPoster),
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                                              errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 16),
                                            )
                                          : const Icon(Icons.movie, size: 16),
                                    )
                                  : const Icon(Icons.movie, size: 16),
                            ),
                          ),
                          title: Text(
                            t.russianTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isChosen ? accent : Colors.white,
                              fontSize: 13,
                              fontWeight: isChosen ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          subtitle: t.genres.isNotEmpty
                              ? Text(
                                  t.genres.take(2).join(', '),
                                  maxLines: 1,
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                )
                              : null,
                          trailing: isChosen
                              ? Icon(Icons.check_circle_rounded, color: accent, size: 18)
                              : const Icon(Icons.add_rounded, color: AppColors.textSecondary, size: 18),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _favAnimeController.text = t.russianTitle;
                              _selectedFavAnimeId = t.id.toString();
                              _selectedFavAnimePoster = t.posterUrl.isNotEmpty
                                  ? t.posterUrl
                                  : t.effectiveFallbackPoster;
                              _searchedCatalogTitles = [];
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ] else ...[
          const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final catalogState = getIt.isRegistered<CatalogCubit>()
                  ? getIt<CatalogCubit>().state
                  : null;
              final savedEntries = getIt.isRegistered<AnimeListCubit>()
                  ? getIt<AnimeListCubit>().state.allEntries
                  : const <UserAnimeEntry>[];

              final List<AnimeTitle> quickPicks = [];
              if (savedEntries.isNotEmpty) {
                for (final e in savedEntries.take(6)) {
                  quickPicks.add(AnimeTitle(
                    id: e.animeId,
                    code: 'saved_${e.animeId}',
                    russianTitle: e.cleanTitleRu,
                    englishTitle: e.cleanTitleRu,
                    posterSmall: e.posterUrl ?? '',
                    posterMedium: e.posterUrl ?? '',
                    posterOriginal: e.posterUrl ?? '',
                    fallbackPosterUrl: e.posterUrl ?? '',
                    genres: const [],
                    description: '',
                    status: e.status.labelRu,
                  ));
                }
              }

              if (catalogState is CatalogLoaded && catalogState.titles.isNotEmpty) {
                for (final t in catalogState.titles) {
                  if (quickPicks.every((p) => p.id != t.id) && quickPicks.length < 8) {
                    quickPicks.add(t);
                  }
                }
              }

              if (quickPicks.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 14, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        'Рекомендуемые для витрины:',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: quickPicks.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final t = quickPicks[index];
                        final isChosen = _selectedFavAnimeId == t.id.toString() ||
                            _favAnimeController.text.trim().toLowerCase() == t.russianTitle.toLowerCase();

                        return InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _favAnimeController.text = t.russianTitle;
                              _selectedFavAnimeId = t.id.toString();
                              _selectedFavAnimePoster = t.posterUrl.isNotEmpty
                                  ? t.posterUrl
                                  : t.effectiveFallbackPoster;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 72,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isChosen ? accent : AppColors.strokeMedium,
                                width: isChosen ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
                                    child: t.posterUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: wrapCorsSafeUrl(t.posterUrl),
                                            memCacheWidth: 200,
                                            fit: BoxFit.cover,
                                            httpHeaders: const {
                                              'User-Agent': 'SyncPai-App/1.0',
                                              'Referer': 'https://shikimori.io/',
                                            },
                                            placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                                            errorWidget: (_, __, ___) => t.effectiveFallbackPoster.isNotEmpty
                                                ? CachedNetworkImage(
                                                    imageUrl: wrapCorsSafeUrl(t.effectiveFallbackPoster),
                                                    memCacheWidth: 200,
                                                    fit: BoxFit.cover,
                                                    placeholder: (_, __) => const ColoredBox(color: Colors.black26),
                                                    errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 20),
                                                  )
                                                : const Icon(Icons.movie, size: 20),
                                          )
                                        : const Icon(Icons.movie, size: 20),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                                  child: Text(
                                    t.russianTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: isChosen ? accent : Colors.white,
                                      fontSize: 10,
                                      fontWeight: isChosen ? FontWeight.w700 : FontWeight.w500,
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
            },
          ),
        ],
      ],
    ),
  );
}

  // --- 6. ВКЛАДКА «ЦВЕТА» ---
  Widget _buildColorsTab(Color accent) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl, vertical: 14),
      children: [
        Text('Неоновые акцентные темы профиля:',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.4,
          ),
          itemCount: SteamProfileThemeAccent.all.length,
          itemBuilder: (context, index) {
            final a = SteamProfileThemeAccent.all[index];
            final isSelected = _selectedAccentHex.toLowerCase() == a.hex.toLowerCase();

            return InkWell(
              onTap: () => setState(() => _selectedAccentHex = a.hex),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isSelected ? a.color.withValues(alpha: 0.16) : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? a.color : AppColors.strokeMedium,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: a.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: a.color.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
