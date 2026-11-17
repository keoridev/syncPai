import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/domain/entities/user_profile.dart';
import '../../features/auth/presentation/widgets/auth_modal_sheet.dart';
import '../theme/app_colors.dart';

/// Плитка привязки Telegram-аккаунта в 1 тап через deep link `@syncpai_bot`.
class TelegramLinkTile extends StatelessWidget {
  final UserProfile? profile;
  final Color themePrimary;
  final bool asCard;
  final Future<void> Function(Uri uri)? onLaunchUri;

  const TelegramLinkTile({
    super.key,
    required this.profile,
    required this.themePrimary,
    this.asCard = false,
    this.onLaunchUri,
  });

  static Uri buildBotUri(UserProfile? profile) {
    if (profile != null &&
        !profile.isAnonymous &&
        profile.telegramId == null) {
      final rawCode = profile.friendCode?.trim();
      final token =
          (rawCode != null && rawCode.isNotEmpty) ? rawCode : profile.id;
      return Uri.parse(
        'https://t.me/syncpai_bot?start=link_${Uri.encodeComponent(token)}',
      );
    }
    return Uri.parse('https://t.me/syncpai_bot');
  }

  Future<void> _handleTap(BuildContext context) async {
    HapticFeedback.lightImpact();
    final current = profile;
    if (current == null || current.isAnonymous) {
      if (current != null) {
        AuthModalSheet.show(context, current);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Войдите в аккаунт, чтобы привязать Telegram'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final uri = buildBotUri(current);
    if (onLaunchUri != null) {
      await onLaunchUri!(uri);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isLinked = profile?.telegramId != null;
    final rawTgUsername = profile?.telegramUsername?.trim();
    final hasTgUsername =
        rawTgUsername != null && rawTgUsername.isNotEmpty;

    final title = isLinked
        ? (hasTgUsername
            ? 'Telegram привязан (@$rawTgUsername)'
            : 'Telegram привязан')
        : 'Привязать Telegram';
    final subtitle = isLinked
        ? 'Нажмите, чтобы открыть @syncpai_bot или сменить аккаунт'
        : 'Быстрая оплата подписки и уведомления через @syncpai_bot';

    const tgBlue = Color(0xFF2AABEE);

    final tile = ListTile(
      key: const ValueKey('telegram_link_tile'),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isLinked ? AppColors.syncActive : tgBlue)
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          isLinked ? Icons.check_circle_rounded : Icons.send_rounded,
          color: isLinked ? AppColors.syncActive : tgBlue,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
      trailing: Icon(
        Icons.open_in_new_rounded,
        color: isLinked ? AppColors.textSecondary : themePrimary,
        size: 18,
      ),
      onTap: () => _handleTap(context),
    );

    if (!asCard) return tile;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.028),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isLinked ? AppColors.syncActive : tgBlue)
              .withValues(alpha: 0.25),
        ),
      ),
      child: tile,
    );
  }
}

