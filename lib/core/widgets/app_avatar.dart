import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../network/image_cors_helper.dart';
import '../theme/app_colors.dart';

/// Элегантный кино-аватар пользователя в стиле Nordic Dark / Liquid Glass.
/// Поддерживает:
/// - Оригинальные фото высокого разрешения из галереи устройства (File)
/// - Удаленные аватары высокого разрешения (Network / CachedNetworkImage)
/// - Стильные векторные пресеты с мягкими градиентами и инициалы.
class AppAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? username;
  final double size;
  final Color? borderColor;
  final double borderWidth;

  const AppAvatar({
    super.key,
    this.avatarUrl,
    this.username,
    this.size = 40,
    this.borderColor,
    this.borderWidth = 1.0,
  });

  static const Map<String, IconData> _presetIconMap = {
    'cat': Icons.pets_rounded,
    '🐱': Icons.pets_rounded,
    'fox': Icons.cruelty_free_rounded,
    '🦊': Icons.cruelty_free_rounded,
    'panda': Icons.face_retouching_natural_rounded,
    '🐼': Icons.face_retouching_natural_rounded,
    'wolf': Icons.nightlight_round,
    '🐺': Icons.nightlight_round,
    'bolt': Icons.bolt_rounded,
    '⚡': Icons.bolt_rounded,
    'flower': Icons.local_florist_rounded,
    '🌸': Icons.local_florist_rounded,
    'shield': Icons.shield_rounded,
    '⚔️': Icons.shield_rounded,
    'fire': Icons.whatshot_rounded,
    '🔥': Icons.whatshot_rounded,
    'gamer': Icons.sports_esports_rounded,
    'star': Icons.auto_awesome_rounded,
    'bot': Icons.smart_toy_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? AppColors.strokeMedium;
    final cleanUrl = avatarUrl?.trim() ?? '';

    // 1. Проверяем, является ли ссылка сетевым URL
    final isNetwork = cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://');

    // 2. Проверяем, является ли путь локальным файлом из галереи
    final isLocalFile = !isNetwork &&
        cleanUrl.isNotEmpty &&
        (cleanUrl.startsWith('/') ||
            cleanUrl.contains(':\\') ||
            cleanUrl.startsWith('file:') ||
            cleanUrl.contains('cache') ||
            cleanUrl.contains('storage'));

    final themePrimary = Theme.of(context).colorScheme.primary;

    if (isNetwork) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: effectiveBorderColor, width: borderWidth),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: wrapCorsSafeUrl(cleanUrl),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            placeholder: (_, __) => _buildFallback(context, themePrimary),
            errorWidget: (_, __, ___) => _buildFallback(context, themePrimary),
          ),
        ),
      );
    }

    if (isLocalFile) {
      final filePath = cleanUrl.replaceFirst('file://', '');
      final file = File(filePath);
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: effectiveBorderColor, width: borderWidth),
        ),
        child: ClipOval(
          child: Image.file(
            file,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _buildFallback(context, themePrimary),
          ),
        ),
      );
    }

    return _buildFallback(context, themePrimary);
  }

  Widget _buildFallback(BuildContext context, Color themePrimary) {
    final effectiveBorderColor = borderColor ?? AppColors.strokeMedium;
    final icon = _presetIconMap[avatarUrl?.trim()];

    // Инициал пользователя для чистого минималистичного аватара
    final initial = (username != null && username!.trim().isNotEmpty)
        ? username!.trim()[0].toUpperCase()
        : null;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            themePrimary.withValues(alpha: 0.28),
            AppColors.surfaceElevated,
          ],
        ),
        border: Border.all(color: effectiveBorderColor, width: borderWidth),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(
              icon,
              size: size * 0.52,
              color: themePrimary,
            )
          : (initial != null
              ? Text(
                  initial,
                  style: TextStyle(
                    fontSize: size * 0.44,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                )
              : Icon(
                  Icons.person_rounded,
                  size: size * 0.52,
                  color: AppColors.textSecondary,
                )),
    );
  }
}
