import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/domain/entities/user_profile.dart';
import '../../features/support/domain/entities/supporter_tier.dart';
import '../theme/app_colors.dart';

/// Превью-шторка для косметики Plus / Pro с переходом в `@syncpai_bot` в 1 тап.
class SupporterGateSheet {
  static Future<void> show(
    BuildContext context, {
    required UserProfile? profile,
    required SupporterTier requiredTier,
    required String featureTitle,
    required String featureDescription,
  }) async {
    final accent = requiredTier.accentColor;
    final tierLabel = requiredTier == SupporterTier.vip ? 'Pro' : 'Plus';

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
                color: const Color(0xFF12161F),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.auto_awesome_rounded, color: accent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              featureTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Доступно с SyncPai $tierLabel',
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    featureDescription,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    key: const ValueKey('supporter_gate_open_bot_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      final rawCode = profile?.friendCode?.trim();
                      final token = (rawCode != null && rawCode.isNotEmpty)
                          ? rawCode
                          : (profile?.id ?? '');
                      final uri = token.isNotEmpty
                          ? Uri.parse(
                              'https://t.me/syncpai_bot?start=link_${Uri.encodeComponent(token)}',
                            )
                          : Uri.parse('https://t.me/syncpai_bot');
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.send_rounded, size: 17),
                    label: const Text(
                      'Открыть в @syncpai_bot',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

