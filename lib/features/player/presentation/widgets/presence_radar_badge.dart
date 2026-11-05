import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../sync_room/domain/entities/sync_protocol.dart';

/// Онлайн-радар присутствия участников в комнате (Presence).
/// Отображает аватарку котика, статус («В сети» / «Отошел») и пульсирующий индикатор.
class PresenceRadarBadge extends StatefulWidget {
  final PeerPresence? presence;
  final String fallbackName;

  const PresenceRadarBadge({
    super.key,
    this.presence,
    this.fallbackName = 'Друг',
  });

  @override
  State<PresenceRadarBadge> createState() => _PresenceRadarBadgeState();
}

class _PresenceRadarBadgeState extends State<PresenceRadarBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presence = widget.presence;
    final status = presence?.status ?? PresenceStatus.online;
    final avatar = presence?.avatar ?? '🐱';
    final name = presence?.name ?? widget.fallbackName;

    Color statusColor;
    String statusText;

    switch (status) {
      case PresenceStatus.online:
        statusColor = AppColors.syncActive;
        statusText = '$name в сети';
        break;
      case PresenceStatus.away:
        statusColor = AppColors.syncWaiting;
        statusText = '$name отошел';
        break;
      case PresenceStatus.offline:
        statusColor = AppColors.textMuted;
        statusText = '$name не в сети';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.15),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Аватарка (котик / эмодзи)
          Text(
            avatar,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 6),

          // Пульсирующая точка радара
          ScaleTransition(
            scale: status == PresenceStatus.online ? _pulseScale : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.7),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Текст статуса
          Text(
            statusText,
            style: AppTypography.caption.copyWith(
              color: status == PresenceStatus.away ? AppColors.syncWaiting : AppColors.textPrimary,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

