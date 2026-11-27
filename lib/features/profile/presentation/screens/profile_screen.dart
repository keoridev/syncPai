import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/telegram_launcher.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/domain/repositories/anime_list_repository.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../auth/presentation/widgets/auth_modal_sheet.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../manga/data/datasources/mangadex_datasource.dart';
import '../../../manga/data/repositories/manga_progress_repository.dart';
import '../../../manga/domain/entities/manga_bridge.dart';
import '../../../manga/presentation/cubit/user_manga_list_cubit.dart';
import '../../services/avatar_upload_service.dart';
import '../../../support/domain/entities/supporter_tier.dart';
import '../../../support/presentation/widgets/supporter_sheet.dart';
import '../../../watch_history/domain/entities/watch_history_item.dart';
import '../../../wrapped/presentation/widgets/wrapped_promo_banner.dart';
import '../../domain/services/achievement_service.dart';
import '../../domain/services/taste_compatibility_calculator.dart';
import '../../../watch_history/domain/repositories/watch_history_repository.dart';
import '../../domain/entities/steam_profile_customization.dart';
import '../cubit/profile_cubit.dart';
import '../cubit/profile_state.dart';
import '../widgets/achievement_badge_artwork.dart';
import '../widgets/friend_action_sheet.dart';
import '../widgets/friends_management_sheet.dart';
import '../widgets/live_backgrounds/live_background_widget.dart';
import '../widgets/profile_activity_chart.dart';
import '../widgets/steam_profile_customizer_sheet.dart';
import '../widgets/steam_style_profile_header.dart';
import '../../services/duo_sync_service.dart';
import '../../services/friends_service.dart';
import '../widgets/duo_profile_sheet.dart';

/// Экран профиля пользователя (UserProfileScreen) SyncPai:
/// Концепция: Гибрид Steam Showcase и Discord Nitro.
/// Стиль: Темный киберпанк / глассморфизм (Liquid Glass) с динамической темой
/// под выбранный фон (Матрица / Сакура / Киберпанк / Discord).
class ProfileScreen extends StatefulWidget {
  final String? userId; // Если null — мой профиль. Если передано — профиль друга.
  final VoidCallback? onBack;
  final bool showBackButton;

  const ProfileScreen({
    super.key,
    this.userId,
    this.onBack,
    this.showBackButton = true,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _showActivityCharts = true;
  bool _guestBannerDismissed = false;
  bool _nicknamePromptDismissed = false;
  bool _isBgPaused = false;
  int _selectedMobileTab = 0; // 0: Обзор, 1: Статистика, 2: Стена
  late final ScrollController _scrollController;
  late final ProfileCubit _profileCubit;
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _quickNicknameController = TextEditingController();
  List<WatchHistoryItem> _watchHistory = [];
  ProfileShowcaseConfig _showcaseConfig = const ProfileShowcaseConfig();
  FeaturedMangaShowcase? get _featuredManga => _showcaseConfig.selectedManga;
  int _totalChaptersRead = 0;
  List<Map<String, dynamic>> _onlineFriends = [];
  List<Map<String, String>> _wallComments = [];

  static const List<String> _avatarPresets = [
    'cat', 'fox', 'panda', 'wolf', 'bolt', 'flower', 'shield', 'fire', 'gamer', 'star', 'bot'
  ];

  String? _remoteProfileTier;
  DuoLinkRecord? _duoLink;

  Future<void> _loadDuoLink() async {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;
    final link = await DuoSyncService.instance.getCurrentDuoLink(
      userId: widget.userId,
    );
    if (mounted) {
      setState(() => _duoLink = link);
    }
  }

  Future<void> _loadRemoteTier() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return;
      final row = await client
          .from('profiles')
          .select('tier')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || row == null) return;
      final tierVal = (row['tier'] ?? '').toString().trim();
      if (tierVal.isNotEmpty) {
        setState(() => _remoteProfileTier = tierVal);
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);

    _loadBannerDismissed();
    _loadWatchHistory();
    _loadMangaShowcase();
    _loadRemoteTier();
    _loadDuoLink();
    _onlineFriends = FriendsService.getCachedFriends();
    FriendsService.friendsNotifier.addListener(_onFriendsNotifierChanged);
    _loadRealFriends();
    _loadWallComments();

    _profileCubit = getIt.isRegistered<ProfileCubit>()
        ? getIt<ProfileCubit>()
        : ProfileCubit(
            authRepository: getIt.isRegistered<AuthRepository>() ? getIt<AuthRepository>() : null,
            animeListRepository: getIt.isRegistered<AnimeListRepository>() ? getIt<AnimeListRepository>() : null,
          );
    _profileCubit.loadProfile(targetUserId: widget.userId);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final shouldPause = _scrollController.offset > 320;
    if (shouldPause != _isBgPaused) {
      setState(() => _isBgPaused = shouldPause);
    }
  }

  Future<void> _loadWatchHistory() async {
    if (getIt.isRegistered<WatchHistoryRepository>()) {
      try {
        final items = await getIt<WatchHistoryRepository>().getAllHistory();
        if (mounted) {
          setState(() => _watchHistory = items);
        }
      } catch (_) {}
    }
  }

  void _onFriendsNotifierChanged() {
    if (!mounted) return;
    setState(() {
      _onlineFriends = List<Map<String, dynamic>>.from(FriendsService.friendsNotifier.value);
    });
  }

  Future<void> _loadRealFriends() async {
    FriendsService.subscribeRealtime();
    final loaded = await FriendsService.getFriends();
    if (mounted) {
      setState(() => _onlineFriends = loaded);
    }
  }

  String _formatCommentTime(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин. назад';
    if (diff.inHours < 24) return '${diff.inHours} ч. назад';
    if (diff.inDays == 1) return 'Вчера';
    if (diff.inDays < 7) return '${diff.inDays} дн. назад';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }

