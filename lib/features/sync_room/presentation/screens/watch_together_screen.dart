import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/player_navigation_guard.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../widgets/qr_scanner_sheet.dart';
import '../widgets/room_audio_settings_section.dart';
import '../widgets/sync_room_lobby_sheet.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../../data/repositories/sync_room_repository_impl.dart';
import '../../../player/domain/entities/player_quality.dart';
import '../../../profile/presentation/widgets/friends_management_sheet.dart';
import '../../../profile/services/friends_service.dart';

class WatchTogetherScreen extends StatefulWidget {
  final VoidCallback? onCreateRoomTap;
  final void Function(AnimeTitle, EpisodeItem)? onStartSyncRoom;

  const WatchTogetherScreen({
    super.key,
    this.onCreateRoomTap,
    this.onStartSyncRoom,
  });

  @override
  State<WatchTogetherScreen> createState() => _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends State<WatchTogetherScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  String? _pinError;
  bool _isJoiningRoom = false;

  List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final list = await FriendsService.getFriends();
    if (mounted) {
      setState(() => _friends = list);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _showNotification(BuildContext ctx, String message, {Color? backgroundColor}) {
    if (!mounted) return;
    final theme = Theme.of(ctx);
    final primary = theme.colorScheme.primary;

    ScaffoldMessenger.of(ctx).clearSnackBars();
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: (backgroundColor ?? primary).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.info_outline_rounded,
                color: backgroundColor ?? primary,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: (backgroundColor ?? primary).withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleJoinRoom() async {
    if (_isJoiningRoom) return;

    FocusScope.of(context).unfocus();
    String raw = _pinController.text.trim();
    if (raw.isEmpty) {
      setState(() => _pinError = 'Введите код комнаты');
      return;
    }
    // Поддержка диплинков syncpai://room/CODE или https://syncpai.app/room/CODE
    if (raw.contains('/room/')) {
      final parts = raw.split('/room/');
      if (parts.length > 1) {
        raw = parts[1].split('?').first.split('#').first.trim();
      }
    }

    final cleanPin = SyncRoomRepositoryImpl.extractPinCode(raw);
    setState(() {
      _pinError = null;
      _isJoiningRoom = true;
    });

    try {
      final repo = getIt<SyncRoomRepository>();
      final exists = await repo.validateRoomExists(cleanPin);
      if (!exists) {
        if (!mounted) return;
        setState(() {
          _isJoiningRoom = false;
          _pinError = 'Комната не найдена или сессия завершена';
        });
        _showNotification(context, 'Комната не найдена или сессия завершена');
        return;
      }

      if (!mounted) return;
      setState(() => _isJoiningRoom = false);
      context.push('/room/$cleanPin');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isJoiningRoom = false;
        _pinError = 'Не удалось проверить комнату';
      });
      _showNotification(context, 'Комната не найдена или сессия завершена');
    }
  }

  static const AnimeTitle _freeRoomTitle = AnimeTitle(
    id: 0,
    code: 'free_sync_room',
    russianTitle: 'Свободная комната (выбрать тайтл в каталоге)',
    englishTitle: 'Free Sync Room',
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    genres: [],
    description: 'Вы подключены! Теперь откройте любой тайтл в каталоге — друзья подключатся автоматически!',
    status: 'Свободный выбор',
  );

