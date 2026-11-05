import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_dimensions.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/shimmer_placeholder.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/player/domain/entities/player_quality.dart';
import '../../domain/entities/sync_room.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../cubit/sync_room_cubit.dart';
import '../cubit/sync_room_state.dart';
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
        if (state is SyncRoomJoined) {
          // Синхронный переход в плеер при подключении участника (PEER_JOINED)
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
                              child: const Icon(
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
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
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

            // Пульсирующий статус ожидания подключения друга
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Внешнее пульсирующее кольцо
                    Container(
                      width: 58 * _pulseAnimation.value,
                      height: 58 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(
                          alpha: (0.35 / _pulseAnimation.value).clamp(0.0, 0.4),
                        ),
                      ),
                    ),
                    // Основной круговой индикатор
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceElevated,
                        border: Border.all(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.person_search_rounded,
                          color: AppColors.primaryLight,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: AppDimensions.spacingMd),

            Text(
              'Ждем подключения друга...',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Передайте код другу. Как только он подключится, плеер запустится синхронно у обоих.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),

            const SizedBox(height: AppDimensions.spacingLg),

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
                  backgroundColor: AppColors.primary,
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
}
