import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';

/// Reusable dark-glass empty state widget featuring Pai-chan sticker
/// for zero-wait offline feedback.
class PaiChanOfflineView extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSaved;
  final bool showSavedButton;
  final String stickerAsset;
  final double stickerSize;

  const PaiChanOfflineView({
    super.key,
    this.title = 'Нет подключения к интернету',
    this.subtitle = 'Пай-тян не может достучаться до сервера. Проверь Wi-Fi или мобильную сеть.',
    this.onRetry,
    this.onOpenSaved,
    this.showSavedButton = true,
    this.stickerAsset = 'assets/stickers/pai_sleepy.png',
    this.stickerSize = 96.0,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.08),
                    Colors.white.withValues(alpha: 0.03),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pai-chan sticker with ambient glow
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: stickerSize + 24,
                        height: stickerSize + 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentTurquoise.withValues(alpha: 0.25),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: AppColors.accentSecondary.withValues(alpha: 0.2),
                              blurRadius: 36,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      Image.asset(
                        stickerAsset,
                        width: stickerSize,
                        height: stickerSize,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: stickerSize,
                            height: stickerSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceElevated,
                            ),
                            child: const Icon(
                              Icons.wifi_off_rounded,
                              size: 48,
                              color: AppColors.accentTurquoise,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.85),
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (onRetry != null)
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accentTurquoise.withValues(alpha: 0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            label: const Text(
                              'Повторить',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentTurquoise,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                      if (showSavedButton) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (onOpenSaved != null) {
                              onOpenSaved!();
                            } else {
                              context.push('/lists');
                            }
                          },
                          icon: const Icon(
                            Icons.bookmark_outline_rounded,
                            size: 18,
                            color: AppColors.textPrimary,
                          ),
                          label: const Text(
                            'Открыть сохранённое',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            backgroundColor: Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