  void _showCreateRoomSheet(BuildContext context) {
    List<AnimeTitle> availableTitles = [];
    try {
      final catalogState = context.read<CatalogCubit>().state;
      if (catalogState is CatalogLoaded && catalogState.titles.isNotEmpty) {
        availableTitles = catalogState.titles;
      }
    } catch (_) {}

    AnimeTitle selectedTitle = availableTitles.isNotEmpty ? availableTitles.first : _freeRoomTitle;
    int selectedMaxPeers = 4;
    bool enableChat = true;
    bool enableReactions = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: AppDimensions.spacingXl,
                right: AppDimensions.spacingXl,
                top: 16,
                bottom: MediaQuery.of(ctx).padding.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.strokeMedium,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.meeting_room_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Создание комнаты',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Приглашайте друзей и смотрите аниме синхронно',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Выбор тайтла
                Text('Тайтл для совместного просмотра:',
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.strokeMedium),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AnimeTitle>(
                      value: selectedTitle,
                      isExpanded: true,
                      dropdownColor: AppColors.surfaceElevated,
                      items: [
                        DropdownMenuItem<AnimeTitle>(
                          value: _freeRoomTitle,
                          child: Text(
                            'Свободная комната (выбрать тайтл в каталоге)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.primaryLight,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...availableTitles.take(20).map((t) {
                          return DropdownMenuItem<AnimeTitle>(
                            value: t,
                            child: Text(
                              t.russianTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          );
                        }),
                      ],
                      onChanged: (newT) {
                        if (newT != null) {
                          setSheetState(() => selectedTitle = newT);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 2. Лимит участников
                Text('Количество участников:',
                    style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 8),
                Row(
                  children: [2, 4, 8, 0].map((count) {
                    final isSel = selectedMaxPeers == count;
                    final label = count == 0 ? 'Безлимит ∞' : '$count чел.';
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          onTap: () => setSheetState(() => selectedMaxPeers = count),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primary : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? AppColors.primary : AppColors.strokeMedium,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                color: isSel ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),

                // 3. Настройки чата
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Текстовый Twitch-чат в углу', style: TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: const Text('Появляется в углу экрана, не мешая просмотру', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  value: enableChat,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setSheetState(() => enableChat = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Быстрые ответы и реакции', style: TextStyle(color: Colors.white, fontSize: 13)),
                  subtitle: const Text('Шорткаты фраз в один тап («Останови», «Крутой трек»)', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  value: enableReactions,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setSheetState(() => enableReactions = v),
                ),

                const SizedBox(height: 12),

                // 4. Выбор микрофона (устройства ввода) и наушников (устройства вывода)
                const RoomAudioSettingsSection(compact: true),

                const SizedBox(height: 14),

                // Кнопка подтверждения создания (Всегда активна!)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      AnimeTitle fullTitle = selectedTitle;

                      // Если выбрана свободная комната (id == 0), пробуем подхватить первый актуальный релиз из каталога,
                      // но в любом случае создаём комнату в БД rooms и открываем лобби!
                      if (fullTitle.id == 0 && getIt.isRegistered<CatalogRepository>()) {
                        try {
                          final updates = await getIt<CatalogRepository>().getUpdates();
                          if (updates.isNotEmpty) {
                            fullTitle = updates.first;
                          }
                        } catch (_) {}
                      }

                      // Если у тайтла еще не загружены полные серии — подгружаем их через репозиторий
                      if (fullTitle.id != 0 &&
                          fullTitle.episodes.isEmpty &&
                          getIt.isRegistered<CatalogRepository>()) {
                        try {
                          fullTitle = await getIt<CatalogRepository>().getTitleDetails(
                            id: fullTitle.id,
                            code: fullTitle.code,
                          );
                        } catch (_) {}
                      }

                      final ep = fullTitle.episodes.isNotEmpty
                          ? fullTitle.episodes.first
                          : const EpisodeItem(
                              episode: 1,
                              name: 'Серия 1',
                            );

                      if (context.mounted) {
                        Navigator.of(sheetCtx).pop();
                        SyncRoomLobbySheet.show(
                          context,
                          title: fullTitle,
                          episode: ep,
                          initialQuality: PlayerQuality.hd,
                          onStartPlayback: (room, isHost) {
                            PlayerNavigationGuard.openPlayer(context, extra: {
                              'title': fullTitle,
                              'episode': ep,
                              'quality': PlayerQuality.hd,
                              'roomCode': room.code,
                              'isHost': isHost,
                            });
                          },
                        );
                      }
                    },
                    child: const Text('Создать комнату и открыть лобби', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          );
        },
      ),
    );
  }

  void _showFriendInviteSheet(BuildContext context, Map<String, dynamic> friend) {
    HapticFeedback.lightImpact();
    final friendName = friend['name'] as String;
    final isOnline = friend['isOnline'] as bool;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.strokeMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  AppAvatar(
                    avatarUrl: friend['avatar'] as String?,
                    username: friendName,
                    size: 48,
                    borderColor: isOnline ? AppColors.syncActive : AppColors.strokeMedium,
                    borderWidth: 2,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friendName,
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          friend['statusText'] as String,
                          style: AppTypography.caption.copyWith(
                            color: isOnline ? AppColors.syncActive : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.meeting_room_rounded, size: 20),
                label: Text('Создать комнату и позвать $friendName'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCreateRoomSheet(context);
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.strokeMedium),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.account_circle_outlined, size: 19, color: Colors.white70),
                label: Text('Посмотреть профиль $friendName'),
                onPressed: () {
                  Navigator.pop(ctx);
                  context.pushNamed('profile', queryParameters: {'userId': friendName});
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.strokeMedium),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(Icons.send_rounded, size: 18, color: AppColors.primaryLight),
                label: const Text('Отправить персональное приглашение'),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Приглашение отправлено другу $friendName!'),
                      backgroundColor: AppColors.syncActive,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _showAddFriendDialog() {
    showFriendsManagementSheet(
      context,
      accentColor: Theme.of(context).colorScheme.primary,
      onFriendsChanged: _loadFriends,
    );
  }

  void _showReportFriendDialog(BuildContext context, Map<String, dynamic> friend) {
    final friendName = friend['name'] as String? ?? 'пользователя';
    final reasons = [
      'Оскорбительное поведение / токсичность',
      'Спам или подозрительная активность',
      'Бот или фейковый аккаунт',
      'Неприемлемый аватар / статус',
    ];
    String selectedReason = reasons.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.flag_rounded, color: AppColors.warning, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Пожаловаться на $friendName',
                  style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Укажите причину вашей жалобы:',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              ...reasons.map((r) => InkWell(
                    onTap: () => setDialogState(() => selectedReason = r),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            selectedReason == r
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            size: 18,
                            color: selectedReason == r
                                ? Theme.of(context).colorScheme.primary
                                : AppColors.textMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Жалоба на $friendName отправлена модераторам.'),
                    backgroundColor: AppColors.surfaceElevated,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Отправить', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteFriend(BuildContext context, Map<String, dynamic> friend) {
    final friendName = friend['name'] as String? ?? 'пользователя';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.person_remove_rounded, color: AppColors.syncError, size: 22),
            SizedBox(width: 10),
            Text('Удалить из друзей', style: TextStyle(color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          'Вы уверены, что хотите удалить $friendName из списка друзей?',
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.syncError,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              setState(() {
                _friends.removeWhere((f) => f['id'] == friend['id']);
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Пользователь $friendName удален из друзей.'),
                  backgroundColor: AppColors.surfaceElevated,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Удалить', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ВЕРХНИЙ БАР: Заголовок «Смотреть вместе»
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.spacingXl,
                  AppDimensions.spacingLg,
                  AppDimensions.spacingXl,
                  AppDimensions.spacingSm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.people_alt_rounded, color: AppColors.primaryLight, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Смотреть вместе',
                            style: AppTypography.displayMedium.copyWith(
                              fontSize: 22,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Синхронный просмотр секунда в секунду',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 14)),

            // БАННЕР СИНДРОМА УПУЩЕННОЙ ВЫГОДЫ (FOMO)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0x33FF2A68), Color(0x227C83FD)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x66FF2A68)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFF2A68),
                        ),
                        child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 14),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NekoChan_99 и Senpai_Kun сейчас в эфире!',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                            SizedBox(height: 1),
                            Text(
                              'Смотрят «Магическая битва». Присоединяйтесь, чтобы не отстать!',
                              style: TextStyle(color: Colors.white70, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // КАРТОЧКА 1 В СТИЛЕ ЖИДКОГО СТЕКЛА: «Подключиться по PIN»
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                    child: GlassContainer(
                      borderRadius: BorderRadius.circular(22),
                      blurSigma: 16,
                      backgroundOpacity: 0.08,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.vpn_key_rounded, color: AppColors.primaryLight, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Присоединиться к комнате',
                                style: AppTypography.titleMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Введите 6-значный пин-код, полученный от друга',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _pinController,
                            focusNode: _pinFocusNode,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              letterSpacing: 2.0,
                            ),
                            decoration: InputDecoration(
                              hintText: 'PIN-код комнаты (напр. SP-4821)',
                              hintStyle: TextStyle(
                                color: AppColors.textMuted.withValues(alpha: 0.6),
                                letterSpacing: 0,
                                fontSize: 13,
                                fontWeight: FontWeight.normal,
                              ),
                              filled: true,
                              fillColor: AppColors.surface.withValues(alpha: 0.7),
                              prefixIcon: const Icon(Icons.key_rounded, color: AppColors.textSecondary, size: 20),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                                    tooltip: 'Сканировать QR камерой',
                                    color: AppColors.syncActive,
                                    onPressed: () {
                                      QrScannerSheet.show(
                                        context,
                                        onCodeScanned: (code) {
                                          _pinController.text = code;
                                          _handleJoinRoom();
                                        },
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.content_paste_rounded, size: 20),
                                    tooltip: 'Вставить из буфера',
                                    color: AppColors.primaryLight,
                                    onPressed: () async {
                                      final data = await Clipboard.getData('text/plain');
                                      if (data?.text != null && data!.text!.isNotEmpty) {
                                        _pinController.text = data.text!.trim();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.strokeMedium),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: Color(0xFF555B6E), width: 1.2),
                              ),
                            ),
                            onSubmitted: (_) => _handleJoinRoom(),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: AppColors.textPrimary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              onPressed: _isJoiningRoom ? null : _handleJoinRoom,
                              child: _isJoiningRoom
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.login_rounded, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          'Войти',
                                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                          if (_pinError != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _pinError!,
                              style: const TextStyle(color: AppColors.syncError, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // КАРТОЧКА 2 В СТИЛЕ ЖИДКОГО СТЕКЛА: «Создать комнату»
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(22),
                  blurSigma: 16,
                  backgroundOpacity: 0.08,
                  padding: const EdgeInsets.all(18),
                  onTap: () => _showCreateRoomSheet(context),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.add_to_queue_rounded, color: AppColors.primaryLight, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Создать свою комнату',
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Настройте комнату, число мест, чат и пригласите друзей',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 16),
                    ],
                  ),
                ),
              ),
            ),



            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // БЛОК ДРУЗЕЙ И PRESENCE-РАДАРА
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Друзья онлайн',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.syncActive.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.syncActive.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              '${_friends.where((f) => f['isOnline'] == true).length} в сети',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.syncActive,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryLight,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.person_add_alt_rounded, size: 16),
                      label: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: _showAddFriendDialog,
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // СПИСОК КАРТОЧЕК ДРУЗЕЙ В СТИЛЕ ЖИДКОГО СТЕКЛА
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final friend = _friends[index];
                    final isOnline = friend['isOnline'] as bool;
                    final canJoin = friend['canJoin'] as bool;
                    final roomCode = friend['roomCode'] as String?;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassContainer(
                        borderRadius: BorderRadius.circular(18),
                        blurSigma: 12,
                        backgroundOpacity: 0.06,
                        padding: const EdgeInsets.all(14),
                        onTap: () {
                          if (canJoin && roomCode != null) {
                            context.push('/room/$roomCode');
                          } else {
                            _showFriendInviteSheet(context, friend);
                          }
                        },
                        child: Row(
                          children: [
                            // Аватарка с точкой онлайна
                            Stack(
                              children: [
                                AppAvatar(
                                  avatarUrl: friend['avatar'] as String?,
                                  username: friend['name'] as String?,
                                  size: 44,
                                  borderColor: isOnline ? AppColors.syncActive : AppColors.strokeMedium,
                                  borderWidth: 1.5,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: isOnline ? AppColors.syncActive : AppColors.textMuted,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.background, width: 2),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          friend['name'] as String,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.labelLarge.copyWith(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (friend['isPending'] == true) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                                          ),
                                          child: Text(
                                            'Ожидает',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              color: AppColors.warning,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ] else if (friend['streakDays'] != null) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF5E3A).withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: const Color(0xFFFF5E3A).withValues(alpha: 0.45)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.local_fire_department_rounded, size: 12, color: Color(0xFFFF5E3A)),
                                              const SizedBox(width: 2),
                                              Text(
                                                '${friend['streakDays']} дн.',
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFFF5E3A),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    friend['statusText'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.caption.copyWith(
                                      color: isOnline ? AppColors.textSecondary : AppColors.textMuted,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (canJoin && roomCode != null) ...[
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryLight,
                                  side: BorderSide(
                                    color: AppColors.primary.withValues(alpha: 0.5),
                                    width: 1.0,
                                  ),
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => context.push('/room/$roomCode'),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, size: 18, color: AppColors.primaryLight),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Войти',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert_rounded, size: 18, color: AppColors.textMuted),
                              color: AppColors.surfaceElevated,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(color: AppColors.strokeMedium),
                              ),
                              onSelected: (value) {
                                if (value == 'report') {
                                  _showReportFriendDialog(context, friend);
                                } else if (value == 'delete') {
                                  _confirmDeleteFriend(context, friend);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'report',
                                  child: Row(
                                    children: [
                                      Icon(Icons.flag_outlined, size: 18, color: AppColors.warning),
                                      SizedBox(width: 10),
                                      Text('Пожаловаться', style: TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_remove_outlined, size: 18, color: AppColors.syncError),
                                      SizedBox(width: 10),
                                      Text('Удалить из друзей', style: TextStyle(fontSize: 13, color: AppColors.syncError)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _friends.length,
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 90), // Отступ под парящий Glass Bottom Nav Bar
            ),
          ],
        ),
      ),
    );
  }
}
