import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../network/image_cors_helper.dart';
import '../theme/app_colors.dart';
import 'anime_silhouette_avatars.dart';
import 'holographic_monogram_avatar.dart';

/// Элегантный кино-аватар пользователя в стиле Nordic Dark / Liquid Glass:
/// 1. Поддержка оригинальных фото высокого разрешения из галереи (File)
/// 2. Удаленные аватары высокого разрешения (Network / CachedNetworkImage)
/// 3. Премиальные аниме-силуэты (Anime Silhouette / Dark Cyberpunk) с горящими неоновыми глазами
/// 4. Генеративные голографические монограммы из матового стекла (Glassmorphism).
class AppAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? username;
  final double size;
  final Color? borderColor;
  final double borderWidth;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  const AppAvatar({
    super.key,
    this.avatarUrl,
    this.username,
    this.size = 40,
    this.borderColor,
    this.borderWidth = 1.0,
    this.borderRadius,
    this.shape = BoxShape.circle,
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
    final themePrimary = Theme.of(context).colorScheme.primary;
    final effectiveShape = borderRadius != null ? BoxShape.rectangle : shape;

    Widget wrapClip(Widget child) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: child);
      }
      return ClipOval(child: child);
    }

    // 1. Проверяем, выбран ли аниме-силуэтный пресет
    final silhouette = AnimeSilhouettePreset.find(cleanUrl);
    if (silhouette != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: effectiveShape,
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: silhouette.backgroundGradient,
          ),
          border: Border.all(color: effectiveBorderColor, width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: silhouette.eyeColor.withValues(alpha: 0.35),
              blurRadius: 10,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              silhouette.silhouetteIcon,
              size: size * 0.58,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            // Неоновый акцент глаз/визора
            Positioned(
              top: size * 0.38,
              child: Container(
                width: size * 0.16,
                height: 2.2,
                decoration: BoxDecoration(
                  color: silhouette.eyeColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: silhouette.eyeColor,
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 2. Векторный пресет иконки (для совместимости)
    final presetIcon = _presetIconMap[cleanUrl];
    if (presetIcon != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: effectiveShape,
          borderRadius: borderRadius,
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
        child: Icon(
          presetIcon,
          size: size * 0.52,
          color: themePrimary,
        ),
      );
    }

    // 3. Проверяем Base64 data URL
    if (cleanUrl.startsWith('data:image/')) {
      try {
        final commaIdx = cleanUrl.indexOf(',');
        if (commaIdx != -1) {
          final bytes = base64Decode(cleanUrl.substring(commaIdx + 1));
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: effectiveShape,
              borderRadius: borderRadius,
              border: Border.all(color: effectiveBorderColor, width: borderWidth),
            ),
            child: wrapClip(
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => _buildHolographicMonogram(themePrimary),
              ),
            ),
          );
        }
      } catch (_) {}
    }

    // 4. Проверяем, является ли ссылка сетевым URL
    final isNetwork = cleanUrl.startsWith('http://') ||
        cleanUrl.startsWith('https://') ||
        cleanUrl.startsWith('//');
    if (isNetwork) {
      final networkUrl = cleanUrl.startsWith('//') ? 'https:$cleanUrl' : cleanUrl;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: effectiveShape,
          borderRadius: borderRadius,
          border: Border.all(color: effectiveBorderColor, width: borderWidth),
        ),
        child: wrapClip(
          CachedNetworkImage(
            imageUrl: wrapCorsSafeUrl(networkUrl),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            placeholder: (_, __) => _buildHolographicMonogram(themePrimary),
            errorWidget: (_, __, ___) => _buildHolographicMonogram(themePrimary),
          ),
        ),
      );
    }

    // 5. Проверяем, является ли путь локальным файлом из галереи или диска
    File? resolvedLocalFile;
    if (!isNetwork && cleanUrl.isNotEmpty) {
      var filePath = cleanUrl;
      if (filePath.startsWith('file:///')) {
        filePath = filePath.substring(8);
      } else if (filePath.startsWith('file://')) {
        filePath = filePath.substring(7);
      }
      if (Platform.isWindows && RegExp(r'^/[a-zA-Z]:').hasMatch(filePath)) {
        filePath = filePath.substring(1);
      }
      try {
        final candidate = File(filePath);
        if (candidate.existsSync() ||
            filePath.startsWith('/') ||
            filePath.contains(':\\') ||
            filePath.contains(':/') ||
            cleanUrl.contains('custom_avatar') ||
            cleanUrl.contains('cache') ||
            cleanUrl.contains('storage') ||
            cleanUrl.contains('Documents')) {
          resolvedLocalFile = candidate;
        }
      } catch (_) {}
    }

    if (resolvedLocalFile != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: effectiveShape,
          borderRadius: borderRadius,
          border: Border.all(color: effectiveBorderColor, width: borderWidth),
        ),
        child: wrapClip(
          Image.file(
            resolvedLocalFile,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, error, ___) {
              debugPrint('AppAvatar Image.file error: $error for path $cleanUrl');
              return _buildHolographicMonogram(themePrimary);
            },
          ),
        ),
      );
    }

    // 6. Если фото нет — генеративная голографическая монограмма из матового стекла
    return _buildHolographicMonogram(themePrimary);
  }

  Widget _buildHolographicMonogram(Color themePrimary) {
    return HolographicMonogramAvatar(
      text: (username != null && username!.trim().isNotEmpty) ? username! : 'S',
      size: size,
      accentColor: borderColor ?? themePrimary,
    );
  }
}
