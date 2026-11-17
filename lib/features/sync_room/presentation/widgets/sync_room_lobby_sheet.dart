import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/network/image_cors_helper.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_dimensions.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/shimmer_placeholder.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:sync_pai/features/auth/presentation/widgets/pai_chan_auth_gate.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import 'package:sync_pai/features/profile/services/friends_service.dart';
import '../../data/repositories/sync_room_repository_impl.dart';
import '../../domain/entities/sync_room.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../../services/active_room_service.dart';
import '../../services/room_audio_devices_service.dart';
import '../cubit/sync_room_cubit.dart';
import '../cubit/sync_room_state.dart';
import '../screens/coop_match_screen.dart';
import 'in_room_anime_picker_sheet.dart';
import 'qr_scanner_sheet.dart';
import 'room_audio_settings_section.dart';

enum SyncLobbyTab { host, join }

class SyncRoomLobbySheet extends StatefulWidget {
  final AnimeTitle title;
  final EpisodeItem episode;
  final PlayerQuality initialQuality;
  final void Function(SyncRoom room, bool isHost) onStartPlayback;

  const SyncRoomLobbySheet({
    super.key,
    required this.title,
    required this.episode,
    this.initialQuality = PlayerQuality.hd,
    required this.onStartPlayback,
  });

  static Future<void> show(
    BuildContext context, {
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality initialQuality = PlayerQuality.hd,
    required void Function(SyncRoom room, bool isHost) onStartPlayback,
  }) {
    final isDesktop = !kIsWeb &&
        (Platform.isWindows ||
            Platform.isMacOS ||
            Platform.isLinux ||
            MediaQuery.of(context).size.width >= 650);

    if (isDesktop) {
      return showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.78),
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
            child: BlocProvider(
              create: (_) => SyncRoomCubit(repository: getIt<SyncRoomRepository>()),
              child: SyncRoomLobbySheet(
                title: title,
                episode: episode,
                initialQuality: initialQuality,
                onStartPlayback: onStartPlayback,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => BlocProvider(
        create: (_) => SyncRoomCubit(repository: getIt<SyncRoomRepository>()),
        child: SyncRoomLobbySheet(
          title: title,
          episode: episode,
          initialQuality: initialQuality,
          onStartPlayback: onStartPlayback,
        ),
      ),
    );
  }

  @override
  State<SyncRoomLobbySheet> createState() => _SyncRoomLobbySheetState();
}

class _SyncRoomLobbySheetState extends State<SyncRoomLobbySheet> {
  SyncLobbyTab _currentTab = SyncLobbyTab.host;
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  final Color _themeAccent = AppColors.primary;

