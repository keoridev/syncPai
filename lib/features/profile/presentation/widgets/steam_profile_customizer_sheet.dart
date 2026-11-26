import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/avatar_upload_service.dart';
import '../../services/duo_sync_service.dart';
import 'duo_profile_sheet.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/utils/telegram_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/cubit/theme_cubit.dart';
import '../../../../core/theme/theme_preset.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/steam_avatar_frame.dart';
import '../../../../core/widgets/supporter_gate_sheet.dart';
import '../../../../core/widgets/vector_country_flag.dart';
import '../../../support/domain/entities/supporter_tier.dart';
import '../../domain/entities/customization_tier_policy.dart';
import '../cubit/profile_cubit.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../domain/entities/steam_profile_customization.dart';
import 'achievement_badge_artwork.dart';
import 'live_backgrounds/live_background_widget.dart';
import 'media_crop_editor_modal.dart';
import 'pai_chan_artwork_banner.dart';
import 'steam_style_profile_header.dart';

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

  static void show(BuildContext context, UserProfile profile,
      {int initialTabIndex = 0}) {
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
  State<SteamProfileCustomizerSheet> createState() =>
      _SteamProfileCustomizerSheetState();
}

class _SteamProfileCustomizerSheetState
    extends State<SteamProfileCustomizerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _selectedFrameId;
  late String _selectedBgId;
  late String _selectedAccentHex;
  late String _selectedBadgeId;
  late String _selectedAvatar;
  late String _selectedShowcaseType;
  late String _selectedCountryFlag;
  late String _selectedCountryName;
  late String _selectedAvatarShape;
  String? _selectedFavAnimeId;
  String? _selectedFavAnimePoster;
  String? _selectedArtworkUrl;
  String? _selectedArtworkTitle;
  Uint8List? _pendingAvatarBytes;

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

  // Поиск персонажей и тайтлов для аватара (Shikimori)
  final TextEditingController _avatarSearchController = TextEditingController();
  Timer? _avatarSearchDebounce;
  List<({String name, String subtitle, String imageUrl})> _avatarSearchResults = [];
  bool _isSearchingAvatars = false;

  // Поиск аниме-фонов (Wallhaven SFW API)
  final TextEditingController _wallhavenController = TextEditingController();
  Timer? _wallhavenDebounce;
  List<({String id, String thumbUrl, String fullUrl})> _wallhavenResults = [];
  bool _isSearchingWallhaven = false;

  // Вкладка «Пара» (Duo Profile)
  DuoLinkRecord? _duoLink;
  bool _isLoadingDuo = false;
  final TextEditingController _duoBannerUrlController = TextEditingController();
  final TextEditingController _duoWallhavenController = TextEditingController();
  final TextEditingController _duoInviteCodeController = TextEditingController();
  Timer? _duoWallhavenDebounce;
  List<({String id, String thumbUrl, String fullUrl})> _duoWallhavenResults = [];
  bool _isSearchingDuoWallhaven = false;
  String _selectedDuoThemeId = 'sunset_bridge';
  String? _selectedDuoBannerUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 7,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 6),
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _searchWallhaven('anime scenery');
    _preloadPopularAvatars();
    _loadDuoState();
    _searchDuoWallhaven('anime landscape');
    _selectedFrameId = widget.profile.frameId ?? 'none';
    _selectedBgId = widget.profile.backgroundId ?? 'none';
    _selectedAccentHex = widget.profile.accentColor ??
        (getIt.isRegistered<ThemeCubit>()
            ? '#${getIt<ThemeCubit>().state.currentPreset.primaryColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
            : '#E06C53');
    _selectedBadgeId = widget.profile.badgeId ?? 'sync_master';
    _selectedAvatar = widget.profile.avatarUrl ?? 'cat';
    _selectedShowcaseType = widget.profile.showcaseType;
    _selectedCountryFlag = widget.profile.countryFlag ?? '🇰🇬';
    _selectedCountryName = widget.profile.countryName ?? 'Kyrgyzstan';
    _selectedAvatarShape = widget.profile.avatarShape;
    _selectedFavAnimeId = widget.profile.favoriteAnimeId;
    _selectedFavAnimePoster = widget.profile.favoriteAnimePoster;
    _selectedArtworkUrl = widget.profile.artworkUrl;
    _selectedArtworkTitle = widget.profile.artworkTitle;

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

    _titleFocusNode = FocusNode()
      ..addListener(() => _ensureFocusVisible(_titleFocusNode));
    _statusFocusNode = FocusNode()
      ..addListener(() => _ensureFocusVisible(_statusFocusNode));
    _bioFocusNode = FocusNode()
      ..addListener(() => _ensureFocusVisible(_bioFocusNode));
    _favAnimeFocusNode = FocusNode()
      ..addListener(() => _ensureFocusVisible(_favAnimeFocusNode));
  }

  Future<void> _preloadPopularAvatars() async {
    if (_avatarSearchResults.isNotEmpty) return;
    if (mounted) setState(() => _isSearchingAvatars = true);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final res = await dio.get(
        'https://api.jikan.moe/v4/characters',
        queryParameters: {
          'order_by': 'favorites',
          'sort': 'desc',
          'limit': 18,
        },
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data['data'];
        if (data is List) {
          final parsed = <({String name, String subtitle, String imageUrl})>[];
          for (final item in data) {
            if (item is! Map) continue;
            final name = (item['name'] ?? '').toString().trim();
            final images = item['images'] is Map ? item['images'] as Map : null;
            final jpg = images?['jpg'] is Map ? images!['jpg'] as Map : null;
            final imgUrl = (jpg?['image_url'] ?? '').toString().trim();
            if (name.isNotEmpty && imgUrl.isNotEmpty) {
              parsed.add((name: name, subtitle: 'Популярное', imageUrl: imgUrl));
            }
          }
          if (mounted && _avatarSearchController.text.trim().isEmpty) {
            setState(() {
              _avatarSearchResults = parsed;
              _isSearchingAvatars = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearchingAvatars = false);
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
    _avatarSearchDebounce?.cancel();
    _avatarSearchController.dispose();
    _wallhavenDebounce?.cancel();
    _wallhavenController.dispose();
    _duoWallhavenDebounce?.cancel();
    _duoBannerUrlController.dispose();
    _duoWallhavenController.dispose();
    _duoInviteCodeController.dispose();
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
          final rawResults =
              await getIt<CatalogRepository>().searchTitles(q, limit: 15);
          final seenTitles = <String>{};
          final results = <AnimeTitle>[];
          for (final item in rawResults) {
            final hasPoster = item.posterOriginal.trim().isNotEmpty ||
                item.posterMedium.trim().isNotEmpty ||
                item.posterSmall.trim().isNotEmpty;
            if (!hasPoster) continue;
            final norm = item.displayTitle.trim().toLowerCase();
            if (norm.isEmpty || !seenTitles.add(norm)) continue;
            results.add(item);
          }
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

  void _onAvatarSearchChanged(String raw) {
    _avatarSearchDebounce?.cancel();
    final q = raw.trim();
    if (q.length < 2) {
      setState(() {
        _avatarSearchResults = [];
        _isSearchingAvatars = false;
      });
      return;
    }
    setState(() => _isSearchingAvatars = true);
    _avatarSearchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final results = <({String name, String subtitle, String imageUrl})>[];
      try {
        final dio = Dio(
          BaseOptions(
            baseUrl: 'https://shikimori.one/api',
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 8),
            headers: const {'User-Agent': 'SyncPai/1.0'},
          ),
        );
        final charRes = await dio.get<dynamic>(
          '/characters/search',
          queryParameters: {'q': q},
        );
        if (charRes.data is List) {
          for (final item in (charRes.data as List).take(6)) {
            if (item is! Map) continue;
            final ru = (item['russian'] ?? '').toString().trim();
            final en = (item['name'] ?? '').toString().trim();
            final name = ru.isNotEmpty ? ru : en;
            final img = item['image'] is Map
                ? (item['image']['original'] ?? item['image']['preview'] ?? '')
                    .toString()
                    .trim()
                : '';
            if (name.isEmpty || img.isEmpty || img.contains('missing_')) continue;
            final fullUrl = img.startsWith('http')
                ? img
                : 'https://shikimori.one$img';
            results.add((name: name, subtitle: 'Персонаж', imageUrl: fullUrl));
          }
        }
        if (results.length < 6) {
          final animeRes = await dio.get<dynamic>(
            '/animes',
            queryParameters: {'search': q, 'limit': 6},
          );
          if (animeRes.data is List) {
            for (final item in (animeRes.data as List).take(6)) {
              if (item is! Map) continue;
              final ru = (item['russian'] ?? '').toString().trim();
              final en = (item['name'] ?? '').toString().trim();
              final name = ru.isNotEmpty ? ru : en;
              final img = item['image'] is Map
                  ? (item['image']['original'] ?? item['image']['preview'] ?? '')
                      .toString()
                      .trim()
                  : '';
              if (name.isEmpty || img.isEmpty) continue;
              final fullUrl = img.startsWith('http')
                  ? img
                  : 'https://shikimori.one$img';
              results.add((name: name, subtitle: 'Тайтл', imageUrl: fullUrl));
            }
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _avatarSearchResults = results.take(9).toList();
          _isSearchingAvatars = false;
        });
      }
    });
  }

  void _showBugHunterUnlockPrompt(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF12161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.terminal_rounded, color: Color(0xFF00E676), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Эксклюзив «Кодинг-хакер»',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: const Text(
          'Этот предмет открывается бесплатно за найденный баг!\n\n'
          'Нажмите кнопку ниже, чтобы отправить баг-репорт в @syncpai_bot — после подтверждения вы получите рамку, фон и аватар «Кодинг-хакер».',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Закрыть', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.bug_report_rounded, size: 16),
            label: const Text('Открыть @syncpai_bot', style: TextStyle(fontWeight: FontWeight.w700)),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              TelegramLauncher.openBugReport(
                context,
                friendCode: widget.profile.friendCode ?? widget.profile.id,
              );
            },
          ),
        ],
      ),
    );
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

    if (newFavAnime.isNotEmpty &&
        (effectiveFavPoster == null || effectiveFavPoster.isEmpty)) {
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
                (t) =>
                    t.russianTitle
                        .toLowerCase()
                        .contains(newFavAnime.toLowerCase()) ||
                    t.englishTitle
                        .toLowerCase()
                        .contains(newFavAnime.toLowerCase()),
              );
              effectiveFavPoster = m.posterUrl.isNotEmpty
                  ? m.posterUrl
                  : m.effectiveFallbackPoster;
              effectiveFavId = m.id.toString();
            }
          }
        } catch (_) {}
      }
    }

    final isFrameLocked = !CustomizationTierPolicy.isFrameUnlocked(
      widget.profile.supporterTier,
      _selectedFrameId,
      unlockedBadges: widget.profile.unlockedBadges,
    );
    final isBgLocked = !CustomizationTierPolicy.isBannerUnlocked(
      widget.profile.supporterTier,
      effectiveBg,
      unlockedBadges: widget.profile.unlockedBadges,
    );
    final isTitleLocked = newTitle.isNotEmpty &&
        !CustomizationTierPolicy.canEditCustomTitle(widget.profile.supporterTier);
    final isArtworkLocked = _selectedArtworkUrl != null &&
        _selectedArtworkUrl!.isNotEmpty &&
        !CustomizationTierPolicy.isArtworkUnlocked(
          widget.profile.supporterTier,
          _selectedArtworkUrl,
          unlockedBadges: widget.profile.unlockedBadges,
        );

    if (isFrameLocked || isBgLocked || isTitleLocked || isArtworkLocked) {
      SupporterTier reqTier = SupporterTier.supporter;
      if (isFrameLocked) {
        final fTier = CustomizationTierPolicy.requiredTierForFrame(_selectedFrameId);
        if (fTier.index > reqTier.index) reqTier = fTier;
      }
      if (isBgLocked) {
        final bTier = CustomizationTierPolicy.requiredTierForBanner(effectiveBg);
        if (bTier.index > reqTier.index) reqTier = bTier;
      }
      if (isTitleLocked) {
        if (SupporterTier.vip.index > reqTier.index) reqTier = SupporterTier.vip;
      }
      if (isArtworkLocked) {
        final aTier = CustomizationTierPolicy.requiredTierForArtwork(_selectedArtworkUrl ?? '');
        if (aTier.index > reqTier.index) reqTier = aTier;
      }

      final frame = SteamAvatarFrame.fromId(_selectedFrameId);
      final bg = SteamBackgroundTheme.fromId(effectiveBg);
      final lockedDetails = <String>[];
      if (isFrameLocked) lockedDetails.add('рамка «${frame.name}»');
      if (isBgLocked) lockedDetails.add('фон «${bg.name}»');
      if (isTitleLocked) lockedDetails.add('кастомный титул');
      if (isArtworkLocked) lockedDetails.add('витрина иллюстраций');

      SupporterGateSheet.show(
        context,
        profile: widget.profile,
        requiredTier: reqTier,
        featureTitle: 'Премиум-витрина профиля',
        featureDescription:
            'Вы собрали витрину с элементами подписки ${reqTier.title} (${lockedDetails.join(", ")}). Чтобы закрепить её в профиле, оформите подписку.',
      );
      return;
    }

    final sanitized = CustomizationTierPolicy.sanitizePayload(
      tier: widget.profile.supporterTier,
      frameId: _selectedFrameId,
      backgroundId: effectiveBg,
      customTitle: newTitle.isNotEmpty ? newTitle : null,
      artworkUrl: _selectedArtworkUrl,
      artworkTitle: _selectedArtworkTitle,
      unlockedBadges: widget.profile.unlockedBadges,
    );

    // 1. Сохраняем в AuthCubit
    context.read<AuthCubit>().updateProfile(
          username: widget.profile.username,
          avatarUrl: effectiveAvatar,
          avatarBytes: _pendingAvatarBytes,
          frameId: sanitized.frameId,
          backgroundId: sanitized.backgroundId,
          customTitle: sanitized.customTitle,
          customStatus: newStatus.isNotEmpty ? newStatus : null,
          bio: newBio.isNotEmpty ? newBio : null,
          badgeId: _selectedBadgeId,
          favoriteAnimeTitle: newFavAnime.isNotEmpty ? newFavAnime : null,
          favoriteAnimeId: newFavAnime.isNotEmpty ? effectiveFavId : null,
          favoriteAnimePoster:
              newFavAnime.isNotEmpty ? effectiveFavPoster : null,
          artworkUrl: sanitized.artworkUrl ?? '',
          artworkTitle: sanitized.artworkTitle ?? '',
          accentColor: _selectedAccentHex,
          showcaseType: _selectedShowcaseType,
          countryFlag: _selectedCountryFlag,
          countryName: _selectedCountryName,
          avatarShape: _selectedAvatarShape,
        );

    try {
      context.read<ProfileCubit>().applyCustomization(
            avatarUrl: effectiveAvatar,
            frameId: sanitized.frameId,
            backgroundId: sanitized.backgroundId,
            customTitle: sanitized.customTitle,
            customStatus: newStatus.isNotEmpty ? newStatus : null,
            bio: newBio.isNotEmpty ? newBio : null,
            badgeId: _selectedBadgeId,
            favoriteAnimeTitle: newFavAnime.isNotEmpty ? newFavAnime : null,
            favoriteAnimeId: newFavAnime.isNotEmpty ? effectiveFavId : null,
            favoriteAnimePoster:
                newFavAnime.isNotEmpty ? effectiveFavPoster : null,
            artworkUrl: sanitized.artworkUrl,
            artworkTitle: sanitized.artworkTitle,
            accentColor: _selectedAccentHex,
            showcaseType: _selectedShowcaseType,
            countryFlag: _selectedCountryFlag,
            countryName: _selectedCountryName,
            avatarShape: _selectedAvatarShape,
          );
    } catch (_) {}

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
        content:
            Text('✨ Кастомизация профиля и тема оформления успешно применены!'),
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
    final effectiveBg = _customUrlController.text.trim().isNotEmpty
        ? _customUrlController.text.trim()
        : _selectedBgId;

    final isFrameLocked = !CustomizationTierPolicy.isFrameUnlocked(
      widget.profile.supporterTier,
      _selectedFrameId,
      unlockedBadges: widget.profile.unlockedBadges,
    );
    final isBgLocked = !CustomizationTierPolicy.isBannerUnlocked(
      widget.profile.supporterTier,
      effectiveBg,
      unlockedBadges: widget.profile.unlockedBadges,
    );
    final isTitleLocked = _titleController.text.trim().isNotEmpty &&
        !CustomizationTierPolicy.canEditCustomTitle(widget.profile.supporterTier);
    final isAccentLocked = !CustomizationTierPolicy.isAccentUnlocked(
      widget.profile.supporterTier,
      _selectedAccentHex,
    );
    final isArtworkLocked = _selectedArtworkUrl != null &&
        _selectedArtworkUrl!.isNotEmpty &&
        !CustomizationTierPolicy.isArtworkUnlocked(
          widget.profile.supporterTier,
          _selectedArtworkUrl,
          unlockedBadges: widget.profile.unlockedBadges,
        );
    final activeTab = _tabController.index;
    final isAvatarLocked = !CustomizationTierPolicy.isAvatarUnlocked(
      effectiveAvatar,
      unlockedBadges: widget.profile.unlockedBadges,
    );
    final hasLockedSelection = switch (activeTab) {
      0 => isBgLocked,
      1 => isFrameLocked,
      2 => isAvatarLocked,
      3 => false,
      4 => isArtworkLocked,
      5 => isAccentLocked || isTitleLocked,
      _ => false,
    };

    SupporterTier requiredTier = SupporterTier.free;
    if (activeTab == 1 && isFrameLocked) {
      final fTier = CustomizationTierPolicy.requiredTierForFrame(_selectedFrameId);
      if (fTier.index > requiredTier.index) requiredTier = fTier;
    }
    if (activeTab == 0 && isBgLocked) {
      final bTier = CustomizationTierPolicy.requiredTierForBanner(effectiveBg);
      if (bTier.index > requiredTier.index) requiredTier = bTier;
    }
    if (activeTab == 5 && isAccentLocked) {
      final cTier = CustomizationTierPolicy.requiredTierForAccent(_selectedAccentHex);
      if (cTier.index > requiredTier.index) requiredTier = cTier;
    }
    if (activeTab == 5 && isTitleLocked) {
      if (SupporterTier.vip.index > requiredTier.index) requiredTier = SupporterTier.vip;
    }
    if (activeTab == 4 && isArtworkLocked) {
      final aTier = CustomizationTierPolicy.requiredTierForArtwork(_selectedArtworkUrl ?? '');
      if (aTier.index > requiredTier.index) requiredTier = aTier;
    }
    if (hasLockedSelection && requiredTier == SupporterTier.free) {
      requiredTier = SupporterTier.supporter;
    }
    final requiredTierDisplay = requiredTier == SupporterTier.supporter
        ? 'SyncPai Sponsor'
        : requiredTier.title;

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
            padding:
                const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
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
                      child:
                          Icon(Icons.palette_outlined, color: accent, size: 20),
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
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Интерактивный живой предпросмотр профиля
          Container(
            margin:
                const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
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

                  // Бейдж предпросмотра витрины при выборе элементов выше текущего уровня
                  if (hasLockedSelection)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: requiredTier.accentColor.withValues(alpha: 0.85),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: requiredTier.accentColor.withValues(alpha: 0.35),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.remove_red_eye_rounded, size: 12, color: requiredTier.accentColor),
                            const SizedBox(width: 4),
                            Text(
                              'Примерка • ${requiredTier.title}',
                              style: TextStyle(
                                color: requiredTier.accentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Инфо поверх
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
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
                                          Shadow(
                                              color: Colors.black,
                                              blurRadius: 6),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Значок Steam
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: badge.color.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: badge.color, width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(badge.icon,
                                            size: 10, color: badge.color),
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
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
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
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              Tab(text: 'Фон (${SteamBackgroundTheme.all.length})'),
              Tab(text: 'Рамка (${SteamAvatarFrame.all.length})'),
              const Tab(text: 'Аватар'),
              const Tab(text: 'Значки'),
              const Tab(text: 'Витрина'),
              const Tab(text: 'Цвета'),
              const Tab(text: 'Пара'),
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
                _buildDuoTab(accent),
              ],
            ),
          ),

          // Кнопка применить / оформить подписку на собранную витрину
          Padding(
            padding: const EdgeInsets.all(AppDimensions.spacingXl),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: hasLockedSelection
                  ? ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: requiredTier.accentColor,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.workspace_premium_rounded, size: 20),
                      label: Text(
                        'Открыть доступ ($requiredTierDisplay)',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                      ),
                      onPressed: () {
                        final frame = SteamAvatarFrame.fromId(_selectedFrameId);
                        final lockedDetails = <String>[];
                        if (isFrameLocked) lockedDetails.add('рамка «${frame.name}»');
                        if (isBgLocked) lockedDetails.add('фон «${bgTheme.name}»');
                        if (isAccentLocked) {
                          lockedDetails.add('цвет «${SteamProfileThemeAccent.fromHex(_selectedAccentHex).name}»');
                        }
                        if (isTitleLocked) lockedDetails.add('кастомный титул');
                        if (isArtworkLocked) lockedDetails.add('витрина иллюстраций');

                        final desc = lockedDetails.isNotEmpty
                            ? 'Вы примерили крутые элементы (${lockedDetails.join(", ")}). Чтобы закрепить эту витрину в своём профиле, оформите подписку ${requiredTier.title}.'
                            : 'Для сохранения выбранной витрины профиля требуется подписка ${requiredTier.title}.';

                        SupporterGateSheet.show(
                          context,
                          profile: widget.profile,
                          requiredTier: requiredTier,
                          featureTitle: 'Премиум-витрина профиля',
                          featureDescription: desc,
                        );
                      },
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B4A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: _applyChanges,
                      child: Text(
                        activeTab == 5 ? 'Применить цвет' : 'Применить изменения',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _searchWallhaven(String query) async {
    final clean = query.trim().isEmpty ? 'anime scenery' : query.trim();
    if (mounted) setState(() => _isSearchingWallhaven = true);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final res = await dio.get(
        'https://wallhaven.cc/api/v1/search',
        queryParameters: {
          'q': clean,
          'categories': '010',
          'purity': '100',
          'atleast': '1280x720',
          'sorting': 'favorites',
        },
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data['data'];
        if (data is List) {
          final parsed = <({String id, String thumbUrl, String fullUrl})>[];
          for (final item in data.take(12)) {
            if (item is! Map) continue;
            final id = (item['id'] ?? '').toString();
            final fullUrl = (item['path'] ?? '').toString();
            final thumbs = item['thumbs'] is Map ? item['thumbs'] as Map : null;
            final thumbUrl = (thumbs?['small'] ?? thumbs?['large'] ?? fullUrl).toString();
            if (fullUrl.isNotEmpty && thumbUrl.isNotEmpty) {
              parsed.add((id: id, thumbUrl: thumbUrl, fullUrl: fullUrl));
            }
          }
          if (mounted) {
            setState(() {
              _wallhavenResults = parsed;
              _isSearchingWallhaven = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearchingWallhaven = false);
  }

  Future<void> _loadDuoState() async {
    if (mounted) setState(() => _isLoadingDuo = true);
    final link = await DuoSyncService.instance.getCurrentDuoLink(
      userId: widget.profile.id,
    );
    if (!mounted) return;
    setState(() {
      _duoLink = link;
      _isLoadingDuo = false;
      if (link != null) {
        _selectedDuoThemeId = link.diptychThemeId;
        _selectedDuoBannerUrl = link.resolvedBannerUrl;
        _duoBannerUrlController.text = _selectedDuoBannerUrl ?? '';
      }
    });
  }

  Future<void> _searchDuoWallhaven(String query) async {
    final clean = query.trim().isEmpty ? 'anime landscape' : query.trim();
    if (mounted) setState(() => _isSearchingDuoWallhaven = true);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final res = await dio.get(
        'https://wallhaven.cc/api/v1/search',
        queryParameters: {
          'q': clean,
          'categories': '010',
          'purity': '100',
          'ratios': '16x9,21x9',
          'sorting': 'favorites',
        },
      );
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data['data'];
        if (data is List) {
          final parsed = <({String id, String thumbUrl, String fullUrl})>[];
          for (final item in data.take(12)) {
            if (item is! Map) continue;
            final id = (item['id'] ?? '').toString();
            final fullUrl = (item['path'] ?? '').toString();
            final thumbs = item['thumbs'] is Map ? item['thumbs'] as Map : null;
            final thumbUrl =
                (thumbs?['small'] ?? thumbs?['large'] ?? fullUrl).toString();
            if (fullUrl.isNotEmpty && thumbUrl.isNotEmpty) {
              parsed.add((id: id, thumbUrl: thumbUrl, fullUrl: fullUrl));
            }
          }
          if (mounted) {
            setState(() {
              _duoWallhavenResults = parsed;
              _isSearchingDuoWallhaven = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearchingDuoWallhaven = false);
  }

  Future<void> _applyDuoWallpaper({
    required String themeId,
    String? bannerUrl,
  }) async {
    setState(() {
      _selectedDuoThemeId = themeId;
      _selectedDuoBannerUrl = bannerUrl;
      _duoBannerUrlController.text = bannerUrl ?? '';
    });
    final link = _duoLink;
    if (link == null) return;
    final updated = await DuoSyncService.instance.updateDuoSettings(
      link,
      diptychThemeId: themeId,
      duoBannerUrl: bannerUrl ?? '',
      customLeftArtUrl: bannerUrl ?? '',
    );
    if (mounted && updated != null) {
      setState(() => _duoLink = updated);
    }
  }

  Future<void> _pickDuoCustomImage() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path == null || path.isEmpty) return;
    await _applyDuoWallpaper(themeId: 'custom_spread', bannerUrl: path);
  }

  Future<void> _createDuoInvite() async {
    setState(() => _isLoadingDuo = true);
    final created = await DuoSyncService.instance.createOrGetPendingInvite(
      diptychThemeId: _selectedDuoThemeId,
    );
    if (!mounted) return;
    setState(() {
      _duoLink = created;
      _isLoadingDuo = false;
    });
  }

  Future<void> _acceptDuoInvite() async {
    final code = _duoInviteCodeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _isLoadingDuo = true);
    final accepted = await DuoSyncService.instance.acceptInviteCode(code);
    if (!mounted) return;
    setState(() {
      if (accepted != null) {
        _duoLink = accepted;
        _selectedDuoThemeId = accepted.diptychThemeId;
        _selectedDuoBannerUrl = accepted.resolvedBannerUrl;
      }
      _isLoadingDuo = false;
    });
  }

  Future<void> _dissolveDuo() async {
    final link = _duoLink;
    if (link == null) return;
    setState(() => _isLoadingDuo = true);
    await DuoSyncService.instance.dissolveDuoLink(link);
    if (!mounted) return;
    setState(() {
      _duoLink = null;
      _isLoadingDuo = false;
    });
  }

  Widget _buildDuoTab(Color accent) {
    final spec = DuoDiptychThemeSpec.fromId(_selectedDuoThemeId);
    final effectiveBanner = (_selectedDuoBannerUrl ?? '').trim().isNotEmpty
        ? _selectedDuoBannerUrl!.trim()
        : (spec.imageUrl ?? '');
    final inviteCode = _duoLink?.inviteCode ?? '';
    final tgUrl = inviteCode.isNotEmpty
        ? 'https://t.me/$kTelegramBotUsername?start=duo_$inviteCode'
        : 'https://t.me/$kTelegramBotUsername';

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingXl,
        vertical: 12,
      ),
      children: [
        if (_isLoadingDuo)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        // Живое превью панорамного баннера «Пара»
        const Text(
          'ПРЕВЬЮ ПАРНОГО БАННЕРА',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        if (_duoLink != null && _duoLink!.isActive)
          DuoProfileCard(
            profile: widget.profile,
            duoLink: _duoLink!.copyWith(
              diptychThemeId: _selectedDuoThemeId,
              duoBannerUrl: _selectedDuoBannerUrl ?? '',
              customLeftArtUrl: _selectedDuoBannerUrl ?? '',
            ),
            onManageTap: () {},
          )
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: const BoxConstraints(minHeight: 132),
              decoration: BoxDecoration(
                color: const Color(0xFF11151E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x18FFFFFF)),
              ),
              child: Stack(
                children: [
                  if (effectiveBanner.isNotEmpty)
                    Positioned.fill(
                      child: effectiveBanner.startsWith('http')
                          ? CachedNetworkImage(
                              imageUrl: wrapCorsSafeUrl(effectiveBanner),
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(effectiveBanner),
                              fit: BoxFit.cover,
                            ),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: const [Color(0xCC0B0E14), Color(0x330B0E14)],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SteamAvatarFrameWidget(
                              frameId: _selectedFrameId,
                              size: 50,
                              child: AppAvatar(
                                avatarUrl: _selectedAvatar,
                                username: widget.profile.username,
                                size: 44,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.profile.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Expanded(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xD90B0E14),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0x18FFFFFF),
                                ),
                              ),
                              child: const Text(
                                'Синхронизация пары',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: Color(0xFF1A202E),
                              child: Icon(
                                Icons.person_add_alt_1_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Напарник',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
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
          ),
        const SizedBox(height: 16),

        // 1. Готовые панорамные аниме-сцены
        const Text(
          'ПАНОРАМНЫЕ СЦЕНЫ',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: DuoDiptychThemeSpec.all
                .where((e) => !e.isCustomSpread)
                .length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, idx) {
              final presets = DuoDiptychThemeSpec.all
                  .where((e) => !e.isCustomSpread)
                  .toList();
              final item = presets[idx];
              final isSelected = _selectedDuoThemeId == item.id &&
                  (_selectedDuoBannerUrl ?? '').isEmpty;
              return GestureDetector(
                onTap: () => _applyDuoWallpaper(themeId: item.id),
                child: Container(
                  width: 146,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF6B4A)
                          : const Color(0x18FFFFFF),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.imageUrl != null)
                          CachedNetworkImage(
                            imageUrl: wrapCorsSafeUrl(item.imageUrl!),
                            fit: BoxFit.cover,
                          ),
                        Container(color: const Color(0x550B0E14)),
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // 2. Поиск широкоформатных обоев Wallhaven (16:9 / 21:9)
        const Text(
          'ПОИСК ОБОЕВ WALLHAVEN (16:9 / 21:9)',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _duoWallhavenController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Например: tokyo night, cyberpunk, sakura...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
            filled: true,
            fillColor: const Color(0xFF161B26),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0x18FFFFFF)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0x18FFFFFF)),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search_rounded, color: Colors.white70),
              onPressed: () =>
                  _searchDuoWallhaven(_duoWallhavenController.text),
            ),
          ),
          onChanged: (val) {
            _duoWallhavenDebounce?.cancel();
            _duoWallhavenDebounce = Timer(
              const Duration(milliseconds: 500),
              () => _searchDuoWallhaven(val),
            );
          },
          onSubmitted: _searchDuoWallhaven,
        ),
        const SizedBox(height: 8),
        if (_isSearchingDuoWallhaven)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_duoWallhavenResults.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _duoWallhavenResults.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 16 / 9,
            ),
            itemBuilder: (_, i) {
              final item = _duoWallhavenResults[i];
              final isSelected = _selectedDuoBannerUrl == item.fullUrl;
              return GestureDetector(
                onTap: () => _applyDuoWallpaper(
                  themeId: 'custom_spread',
                  bannerUrl: item.fullUrl,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFFF6B4A)
                          : const Color(0x18FFFFFF),
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: CachedNetworkImage(
                      imageUrl: wrapCorsSafeUrl(item.thumbUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
        const SizedBox(height: 14),

        // 3. Своя картинка или URL
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _duoBannerUrlController,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Прямая ссылка на панораму (https://...)',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF161B26),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0x18FFFFFF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0x18FFFFFF)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final url = _duoBannerUrlController.text.trim();
                if (url.isNotEmpty) {
                  _applyDuoWallpaper(themeId: 'custom_spread', bannerUrl: url);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickDuoCustomImage,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Загрузить панораму с устройства'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0x18FFFFFF)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 4. Приглашение напарника / отвязка пары
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF141821),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x18FFFFFF)),
          ),
          child: _duoLink?.isActive == true
              ? Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Пара активна и синхронизирована',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _dissolveDuo,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0x44EF4444)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Отвязать пару'),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ПРИГЛАСИТЬ НАПАРНИКА',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _createDuoInvite,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B4A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.link_rounded, size: 16),
                          label: Text(
                            inviteCode.isNotEmpty
                                ? 'Код: $inviteCode'
                                : 'Создать код пары',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            launchUrl(
                              Uri.parse(tgUrl),
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x18FFFFFF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 15),
                          label: const Text('Открыть @syncpai_bot'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _duoInviteCodeController,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Введите код приглашения друга...',
                              hintStyle: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF161B26),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Color(0x18FFFFFF),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Color(0x18FFFFFF),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _acceptDuoInvite,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Привязать'),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingXl, vertical: 12),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () async {
            try {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: [
                  'jpg',
                  'jpeg',
                  'png',
                  'gif',
                  'webp',
                  'mp4',
                  'webm'
                ],
                withData: true,
              );
              if (result != null && result.files.isNotEmpty) {
                final file = result.files.first;
                final appDir = await getApplicationDocumentsDirectory();
                final ext = file.extension ?? 'jpg';
                final targetPath =
                    '${appDir.path}/custom_bg_${DateTime.now().millisecondsSinceEpoch}.$ext';
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

        // Ввод произвольного URL или GIF/MP4
        Text('Или вставьте прямую ссылку на видео (MP4) или арт/GIF:',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 6),
        TextField(
          controller: _customUrlController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'https://example.com/art.jpg, .gif или .mp4',
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 12),
            filled: true,
            fillColor: AppColors.surface,
            prefixIcon: Icon(Icons.link_rounded, size: 18, color: accent),
            suffixIcon: _customUrlController.text.trim().isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.check_circle_rounded,
                        color: accent, size: 20),
                    onPressed: () {
                      final url = _customUrlController.text.trim();
                      if (url.isNotEmpty) {
                        setState(() => _selectedBgId = url);
                      }
                    },
                  )
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            setState(() {
              if (val.trim().isNotEmpty) {
                _selectedBgId = val.trim();
              }
            });
          },
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              setState(() => _selectedBgId = val.trim());
            }
          },
        ),

        const SizedBox(height: 18),
        Text('Найти аниме-фон (Wallhaven):',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 6),
        TextField(
          controller: _wallhavenController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Найти аниме-фон (Wallhaven)...',
            hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            filled: true,
            fillColor: AppColors.surface,
            prefixIcon: Icon(Icons.wallpaper_rounded, size: 18, color: accent),
            suffixIcon: _isSearchingWallhaven
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search_rounded, color: Colors.white70, size: 18),
                    onPressed: () => _searchWallhaven(_wallhavenController.text),
                  ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            _wallhavenDebounce?.cancel();
            _wallhavenDebounce = Timer(const Duration(milliseconds: 500), () {
              _searchWallhaven(val);
            });
          },
          onSubmitted: _searchWallhaven,
        ),
        if (_wallhavenResults.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _wallhavenResults.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, idx) {
                final wp = _wallhavenResults[idx];
                final isSelected = _selectedBgId == wp.fullUrl;
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedBgId = wp.fullUrl;
                      _customUrlController.text = wp.fullUrl;
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 136,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? accent : AppColors.strokeMedium,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: CachedNetworkImage(
                        imageUrl: wp.thumbUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 18),
        Text('Коллекция аниме фонов:',
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
            final isBugHunterItem = CustomizationTierPolicy.isBugHunterCosmetic(bg.id);
            final isBgUnlocked = CustomizationTierPolicy.isBannerUnlocked(
              widget.profile.supporterTier,
              bg.id,
              unlockedBadges: widget.profile.unlockedBadges,
            );
            final requiredBgTier = CustomizationTierPolicy.requiredTierForBanner(bg.id);

            return RepaintBoundary(
              child: InkWell(
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
                        LiveBackgroundWidget(
                          backgroundId: bg.id,
                          assetOrUrl: bg.assetOrUrl,
                          fallbackGradient: bg.gradient,
                          isPaused: !isSelected,
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
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isBgUnlocked
                                  ? (requiredBgTier == SupporterTier.free
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : requiredBgTier.accentColor.withValues(alpha: 0.4))
                                  : requiredBgTier.accentColor.withValues(alpha: 0.65),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isBgUnlocked) ...[
                                Icon(Icons.lock_rounded, size: 10, color: requiredBgTier.accentColor),
                                const SizedBox(width: 3),
                              ],
                              Text(
                                isBugHunterItem
                                    ? 'За баг'
                                    : (requiredBgTier == SupporterTier.free
                                        ? 'Бесплатно'
                                        : 'Sponsor'),
                                style: TextStyle(
                                  color: isBugHunterItem
                                      ? const Color(0xFF00E676)
                                      : (requiredBgTier == SupporterTier.free
                                          ? AppColors.textSecondary
                                          : requiredBgTier.accentColor),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
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
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
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
                              child: const Icon(Icons.check,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
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
    return Column(
      children: [
        // Переключатель формы аватара и рамки: Квадратная (Steam) / Круглая (Classic)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppDimensions.spacingXl, 10, AppDimensions.spacingXl, 6),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedAvatarShape = 'square'),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _selectedAvatarShape == 'square'
                          ? accent.withValues(alpha: 0.18)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedAvatarShape == 'square' ? accent : AppColors.strokeMedium,
                        width: _selectedAvatarShape == 'square' ? 1.8 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.crop_square_rounded,
                          size: 17,
                          color: _selectedAvatarShape == 'square' ? accent : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Квадратная (Steam)',
                          style: TextStyle(
                            color: _selectedAvatarShape == 'square' ? Colors.white : AppColors.textSecondary,
                            fontWeight: _selectedAvatarShape == 'square' ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selectedAvatarShape = 'circle'),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _selectedAvatarShape == 'circle'
                          ? accent.withValues(alpha: 0.18)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedAvatarShape == 'circle' ? accent : AppColors.strokeMedium,
                        width: _selectedAvatarShape == 'circle' ? 1.8 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.circle_outlined,
                          size: 16,
                          color: _selectedAvatarShape == 'circle' ? accent : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Круглая (Classic)',
                          style: TextStyle(
                            color: _selectedAvatarShape == 'circle' ? Colors.white : AppColors.textSecondary,
                            fontWeight: _selectedAvatarShape == 'circle' ? FontWeight.w700 : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth <= 360;
              final isWide = constraints.maxWidth >= 600;
              final crossCount = isNarrow ? 2 : (isWide ? 4 : 3);
              final ratio = isNarrow ? 0.72 : (isWide ? 0.85 : 0.68);

              return GridView.builder(
                padding: EdgeInsets.symmetric(
                  horizontal: isNarrow ? 8 : AppDimensions.spacingXl,
                  vertical: 8,
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
                  final isBugHunterFrame = CustomizationTierPolicy.isBugHunterCosmetic(frame.id);
                  final isFrameUnlocked = CustomizationTierPolicy.isFrameUnlocked(
                    widget.profile.supporterTier,
                    frame.id,
                    unlockedBadges: widget.profile.unlockedBadges,
                  );
                  final requiredFrameTier =
                      CustomizationTierPolicy.requiredTierForFrame(frame.id);

                  return InkWell(
                    onTap: () {
                      setState(() => _selectedFrameId = frame.id);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent.withValues(alpha: 0.12)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? accent : AppColors.strokeMedium,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 3,
                                child: Center(
                                  child: SteamAvatarFrameWidget(
                                    frameId: frame.id,
                                    size: 30,
                                    shape: _selectedAvatarShape,
                                    animate: isSelected,
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: _selectedAvatarShape == 'circle' ? BoxShape.circle : BoxShape.rectangle,
                                        borderRadius: _selectedAvatarShape == 'square' ? BorderRadius.circular(6) : null,
                                        color: const Color(0xFF1E2028),
                                      ),
                                      child: Icon(frame.previewIcon,
                                          size: 15, color: frame.colors.first),
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
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? Colors.white
                                              : AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: isFrameUnlocked
                                      ? (requiredFrameTier == SupporterTier.free
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : requiredFrameTier.accentColor.withValues(alpha: 0.4))
                                      : requiredFrameTier.accentColor.withValues(alpha: 0.65),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isFrameUnlocked) ...[
                                    Icon(Icons.lock_rounded, size: 8.5, color: requiredFrameTier.accentColor),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    isBugHunterFrame
                                        ? 'За баг'
                                        : (requiredFrameTier == SupporterTier.free
                                            ? 'Бесплатно'
                                            : 'Sponsor'),
                                    style: TextStyle(
                                      color: isBugHunterFrame
                                          ? const Color(0xFF00E676)
                                          : (requiredFrameTier == SupporterTier.free
                                              ? AppColors.textSecondary
                                              : requiredFrameTier.accentColor),
                                      fontSize: 8,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
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
    ),
  ),
],
);
  }

  // --- 3. ВКЛАДКА «АВАТАР» ---
  Widget _buildAvatarTab(Color accent) {
    return ListView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingXl, vertical: 14),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                final targetPath =
                    '${appDir.path}/custom_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final targetFile = File(targetPath);

                Uint8List? rawBytes = file.bytes;
                if ((rawBytes == null || rawBytes.isEmpty) &&
                    file.path != null &&
                    file.path!.isNotEmpty) {
                  final srcFile = File(file.path!);
                  if (await srcFile.exists()) {
                    rawBytes = await srcFile.readAsBytes();
                  }
                }

                String effectiveChosenPath = '';
                Uint8List? compressedBytes;
                if (rawBytes != null && rawBytes.isNotEmpty) {
                  compressedBytes =
                      AvatarUploadService.compressAvatarToJpeg(rawBytes);
                  await targetFile.writeAsBytes(compressedBytes, flush: true);
                  if (await targetFile.exists()) {
                    effectiveChosenPath = targetFile.path;
                  }
                }

                if (effectiveChosenPath.isNotEmpty && mounted) {
                  if (context.mounted) {
                    await MediaCropEditorModal.show(
                      context,
                      imagePathOrUrl: effectiveChosenPath,
                      shape: CropShape.circle,
                    );
                  }
                  setState(() {
                    _pendingAvatarBytes = compressedBytes;
                    _selectedAvatar = effectiveChosenPath;
                    _customAvatarUrlController.text = effectiveChosenPath;
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
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                icon: const Icon(Icons.clear_rounded,
                    color: AppColors.textSecondary),
                onPressed: () {
                  setState(() {
                    _customAvatarUrlController.clear();
                  });
                },
              ),
          ],
        ),

        const SizedBox(height: 18),
        Text(
          'Поиск персонажа или тайтла (Shikimori):',
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _avatarSearchController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Найти персонажа или тайтл...',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Colors.white54,
              size: 18,
            ),
            suffixIcon: _avatarSearchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 18),
                    onPressed: () {
                      setState(() {
                        _avatarSearchController.clear();
                        _avatarSearchResults = [];
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.strokeMedium),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.strokeMedium),
            ),
          ),
          onChanged: _onAvatarSearchChanged,
        ),
        const SizedBox(height: 10),
        if (_isSearchingAvatars)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_avatarSearchResults.isNotEmpty) ...[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _avatarSearchResults.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final item = _avatarSearchResults[index];
              return _buildCharacterAvatarTile(
                name: item.name,
                anime: item.subtitle,
                url: item.imageUrl,
                accent: accent,
              );
            },
          ),
          const SizedBox(height: 16),
        ],

        const SizedBox(height: 8),
        Text(
          'Монограммы SyncPai:',
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final mono in const [
              (id: 'monogram:graphite', label: 'Графит', color: Color(0xFF94A3B8)),
              (id: 'monogram:coral', label: 'Коралл', color: Color(0xFFFF6B4A)),
              (id: 'monogram:indigo', label: 'Индиго', color: Color(0xFF818CF8)),
              (id: 'monogram:emerald', label: 'Изумруд', color: Color(0xFF10B981)),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Tooltip(
                  message: mono.label,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedAvatar = mono.id;
                        _customAvatarUrlController.clear();
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedAvatar == mono.id &&
                                  _customAvatarUrlController.text.isEmpty
                              ? mono.color
                              : const Color(0x18FFFFFF),
                          width: _selectedAvatar == mono.id &&
                                  _customAvatarUrlController.text.isEmpty
                              ? 2.0
                              : 1.0,
                        ),
                      ),
                      child: AppAvatar(
                        avatarUrl: mono.id,
                        username: widget.profile.username,
                        size: 36,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildCharacterAvatarTile({
    required String name,
    required String anime,
    required String url,
    required Color accent,
  }) {
    final isSelected = _selectedAvatar == url ||
        _customAvatarUrlController.text.trim() == url;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedAvatar = url;
          _customAvatarUrlController.text = url;
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.16) : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accent : AppColors.strokeMedium,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: AppAvatar(
                  avatarUrl: url,
                  size: 52,
                  shape: _selectedAvatarShape == 'square'
                      ? BoxShape.rectangle
                      : BoxShape.circle,
                  borderColor: isSelected ? accent : AppColors.strokeMedium,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            Text(
              anime,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent.withValues(alpha: 0.85),
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 4. ВКЛАДКА «ЗНАЧКИ STEAM» ---
  Widget _buildBadgesTab(Color accent) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingXl, vertical: 14),
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
              color: isSelected
                  ? b.color.withValues(alpha: 0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? b.color : AppColors.strokeMedium,
                width: isSelected ? 1.8 : 1,
              ),
            ),
            child: Row(
              children: [
                AchievementBadgeArtwork(
                  badgeId: b.id,
                  isUnlocked: true,
                  size: 46,
                  rarity: b.rarity.name,
                  accentColor: b.color,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              b.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
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
                        b.unlockCriteria.isNotEmpty
                            ? b.unlockCriteria
                            : b.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
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
    final badge = SteamBadge.fromId(_selectedBadgeId);

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
          // 1. Готовые иллюстрации главной витрины Steam (Steam Artwork Showcase)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '1. Главная витрина иллюстраций (Steam Artwork):',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  widget.profile.isProOrHigher
                      ? Icons.add_photo_alternate_rounded
                      : Icons.lock_rounded,
                  size: 15,
                ),
                label: Text(
                  widget.profile.isProOrHigher
                      ? 'Свой арт'
                      : 'Свой арт (Pro)',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                onPressed: () async {
                  if (!widget.profile.isProOrHigher) {
                    await SupporterGateSheet.show(
                      context,
                      profile: widget.profile,
                      requiredTier: SupporterTier.vip,
                      featureTitle: 'Своя витрина иллюстраций',
                      featureDescription:
                          'Загрузите собственный арт или GIF-баннер в главную витрину с SyncPai Pro.',
                    );
                    return;
                  }
                  try {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.image,
                      withData: true,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      final file = result.files.first;
                      final appDir = await getApplicationDocumentsDirectory();
                      final ext = file.extension ?? 'jpg';
                      final targetPath =
                          '${appDir.path}/custom_artwork_${DateTime.now().millisecondsSinceEpoch}.$ext';
                      final targetFile = File(targetPath);
                      String chosenPath = '';
                      if (file.bytes != null && file.bytes!.isNotEmpty) {
                        await targetFile.writeAsBytes(file.bytes!, flush: true);
                        chosenPath = targetFile.path;
                      } else if (file.path != null && file.path!.isNotEmpty) {
                        chosenPath = file.path!;
                      }
                      if (chosenPath.isNotEmpty && mounted) {
                        setState(() {
                          _selectedArtworkUrl = chosenPath;
                          _selectedArtworkTitle = 'Свой арт';
                        });
                      }
                    }
                  } catch (e) {
                    debugPrint('Custom artwork pick error: $e');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: SteamStyleProfileHeader.curatedPresets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final preset = SteamStyleProfileHeader.curatedPresets[index];
                final isSelected = _selectedArtworkUrl == preset.imageUrl;
                final isLive = preset.imageUrl.startsWith('live:');
                final isPai = preset.imageUrl.startsWith('pai_');
                final isFreePai = preset.imageUrl == 'pai_chill' || preset.imageUrl == 'pai_winter';
                final isPlusPai = preset.imageUrl == 'pai_celebrate';
                final isHackerPai = preset.imageUrl == 'pai_hacker_art';

                final isUnlocked = CustomizationTierPolicy.isArtworkUnlocked(
                  widget.profile.supporterTier,
                  preset.imageUrl,
                  unlockedBadges: widget.profile.unlockedBadges,
                );
                return RepaintBoundary(
                  child: InkWell(
                    onTap: () {
                      if (!isUnlocked) {
                        if (isHackerPai) {
                          _showBugHunterUnlockPrompt(context);
                          return;
                        }
                        final requiredTier = isPlusPai ? SupporterTier.supporter : SupporterTier.vip;
                        SupporterGateSheet.show(
                          context,
                          profile: widget.profile,
                          requiredTier: requiredTier,
                          featureTitle: 'Витрина «${preset.title}»',
                          featureDescription: isPlusPai
                              ? 'Эксклюзивная витрина Пай-тян доступна для подписчиков SyncPai Sponsor.'
                              : 'Анимированные LIVE-сцены витрины доступны с SyncPai Pro.',
                        );
                        return;
                      }
                      setState(() {
                        _selectedArtworkUrl = preset.imageUrl;
                        _selectedArtworkTitle = preset.title;
                      });
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 155,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? accent : AppColors.strokeMedium,
                          width: isSelected ? 2.2 : 1.0,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (isPai)
                            PaiChanArtworkBanner(
                              artworkId: preset.imageUrl,
                              width: 155,
                              height: 108,
                              isSelected: isSelected,
                            )
                          else if (isLive)
                            LiveBackgroundWidget(
                              backgroundId: preset.imageUrl.substring(5),
                              fallbackGradient: const [Color(0xFF14161F), Color(0xFF23133A)],
                              isPaused: !isSelected,
                            )
                          else
                            CachedNetworkImage(
                              imageUrl: wrapCorsSafeUrl(preset.imageUrl),
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(color: const Color(0xFF14161F)),
                              errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFF14161F),
                                child: const Icon(Icons.broken_image_rounded, color: Colors.white24, size: 28),
                              ),
                            ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.15),
                                  Colors.black.withValues(alpha: 0.85),
                                ],
                              ),
                            ),
                          ),
                          // Бейджи в левом верхнем углу
                          if (isFreePai)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Бесплатно',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                          else if (isPlusPai)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Plus',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                          else if (isHackerPai)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00FF87).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Bug Hunter',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            )
                          else if (isLive)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'LIVE АНИМЕ',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          if (isSelected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(Icons.check_circle_rounded, color: accent, size: 18),
                            )
                          else if (!isUnlocked)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: (isPlusPai
                                            ? SupporterTier.supporter.accentColor
                                            : isHackerPai
                                                ? const Color(0xFF00FF87)
                                                : SupporterTier.vip.accentColor)
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isHackerPai ? Icons.bug_report_rounded : Icons.lock_rounded,
                                      size: 9,
                                      color: isPlusPai
                                          ? SupporterTier.supporter.accentColor
                                          : isHackerPai
                                              ? const Color(0xFF00FF87)
                                              : SupporterTier.vip.accentColor,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      isPlusPai
                                          ? 'Plus'
                                          : isHackerPai
                                              ? 'Хакер'
                                              : 'Pro',
                                      style: TextStyle(
                                        color: isPlusPai
                                            ? SupporterTier.supporter.accentColor
                                            : isHackerPai
                                                ? const Color(0xFF00FF87)
                                                : SupporterTier.vip.accentColor,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 8,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  preset.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  preset.tagline,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 2. Селектор типа дополнительной карточки витрины (Steam Showcase Mode)
          Text('2. Дополнительный блок под витриной Steam:',
              style:
                  AppTypography.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildShowcaseTypeOption(
                type: 'favorite_anime',
                title: 'Любимый тайтл',
                icon: Icons.movie_filter_rounded,
                accent: accent,
              ),
              const SizedBox(width: 8),
              _buildShowcaseTypeOption(
                type: 'stats_badges',
                title: 'Значки и статы',
                icon: Icons.military_tech_rounded,
                accent: accent,
              ),
              const SizedBox(width: 8),
              _buildShowcaseTypeOption(
                type: 'custom_text',
                title: 'Инфо-бокс',
                icon: Icons.article_rounded,
                accent: accent,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Живой интерактивный предпросмотр Витрины (Live Preview)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
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
                    Expanded(
                      child: Text(
                        'ПРЕДПРОСМОТР ВИТРИНЫ (${_selectedShowcaseType == "stats_badges" ? "ЗНАЧКИ И СТАТИСТИКА" : (_selectedShowcaseType == "custom_text" ? "ИНФО-БОКС" : "ЛЮБИМЫЙ ТАЙТЛ")})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 10.5,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_selectedShowcaseType == 'favorite_anime') ...[
                  Row(
                    children: [
                      if (_selectedFavAnimePoster != null &&
                          _selectedFavAnimePoster!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: wrapCorsSafeUrl(_selectedFavAnimePoster!),
                            width: 44,
                            height: 60,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const Icon(Icons.movie, size: 24),
                          ),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _favAnimeController.text.isNotEmpty
                                  ? _favAnimeController.text
                                  : 'Любимое аниме не выбрано',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _statusController.text.isNotEmpty
                                  ? '«${_statusController.text}»'
                                  : '«Смотрю аниме...»',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: accent, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else if (_selectedShowcaseType == 'stats_badges') ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: badge.color.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: badge.color),
                        ),
                        child: Icon(badge.icon, color: badge.color, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(badge.title,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: badge.color.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('LVL ${badge.level}',
                                      style: TextStyle(
                                          color: badge.color,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(badge.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  if (_titleController.text.trim().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: accent, width: 0.8),
                      ),
                      child: Text(
                        _titleController.text.trim(),
                        style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    '«${_statusController.text.isNotEmpty ? _statusController.text : 'Смотрю аниме...'}»',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                  if (_bioController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _bioController.text.trim(),
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Произвольный кастомный титул
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Кастомный титул профиля:',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textMuted)),
                  if (!widget.profile.isProOrHigher) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.lock_outline_rounded,
                      size: 12,
                      color: Color(0xFFA855F7),
                    ),
                    const SizedBox(width: 2),
                    const Text(
                      'Pro',
                      style: TextStyle(
                        color: Color(0xFFA855F7),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              Text('${_titleController.text.length}/30',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleController,
            focusNode: _titleFocusNode,
            readOnly: !widget.profile.isProOrHigher,
            onTap: !widget.profile.isProOrHigher
                ? () {
                    SupporterGateSheet.show(
                      context,
                      profile: widget.profile,
                      requiredTier: SupporterTier.vip,
                      featureTitle: 'Кастомный титул профиля',
                      featureDescription:
                          'Установите уникальный титул профиля в SyncPai Pro.',
                    );
                  }
                : null,
            maxLength: 30,
            cursorColor: accent,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Например: Тень Монарха, Верховный Архимаг...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            children:
                SteamCustomTitle.titles.where((t) => t.isNotEmpty).map((t) {
              return InkWell(
                onTap: () {
                  if (!widget.profile.isProOrHigher) {
                    SupporterGateSheet.show(
                      context,
                      profile: widget.profile,
                      requiredTier: SupporterTier.vip,
                      featureTitle: 'Кастомный титул профиля',
                      featureDescription:
                          'Установите уникальный титул профиля в SyncPai Pro.',
                    );
                    return;
                  }
                  setState(() {
                    _titleController.text = t;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: Text(t,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
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
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textMuted)),
              Text('${_statusController.text.length}/50',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _statusController,
            focusNode: _statusFocusNode,
            maxLength: 50,
            cursorColor: accent,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Что сейчас делаете?',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: Text(s,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // Выбор страны профиля через компактный выпадающий селектор (Option Dropdown)
          Text('Страна профиля (Steam Flag & Country):',
              style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: SteamCountry.popular.any((c) => c.name == _selectedCountryName)
                    ? _selectedCountryName
                    : SteamCountry.popular.first.name,
                isExpanded: true,
                dropdownColor: const Color(0xFF161822),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: accent),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                items: SteamCountry.popular.map((country) {
                  return DropdownMenuItem<String>(
                    value: country.name,
                    child: Row(
                      children: [
                        VectorCountryFlag(
                          countryFlag: country.flag,
                          countryName: country.name,
                          width: 20,
                          height: 14,
                          borderRadius: 3,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          country.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (selectedName) {
                  if (selectedName == null) return;
                  final found = SteamCountry.popular.firstWhere(
                    (c) => c.name == selectedName,
                    orElse: () => SteamCountry.popular.first,
                  );
                  setState(() {
                    _selectedCountryFlag = found.flag;
                    _selectedCountryName = found.name;
                  });
                },
              ),
            ),
          ),

          const SizedBox(height: 18),

          // О себе / Цитата
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('О себе / Цитата:',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textMuted)),
              Text('${_bioController.text.length}/150',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 10.5)),
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
              style:
                  AppTypography.caption.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          if (_selectedFavAnimePoster != null &&
              _selectedFavAnimePoster!.isNotEmpty) ...[
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
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.movie, size: 24),
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
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: Colors.white70),
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
              hintText:
                  'Начните вводить название (например: Восхождение в тени)...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface,
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.textSecondary, size: 20),
              suffixIcon: _favAnimeController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded,
                          size: 18, color: AppColors.textMuted),
                      onPressed: () {
                        setState(() {
                          _favAnimeController.clear();
                          _selectedFavAnimeId = null;
                          _selectedFavAnimePoster = null;
                        });
                      },
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.strokeMedium),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: AppColors.textMuted, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Название «${_favAnimeController.text.trim()}» будет сохранено как произвольный текст',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11.5),
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
                          final isChosen = _selectedFavAnimeId ==
                                  t.id.toString() ||
                              _favAnimeController.text.trim().toLowerCase() ==
                                  t.russianTitle.toLowerCase();

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
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
                                        placeholder: (_, __) =>
                                            const ColoredBox(
                                                color: Colors.black26),
                                        errorWidget: (_, __, ___) => t
                                                .effectiveFallbackPoster
                                                .isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: wrapCorsSafeUrl(
                                                    t.effectiveFallbackPoster),
                                                fit: BoxFit.cover,
                                                placeholder: (_, __) =>
                                                    const ColoredBox(
                                                        color: Colors.black26),
                                                errorWidget: (_, __, ___) =>
                                                    const Icon(Icons.movie,
                                                        size: 16),
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
                                fontWeight: isChosen
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: t.genres.isNotEmpty
                                ? Text(
                                    t.genres.take(2).join(', '),
                                    maxLines: 1,
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11),
                                  )
                                : null,
                            trailing: isChosen
                                ? Icon(Icons.check_circle_rounded,
                                    color: accent, size: 18)
                                : const Icon(Icons.add_rounded,
                                    color: AppColors.textSecondary, size: 18),
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

                if (catalogState is CatalogLoaded &&
                    catalogState.titles.isNotEmpty) {
                  for (final t in catalogState.titles) {
                    if (quickPicks.every((p) => p.id != t.id) &&
                        quickPicks.length < 8) {
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
                        Icon(Icons.auto_awesome_rounded,
                            size: 14, color: accent),
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
                          final isChosen = _selectedFavAnimeId ==
                                  t.id.toString() ||
                              _favAnimeController.text.trim().toLowerCase() ==
                                  t.russianTitle.toLowerCase();

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
                                  color: isChosen
                                      ? accent
                                      : AppColors.strokeMedium,
                                  width: isChosen ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(9)),
                                      child: t.posterUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl:
                                                  wrapCorsSafeUrl(t.posterUrl),
                                              memCacheWidth: 200,
                                              fit: BoxFit.cover,
                                              httpHeaders: const {
                                                'User-Agent': 'SyncPai-App/1.0',
                                                'Referer':
                                                    'https://shikimori.io/',
                                              },
                                              placeholder: (_, __) =>
                                                  const ColoredBox(
                                                      color: Colors.black26),
                                              errorWidget: (_, __, ___) => t
                                                      .effectiveFallbackPoster
                                                      .isNotEmpty
                                                  ? CachedNetworkImage(
                                                      imageUrl: wrapCorsSafeUrl(
                                                          t.effectiveFallbackPoster),
                                                      memCacheWidth: 200,
                                                      fit: BoxFit.cover,
                                                      placeholder: (_, __) =>
                                                          const ColoredBox(
                                                              color: Colors
                                                                  .black26),
                                                      errorWidget:
                                                          (_, __, ___) =>
                                                              const Icon(
                                                                  Icons.movie,
                                                                  size: 20),
                                                    )
                                                  : const Icon(Icons.movie,
                                                      size: 20),
                                            )
                                          : const Icon(Icons.movie, size: 20),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 3),
                                    child: Text(
                                      t.russianTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isChosen ? accent : Colors.white,
                                        fontSize: 10,
                                        fontWeight: isChosen
                                            ? FontWeight.w700
                                            : FontWeight.w500,
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


  Widget _buildShowcaseTypeOption({
    required String type,
    required String title,
    required IconData icon,
    required Color accent,
  }) {
    final isSelected = _selectedShowcaseType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedShowcaseType = type),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color:
                isSelected ? accent.withValues(alpha: 0.16) : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accent : AppColors.strokeMedium,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 20,
                  color: isSelected ? accent : AppColors.textSecondary),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- 6. ВКЛАДКА «ЦВЕТА» ---
  Widget _buildColorsTab(Color accent) {
    return ListView(
      padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spacingXl, vertical: 14),
      children: [
        Text('Акцентная палитра профиля:',
            style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.85,
          ),
          itemCount: SteamProfileThemeAccent.all.length,
          itemBuilder: (context, index) {
            final a = SteamProfileThemeAccent.all[index];
            final isSelected =
                _selectedAccentHex.toLowerCase() == a.hex.toLowerCase();
            final isUnlocked = CustomizationTierPolicy.isAccentUnlocked(
              widget.profile.supporterTier,
              a.hex,
            );
            final isFree = CustomizationTierPolicy.requiredTierForAccent(a.hex) ==
                SupporterTier.free;

            return InkWell(
              onTap: () => setState(() => _selectedAccentHex = a.hex),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? a.color.withValues(alpha: 0.14)
                      : const Color(0xFF161B26),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? a.color : const Color(0x14FFFFFF),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: a.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0x33FFFFFF),
                              width: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (!isUnlocked)
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: Color(0xFF94A3B8),
                          ),
                      ],
                    ),
                    // Мини-превью пилюли и кнопки с выбранным акцентом
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: a.color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: a.color.withValues(alpha: 0.45),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            isFree ? 'Бесплатно' : 'Sponsor',
                            style: TextStyle(
                              color: a.color,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: a.color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Кнопка',
                            style: TextStyle(
                              color: Color(0xFF0B0E14),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
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
