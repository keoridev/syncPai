import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import 'coop_match_screen.dart';
import '../widgets/qr_scanner_sheet.dart';
import '../widgets/sync_room_lobby_sheet.dart';
import '../../../player/domain/entities/player_quality.dart';

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
  String? _pinError;

  // Демонстрационный список друзей с Presence-статусом
  final List<Map<String, dynamic>> _friends = [
    {
      'id': 'fr_1',
      'name': 'NekoChan_99',
      'avatar': 'cat',
      'isOnline': true,
      'statusText': 'Смотрит «Магическая битва: Серия 4»',
      'canJoin': true,
      'roomCode': 'SP-4821',
    },
    {
      'id': 'fr_2',
      'name': 'Senpai_Kun',
      'avatar': 'fox',
      'isOnline': true,
      'statusText': 'В главном меню • Свободен',
      'canJoin': false,
      'roomCode': null,
    },
    {
      'id': 'fr_3',
      'name': 'OtakuMaster',
      'avatar': 'wolf',
      'isOnline': false,
      'statusText': 'Был в сети 45 мин. назад',
      'canJoin': false,
      'roomCode': null,
    },
  ];

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _handleJoinRoom() {
    final raw = _pinController.text.trim();
    if (raw.isEmpty) {
      setState(() => _pinError = 'Введите код комнаты');
      return;
    }
    setState(() => _pinError = null);
    context.push('/room/$raw');
  }

  static const AnimeTitle _freeRoomTitle = AnimeTitle(
    id: 0,
    code: 'free_sync_room',
    russianTitle: '🌐 Свободная комната (выбрать тайтл в каталоге)',
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
          return Padding(
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
                      child: const Icon(Icons.meeting_room_rounded, color: AppColors.primary, size: 22),
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
                        const DropdownMenuItem<AnimeTitle>(
                          value: _freeRoomTitle,
                          child: Text(
                            '🌐 Свободная комната (выбрать тайтл в каталоге)',
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
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      final ep = EpisodeItem(
                        episode: 1,
                        name: 'Серия 1',
                        fhdUrl: '',
                        hdUrl: '',
                        sdUrl: '',
                      );
                      SyncRoomLobbySheet.show(
                        context,
                        title: selectedTitle,
                        episode: ep,
                        initialQuality: PlayerQuality.hd,
                        onStartPlayback: (room, isHost) {
                          Navigator.of(context).pop();
                          if (selectedTitle.id == 0) {
                            // Свободная комната: уведомляем и направляем в каталог
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '🎉 Вы подключены! Теперь откройте любой тайтл в каталоге — друзья подключатся автоматически!',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                backgroundColor: AppColors.syncActive,
                                duration: Duration(seconds: 5),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            if (widget.onCreateRoomTap != null) {
                              widget.onCreateRoomTap!();
                            } else {
                              context.go('/');
                            }
                          } else {
                            context.pushNamed('player', extra: {
                              'title': selectedTitle,
                              'episode': ep,
                              'quality': PlayerQuality.hd,
                              'roomCode': room.code,
                              'isHost': isHost,
                            });
                          }
                        },
                      );
                    },
                    child: const Text('Создать комнату и открыть лобби', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
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
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.strokeMedium),
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.send_rounded, size: 18, color: AppColors.primaryLight),
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
    );
  }

  void _showAddFriendDialog() {
    final friendController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppDimensions.spacingXl,
          right: AppDimensions.spacingXl,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
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
                  child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  'Добавить друга',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Введите никнейм друга или его персональный код (например @NekoChan или SP-USER-1029)',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: friendController,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Никнейм или ID друга',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface,
                prefixIcon: const Icon(Icons.alternate_email_rounded, color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.strokeMedium),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final text = friendController.text.trim();
                  if (text.isNotEmpty) {
                    setState(() {
                      _friends.insert(0, {
                        'id': 'fr_${DateTime.now().millisecondsSinceEpoch}',
                        'name': text,
                        'avatar': 'star',
                        'isOnline': true,
                        'statusText': 'Только что добавлен в друзья',
                        'canJoin': false,
                        'roomCode': null,
                      });
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Друг $text успешно добавлен!'),
                        backgroundColor: AppColors.syncActive,
                      ),
                    );
                  }
                },
                child: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCoopMatch(BuildContext context) {
    List<AnimeTitle> deck = [];
    try {
      final catalogState = context.read<CatalogCubit>().state;
      if (catalogState is CatalogLoaded && catalogState.titles.isNotEmpty) {
        deck = catalogState.titles;
      }
    } catch (_) {}

    if (deck.isEmpty) {
      deck = [
        const AnimeTitle(
          id: 101,
          code: 'frieren',
          russianTitle: 'Провожающая в последний путь Фрирен',
          englishTitle: 'Sousou no Frieren',
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          genres: ['Приключения', 'Фэнтези'],
          description: 'История эльфийки-волшебницы Фрирен после победы над Королем демонов.',
          status: 'Онгоинг',
        ),
        const AnimeTitle(
          id: 102,
          code: 'jujutsu_kaisen',
          russianTitle: 'Магическая битва',
          englishTitle: 'Jujutsu Kaisen',
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          genres: ['Экшен', 'Сёнэн'],
          description: 'Юдзи Итадори проглатывает палец проклятого духа Сукуны.',
          status: 'Онгоинг',
        ),
      ];
    }

    CoopMatchScreen.open(
      context,
      deck: deck,
      roomCode: null,
      userName: 'Вы',
      onStartWatching: (matched) {
        final ep = matched.episodes.isNotEmpty
            ? matched.episodes.first
            : const EpisodeItem(episode: 1);
        widget.onStartSyncRoom?.call(matched, ep);
      },
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
                      child: const Icon(Icons.people_alt_rounded, color: AppColors.primaryLight, size: 24),
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

            // КАРТОЧКА 1 В СТИЛЕ ЖИДКОГО СТЕКЛА: «Подключиться по PIN»
            SliverToBoxAdapter(
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
                          const Icon(Icons.vpn_key_rounded, color: AppColors.primaryLight, size: 20),
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
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pinController,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: 1.5,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Код комнаты',
                                hintStyle: TextStyle(
                                  color: AppColors.textMuted.withValues(alpha: 0.6),
                                  letterSpacing: 0,
                                  fontSize: 12,
                                ),
                                filled: true,
                                fillColor: AppColors.surface.withValues(alpha: 0.7),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.strokeMedium),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: AppColors.primary),
                                ),
                              ),
                              onSubmitted: (_) => _handleJoinRoom(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GlassIconButton(
                            icon: Icons.qr_code_scanner_rounded,
                            tooltip: 'Сканировать QR камерой',
                            size: 46,
                            iconColor: AppColors.syncActive,
                            onTap: () {
                              QrScannerSheet.show(
                                context,
                                onCodeScanned: (code) {
                                  _pinController.text = code;
                                  _handleJoinRoom();
                                },
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          GlassIconButton(
                            icon: Icons.content_paste_rounded,
                            tooltip: 'Вставить из буфера',
                            size: 46,
                            iconColor: AppColors.primaryLight,
                            onTap: () async {
                              final data = await Clipboard.getData('text/plain');
                              if (data?.text != null && data!.text!.isNotEmpty) {
                                _pinController.text = data.text!.trim();
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: AppColors.textPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: _handleJoinRoom,
                            child: const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Войти', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ],
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
                        child: const Icon(Icons.add_to_queue_rounded, color: AppColors.primaryLight, size: 24),
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
                      const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 16),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // КАРТОЧКА 3 В СТИЛЕ ЖИДКОГО СТЕКЛА: «Anime Match (Co-op Tinder)»
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                child: GlassContainer(
                  borderRadius: BorderRadius.circular(22),
                  blurSigma: 16,
                  backgroundOpacity: 0.08,
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF5E3A), Color(0xFFFF2A68)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF2A68).withValues(alpha: 0.4),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.style_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 2,
                              children: [
                                Text(
                                  'Anime Match',
                                  style: AppTypography.titleMedium.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF2A68).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('Co-op Tinder', style: TextStyle(fontSize: 10, color: Color(0xFFFF5E3A), fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Свайпайте карточки тайтлов вдвоем до первого совпадения',
                              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 38,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF2A68),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _openCoopMatch(context),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Свайпать', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ),
                      ),
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
                    Row(
                      children: [
                        Text(
                          'Друзья онлайн',
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
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
                                  Text(
                                    friend['name'] as String,
                                    style: AppTypography.labelLarge.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
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
                                  backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => context.push('/room/$roomCode'),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.primaryLight),
                                    SizedBox(width: 3),
                                    Text(
                                      'Войти',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
