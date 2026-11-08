import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import '../../domain/entities/sync_room.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../cubit/sync_room_cubit.dart';
import '../cubit/sync_room_state.dart';
import '../screens/coop_match_screen.dart';
import 'qr_scanner_sheet.dart';

enum SyncLobbyTab { host, join }

/// Интерактивная шторка лобби совместного просмотра (SyncRoomLobbySheet)
/// в стиле Frosted Glass / Nordic Dark.
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

class _SyncRoomLobbySheetState extends State<SyncRoomLobbySheet>
    with SingleTickerProviderStateMixin {
  SyncLobbyTab _currentTab = SyncLobbyTab.host;
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocusNode = FocusNode();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

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
    _pulseController.dispose();
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  void _onPinChanged(String value) {
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

  @override
  Widget build(BuildContext context) {
    return BlocListener<SyncRoomCubit, SyncRoomState>(
      listener: (context, state) {
        if (state is SyncRoomPlaybackStarting) {
          // Синхронный переход в плеер при старте воспроизведения хостом
          Navigator.of(context).pop();
          widget.onStartPlayback(state.room, state.isHost);
        }
      },
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.96),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1.0,
              ),
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

                    // Заголовок и кнопка закрытия
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
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
                            Text(
                              'Совместный просмотр',
                              style: AppTypography.titleLarge.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                          ],
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
              _pinFocusNode.requestFocus();
            } else {
              _pinFocusNode.unfocus();
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
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

        final room = state is SyncRoomHostWaiting ? state.room : null;
        final roomCode = room?.code ?? 'SP-4821';
        final isCodeCopied = state is SyncRoomHostWaiting && state.codeCopied;
        final isLinkCopied = state is SyncRoomHostWaiting && state.linkCopied;

        final previewUrl = widget.episode.previewUrl ??
            (widget.title.posterMedium.isNotEmpty
                ? widget.title.posterMedium
                : widget.title.posterSmall);

        return Column(
          children: [
            // Карточка выбранного тайтла и серии (с фиксацией качества 720p HD)
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
                  const SizedBox(width: AppDimensions.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title.displayTitle,
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
                              'Серия ${widget.episode.episode}',
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
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: 'https://syncpai.app/room/${roomCode.replaceAll(RegExp(r'[^A-Z0-9]'), '')}',
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
                  Navigator.of(context).pop();
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

            // Поле ввода пин-кода со стильным оформлением
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: errorMsg != null
                      ? AppColors.syncError
                      : AppColors.primary.withValues(alpha: 0.5),
                  width: 1.2,
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
                cursorColor: AppColors.primary,
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
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
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
              Row(
                children: [
                  const Icon(Icons.people_alt_rounded, size: 16, color: Colors.white70),
                  const SizedBox(width: 6),
                  Text(
                    'Участники комнаты',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
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
                    : ScaleTransition(
                        scale: _pulseAnimation,
                        child: Text(
                          'Ждем подключения друга...',
                          style: TextStyle(
                            color: AppColors.primaryLight,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
          Row(
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
                    Text(
                      hasGuest ? (guestName ?? 'Друг') : 'Ожидание подключения друга…',
                      style: TextStyle(
                        color: hasGuest ? Colors.white : AppColors.textMuted,
                        fontWeight: hasGuest ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      hasGuest ? 'В комнате' : 'Отправьте код или ссылку для входа',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
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
                        color: hasGuest ? const Color(0xFF00E676) : Colors.white54,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
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
                        'Вдвоем',
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
                  'Свайпайте тайтлы — совпадение сразу включит серию!',
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
      },
    );
  }
}