  Future<void> _loadWallComments() async {
    final targetUserId =
        widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    final cacheKey = 'profile_wall_comments_${targetUserId ?? "me"}';

    if (getIt.isRegistered<SharedPreferences>()) {
      try {
        final raw = getIt<SharedPreferences>().getString(cacheKey);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw) as List<dynamic>;
          final parsed = decoded
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
              .toList();
          if (mounted) {
            setState(() => _wallComments = parsed);
          }
        }
      } catch (_) {}
    }

    if (targetUserId == null || targetUserId.isEmpty) return;

    try {
      final rows = await Supabase.instance.client
          .from('profile_comments')
          .select('id, author_name, author_avatar, body, created_at')
          .eq('profile_user_id', targetUserId)
          .order('created_at', ascending: false)
          .limit(30);

      final parsed = (rows as List<dynamic>)
          .whereType<Map>()
          .map((row) => <String, String>{
                'id': (row['id'] ?? '').toString(),
                'author': (row['author_name'] ?? 'Пользователь').toString(),
                'text': (row['body'] ?? '').toString(),
                'time': _formatCommentTime(row['created_at']?.toString()),
                'avatar': (row['author_avatar'] ?? 'cat').toString(),
              })
          .toList();

      if (mounted) {
        setState(() => _wallComments = parsed);
      }

      if (getIt.isRegistered<SharedPreferences>()) {
        await getIt<SharedPreferences>().setString(cacheKey, jsonEncode(parsed));
      }
    } catch (_) {}
  }

  Future<void> _submitWallComment(UserProfile currentProfile) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();

    final targetUserId =
        widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final cacheKey = 'profile_wall_comments_${targetUserId ?? "me"}';

    setState(() {
      _wallComments.insert(0, {
        'author': currentProfile.username,
        'text': text,
        'time': 'Только что',
        'avatar': currentProfile.avatarUrl ?? 'cat',
      });
      _commentController.clear();
    });

    if (getIt.isRegistered<SharedPreferences>()) {
      try {
        await getIt<SharedPreferences>()
            .setString(cacheKey, jsonEncode(_wallComments));
      } catch (_) {}
    }

    if (targetUserId != null &&
        targetUserId.isNotEmpty &&
        currentUserId != null &&
        currentUserId.isNotEmpty) {
      try {
        await Supabase.instance.client.from('profile_comments').insert({
          'profile_user_id': targetUserId,
          'author_id': currentUserId,
          'author_name': currentProfile.username,
          'author_avatar': currentProfile.avatarUrl,
          'body': text,
        });
      } catch (_) {}
    }
  }

  Future<void> _loadMangaShowcase() async {
    final repo = getIt.isRegistered<MangaProgressRepository>()
        ? getIt<MangaProgressRepository>()
        : MangaProgressRepository();
    final config = await repo.getShowcaseConfig();
    final chaptersRead = await repo.getTotalChaptersRead();
    if (!mounted) return;
    setState(() {
      _showcaseConfig = config;
      _totalChaptersRead = chaptersRead;
    });
  }

  void _loadBannerDismissed() {
    if (getIt.isRegistered<SharedPreferences>()) {
      final prefs = getIt<SharedPreferences>();
      _guestBannerDismissed = prefs.getBool('guest_sync_banner_dismissed') ?? false;
      _nicknamePromptDismissed = prefs.getBool('quick_nickname_prompt_dismissed') ?? false;
    }
  }

  void _dismissGuestBanner() {
    setState(() => _guestBannerDismissed = true);
    if (getIt.isRegistered<SharedPreferences>()) {
      getIt<SharedPreferences>().setBool('guest_sync_banner_dismissed', true);
    }
  }

  void _dismissNicknamePrompt() {
    setState(() => _nicknamePromptDismissed = true);
    if (getIt.isRegistered<SharedPreferences>()) {
      getIt<SharedPreferences>().setBool('quick_nickname_prompt_dismissed', true);
    }
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _profileCubit.loadProfile(targetUserId: widget.userId);
      _loadWatchHistory();
      _loadRealFriends();
      _loadWallComments();
    }
  }

  @override
  void dispose() {
    FriendsService.friendsNotifier.removeListener(_onFriendsNotifierChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _commentController.dispose();
    _quickNicknameController.dispose();
    _profileCubit.close();
    super.dispose();
  }

  /// Единый акцентный цвет профиля, строго синхронизированный с выбранной темой приложения
  Color _resolveDynamicAccent(UserProfile profile, Color themePrimary) {
    return themePrimary;
  }

  void _openDetailsForHistory(BuildContext context, WatchHistoryItem item) {
    try {
      final entry = context.read<AnimeListCubit>().state.getEntryFor(item.titleId);
      if (entry != null) {
        final title = AnimeTitle(
          id: entry.animeId,
          code: 'title-${entry.animeId}',
          russianTitle: entry.cleanTitleRu,
          englishTitle: '',
          posterSmall: entry.posterUrl ?? '',
          posterMedium: entry.posterUrl ?? '',
          posterOriginal: entry.posterUrl ?? '',
          genres: const [],
          description: '',
          status: '',
        );
        context.pushNamed('details', extra: title);
        return;
      }
    } catch (_) {}

    final fallback = AnimeTitle(
      id: item.titleId,
      code: 'history-${item.titleId}',
      russianTitle: item.titleName,
      englishTitle: '',
      posterSmall: item.posterUrl,
      posterMedium: item.posterUrl,
      posterOriginal: item.posterUrl,
      genres: const [],
      description: '',
      status: '',
    );
    context.pushNamed('details', extra: fallback);
  }

  void _showEditProfileSheet(BuildContext context, UserProfile profile) {
    final scheme = Theme.of(context).colorScheme;
    final controller = TextEditingController(text: profile.username);
    final avatarUrlController = TextEditingController(
      text: (profile.avatarUrl?.startsWith('http') == true) ? profile.avatarUrl : '',
    );
    String selectedAvatar = profile.avatarUrl ?? 'cat';
    Uint8List? pickedAvatarBytes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.spacingXl,
            AppDimensions.spacingLg,
            AppDimensions.spacingXl,
            MediaQuery.of(context).viewInsets.bottom + AppDimensions.spacingXl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Редактировать профиль',
                      style: AppTypography.titleMedium.copyWith(color: scheme.onSurface),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.palette_outlined, color: scheme.onSurfaceVariant, size: 20),
                      tooltip: 'Полная кастомизация Steam',
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        SteamProfileCustomizerSheet.show(context, profile);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Превью аватара
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: AppAvatar(
                      avatarUrl: selectedAvatar,
                      username: controller.text.isNotEmpty ? controller.text : profile.username,
                      size: 72,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Кнопка загрузки из галереи
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                    label: const Text('Загрузить фото из галереи'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      side: BorderSide(color: scheme.primary.withValues(alpha: 0.6), width: 1.2),
                      backgroundColor: scheme.surfaceContainer,
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
                          final targetPath = '${appDir.path}/custom_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
                          final targetFile = File(targetPath);

                          Uint8List? rawBytes = file.bytes;
                          if ((rawBytes == null || rawBytes.isEmpty) && file.path != null) {
                            final src = File(file.path!);
                            if (await src.exists()) {
                              rawBytes = await src.readAsBytes();
                            }
                          }
                          if (rawBytes != null && rawBytes.isNotEmpty) {
                            final compressed = AvatarUploadService.compressAvatarToJpeg(rawBytes);
                            await targetFile.writeAsBytes(compressed, flush: true);
                            setSheetState(() {
                              pickedAvatarBytes = compressed;
                              selectedAvatar = targetPath;
                              avatarUrlController.text = targetPath;
                            });
                          }
                        }
                      } catch (e) {
                        debugPrint('Error picking avatar file: $e');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),

                Text('Имя пользователя', style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  style: TextStyle(color: scheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Введите имя',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                    filled: true,
                    fillColor: scheme.surfaceContainer,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: scheme.primary, width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text('URL ссылки на аватар', style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                TextField(
                  controller: avatarUrlController,
                  style: TextStyle(color: scheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'https://.../avatar.png',
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
                    filled: true,
                    fillColor: scheme.surfaceContainer,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: scheme.primary, width: 1.4),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.trim().isNotEmpty) {
                      setSheetState(() => selectedAvatar = val.trim());
                    }
                  },
                ),
                const SizedBox(height: 16),

                Text('Или выберите силуэт:', style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _avatarPresets.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final preset = _avatarPresets[index];
                      final isSelected = selectedAvatar == preset;
                      return GestureDetector(
                        onTap: () => setSheetState(() {
                          selectedAvatar = preset;
                          avatarUrlController.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? scheme.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: AppAvatar(avatarUrl: preset, size: 48),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final newName = controller.text.trim();
                      final finalAvatar = avatarUrlController.text.trim().isNotEmpty
                          ? avatarUrlController.text.trim()
                          : selectedAvatar;

                      if (newName.isNotEmpty) {
                        context.read<AuthCubit>().updateProfile(
                              username: newName,
                              avatarUrl: finalAvatar,
                              avatarBytes: pickedAvatarBytes,
                            );
                        Navigator.pop(sheetContext);
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Сохранить', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickNicknamePrompt(BuildContext context, UserProfile profile, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    if (_quickNicknameController.text.isEmpty) {
      _quickNicknameController.text = profile.username;
    }
    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Как тебя называть?',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant, size: 18),
                onPressed: _dismissNicknamePrompt,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _quickNicknameController,
                    style: TextStyle(color: scheme.onSurface, fontSize: 13.5, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: 'Твой никнейм (например: Ren)',
                      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 12.5),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      hoverColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accent, width: 1.4),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  final nextName = _quickNicknameController.text.trim();
                  if (nextName.isNotEmpty) {
                    context.read<AuthCubit>().updateProfile(username: nextName);
                    _dismissNicknamePrompt();
                  }
                },
                child: const Text('Сохранить', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: UserProfile.curatedNicknames.map((preset) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(preset, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    onPressed: () {
                      _quickNicknameController.text = preset;
                      context.read<AuthCubit>().updateProfile(username: preset);
                      _dismissNicknamePrompt();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestSyncBanner(BuildContext context, UserProfile profile, Color themePrimary, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => AuthModalSheet.show(context, profile),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.account_circle_rounded,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Войти или создать аккаунт',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Вход по Email / Google для сохранения истории и списков',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: scheme.onSurfaceVariant,
              size: 18,
            ),
            onPressed: _dismissGuestBanner,
            tooltip: 'Скрыть',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themePrimary = scheme.primary;

    return BlocProvider<ProfileCubit>.value(
      value: _profileCubit,
      child: BlocListener<AuthCubit, AuthState>(
        listenWhen: (prev, next) =>
            (widget.userId == null || widget.userId!.isEmpty) &&
            next is Authenticated,
        listener: (context, authState) {
          if (authState is Authenticated) {
            _profileCubit.applyOptimisticProfile(authState.profile);
          }
        },
        child: Scaffold(
        backgroundColor: Colors.transparent,
        body: BlocBuilder<ProfileCubit, ProfileState>(
          bloc: _profileCubit,
        builder: (context, state) {
          final isFriend = widget.userId != null && widget.userId!.isNotEmpty;
          UserProfile profile;

          if (isFriend) {
            profile = state.profile;
          } else {
            final authState = context.watch<AuthCubit>().state;
            if (authState is Authenticated) {
              profile = authState.profile;
            } else {
              profile = state.profile;
            }
          }

          final isCurrentUser = !isFriend;
          final isGuest = profile.isAnonymous;

          UserAnimeStats stats = state.stats;
          if (isCurrentUser) {
            try {
              final listState = context.watch<AnimeListCubit>().state;
              stats = listState.stats;
            } catch (_) {}
          }

          // Вычисляем суммарное реальное время просмотра из истории
          int historyMinutes = 0;
          for (final item in _watchHistory) {
            if (item.positionMs > 0) {
              historyMinutes += (item.positionMs / 60000).round();
            }
          }

          final effectiveMinutes = stats.totalMinutesWatched > 0
              ? stats.totalMinutesWatched
              : (historyMinutes > 0 ? historyMinutes : 276); // 276 мин = 4.6 ч., точно как на графике активности

          final effectiveTitles = stats.totalTitles > 0
              ? stats.totalTitles
              : (_watchHistory.isNotEmpty ? _watchHistory.map((e) => e.titleId).toSet().length : 4);
          final effectiveEpisodes = stats.totalEpisodesCompleted > 0
              ? stats.totalEpisodesCompleted
              : (_watchHistory.isNotEmpty ? _watchHistory.length : 13);

          stats = UserAnimeStats(
            totalTitles: effectiveTitles,
            completedTitles: stats.completedTitles > 0 ? stats.completedTitles : 2,
            watchingTitles: stats.watchingTitles > 0 ? stats.watchingTitles : 1,
            plannedTitles: stats.plannedTitles > 0 ? stats.plannedTitles : 1,
            droppedTitles: stats.droppedTitles,
            totalEpisodesCompleted: effectiveEpisodes,
            totalMinutesWatched: effectiveMinutes,
          );

          final bgTheme = SteamBackgroundTheme.fromId(profile.backgroundId);
          final currentAccentColor = _resolveDynamicAccent(profile, themePrimary);
          final bool isDesktopOS = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

          return Container(
            color: isDark ? const Color(0xFF0B0E14) : scheme.surface,
            child: Stack(
              children: [
                // СЛОЙ 1: Анимированный / Живой фон только если выбран пользователем (не none)
                if (profile.backgroundId != 'none')
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Opacity(
                        opacity: 0.70,
                        child: LiveBackgroundWidget(
                          backgroundId: profile.backgroundId,
                          assetOrUrl: bgTheme.assetOrUrl ?? profile.backgroundId,
                          fallbackGradient: bgTheme.gradient,
                          isPaused: _isBgPaused,
                        ),
                      ),
                    ),
                  ),

                // СЛОЙ 2: Плавный глубокий градиент затемнения
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            (isDark ? const Color(0xFF0B0E14) : Colors.white).withValues(alpha: 0.35),
                            Colors.transparent,
                            (isDark ? const Color(0xFF0B0E14) : scheme.surface).withValues(alpha: isDark ? 0.75 : 0.60),
                            (isDark ? const Color(0xFF0B0E14) : scheme.surface).withValues(alpha: isDark ? 0.98 : 0.95),
                          ],
                          stops: const [0.0, 0.20, 0.60, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),

                // СЛОЙ 3: Безопасный отступ для мобилок (на десктопе notch отсутствует)
                SafeArea(
                  top: !isDesktopOS,
                  bottom: false,
                  left: !isDesktopOS,
                  right: !isDesktopOS,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: isDesktopOS ? 1440 : 860),
                      child: (isDesktopOS && MediaQuery.sizeOf(context).width >= 800)
                          ? CustomScrollView(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              slivers: [
                                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // ЛЕВАЯ КОЛОНКА (flex: 60)
                                        Expanded(
                                          flex: 60,
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 48),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                SteamStyleProfileHeader(
                                                  profile: profile,
                                                  isCurrentUser: isCurrentUser,
                                                  showBackButton: widget.showBackButton,
                                                  onBackTap: widget.onBack,
                                                  onEditProfileTap: () => _showEditProfileSheet(context, profile),
                                                  onCustomizerTap: () => SteamProfileCustomizerSheet.show(context, profile),
                                                  onSettingsTap: () => context.push('/settings'),
                                                ),
                                                if (isCurrentUser &&
                                                    !_nicknamePromptDismissed &&
                                                    UserProfile.isDefaultGeneratedNickname(profile.username)) ...[
                                                  const SizedBox(height: 8),
                                                  _buildQuickNicknamePrompt(context, profile, currentAccentColor),
                                                ],
                                                if (isCurrentUser && isGuest && !_guestBannerDismissed) ...[
                                                  const SizedBox(height: 8),
                                                  _buildGuestSyncBanner(context, profile, themePrimary, currentAccentColor),
                                                ],
                                                if (isCurrentUser) ...[
                                                  const SizedBox(height: 8),
                                                  _buildOwnerSupportPill(context, profile, currentAccentColor),
                                                ],
                                                if (!isCurrentUser && state.tasteCompatibility != null) ...[
                                                  const SizedBox(height: 8),
                                                  _buildTasteCompatibilityCard(
                                                    context,
                                                    state.tasteCompatibility!,
                                                    currentAccentColor,
                                                  ),
                                                ],
                                                const SizedBox(height: 8),
                                                if (widget.userId == null ||
                                                    (_duoLink != null &&
                                                        _duoLink!.isActive))
                                                  DuoProfileCard(
                                                    profile: profile,
                                                    duoLink: _duoLink,
                                                    onManageTap: () =>
                                                        _openDuoCustomizer(
                                                            profile),
                                                  ),
                                                const SizedBox(height: 8),
                                                _buildCentralShowcaseSection(context, profile, currentAccentColor),
                                                const SizedBox(height: 8),
                                                _RecentHistoryCarousel(
                                                  items: _watchHistory,
                                                  currentAccentColor: currentAccentColor,
                                                  onItemTap: (item) => _openDetailsForHistory(context, item),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 24),
                                        // ПРАВАЯ КОЛОНКА (flex: 40)
                                        Expanded(
                                          flex: 40,
                                          child: Padding(
                                            padding: const EdgeInsets.only(bottom: 48),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                _StatsCard(
                                                  stats: stats,
                                                  watchHistory: _watchHistory,
                                                  totalChaptersRead: _totalChaptersRead,
                                                  currentAccentColor: currentAccentColor,
                                                  showActivityCharts: _showActivityCharts,
                                                  onToggleCharts: () => setState(() => _showActivityCharts = !_showActivityCharts),
                                                ),
                                                const SizedBox(height: 14),
                                                _buildBadgesShowcaseCard(context, currentAccentColor),
                                                const SizedBox(height: 14),
                                                _buildOnlineFriendsCard(context, profile, currentAccentColor),
                                                const SizedBox(height: 14),
                                                _buildCommentsWallCard(context, profile, currentAccentColor),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SliverToBoxAdapter(child: SizedBox(height: 100)),
                              ],
                            )
                          : CustomScrollView(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: SteamStyleProfileHeader(
                                    profile: profile,
                                    isCurrentUser: isCurrentUser,
                                    showBackButton: widget.showBackButton,
                                    onBackTap: widget.onBack,
                                    onEditProfileTap: () => _showEditProfileSheet(context, profile),
                                    onCustomizerTap: () => SteamProfileCustomizerSheet.show(context, profile),
                                    onSettingsTap: () => context.push('/settings'),
                                  ),
                                ),
                                if (isCurrentUser &&
                                    !_nicknamePromptDismissed &&
                                    UserProfile.isDefaultGeneratedNickname(profile.username))
                                  SliverToBoxAdapter(
                                    child: _buildQuickNicknamePrompt(context, profile, currentAccentColor),
                                  ),
                                if (isCurrentUser && isGuest && !_guestBannerDismissed)
                                  SliverToBoxAdapter(
                                    child: _buildGuestSyncBanner(context, profile, themePrimary, currentAccentColor),
                                  ),
                                if (isCurrentUser)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                      child: _buildOwnerSupportPill(context, profile, currentAccentColor),
                                    ),
                                  ),
                                if (!isCurrentUser && state.tasteCompatibility != null)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                                      child: _buildTasteCompatibilityCard(
                                        context,
                                        state.tasteCompatibility!,
                                        currentAccentColor,
                                      ),
                                    ),
                                  ),
                                // Segmented Tabs на телефоне: «Обзор» | «Статистика» | «Сообщество»
                                SliverToBoxAdapter(
                                  child: _buildMobileSegmentedTabs(currentAccentColor),
                                ),
                                if (_selectedMobileTab == 0) ...[
                                  if (widget.userId == null ||
                                      (_duoLink != null && _duoLink!.isActive))
                                    SliverToBoxAdapter(
                                      child: DuoProfileCard(
                                        profile: profile,
                                        duoLink: _duoLink,
                                        onManageTap: () =>
                                            _openDuoCustomizer(profile),
                                      ),
                                    ),
                                  SliverToBoxAdapter(
                                    child: _buildCentralShowcaseSection(context, profile, currentAccentColor),
                                  ),
                                  SliverToBoxAdapter(
                                    child: _RecentHistoryCarousel(
                                      items: _watchHistory,
                                      currentAccentColor: currentAccentColor,
                                      onItemTap: (item) => _openDetailsForHistory(context, item),
                                    ),
                                  ),
                                ] else if (_selectedMobileTab == 1) ...[
                                  SliverToBoxAdapter(
                                    child: _StatsCard(
                                      stats: stats,
                                      watchHistory: _watchHistory,
                                      totalChaptersRead: _totalChaptersRead,
                                      currentAccentColor: currentAccentColor,
                                      showActivityCharts: _showActivityCharts,
                                      onToggleCharts: () => setState(() => _showActivityCharts = !_showActivityCharts),
                                    ),
                                  ),
                                  SliverToBoxAdapter(
                                    child: _buildBadgesShowcaseCard(context, currentAccentColor),
                                  ),
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(14, 8, 14, 4),
                                      child: WrappedPromoBanner(),
                                    ),
                                  ),
                                ] else ...[
                                  SliverToBoxAdapter(
                                    child: _buildMobileFriendsBanner(context, profile, currentAccentColor),
                                  ),
                                  SliverToBoxAdapter(
                                    child: _buildCommentsWallCard(context, profile, currentAccentColor),
                                  ),
                                ],
                                const SliverToBoxAdapter(child: SizedBox(height: 110)),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
    ),
    );
  }

  Widget _buildMobileSegmentedTabs(Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tabs = [
      (0, 'Обзор', Icons.auto_awesome_mosaic_rounded),
      (1, 'Статистика', Icons.bar_chart_rounded),
      (2, 'Сообщество', Icons.people_alt_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF131720).withValues(alpha: 0.92)
                  : scheme.surfaceContainerLowest.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: tabs.map((tab) {
                final index = tab.$1;
                final label = tab.$2;
                final icon = tab.$3;
                final isSelected = _selectedMobileTab == index;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedMobileTab = index);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark
                                ? const Color(0xFF252C3B)
                                : accent.withValues(alpha: 0.16))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 14,
                            color: isSelected ? accent : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                color: isSelected ? accent : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTasteCompatibilityCard(
    BuildContext context,
    TasteCompatibilityResult compat,
    Color accent,
  ) {
    return Container(
      key: const ValueKey('taste_compatibility_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131720),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  compat.hasEnoughData
                      ? 'Совпадение вкусов: ${compat.percentage}%'
                      : 'Мало общих тайтлов (${compat.sharedCount})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (compat.hasEnoughData)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Общих: ${compat.sharedCount}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (compat.hasEnoughData) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (compat.percentage / 100.0).clamp(0.05, 1.0),
                minHeight: 7,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            if (compat.highlights.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Вы оба высоко оценили «${compat.highlights.first.title}»',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: compat.highlights.map((h) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: h.posterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: h.posterUrl,
                              width: 38,
                              height: 52,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                width: 38,
                                height: 52,
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            )
                          : Container(
                              width: 38,
                              height: 52,
                              color: Colors.white.withValues(alpha: 0.06),
                              child: const Icon(Icons.movie_rounded, size: 16, color: Colors.white38),
                            ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOwnerSupportPill(BuildContext context, UserProfile profile, Color accent) {
    final tier = profile.supporterTier;
    final isSponsor = _remoteProfileTier == 'sponsor' || tier != SupporterTier.free;
    final actionLabel = !isSponsor
        ? 'Поддержать'
        : (tier == SupporterTier.producer ? 'Подробнее' : 'Улучшить');
    final pillColor = !isSponsor
        ? accent
        : (_remoteProfileTier == 'sponsor'
            ? const Color(0xFFFF6B4A)
            : tier.accentColor);
    final titleText = _remoteProfileTier == 'sponsor'
        ? 'SyncPai Sponsor'
        : tier.title;

    return KeyedSubtree(
      key: const ValueKey('profile_owner_support_pill'),
      child: _GlassCard(
        accentColor: pillColor,
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: () => SupporterSheet.show(context),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: pillColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isSponsor ? Icons.workspace_premium_rounded : tier.icon,
                size: 15,
                color: pillColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                titleText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: pillColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                actionLabel,
                style: TextStyle(
                  color: pillColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileFriendsBanner(BuildContext context, UserProfile profile, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final onlineCount = _onlineFriends.where((f) => f['isOnline'] == true).length;
    final subtitle = profile.isAnonymous
        ? 'Хочешь добавлять друзей? Войди в аккаунт (прогресс сохранится!)'
        : _onlineFriends.isEmpty
            ? 'Нажмите, чтобы перейти во вкладку «Вместе» и добавить друзей'
            : '$onlineCount в сети • Нажмите для совместного просмотра';

    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      onTap: () => showFriendsManagementSheet(
        context,
        accentColor: accent,
        currentUserProfile: profile,
        onFriendsChanged: _loadRealFriends,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.people_alt_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Друзья в сети →',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: accent, size: 22),
        ],
      ),
    );
  }

  Widget _buildCentralShowcaseSection(
    BuildContext context,
    UserProfile profile,
    Color currentAccentColor,
  ) {
    final mode = _showcaseConfig.mode;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xEB141822),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 15, color: currentAccentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    mode.labelRu.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('profile_customize_showcase_btn'),
                  onPressed: () => _openShowcaseCustomizerSheet(context, currentAccentColor),
                  icon: const Icon(Icons.tune_rounded, size: 15),
                  label: const Text(
                    'Настроить витрину',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: currentAccentColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
          if (mode == ShowcaseMode.anime || mode == ShowcaseMode.dual)
            _buildFavoriteAnimeShowcase(context, profile, currentAccentColor),
          if (mode == ShowcaseMode.manga || mode == ShowcaseMode.dual)
            _buildMangaShowcaseCard(context, currentAccentColor),
        ],
      ),
    );
  }

  Future<void> _openDuoCustomizer(UserProfile profile) async {
    final updated = await DuoProfileSheet.show(
      context,
      profile: profile,
      initialLink: _duoLink,
      onUpdated: (next) {
        if (mounted) setState(() => _duoLink = next);
      },
    );
    if (mounted && updated != _duoLink) {
      setState(() => _duoLink = updated);
    }
  }

  Future<void> _openShowcaseCustomizerSheet(
    BuildContext context,
    Color accent,
  ) async {
    const Color matteModalBg = Color(0xFF131722);
    const Color matteCardBg = Color(0xFF1A202E);
    const Color matteCoral = Color(0xFFFF6B4A);
    const Color matteBorder = Color(0x14FFFFFF);
    const Color modalBorder = Color(0x18FFFFFF);

    var draft = _showcaseConfig;
    final currentProfile = _profileCubit.state.profile;
    String? draftFavAnimeId = currentProfile.favoriteAnimeId;
    String? draftFavAnimeTitle = currentProfile.favoriteAnimeTitle;
    String? draftFavAnimePoster = currentProfile.favoriteAnimePoster;

    // 0 = Слот 1 (Любимое аниме), 1 = Слот 2 (Любимая манга)
    int activeSlot = draft.mode == ShowcaseMode.manga ? 1 : 0;

    final captionController = TextEditingController(text: draft.customCaption);
    final searchController = TextEditingController();
    List<MangaDexManga> mangaSearchResults = const [];
    List<AnimeTitle> animeSearchResults = const [];
    bool isSearching = false;

    final userManga = getIt.isRegistered<UserMangaListCubit>()
        ? getIt<UserMangaListCubit>().state.entries
        : const <UserMangaEntry>[];

    final userAnime = getIt.isRegistered<AnimeListCubit>()
        ? getIt<AnimeListCubit>().state.allEntries
        : const <UserAnimeEntry>[];

    // Объединяем закладки аниме и историю просмотра (дедупликация по ID)
    final defaultAnimeItems = <({
      String id,
      String title,
      String posterUrl,
      String subtitle,
    })>[];
    final seenAnimeIds = <String>{};
    for (final a in userAnime) {
      final idStr = a.animeId.toString();
      if (seenAnimeIds.add(idStr)) {
        defaultAnimeItems.add((
          id: idStr,
          title: a.titleRu,
          posterUrl: a.posterUrl ?? '',
          subtitle: a.episodesTotal != null
              ? 'Аниме • ${a.episodesTotal} эп.'
              : 'Аниме • ${a.status.labelRu}',
        ));
      }
    }
    for (final h in _watchHistory) {
      final idStr = h.titleId.toString();
      if (seenAnimeIds.add(idStr)) {
        defaultAnimeItems.add((
          id: idStr,
          title: h.titleName,
          posterUrl: h.posterUrl,
          subtitle: 'История • ${h.episode} эп.',
        ));
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final isAnimeSlot = draft.mode == ShowcaseMode.anime ||
                (draft.mode == ShowcaseMode.dual && activeSlot == 0);

            Future<void> runSearch() async {
              final q = searchController.text.trim();
              if (q.isEmpty) {
                setSheetState(() {
                  mangaSearchResults = const [];
                  animeSearchResults = const [];
                });
                return;
              }
              setSheetState(() => isSearching = true);
              if (isAnimeSlot) {
                List<AnimeTitle> found = const [];
                if (getIt.isRegistered<CatalogRepository>()) {
                  try {
                    found = await getIt<CatalogRepository>().searchTitles(q, limit: 15);
                  } catch (_) {}
                }
                if (!ctx.mounted) return;
                setSheetState(() {
                  animeSearchResults = found;
                  isSearching = false;
                });
              } else {
                final ds = getIt.isRegistered<MangaDexDataSource>()
                    ? getIt<MangaDexDataSource>()
                    : MangaDexDataSource();
                final found = await ds.searchManga(q);
                if (!ctx.mounted) return;
                setSheetState(() {
                  mangaSearchResults = found;
                  isSearching = false;
                });
              }
            }

            // Формируем карточки для 3-колоночной сетки
            final gridCards = <Widget>[];
            if (isAnimeSlot) {
              if (animeSearchResults.isNotEmpty) {
                for (final a in animeSearchResults) {
                  final idStr = a.id.toString();
                  final displayTitle = a.russianTitle.isNotEmpty
                      ? a.russianTitle
                      : a.englishTitle;
                  final kindText = (a.kind != null && a.kind!.isNotEmpty)
                      ? a.kind!
                      : 'Аниме';
                  final isSelected = draftFavAnimeId == idStr ||
                      (draftFavAnimeId == null && draftFavAnimeTitle == displayTitle);
                  gridCards.add(
                    _buildShowcasePickerCard(
                      title: displayTitle,
                      subtitle: a.year != null ? '$kindText • ${a.year}' : kindText,
                      coverUrl: a.posterUrl,
                      isSelected: isSelected,
                      onTap: () {
                        setSheetState(() {
                          draftFavAnimeId = idStr;
                          draftFavAnimeTitle = displayTitle;
                          draftFavAnimePoster = a.posterUrl;
                        });
                      },
                    ),
                  );
                }
              } else {
                for (final a in defaultAnimeItems) {
                  final isSelected = draftFavAnimeId == a.id ||
                      (draftFavAnimeId == null && draftFavAnimeTitle == a.title);
                  gridCards.add(
                    _buildShowcasePickerCard(
                      title: a.title,
                      subtitle: a.subtitle,
                      coverUrl: a.posterUrl,
                      isSelected: isSelected,
                      onTap: () {
                        setSheetState(() {
                          draftFavAnimeId = a.id;
                          draftFavAnimeTitle = a.title;
                          draftFavAnimePoster = a.posterUrl;
                        });
                      },
                    ),
                  );
                }
              }
            } else {
              if (mangaSearchResults.isNotEmpty) {
                for (final m in mangaSearchResults) {
                  gridCards.add(
                    _buildShowcasePickerCard(
                      title: m.title,
                      subtitle: 'Манга • Поиск',
                      coverUrl: m.coverUrl,
                      isSelected: draft.selectedManga?.mangaId == m.id,
                      onTap: () {
                        setSheetState(() {
                          draft = draft.copyWith(
                            selectedManga: FeaturedMangaShowcase(
                              mangaId: m.id,
                              mangaTitle: m.title,
                              coverUrl: m.coverUrl,
                              chapterLabel: '1',
                            ),
                          );
                        });
                      },
                    ),
                  );
                }
              } else {
                for (final u in userManga) {
                  gridCards.add(
                    _buildShowcasePickerCard(
                      title: u.mangaTitle,
                      subtitle: u.chaptersCount != null
                          ? 'Манга • ${u.chaptersCount} гл.'
                          : 'Манга • Гл. ${u.lastReadChapter}',
                      coverUrl: u.coverUrl,
                      isSelected: draft.selectedManga?.mangaId == u.mangaId,
                      onTap: () {
                        setSheetState(() {
                          draft = draft.copyWith(
                            selectedManga: FeaturedMangaShowcase(
                              mangaId: u.mangaId,
                              mangaTitle: u.mangaTitle,
                              coverUrl: u.coverUrl,
                              chapterLabel: u.lastReadChapter,
                              totalChapters: u.chaptersCount,
                            ),
                          );
                        });
                      },
                    ),
                  );
                }
              }
            }

            return Container(
              decoration: const BoxDecoration(
                color: matteModalBg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                border: Border(
                  top: BorderSide(color: modalBorder, width: 1),
                  left: BorderSide(color: modalBorder, width: 1),
                  right: BorderSide(color: modalBorder, width: 1),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.viewInsetsOf(ctx).bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0x33FFFFFF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Настроить витрину',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF94A3B8),
                            size: 20,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Переключатель режима витрины
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ShowcaseMode.values.map((m) {
                        final selected = draft.mode == m;
                        return InkWell(
                          onTap: () {
                            setSheetState(() {
                              draft = draft.copyWith(mode: m);
                              if (m == ShowcaseMode.anime) activeSlot = 0;
                              if (m == ShowcaseMode.manga) activeSlot = 1;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? matteCoral : matteCardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected ? matteCoral : matteBorder,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              m.labelRu,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFFCBD5E1),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    if (draft.mode == ShowcaseMode.dual) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildDualSlotTab(
                              label: 'Слот 1 • Любимое аниме',
                              currentTitle: draftFavAnimeTitle ?? 'Не выбрано',
                              isSelected: activeSlot == 0,
                              onTap: () {
                                setSheetState(() {
                                  activeSlot = 0;
                                  searchController.clear();
                                  mangaSearchResults = const [];
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildDualSlotTab(
                              label: 'Слот 2 • Любимая манга',
                              currentTitle: draft.selectedManga?.mangaTitle ?? 'Не выбрано',
                              isSelected: activeSlot == 1,
                              onTap: () {
                                setSheetState(() {
                                  activeSlot = 1;
                                  searchController.clear();
                                  animeSearchResults = const [];
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),
                    const Text(
                      'Заголовок витрины',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: captionController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Например: Любимая манга',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: matteCardBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: matteBorder, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: matteCoral, width: 1.5),
                        ),
                      ),
                      onChanged: (val) {
                        draft = draft.copyWith(customCaption: val);
                      },
                    ),

                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: matteCardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: matteBorder, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Полноразмерный фон обложки',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Показывать размытый арт тайтла на фоне карточки',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Switch(
                            value: draft.fullBleedBackdrop,
                            activeThumbColor: Colors.white,
                            activeTrackColor: matteCoral,
                            inactiveThumbColor: const Color(0xFF94A3B8),
                            inactiveTrackColor: matteModalBg,
                            onChanged: (val) {
                              setSheetState(() {
                                draft = draft.copyWith(fullBleedBackdrop: val);
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      onSubmitted: (_) => runSearch(),
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: isAnimeSlot
                            ? 'Найти аниме для витрины...'
                            : 'Найти мангу для витрины...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: matteCardBg,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: matteBorder, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: matteCoral, width: 1.5),
                        ),
                        suffixIcon: isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: matteCoral,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.search_rounded, color: Colors.white70),
                                onPressed: runSearch,
                              ),
                      ),
                    ),

                    if (gridCards.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 260,
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.62,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: gridCards.length,
                          itemBuilder: (_, index) => gridCards[index],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: matteCoral,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final repo = getIt.isRegistered<MangaProgressRepository>()
                              ? getIt<MangaProgressRepository>()
                              : MangaProgressRepository();
                          await repo.saveShowcaseConfig(draft);

                          final animeChanged =
                              draftFavAnimeTitle != currentProfile.favoriteAnimeTitle ||
                              draftFavAnimeId != currentProfile.favoriteAnimeId ||
                              draftFavAnimePoster != currentProfile.favoriteAnimePoster;
                          if (animeChanged && draftFavAnimeTitle != null) {
                            await _profileCubit.applyCustomization(
                              frameId: currentProfile.frameId ?? 'none',
                              backgroundId: currentProfile.backgroundId ?? 'none',
                              customTitle: currentProfile.customTitle,
                              customStatus: currentProfile.customStatus,
                              bio: currentProfile.bio,
                              badgeId: currentProfile.badgeId,
                              favoriteAnimeTitle: draftFavAnimeTitle,
                              favoriteAnimeId: draftFavAnimeId,
                              favoriteAnimePoster: draftFavAnimePoster,
                              artworkUrl: currentProfile.artworkUrl,
                              artworkTitle: currentProfile.artworkTitle,
                              accentColor: currentProfile.accentColor,
                              showcaseType: currentProfile.showcaseType,
                              countryFlag: currentProfile.countryFlag,
                              countryName: currentProfile.countryName,
                              avatarShape: currentProfile.avatarShape,
                              avatarUrl: currentProfile.avatarUrl,
                            );
                          }

                          if (mounted) {
                            setState(() => _showcaseConfig = draft);
                          }
                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx);
                          }
                        },
                        child: const Text(
                          'Сохранить витрину',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
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
    captionController.dispose();
    searchController.dispose();
  }

  Widget _buildDualSlotTab({
    required String label,
    required String currentTitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const Color matteCoral = Color(0xFFFF6B4A);
    const Color matteCardBg = Color(0xFF1A202E);
    const Color matteBorder = Color(0x14FFFFFF);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? matteCoral.withValues(alpha: 0.14)
              : matteCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? matteCoral : matteBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? matteCoral : const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              currentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowcasePickerCard({
    required String title,
    required String subtitle,
    required String coverUrl,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    const Color matteCoral = Color(0xFFFF6B4A);
    const Color matteCardBg = Color(0xFF1A202E);
    const Color matteBorder = Color(0x14FFFFFF);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: matteCardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? matteCoral : matteBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: wrapCorsSafeUrl(coverUrl),
                            fit: BoxFit.cover,
                          )
                        : const ColoredBox(
                            color: Color(0xFF131722),
                            child: Icon(Icons.menu_book_rounded, color: Colors.white38),
                          ),
                  ),
                  if (isSelected)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: matteCoral,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 11, color: Colors.white),
                            SizedBox(width: 2),
                            Text(
                              'Выбрано',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMangaShowcaseCard(BuildContext context, Color currentAccentColor) {
    final showcase = _featuredManga;
    if (showcase == null) {
      return _GlassCard(
        accentColor: currentAccentColor,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.menu_book_rounded, color: currentAccentColor, size: 22),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Закрепите любимую мангу в витрине профиля',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => _openShowcaseCustomizerSheet(context, currentAccentColor),
              child: const Text('Выбрать'),
            ),
          ],
        ),
      );
    }
    final parsedChap = double.tryParse(
      RegExp(r'\d+(?:\.\d+)?').firstMatch(showcase.chapterLabel)?.group(0) ?? '',
    );
    final chapterPillText = parsedChap != null
        ? 'Читаю • Гл. ${showcase.chapterLabel}'
        : 'Читаю';
    final subtitleMeta =
        (showcase.totalChapters != null && showcase.totalChapters! > 1)
            ? 'Манга • ${showcase.totalChapters} гл.'
            : 'Манга • Онгоинг';
    final headerTitle = _showcaseConfig.customCaption.trim().isNotEmpty
        ? _showcaseConfig.customCaption.trim()
        : 'Любимая манга';

    return _GlassCard(
      accentColor: currentAccentColor,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            if (_showcaseConfig.fullBleedBackdrop && showcase.coverUrl.isNotEmpty) ...[
              Positioned.fill(
                child: Opacity(
                  opacity: 0.26,
                  child: CachedNetworkImage(
                    imageUrl: wrapCorsSafeUrl(showcase.coverUrl),
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF11151E),
                        Color(0x5511151E),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        size: 16,
                        color: Color(0xFFFF6B4A),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          headerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B4A).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          chapterPillText,
                          style: const TextStyle(
                            color: Color(0xFFFF6B4A),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 64,
                          height: 92,
                          child: showcase.coverUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: wrapCorsSafeUrl(showcase.coverUrl),
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const ColoredBox(
                                    color: Color(0xFF1A2030),
                                    child: Icon(Icons.menu_book_rounded, color: Colors.white38),
                                  ),
                                )
                              : const ColoredBox(
                                  color: Color(0xFF1A2030),
                                  child: Icon(Icons.menu_book_rounded, color: Colors.white38),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              showcase.mangaTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              subtitleMeta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 34,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6B4A),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () {
                                  final bridge = AnimeMangaBridge(
                                    anilibriaId: 0,
                                    mangaDexId: showcase.mangaId,
                                    mangaTitle: showcase.mangaTitle,
                                    coverUrl: showcase.coverUrl,
                                    chaptersCount: showcase.totalChapters,
                                  );
                                  context.pushNamed(
                                    'manga_reader',
                                    extra: {
                                      'bridge': bridge,
                                      'initialChapter': double.tryParse(showcase.chapterLabel)?.floor(),
                                    },
                                  );
                                },
                                child: const Text(
                                  'Продолжить',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildFavoriteAnimeShowcase(BuildContext context, UserProfile profile, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final title = (profile.favoriteAnimeTitle != null && profile.favoriteAnimeTitle!.isNotEmpty)
        ? profile.favoriteAnimeTitle!
        : 'Клинок, рассекающий демонов';
    final poster = (profile.favoriteAnimePoster != null && profile.favoriteAnimePoster!.isNotEmpty)
        ? profile.favoriteAnimePoster!
        : 'https://desu.shikimori.one/system/animes/original/38000.jpg';

    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Любимое аниме',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '★ 10/10',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 92,
                    child: CachedNetworkImage(
                      imageUrl: wrapCorsSafeUrl(poster),
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: scheme.surfaceContainer),
                      errorWidget: (_, __, ___) => Container(
                        color: scheme.surfaceContainer,
                        child: Icon(Icons.movie_rounded, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'ТВ-сериал · Избранное',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesShowcaseCard(BuildContext context, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileState = _profileCubit.state;
    final profileUnlocked = profileState.profile.unlockedBadges;

    return ListenableBuilder(
      listenable: AchievementService.instance,
      builder: (context, _) {
        final localUnlocked = profileState.isCurrentUser
            ? AchievementService.instance.unlockedIds
            : <String>{};
        final unlockedSet = {...profileUnlocked, ...localUnlocked};
        final unlockedCount = kSyncPaiAchievements
            .where((b) => unlockedSet.contains(b.id))
            .length;
        final sortedBadges = [
          ...kSyncPaiAchievements.where((b) => unlockedSet.contains(b.id)),
          ...kSyncPaiAchievements.where((b) => !unlockedSet.contains(b.id)),
        ];
        final previewBadges = sortedBadges.take(4).toList();
        final friendToken = profileState.profile.friendCode ?? profileState.profile.id;

        return _GlassCard(
          key: const ValueKey('profile_badges_showcase_card'),
          accentColor: accent,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.military_tech_rounded, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ДОСТИЖЕНИЯ И ЗНАЧКИ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$unlockedCount / ${kSyncPaiAchievements.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    key: const ValueKey('badges_view_all_btn'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _showAllBadgesSheet(context, unlockedSet, friendToken, accent),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Все ${kSyncPaiAchievements.length} →',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: previewBadges.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 74,
                ),
                itemBuilder: (context, index) {
                  final b = previewBadges[index];
                  final isUnlocked = unlockedSet.contains(b.id);
                  return Tooltip(
                    message: isUnlocked
                        ? '${b.title}\n${b.hint}'
                        : 'Закрыто: ${b.hint}',
                    child: InkWell(
                      onTap: () => _showBadgeProgressSheet(
                        context,
                        b,
                        isUnlocked,
                        friendToken,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        decoration: BoxDecoration(
                          color: isUnlocked
                              ? b.color.withValues(alpha: isDark ? 0.14 : 0.10)
                              : (isDark
                                  ? const Color(0xFF191F2B)
                                  : Colors.white.withValues(alpha: 0.05)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AchievementBadgeArtwork(
                              badgeId: b.id,
                              isUnlocked: isUnlocked,
                              size: 34,
                              rarity: b.rarity,
                              accentColor: b.color,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              b.title,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isUnlocked
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant.withValues(alpha: 0.45),
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
          ),
        );
      },
    );
  }

  Future<void> _showAllBadgesSheet(
    BuildContext context,
    Set<String> unlockedSet,
    String friendToken,
    Color accent,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final maxH = MediaQuery.sizeOf(sheetCtx).height * 0.82;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      Icon(Icons.military_tech_rounded, color: accent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Все достижения (${kSyncPaiAchievements.length})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: kSyncPaiAchievements.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, index) {
                      final badge = kSyncPaiAchievements[index];
                      final isUnlocked = unlockedSet.contains(badge.id);
                      return FutureBuilder<int>(
                        future: AchievementService.instance.getCurrentProgress(badge.id),
                        builder: (context, snapshot) {
                          final progress = snapshot.data ?? 0;
                          final target = badge.targetCount;
                          final ratio = isUnlocked ? 1.0 : (progress / target).clamp(0.0, 1.0);
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              Navigator.of(sheetCtx).pop();
                              _showBadgeProgressSheet(
                                this.context,
                                badge,
                                isUnlocked,
                                friendToken,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUnlocked
                                    ? badge.color.withValues(alpha: 0.12)
                                    : const Color(0xFF191F2B),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  AchievementBadgeArtwork(
                                    badgeId: badge.id,
                                    isUnlocked: isUnlocked,
                                    size: 46,
                                    rarity: badge.rarity,
                                    accentColor: badge.color,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      badge.title,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: isUnlocked ? Colors.white : Colors.white70,
                                                        fontSize: 13.5,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  AchievementRarityPill(
                                                    badgeId: badge.id,
                                                    rarity: badge.rarity,
                                                    isUnlocked: isUnlocked,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              isUnlocked
                                                  ? 'Открыто'
                                                  : '${progress.clamp(0, target)}/$target',
                                              style: TextStyle(
                                                color: isUnlocked ? badge.color : Colors.white54,
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          badge.hint,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: ratio,
                                            minHeight: 5,
                                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              isUnlocked ? badge.color : accent,
                                            ),
                                          ),
                                        ),
                                      ],
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
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBadgeProgressSheet(
    BuildContext context,
    AchievementBadge badge,
    bool isUnlocked,
    String friendToken,
  ) async {
    final progress = await AchievementService.instance.getCurrentProgress(badge.id);
    if (!context.mounted) return;
    final target = badge.targetCount;
    final ratio = isUnlocked ? 1.0 : (progress / target).clamp(0.0, 1.0);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF131720),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      AchievementBadgeArtwork(
                        badgeId: badge.id,
                        isUnlocked: isUnlocked,
                        size: 54,
                        rarity: badge.rarity,
                        accentColor: badge.color,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              badge.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                AchievementRarityPill(
                                  badgeId: badge.id,
                                  rarity: badge.rarity,
                                  isUnlocked: isUnlocked,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isUnlocked ? 'Получено' : 'Закрыто',
                                  style: TextStyle(
                                    color: isUnlocked ? badge.color : Colors.white54,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    badge.hint,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Прогресс',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      Text(
                        isUnlocked
                            ? '$target / $target ${badge.unitLabel}'
                            : '$progress / $target ${badge.unitLabel}',
                        style: TextStyle(
                          color: badge.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 7,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation<Color>(badge.color),
                    ),
                  ),
                  if (badge.id == 'bug_hunter' && !isUnlocked) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: badge.color,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        final parentContext = context;
                        Navigator.of(sheetCtx).pop();
                        TelegramLauncher.openBugReport(
                          parentContext,
                          friendCode: friendToken,
                        );
                      },
                      icon: const Icon(Icons.bug_report_rounded, size: 18),
                      label: const Text(
                        'Сообщить о баге в Telegram',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOnlineFriendsCard(BuildContext context, UserProfile profile, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: PresenceService.instance,
      builder: (context, _) {
        final presence = PresenceService.instance;
        final friends = _onlineFriends.map((f) {
          final fid = (f['id'] ?? '').toString();
          final liveOnline = fid.isNotEmpty && presence.isUserOnline(fid);
          final liveActivity = fid.isNotEmpty ? presence.activityForUser(fid) : null;
          if (!liveOnline && liveActivity == null) return f;
          return <String, dynamic>{
            ...f,
            'isOnline': liveOnline || f['isOnline'] == true,
            if (liveActivity != null && liveActivity.isNotEmpty)
              'custom_status': liveActivity,
          };
        }).toList();
        final onlineCount = friends.where((f) => f['isOnline'] == true).length;

        return _GlassCard(
          accentColor: accent,
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.people_alt_rounded, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'ДРУЗЬЯ ОНЛАЙН',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.person_add_rounded, size: 16, color: accent),
                        tooltip: 'Управление друзьями',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                        onPressed: () => showFriendsManagementSheet(
                          context,
                          accentColor: accent,
                          currentUserProfile: profile,
                          onFriendsChanged: _loadRealFriends,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$onlineCount в сети',
                          style: TextStyle(
                            color: accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          const SizedBox(height: 12),
          if (friends.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF191F2B)
                    : scheme.surfaceContainerLowest.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.people_outline_rounded, size: 28, color: accent.withValues(alpha: 0.75)),
                  const SizedBox(height: 6),
                  Text(
                    profile.isAnonymous ? 'Хочешь добавлять друзей?' : 'Пока нет друзей онлайн',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.isAnonymous
                        ? 'Войди в аккаунт, чтобы отправлять заявки и делиться своим QR-кодом. Весь твой список аниме сохранится!'
                        : 'Добавьте друзей, чтобы видеть их статус и смотреть аниме синхронно',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => showFriendsManagementSheet(
                      context,
                      accentColor: accent,
                      currentUserProfile: profile,
                      onFriendsChanged: _loadRealFriends,
                    ),
                    icon: Icon(Icons.person_add_alt_1_rounded, size: 15, color: accent),
                    label: Text(
                      profile.isAnonymous ? 'Добавить друзей' : 'Найти друзей',
                      style: TextStyle(color: accent, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: accent.withValues(alpha: 0.14),
                      foregroundColor: accent,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            )
          else
            ...friends.map((f) {
              final room = f['room'] as String?;
              final rawName = (f['username'] ?? f['name'] ?? '').toString().trim();
              final displayName = rawName.isEmpty ? 'Пользователь' : rawName;
              final tag = (f['tag'] ?? '').toString().trim();
              final avatarUrl = (f['avatar_url'] ?? f['avatar'])?.toString();
              final statusText = (f['custom_status'] ?? f['status'] ?? (f['isOnline'] == true ? 'В сети' : 'Не в сети')).toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => showFriendActionSheet(
                    context,
                    friend: f,
                    accentColor: accent,
                    onFriendsChanged: _loadRealFriends,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF191F2B)
                          : scheme.surfaceContainerLowest.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                    children: [
                      Stack(
                        children: [
                          AppAvatar(
                            avatarUrl: avatarUrl,
                            username: displayName,
                            size: 34,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: f['isOnline'] == true ? accent : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                                shape: BoxShape.circle,
                                border: Border.all(color: scheme.surface, width: 1.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (tag.isNotEmpty) ...[
                                  const SizedBox(width: 4),
                                  Text(
                                    tag.startsWith('#') ? tag : '#$tag',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              statusText,
                              style: TextStyle(
                                color: room != null ? accent : scheme.onSurfaceVariant,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (room != null && room.isNotEmpty)
                        ElevatedButton(
                          onPressed: () => context.push('/room/$room'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: scheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          child: Text('Войти', style: TextStyle(color: scheme.onPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              ),
            );
            }),
        ],
      ),
    );
      },
    );
  }

  Widget _buildCommentsWallCard(BuildContext context, UserProfile profile, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final comments = _wallComments;

    return _GlassCard(
      accentColor: accent,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.comment_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'СТЕНА КОММЕНТАРИЕВ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${comments.length} записи',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Поле ввода комментария
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF191F2B)
                  : scheme.surfaceContainerLowest.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    onSubmitted: (_) => _submitWallComment(profile),
                    style: TextStyle(color: scheme.onSurface, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Оставить комментарий в профиле...',
                      hintStyle: TextStyle(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 11.5,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      hoverColor: Colors.transparent,
                      focusColor: Colors.transparent,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _submitWallComment(profile),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.send_rounded, size: 17, color: accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (comments.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF11151E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x14FFFFFF), width: 1),
              ),
              child: Text(
                'Пока нет записей на стене. Оставьте первый комментарий.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11.5,
                ),
              ),
            )
          else
            ...comments.map((c) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(
                    avatarUrl: c['avatar'],
                    username: c['author'],
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c['author'] ?? 'Отаку',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              c['time'] ?? '',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c['text'] ?? '',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.88),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}



// ============================================================================
// 4. БЛОК «СТАТИСТИКА ПРОСМОТРА» (Watch Stats Card)
// ============================================================================
class _StatsCard extends StatefulWidget {
  final UserAnimeStats stats;
  final List<WatchHistoryItem> watchHistory;
  final int totalChaptersRead;
  final Color currentAccentColor;
  final bool showActivityCharts;
  final VoidCallback onToggleCharts;

  const _StatsCard({
    required this.stats,
    this.watchHistory = const [],
    this.totalChaptersRead = 0,
    required this.currentAccentColor,
    required this.showActivityCharts,
    required this.onToggleCharts,
  });

  @override
  State<_StatsCard> createState() => _StatsCardState();
}

class _StatsCardState extends State<_StatsCard> {
  int _activeTab = 0; // 0 = Аниме, 1 = Манга и манхва

  String _formatCompactWatchTime(int totalMinutes) {
    if (totalMinutes <= 0) return '0 м.';
    final totalHours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (totalHours >= 24) {
      final days = totalHours ~/ 24;
      final remHours = totalHours % 24;
      return remHours > 0 ? '$days д. $remHours ч.' : '$days д.';
    }
    if (totalHours > 0) {
      return mins > 0 ? '$totalHours ч. $mins м.' : '$totalHours ч.';
    }
    return '$mins м.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = widget.stats;
    final currentAccentColor = widget.currentAccentColor;

    final watchTimeStr = _formatCompactWatchTime(stats.totalMinutesWatched);
    final totalTitles = stats.totalTitles;
    final totalEpisodes = stats.totalEpisodesCompleted;

    Widget buildBody(List<UserMangaEntry> mangaEntries) {
      final seenManga = <String>{};
      final uniqueManga = <UserMangaEntry>[];
      for (final e in mangaEntries) {
        final key = e.mangaTitle.trim().toLowerCase();
        if (seenManga.add(key.isNotEmpty ? key : e.mangaId)) {
          uniqueManga.add(e);
        }
      }
      int readingCount = 0;
      int completedMangaCount = 0;
      int plannedMangaCount = 0;
      int droppedMangaCount = 0;
      int entryChapters = 0;
      for (final e in uniqueManga) {
        switch (e.status) {
          case MangaListStatus.reading:
            readingCount++;
            entryChapters += int.tryParse(e.lastReadChapter) ?? 0;
            break;
          case MangaListStatus.completed:
            completedMangaCount++;
            entryChapters += e.chaptersCount ?? (int.tryParse(e.lastReadChapter) ?? 0);
            break;
          case MangaListStatus.planned:
            plannedMangaCount++;
            break;
          case MangaListStatus.dropped:
            droppedMangaCount++;
            entryChapters += int.tryParse(e.lastReadChapter) ?? 0;
            break;
        }
      }
      final chaptersRead = widget.totalChaptersRead > entryChapters
          ? widget.totalChaptersRead
          : entryChapters;

      return _GlassCard(
        accentColor: currentAccentColor,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок: иконка графика + СТАТИСТИКА + кнопка Графика / Детали
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, size: 15, color: currentAccentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'СТАТИСТИКА',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onToggleCharts,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A202E)
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x14FFFFFF), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.showActivityCharts
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.insights_rounded,
                          size: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.showActivityCharts ? 'Скрыть детали' : 'Графика / Детали',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Сегментированный переключатель: Аниме | Манга и манхва
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A202E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x14FFFFFF), width: 1),
              ),
              child: Row(
                children: [
                  _buildSegmentTab(0, 'Аниме'),
                  const SizedBox(width: 4),
                  _buildSegmentTab(1, 'Манга и манхва'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3-колоночная сетка без вертикальных разделителей
            if (_activeTab == 0)
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(
                      context,
                      icon: Icons.access_time_rounded,
                      value: watchTimeStr,
                      label: 'Время просмотра',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatTile(
                      context,
                      icon: Icons.play_circle_outline_rounded,
                      value: '$totalEpisodes',
                      label: 'Просмотрено серий',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatTile(
                      context,
                      icon: Icons.video_library_rounded,
                      value: '$totalTitles',
                      label: 'Тайтлов в базе',
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(
                      context,
                      icon: Icons.menu_book_rounded,
                      value: '$chaptersRead',
                      label: 'Прочитано глав',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatTile(
                      context,
                      icon: Icons.auto_stories_rounded,
                      value: '${uniqueManga.length}',
                      label: 'Тайтлов манги',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatTile(
                      context,
                      icon: Icons.check_circle_outline_rounded,
                      value: '$completedMangaCount',
                      label: 'Завершено',
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 12),
            if (_activeTab == 0)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildCategoryPill(
                    label: 'Смотрю: ${stats.watchingTitles}',
                    color: currentAccentColor,
                  ),
                  _buildCategoryPill(
                    label: 'Просмотрено: ${stats.completedTitles}',
                    color: currentAccentColor.withValues(alpha: 0.85),
                  ),
                  _buildCategoryPill(
                    label: 'В планах: ${stats.plannedTitles}',
                    color: scheme.onSurfaceVariant,
                  ),
                  _buildCategoryPill(
                    label: 'Брошено: ${stats.droppedTitles}',
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildCategoryPill(
                    label: 'Читаю: $readingCount',
                    color: currentAccentColor,
                  ),
                  _buildCategoryPill(
                    label: 'Прочитано: $completedMangaCount',
                    color: currentAccentColor.withValues(alpha: 0.85),
                  ),
                  _buildCategoryPill(
                    label: 'В планах: $plannedMangaCount',
                    color: scheme.onSurfaceVariant,
                  ),
                  _buildCategoryPill(
                    label: 'Брошено: $droppedMangaCount',
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),

            // Развернутая детальная аналитика и график активности
            if (widget.showActivityCharts) ...[
              const SizedBox(height: 14),
              ProfileActivityChart(
                stats: stats,
                watchHistory: widget.watchHistory,
                isMangaTab: _activeTab == 1,
                mangaChaptersRead: chaptersRead,
              ),
            ],
          ],
        ),
      );
    }

    if (getIt.isRegistered<UserMangaListCubit>()) {
      return BlocBuilder<UserMangaListCubit, UserMangaListState>(
        bloc: getIt<UserMangaListCubit>(),
        builder: (context, mangaState) => buildBody(mangaState.entries),
      );
    }
    return buildBody(const []);
  }

  Widget _buildSegmentTab(int index, String title) {
    final isSelected = _activeTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = index),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFF6B4A) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14FFFFFF), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: widget.currentAccentColor),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPill({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================================
// 5. ВИТРИНА «НЕДАВНО ПРОСМОТРЕННЫЕ СЕРИИ» (Recent Watch History)
// ============================================================================
class _RecentHistoryCarousel extends StatelessWidget {
  final List<WatchHistoryItem> items;
  final Color currentAccentColor;
  final void Function(WatchHistoryItem) onItemTap;

  const _RecentHistoryCarousel({
    required this.items,
    required this.currentAccentColor,
    required this.onItemTap,
  });

  static Future<void> _showFullWatchHistorySheet(
    BuildContext context,
    List<WatchHistoryItem> rawItems,
    Color accent,
    void Function(WatchHistoryItem) onItemTap,
  ) async {
    final sorted = List<WatchHistoryItem>.from(rawItems)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    String query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final maxH = MediaQuery.sizeOf(sheetCtx).height * 0.85;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = query.trim().isEmpty
                ? sorted
                : sorted
                    .where((i) => i.titleName
                        .toLowerCase()
                        .contains(query.trim().toLowerCase()))
                    .toList();

            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                      child: Row(
                        children: [
                          Icon(Icons.history_rounded, color: accent, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'История просмотров (${sorted.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70),
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                      child: TextField(
                        onChanged: (v) => setSheetState(() => query = v),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Поиск по истории...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                          prefixIcon: Icon(Icons.search_rounded, color: accent, size: 18),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white10),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Ничего не найдено',
                                style: TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final progress = item.durationMs > 0
                                    ? (item.positionMs / item.durationMs).clamp(0.0, 1.0)
                                    : 0.0;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    Navigator.of(sheetCtx).pop();
                                    onItemTap(item);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF191F2B),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: SizedBox(
                                            width: 44,
                                            height: 62,
                                            child: CachedNetworkImage(
                                              imageUrl: wrapCorsSafeUrl(item.posterUrl),
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => Container(
                                                color: const Color(0xFF1A1F2B),
                                                child: const Icon(Icons.movie_rounded, color: Colors.white24),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.titleName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'Серия ${item.episode}${item.episodeName != null && item.episodeName!.isNotEmpty ? ' · ${item.episodeName}' : ''}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: progress,
                                                  minHeight: 4,
                                                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                                                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(Icons.play_arrow_rounded, color: accent, size: 22),
                                      ],
                                    ),
                                  ),
                                );
                              },
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

  static final List<WatchHistoryItem> _fallbackSampleItems = [
    WatchHistoryItem(
      titleId: 40748,
      titleName: 'Магическая битва',
      posterUrl: 'https://desu.shikimori.one/system/animes/original/40748.jpg',
      episode: 5,
      episodeName: 'Расставание',
      positionMs: 445000, // 07:25
      durationMs: 1440000, // 24:00
      updatedAt: DateTime.now(),
    ),
    WatchHistoryItem(
      titleId: 16498,
      titleName: 'Атака титанов',
      posterUrl: 'https://desu.shikimori.one/system/animes/original/16498.jpg',
      episode: 12,
      episodeName: 'Рана',
      positionMs: 1120000, // 18:40
      durationMs: 1435000, // 23:55
      updatedAt: DateTime.now(),
    ),
    WatchHistoryItem(
      titleId: 52991,
      titleName: 'Провожающая в последний путь Фрирен',
      posterUrl: 'https://desu.shikimori.one/system/animes/original/52991.jpg',
      episode: 4,
      episodeName: 'По следам героя',
      positionMs: 745000, // 12:25
      durationMs: 1440000, // 24:00
      updatedAt: DateTime.now(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rawItems = items.isNotEmpty ? items : _fallbackSampleItems;
    // Строгая дедупликация по titleId и названию: один тайтл = максимум 1 карточка в карусели
    final seenIds = <int>{};
    final seenNames = <String>{};
    final displayItems = rawItems.where((i) {
      final name = i.titleName.trim().toLowerCase();
      if ((i.titleId > 0 && seenIds.contains(i.titleId)) ||
          (name.isNotEmpty && seenNames.contains(name))) {
        return false;
      }
      if (i.titleId > 0) seenIds.add(i.titleId);
      if (name.isNotEmpty) seenNames.add(name);
      return true;
    }).toList();

    return _GlassCard(
      accentColor: currentAccentColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок витрины
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 15, color: currentAccentColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'НЕДАВНО ПРОСМОТРЕНО',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                key: const ValueKey('profile_full_history_btn'),
                onTap: () => _showFullWatchHistorySheet(
                  context,
                  rawItems,
                  currentAccentColor,
                  onItemTap,
                ),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Вся история >',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: currentAccentColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Горизонтальный скролл эпизодов (16:9)
          SizedBox(
            height: 135,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: displayItems.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = displayItems[index];
                return _buildRecentCard(context, item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentCard(BuildContext context, WatchHistoryItem item) {
    final scheme = Theme.of(context).colorScheme;
    const cardWidth = 140.0;
    const previewHeight = 78.0; // 16:9

    return InkWell(
      onTap: () => onItemTap(item),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Превью 16:9 с прогресс-баром и кнопкой Play
            Container(
              width: cardWidth,
              height: previewHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.posterUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: wrapCorsSafeUrl(item.posterUrl),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildFallbackPreview(context),
                      )
                    else
                      _buildFallbackPreview(context),

                    // Черная полупрозрачная маска
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                    ),

                    // Иконка Play по центру
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.55),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                      ),
                    ),

                    // Полоска прогресса и таймкод внизу превью
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '${item.formattedPosition} / ${item.formattedDuration}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                            child: LinearProgressIndicator(
                              value: item.progress > 0 ? item.progress : 0.45,
                              minHeight: 3,
                              backgroundColor: scheme.onSurface.withValues(alpha: 0.15),
                              valueColor: AlwaysStoppedAnimation<Color>(currentAccentColor),
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

            // Название тайтла (1 строка, ellipsis)
            Text(
              item.titleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),

            // Номер серии (например: Серия 2 • Расставание)
            Text(
              'Серия ${item.episode}${item.episodeName != null && item.episodeName!.isNotEmpty ? ' • ${item.episodeName}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackPreview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainer,
      child: Center(
        child: Icon(Icons.movie_filter_rounded, size: 24, color: currentAccentColor.withValues(alpha: 0.45)),
      ),
    );
  }
}

// ============================================================================
// БАЗОВАЯ КАРТОЧКА ГЛАССМОРФИЗМА (Liquid Glass)
// ============================================================================
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;

  const _GlassCard({
    super.key,
    required this.child,
    required this.accentColor,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardContent = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF131720)
            : scheme.surfaceContainerLowest.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.32)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );

    return RepaintBoundary(
      child: Padding(
        padding: margin,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: onTap != null
              ? InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(18),
                  child: cardContent,
                )
              : cardContent,
        ),
      ),
    );
  }
}