  @override
  void initState() {
    super.initState();

    // По умолчанию сразу создаем комнату для выбранного тайтла и серии в 720p HD
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SyncRoomCubit>().createRoom(
            title: widget.title,
            episode: widget.episode,
            quality: widget.initialQuality,
          );
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _onPinChanged(String value) {
    // При любом вводе сбрасываем предыдущую ошибку
    context.read<SyncRoomCubit>().clearError();
    // Авто-проверка при заполнении 6 символов
    final digits = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (digits.length >= 6) {
      context.read<SyncRoomCubit>().joinRoom(value);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      final code = text.replaceAll('syncpai://room/', '').trim();
      _pinController.text = code;
      _onPinChanged(code);
    }
  }

  void _minimizeLobby(BuildContext context) {
    final cubitState = context.read<SyncRoomCubit>().state;
    SyncRoom? room;
    bool isHost = _currentTab == SyncLobbyTab.host;
    if (cubitState is SyncRoomHostWaiting) {
      room = cubitState.room;
      isHost = true;
    } else if (cubitState is SyncRoomJoined) {
      room = cubitState.room;
      isHost = cubitState.isHost;
    } else {
      room = SyncRoom(
        code: 'SP-482100',
        title: widget.title,
        episode: widget.episode,
        quality: widget.initialQuality,
        hostName: 'Хост (Вы)',
        status: SyncRoomStatus.waiting,
        createdAt: DateTime.now(),
      );
    }

    final rootNav = Navigator.of(context, rootNavigator: true);
    final onStartPlayback = widget.onStartPlayback;

    ActiveRoomService.instance.minimizeRoom(
      room: room,
      isHost: isHost,
      isInPlayer: false,
      onExpandRoom: (expandedRoom, hostFlag) {
        final navCtx = rootNav.context;
        if (navCtx.mounted) {
          SyncRoomLobbySheet.show(
            navCtx,
            title: expandedRoom.title,
            episode: expandedRoom.episode,
            initialQuality: expandedRoom.quality,
            onStartPlayback: onStartPlayback,
          );
        }
      },
    );

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openInRoomAnimePicker(BuildContext context, SyncRoom? room, AnimeTitle currentTitle) async {
    final cubit = context.read<SyncRoomCubit>();
    final selected = await InRoomAnimePickerSheet.show(
      context,
      roomCode: room?.code,
      currentTitle: currentTitle,
      onAnimeSelected: (newTitle) async {
        await cubit.changeRoomAnime(newTitle);
        if (ActiveRoomService.instance.hasActiveRoom) {
          await ActiveRoomService.instance.switchAnimeInActiveRoom(newTitle);
        }
      },
    );
    if (selected != null && context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📺 Тайтл комнаты изменён на «${selected.displayTitle}»'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SyncRoomCubit, SyncRoomState>(
      listener: (context, state) {
        if (state is SyncRoomHostWaiting) {
          if (ActiveRoomService.instance.hasActiveRoom) {
            ActiveRoomService.instance.registerActiveRoom(
              room: state.room,
              isHost: true,
              isInPlayer: false,
              initialParticipants: state.participants,
            );
          }
        } else if (state is SyncRoomJoined) {
          if (ActiveRoomService.instance.hasActiveRoom) {
            ActiveRoomService.instance.registerActiveRoom(
              room: state.room,
              isHost: state.isHost,
              isInPlayer: false,
              initialParticipants: state.participants,
            );
          }
        } else if (state is SyncRoomPlaybackStarting) {
          if (ActiveRoomService.instance.hasActiveRoom) {
            ActiveRoomService.instance.registerActiveRoom(
              room: state.room,
              isHost: state.isHost,
              isInPlayer: true,
            );
          }
          // Синхронный переход в плеер при старте воспроизведения хостом
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          widget.onStartPlayback(state.room, state.isHost);
        }
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.96),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: _themeAccent.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _themeAccent.withValues(alpha: 0.18),
                  blurRadius: 32,
                  spreadRadius: 2,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.spacingXl,
                  AppDimensions.spacingMd,
                  AppDimensions.spacingXl,
                  AppDimensions.spacingXl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle Bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppDimensions.spacingLg),

                    // Заголовок и кнопки управления (Свернуть / Закрыть)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.group_outlined,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: AppDimensions.spacingSm),
                              Flexible(
                                child: Text(
                                  'Совместный просмотр',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.titleLarge.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 17,
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
                              key: const ValueKey('sync_lobby_minimize_btn'),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Свернуть комнату в мини-окно',
                              icon: Icon(
                                Icons.picture_in_picture_alt_rounded,
                                color: AppColors.primaryLight,
                                size: 20,
                              ),
                              onPressed: () => _minimizeLobby(context),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: AppDimensions.spacingLg),

                    // Переключатель режимов: «Я хост» / «Присоединиться к другу»
                    _buildTabSelector(),

                    const SizedBox(height: AppDimensions.spacingLg),

                    // Содержимое выбранной вкладки
                    if (_currentTab == SyncLobbyTab.host)
                      _buildHostTab()
                    else
                      _buildJoinTab(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Переключатель вкладок
  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              title: 'Я хост (Создать)',
              icon: Icons.add_circle_outline_rounded,
              tab: SyncLobbyTab.host,
            ),
          ),
          Expanded(
            child: _buildTabButton(
              title: 'Присоединиться',
              icon: Icons.login_rounded,
              tab: SyncLobbyTab.join,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required SyncLobbyTab tab,
  }) {
    final isSelected = _currentTab == tab;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _currentTab = tab;
            if (tab == SyncLobbyTab.join) {
              context.read<SyncRoomCubit>().clearError();
              _pinFocusNode.requestFocus();
            } else {
              _pinFocusNode.unfocus();
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? _themeAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _themeAccent.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // РЕЖИМ 1: «Я ХОСТ»
  Widget _buildHostTab() {
    return BlocBuilder<SyncRoomCubit, SyncRoomState>(
      builder: (context, state) {
        if (state is SyncRoomCreating) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        if (state is SyncRoomError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.syncError.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.syncError.withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: AppColors.syncError,
                    size: 32,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Не удалось создать комнату в облаке',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      context.read<SyncRoomCubit>().createRoom(
                            title: widget.title,
                            episode: widget.episode,
                            quality: widget.initialQuality,
                          );
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Повторить'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _themeAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final room = state is SyncRoomHostWaiting ? state.room : null;
        final currentTitle = room?.title ?? widget.title;
        final currentEpisode = room?.episode ?? widget.episode;
        final roomCode = SyncRoomRepositoryImpl.extractPinCode(room?.code ?? '482100');
        final isCodeCopied = state is SyncRoomHostWaiting && state.codeCopied;
        final isLinkCopied = state is SyncRoomHostWaiting && state.linkCopied;

        final previewUrl = currentEpisode.previewUrl ??
            (currentTitle.posterMedium.isNotEmpty
                ? currentTitle.posterMedium
                : currentTitle.posterSmall);

        return Column(
          children: [
            // Карточка выбранного тайтла и серии + кнопка «Сменить аниме»
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 90,
                      height: 52,
                      child: Hero(
                        tag: 'anime-poster-${currentTitle.id}',
                        child: previewUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: previewUrl,
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const ShimmerPlaceholder.card(),
                                errorWidget: (context, url, error) =>
                                    Container(color: AppColors.surfaceElevated),
                              )
                            : Container(color: AppColors.surfaceElevated),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentTitle.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleSmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            Text(
                              'Серия ${currentEpisode.episode}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const Text('•', style: TextStyle(color: AppColors.textMuted)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.initialQuality.label,
                                style: AppTypography.badge.copyWith(
                                  fontSize: 10,
                                  color: AppColors.primaryLight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('sync_lobby_change_anime_btn'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Сменить аниме в комнате',
                    onPressed: () => _openInRoomAnimePicker(context, room, currentTitle),
                    icon: Icon(
                      Icons.swap_horiz_rounded,
                      size: 20,
                      color: AppColors.primaryLight,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppDimensions.spacingLg),

            // Блок с кодом комнаты
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'КОД КОМНАТЫ',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    roomCode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppDimensions.spacingMd),

            // Кнопки «Скопировать код» и «Поделиться ссылкой»
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.read<SyncRoomCubit>().copyCode(),
                    icon: Icon(
                      isCodeCopied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 16,
                      color: isCodeCopied ? AppColors.syncActive : AppColors.textPrimary,
                    ),
                    label: Text(
                      isCodeCopied ? 'Скопировано!' : 'Скопировать код',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isCodeCopied ? AppColors.syncActive : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: isCodeCopied
                            ? AppColors.syncActive
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingSm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.read<SyncRoomCubit>().copyShareLink(),
                    icon: Icon(
                      isLinkCopied ? Icons.check_rounded : Icons.share_rounded,
                      size: 16,
                      color: isLinkCopied ? AppColors.syncActive : AppColors.textPrimary,
                    ),
                    label: Text(
                      isLinkCopied ? 'Ссылка скопирована!' : 'Поделиться',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isLinkCopied ? AppColors.syncActive : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: isLinkCopied
                            ? AppColors.syncActive
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppDimensions.spacingMd),

            // QR-код для подключения в один клик с камеры другого устройства
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _themeAccent.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: 'syncpai://room/$roomCode',
                    version: QrVersions.auto,
                    size: 120,
                    gapless: true,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Наведите камеру смартфона для подключения',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppDimensions.spacingXl),

            const SizedBox(height: AppDimensions.spacingMd),

            // Статус связи и общения в комнате
            _buildRoomCommunicationBanner(),

            // Список участников комнаты («Кто есть, кого нет»)
            _buildParticipantsList(
              hostName: room?.hostName ?? 'Хост (Вы)',
              guestName: room?.peerName,
              hasGuest: state is SyncRoomHostWaiting && state.hasGuest,
            ),

            const SizedBox(height: AppDimensions.spacingMd),

            // Интерактивная плашка Anime Match для совместного выбора в комнате
            if (room != null)
              _buildInRoomAnimeMatchBanner(room, isHost: true),

            const SizedBox(height: AppDimensions.spacingSm),

            // Кнопка старта для хоста
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: (state is SyncRoomHostWaiting && state.hasGuest)
                    ? const Color(0xFF00E676)
                    : Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: (state is SyncRoomHostWaiting && state.hasGuest) ? 6 : 0,
              ),
              icon: Icon(
                (state is SyncRoomHostWaiting && state.hasGuest)
                    ? Icons.play_arrow_rounded
                    : Icons.play_circle_outline_rounded,
                size: 24,
              ),
              label: Text(
                (state is SyncRoomHostWaiting && state.hasGuest)
                    ? 'Запустить просмотр вместе (2/2) ▶'
                    : 'Начать сейчас (Хост) ▶',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onPressed: room == null
                  ? null
                  : () => context.read<SyncRoomCubit>().startPlaybackForAll(),
            ),

            const SizedBox(height: AppDimensions.spacingSm),

            // Демо-кнопка для быстрого тестирования в одном окне
            TextButton.icon(
              onPressed: () => context.read<SyncRoomCubit>().simulatePeerJoin(),
              icon: const Icon(Icons.bolt_rounded, color: AppColors.syncWaiting, size: 16),
              label: Text(
                'Симулировать подключение друга (Тест)',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.syncWaiting,
                  fontSize: 12,
                ),
              ),
            ),

            const SizedBox(height: 4),

            // Кнопка явного закрытия комнаты для всех участников
            TextButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dlgCtx) => AlertDialog(
                    backgroundColor: const Color(0xFF181D27),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    title: const Text('Закрыть комнату?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    content: const Text(
                      'Комната будет полностью закрыта и удалена для всех участников.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dlgCtx, false),
                        child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2A68)),
                        onPressed: () => Navigator.pop(dlgCtx, true),
                        child: const Text('Закрыть для всех', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await context.read<SyncRoomCubit>().closeRoomForAll();
                  if (context.mounted) Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFFF4D4D), size: 16),
              label: const Text(
                'Закрыть комнату для всех',
                style: TextStyle(
                  color: Color(0xFFFF4D4D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // РЕЖИМ 2: «ПРИСОЕДИНИТЬСЯ К ДРУГУ»
  Widget _buildJoinTab() {
    return BlocBuilder<SyncRoomCubit, SyncRoomState>(
      builder: (context, state) {
        if (state is SyncRoomJoined) {
          final room = state.room;
          final previewUrl = room.episode.previewUrl ??
              (room.title.posterMedium.isNotEmpty
                  ? room.title.posterMedium
                  : room.title.posterSmall);

          return Column(
            children: [
              // Карточка тайтла и серии комнаты
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 90,
                        height: 52,
                        child: previewUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: wrapCorsSafeUrl(previewUrl),
                                fit: BoxFit.cover,
                                placeholder: (context, url) =>
                                    const ShimmerPlaceholder.card(),
                                errorWidget: (context, url, error) =>
                                    Container(color: AppColors.surfaceElevated),
                              )
                            : Container(color: AppColors.surfaceElevated),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.title.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleSmall.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                'Серия ${room.episode.episode}',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const Text('  •  ', style: TextStyle(color: AppColors.textMuted)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  room.quality.label,
                                  style: AppTypography.badge.copyWith(
                                    fontSize: 10,
                                    color: AppColors.primaryLight,
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

              const SizedBox(height: AppDimensions.spacingMd),

              // Статус связи и общения в комнате
              _buildRoomCommunicationBanner(),

              // Список участников («Кто в комнате»)
              _buildParticipantsList(
                hostName: room.hostName,
                guestName: room.peerName ?? 'Вы (Гость)',
                hasGuest: true,
              ),

              const SizedBox(height: AppDimensions.spacingMd),

              // Интерактивная плашка Anime Match для гостя
              _buildInRoomAnimeMatchBanner(room, isHost: false),

              const SizedBox(height: AppDimensions.spacingSm),

              // Статус ожидания запуска от хоста
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ожидание запуска от хоста…',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Как только хост нажмет «Старт», плеер откроется синхронно у всех участников.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spacingLg),

              // Кнопка входа
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: const Text('Войти в плеер сейчас ▶', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  widget.onStartPlayback(room, false);
                },
              ),
            ],
          );
        }

        final isLoading = state is SyncRoomJoining;
        final errorMsg = state is SyncRoomError ? state.message : null;

        return Column(
          children: [
            Text(
              'Введите 6-значный код комнаты',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Например: SP-4821 или 749301',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: AppDimensions.spacingLg),

            // Поле ввода пин-кода со стильным нейтральным оформлением
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: _pinFocusNode.hasFocus ? 0.06 : 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (errorMsg != null && _pinController.text.isNotEmpty)
                      ? AppColors.syncError
                      : (_pinFocusNode.hasFocus
                          ? _themeAccent
                          : Colors.white.withValues(alpha: 0.15)),
                  width: 1.4,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _pinController,
                focusNode: _pinFocusNode,
                textAlign: TextAlign.center,
                autofocus: true,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                  color: AppColors.textPrimary,
                ),
                cursorColor: Theme.of(context).colorScheme.primary,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'SP-XXXX',
                  hintStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  filled: false,
                  isDense: true,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
                onChanged: _onPinChanged,
              ),
            ),

            // Сообщение об ошибке
            if (errorMsg != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.syncError, size: 15),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      errorMsg,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.syncError,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppDimensions.spacingMd),

            // Кнопка быстрой вставки из буфера обмена
            OutlinedButton.icon(
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste_rounded, size: 16, color: AppColors.textPrimary),
              label: const Text(
                'Вставить из буфера обмена',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Кнопка сканирования QR-кода камерой
            OutlinedButton.icon(
              onPressed: () {
                QrScannerSheet.show(
                  context,
                  onCodeScanned: (code) {
                    _pinController.text = code;
                    _onPinChanged(code);
                  },
                );
              },
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 16, color: AppColors.syncActive),
              label: const Text(
                'Сканировать QR-код камерой',
                style: TextStyle(
                  color: AppColors.syncActive,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                side: const BorderSide(color: AppColors.syncActive, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: AppDimensions.spacingXl),

            // Кнопка подтверждения подключения
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () => _onPinChanged(_pinController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.login_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Подключиться к комнате',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildParticipantsList({
    required String hostName,
    String? guestName,
    required bool hasGuest,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasGuest
              ? const Color(0xFF00E676).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.people_alt_rounded, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Участники комнаты',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: hasGuest
                      ? const Color(0xFF00E676).withValues(alpha: 0.18)
                      : AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: hasGuest
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00E676),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            '2/2 в сборе',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/mascot/watch_party/mascot_waiting_friends.png',
                            width: 18,
                            height: 18,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Ждем подключения друга...',
                            style: TextStyle(
                              color: AppColors.primaryLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Хост
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.amber.withValues(alpha: 0.2),
                  border: Border.all(color: Colors.amber, width: 1.2),
                ),
                child: const Center(
                  child: Icon(Icons.workspace_premium_rounded, size: 18, color: Colors.amber),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hostName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Text(
                      'Создатель комнаты',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E676).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00E676),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('Готов', style: TextStyle(color: Color(0xFF00E676), fontSize: 10.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(color: AppColors.strokeMedium, height: 1),
          const SizedBox(height: 10),
          // Гость
          InkWell(
            onTap: hasGuest
                ? () {
                    context.pushNamed('profile', queryParameters: {'userId': guestName ?? 'Друг'});
                  }
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasGuest ? const Color(0xFF00E676).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                        color: hasGuest ? const Color(0xFF00E676) : Colors.white24,
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        hasGuest ? Icons.person_rounded : Icons.schedule_rounded,
                        size: 18,
                        color: hasGuest ? const Color(0xFF00E676) : Colors.white54,
                      ),
                    ),
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
                                hasGuest ? (guestName ?? 'Друг') : 'Ожидание подключения друга…',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: hasGuest ? Colors.white : AppColors.textMuted,
                                  fontWeight: hasGuest ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (hasGuest) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Профиль ›',
                                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          hasGuest ? 'В комнате • Нажмите для профиля' : 'Отправьте код или ссылку для входа',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (hasGuest) ...[
                    IconButton(
                      icon: Icon(Icons.person_add_alt_1_rounded, size: 17, color: AppColors.primaryLight),
                      tooltip: 'Добавить в друзья',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final peerName = guestName ?? 'Друг';
                        final friendData = <String, dynamic>{
                          'name': peerName,
                          'username': peerName,
                        };
                        if (PaiChanAuthGate.isGuest(context)) {
                          await PaiChanAuthGate.show(
                            context,
                            accentColor: AppColors.primary,
                            pendingFriendUser: friendData,
                          );
                          return;
                        }
                        await FriendsService.addFriend(friendData);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Заявка отправлена пользователю $peerName! ✨'),
                            backgroundColor: AppColors.syncActive,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: hasGuest
                          ? const Color(0xFF00E676).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: hasGuest ? const Color(0xFF00E676) : Colors.white38,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          hasGuest ? 'Подключен' : 'Ожидание',
                          style: TextStyle(
                            color: hasGuest ? const Color(0xFF00E676) : Colors.white38,
                            fontSize: 10.5,
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
        ],
      ),
    );
  }

  Widget _buildRoomCommunicationBanner() {
    final audioService = RoomAudioDevicesService.instance;
    return ListenableBuilder(
      listenable: audioService,
      builder: (context, _) {
        final isMuted = audioService.isMicMuted;
        final micName = audioService.selectedInputDevice.label;
        final outName = audioService.selectedOutputDevice.label;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: (isMuted ? AppColors.syncError : const Color(0xFF00E676))
                  .withValues(alpha: 0.28),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => audioService.toggleMicMute(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (isMuted ? AppColors.syncError : const Color(0xFF00E676))
                            .withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        isMuted ? Icons.mic_off_rounded : Icons.record_voice_over_rounded,
                        color: isMuted ? AppColors.syncError : const Color(0xFF00E676),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Связь в комнате активна',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '🎙 $micName\n🎧 $outName',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => RoomAudioSettingsSection.showModal(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune_rounded, color: Colors.white, size: 13),
                          SizedBox(width: 4),
                          Text(
                            'Устройства',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => audioService.toggleMicMute(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isMuted ? AppColors.syncError : const Color(0xFF00E676))
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            color: isMuted ? AppColors.syncError : const Color(0xFF00E676),
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isMuted ? 'MUTE' : 'Голос ON',
                            style: TextStyle(
                              color: isMuted ? AppColors.syncError : const Color(0xFF00E676),
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInRoomAnimeMatchBanner(SyncRoom room, {required bool isHost}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF5E3A).withValues(alpha: 0.14),
            const Color(0xFFFF2A68).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF2A68).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5E3A), Color(0xFFFF2A68)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF2A68).withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.style_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    const Text(
                      'Anime Match',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2A68).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'В комнате',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFFFF5E3A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Свайпайте карточки тайтлов вдвоем — первое совпадение сразу включит серию!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2A68),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _startAnimeMatch(context, room, isHost: isHost),
            child: const Text(
              'Свайпать',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _startAnimeMatch(BuildContext context, SyncRoom room, {required bool isHost}) {
    List<AnimeTitle> deck = [];
    try {
      if (getIt.isRegistered<CatalogCubit>()) {
        final catalogState = getIt<CatalogCubit>().state;
        if (catalogState is CatalogLoaded && catalogState.titles.isNotEmpty) {
          deck = catalogState.titles;
        }
      }
    } catch (_) {}

    if (deck.isEmpty) {
      deck = [
        room.title,
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
      roomCode: room.code,
      userName: isHost ? room.hostName : (room.peerName ?? 'Гость'),
      syncRepository: getIt<SyncRoomRepository>(),
      onStartWatching: (matched) {
        if (getIt.isRegistered<SyncRoomCubit>()) {
          getIt<SyncRoomCubit>().startMatchedTitlePlayback(matched);
        }
        // Запускаем просмотр подобранного тайтла в плеере и закрываем лобби
        final updatedRoom = room.copyWith(title: matched);
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop(); // закрываем лобби
        }
        widget.onStartPlayback(updatedRoom, isHost);
      },
    );
  }
}
