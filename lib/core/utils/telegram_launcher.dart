import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Безопасный запуск Telegram deep-link для баг-репортов и бота @syncpai_bot.
class TelegramLauncher {
  static Future<void> openBugReport(
    BuildContext context, {
    String? friendCode,
  }) async {
    final trimmed = friendCode?.trim();
    final token = (trimmed != null && trimmed.isNotEmpty) ? trimmed : 'guest';
    final encoded = Uri.encodeComponent(token);

    final tgUri = Uri.parse('tg://resolve?domain=syncpai_bot&start=bug_$encoded');
    final webUri = Uri.parse('https://t.me/syncpai_bot?start=bug_$encoded');

    bool launched = false;
    try {
      if (await canLaunchUrl(tgUri)) {
        launched = await launchUrl(tgUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    if (!launched) {
      try {
        launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    if (!launched) {
      await Clipboard.setData(const ClipboardData(text: '@syncpai_bot'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ссылка скопирована — откройте @syncpai_bot в Telegram и нажмите «🐞 Нашёл баг»',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static Future<void> openBotStart(
    BuildContext context,
    String startParam, {
    String? fallbackMessage,
  }) async {
    final encoded = Uri.encodeComponent(startParam);
    final tgUri = Uri.parse('tg://resolve?domain=syncpai_bot&start=$encoded');
    final webUri = Uri.parse('https://t.me/syncpai_bot?start=$encoded');

    bool launched = false;
    try {
      if (await canLaunchUrl(tgUri)) {
        launched = await launchUrl(tgUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    if (!launched) {
      try {
        launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    if (!launched) {
      await Clipboard.setData(const ClipboardData(text: '@syncpai_bot'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fallbackMessage ?? 'Бот @syncpai_bot скопирован — откройте его в Telegram',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

