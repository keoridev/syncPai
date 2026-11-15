import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/mascot/mascot_state.dart';
import '../../../../core/widgets/mascot/sync_pai_mascot.dart';
import '../../services/active_room_service.dart';
import 'in_room_anime_picker_sheet.dart';

/// Плавающий мини-док свернутой комнаты совместного просмотра (PiP / Lobby Dock)
/// + мгновенный баннер с маскотом Пай-чан при подключении друга к комнате.
class FloatingRoomOverlay extends StatefulWidget {
  final double mobileBottomInset;
  final ActiveRoomService? service;

  const FloatingRoomOverlay({
    super.key,
    this.mobileBottomInset = 86.0,
    this.service,
  });

  @override
  State<FloatingRoomOverlay> createState() => _FloatingRoomOverlayState();
}

class _FloatingRoomOverlayState extends State<FloatingRoomOverlay> {
  Offset _desktopDragOffset = Offset.zero;
  bool _linkCopied = false;

  ActiveRoomService get _service => widget.service ?? ActiveRoomService.instance;

  Future<void> _copyInviteLink(BuildContext context, String shareUrl, String roomCode) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await Clipboard.setData(ClipboardData(text: shareUrl));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _linkCopied = true);
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Ссылка приглашения в комнату $roomCode скопирована!'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _linkCopied = false);
      }
    });
  }

  Future<void> _openAnimeSwitcher(BuildContext context) async {
    final room = _service.activeRoom;
    if (room == null) return;
    final selected = await InRoomAnimePickerSheet.show(
      context,
      roomCode: _service.formattedRoomCode,
      currentTitle: room.title,
      onAnimeSelected: (newTitle) async {
        await _service.switchAnimeInActiveRoom(newTitle);
      },
    );
    if (selected != null && context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📺 Аниме в комнате изменено на «${selected.displayTitle}»'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final room = _service.activeRoom;
        if (!_service.isMinimized || room == null) {
          return const SizedBox.shrink();
        }

        final isDesktop = (!kIsWeb &&
                (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
            MediaQuery.sizeOf(context).width >= 900;
        final bannerText = _service.friendJoinedBannerText;
        final roomCode = _service.formattedRoomCode;
        final count = _service.participantCount;
        final maxPeers = _service.maxPeers;
        final isConnected = count > 1 || _service.pulseParticipantBadge;
        final posterUrl = room.title.posterUrl;

        return Stack(
          children: [
            // 1. Всплывающий баннер с Пай-чан при подключении друга в свернутую комнату
            if (bannerText != null)
              Positioned(
                top: isDesktop ? 20 : MediaQuery.paddingOf(context).top + 12,
                left: isDesktop ? null : 16,
                right: isDesktop ? 24 : 16,
                width: isDesktop ? 420 : null,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('floating_room_friend_joined_banner'),
                    onTap: () => _service.expandRoom(),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A2421), Color(0xFF141822)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.syncActive.withValues(alpha: 0.65),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.syncActive.withValues(alpha: 0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 48,
                            height: 48,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: SyncPaiMascot(
                                state: MascotState.happy,
                                size: MascotSize.small,
                                animated: false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.syncActive,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Flexible(
                                      child: Text(
                                        'Пай-чан • Друг подключился!',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.syncActive,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  bannerText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white60,
                              size: 18,
                            ),
                            onPressed: () => _service.dismissFriendJoinedBanner(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 2. Плавающий док комнаты (снизу на Mobile, в правом нижнем углу на Windows Desktop)
            Positioned(
              left: isDesktop ? null : 12,
              right: isDesktop ? (24 - _desktopDragOffset.dx).clamp(8.0, 800.0) : 12,
              bottom: isDesktop
                  ? (24 - _desktopDragOffset.dy).clamp(8.0, 600.0)
                  : widget.mobileBottomInset,
              width: isDesktop ? 440 : null,
              child: GestureDetector(
                onPanUpdate: isDesktop
                    ? (details) {
                        setState(() {
                          _desktopDragOffset += details.delta;
                        });
                      }
                    : null,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    key: const ValueKey('floating_room_dock_card'),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141720).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isConnected
                            ? AppColors.syncActive.withValues(alpha: 0.55)
                            : AppColors.primary.withValues(alpha: 0.45),
                        width: 1.3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.65),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Верхний ряд: Постер + Код комнаты + Бейдж участников + Названия + Кнопка Выйти
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => _service.expandRoom(),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: posterUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: wrapCorsSafeUrl(posterUrl),
                                          fit: BoxFit.cover,
                                          errorWidget: (_, __, ___) => Container(
                                            color: AppColors.surfaceElevated,
                                            child: Icon(
                                              Icons.meeting_room_rounded,
                                              color: AppColors.primary,
                                              size: 20,
                                            ),
                                          ),
                                        )
                                      : Container(
                                          color: AppColors.surfaceElevated,
                                          child: Icon(
                                            Icons.meeting_room_rounded,
                                            color: AppColors.primary,
                                            size: 20,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _service.expandRoom(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        // Код комнаты SP-XXXXXX
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: AppColors.primary.withValues(alpha: 0.45),
                                            ),
                                          ),
                                          child: Text(
                                            roomCode,
                                            style: TextStyle(
                                              color: AppColors.primaryLight,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        // Счетчик участников 👥 2/5
                                        Container(
                                          key: const ValueKey('floating_room_participants_badge'),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isConnected
                                                ? AppColors.syncActive.withValues(alpha: 0.18)
                                                : Colors.white.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isConnected
                                                  ? AppColors.syncActive.withValues(alpha: 0.5)
                                                  : Colors.white.withValues(alpha: 0.14),
                                            ),
                                          ),
                                          child: Text(
                                            '👥 $count/$maxPeers',
                                            style: TextStyle(
                                              color: isConnected
                                                  ? AppColors.syncActive
                                                  : Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${room.title.displayTitle} • Серия ${room.episode.episode}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Кнопка закрытия / выхода из комнаты (✕)
                            IconButton(
                              key: const ValueKey('floating_room_leave_btn'),
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Выйти из комнаты',
                              onPressed: () => _service.leaveActiveRoom(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: AppColors.textSecondary,
                                size: 19,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Нижний ряд быстрых действий: Сменить аниме • Пригласить • Развернуть
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const ValueKey('floating_room_switch_anime_btn'),
                                onPressed: () => _openAnimeSwitcher(context),
                                icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                                label: const Text(
                                  'Сменить аниме',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              key: const ValueKey('floating_room_invite_btn'),
                              onPressed: () => _copyInviteLink(context, room.shareUrl, roomCode),
                              icon: Icon(
                                _linkCopied ? Icons.check_rounded : Icons.share_rounded,
                                size: 14,
                                color: _linkCopied ? AppColors.syncActive : Colors.white,
                              ),
                              label: Text(
                                _linkCopied ? 'Скопировано' : 'Пригласить',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _linkCopied ? AppColors.syncActive : Colors.white,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: _linkCopied
                                      ? AppColors.syncActive
                                      : Colors.white.withValues(alpha: 0.15),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton.icon(
                              key: const ValueKey('floating_room_expand_btn'),
                              onPressed: () => _service.expandRoom(),
                              icon: const Icon(Icons.open_in_full_rounded, size: 14),
                              label: const Text(
                                'Развернуть',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

