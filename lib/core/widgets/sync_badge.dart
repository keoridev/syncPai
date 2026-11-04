import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../theme/app_typography.dart';

enum SyncStatus {
  active,
  buffering,
  disconnected,
}

/// Крошечный, деликатный статус-бейдж синхронизации в стиле Nordic Dark.
/// Зеленая/янтарная точка + лаконичная подпись, без назойливого мигания.
class SyncBadge extends StatelessWidget {
  final SyncStatus status;
  final String? peerName;

  const SyncBadge({
    super.key,
    required this.status,
    this.peerName,
  });

  @override
  Widget build(BuildContext context) {
    final (Color dotColor, String label) = switch (status) {
      SyncStatus.active => (
        AppColors.syncActive,
        peerName != null ? 'Синхрон ($peerName)' : 'В синхроне',
      ),
      SyncStatus.buffering => (
        AppColors.syncWaiting,
        peerName != null ? 'Ждем $peerName…' : 'Буферизация…',
      ),
      SyncStatus.disconnected => (
        AppColors.textMuted,
        'Офлайн',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spacingSm + 2,
        vertical: AppDimensions.spacingXs + 1,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated.withValues(alpha: 0.85),
        borderRadius: AppDimensions.borderRadiusSmall,
        border: Border.all(
          color: AppColors.strokeMedium,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6.0,
            height: 6.0,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppDimensions.spacingSm),
          Text(
            label,
            style: AppTypography.badge.copyWith(
              color: AppColors.textPrimary.withValues(alpha: 0.9),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

