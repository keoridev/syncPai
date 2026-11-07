import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/steam_avatar_frame.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../domain/entities/steam_profile_customization.dart';

/// Шапка профиля в стиле Steam Community:
/// 1. Широкоформатный арт/обои на 240 dp с плавным затуханием в цвет фона #121316
/// 2. Аватар в неоновой/киберпанк рамке SteamAvatarFrameWidget
/// 3. Никнейм, кастомный статус и титул с тенями
/// 4. Быстрый доступ к меню кастомизации (палитра)
class SteamStyleProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onCustomizerTap;
  final VoidCallback onEditProfileTap;
  final VoidCallback? onBackTap;
  final bool showBackButton;

  const SteamStyleProfileHeader({
    super.key,
    required this.profile,
    required this.onCustomizerTap,
    required this.onEditProfileTap,
    this.onBackTap,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgTheme = SteamBackgroundTheme.fromId(profile.backgroundId);
    final accent = SteamProfileThemeAccent.fromHex(profile.accentColor).color;

    return Stack(
      children: [
        // 1. Арт / Обои на фоне шапки профиля (высокое оригинальное разрешение)
        SizedBox(
          height: 240,
          width: double.infinity,
          child: _buildBgImage(bgTheme),
        ),

        // 2. Градиентная маска для бесшовного перехода в темноту Cinema Dark
        Container(
          height: 241,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                Colors.transparent,
                AppColors.background.withValues(alpha: 0.65),
                AppColors.background,
              ],
              stops: const [0.0, 0.25, 0.70, 1.0],
            ),
          ),
        ),

        // 3. Кнопка "Назад" (если требуется)
        if (showBackButton)
          Positioned(
            top: 14,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black.withValues(alpha: 0.5),
              radius: 18,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                onPressed: onBackTap ?? () => Navigator.of(context).maybePop(),
                padding: EdgeInsets.zero,
              ),
            ),
          ),

        // 4. Плашка "Мой профиль"
        Positioned(
          top: 16,
          left: showBackButton ? 58 : 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Text(
              'Мой профиль',
              style: AppTypography.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                fontSize: 11,
              ),
            ),
          ),
        ),

        // 5. Данные пользователя поверх фона
        Positioned(
          bottom: 12,
          left: 18,
          right: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Аватар в кастомной рамке Steam
              SteamAvatarFrameWidget(
                frameId: profile.frameId,
                size: 68,
                child: AppAvatar(
                  avatarUrl: profile.avatarUrl,
                  username: profile.username,
                  size: 68,
                  borderColor: accent,
                  borderWidth: 2.0,
                ),
              ),
              const SizedBox(width: 14),

              // Никнейм, статус, значок и титул
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 2)),
                              ],
                            ),
                          ),
                        ),
                        if (profile.badgeId != null) ...[
                          const SizedBox(width: 6),
                          Builder(
                            builder: (context) {
                              final badge = SteamBadge.fromId(profile.badgeId);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: badge.color.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: badge.color, width: 0.8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(badge.icon, size: 11, color: badge.color),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${badge.level}',
                                      style: TextStyle(
                                        color: badge.color,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.customStatus ?? 'Смотрю аниме...',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.9),
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                    if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '«${profile.bio!}»',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.white.withValues(alpha: 0.8),
                          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ],
                    if (profile.customTitle != null && profile.customTitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.6),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          profile.customTitle!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Кнопка быстрой кастомизации Steam (Палитра) + Редактирование
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.palette_outlined, color: accent, size: 20),
                      onPressed: onCustomizerTap,
                      tooltip: 'Кастомизировать профиль (Steam Style)',
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      padding: EdgeInsets.zero,
                    ),
                    Container(width: 1, height: 20, color: Colors.white.withValues(alpha: 0.15)),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
                      onPressed: onEditProfileTap,
                      tooltip: 'Изменить имя и аватарку',
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBgImage(SteamBackgroundTheme bgTheme) {
    final bgUrl = bgTheme.assetOrUrl?.trim();
    if (bgUrl == null || bgUrl.isEmpty) {
      return _buildFallbackBg(bgTheme);
    }

    final isNetwork = bgUrl.startsWith('http://') || bgUrl.startsWith('https://');
    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: wrapCorsSafeUrl(bgUrl),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorWidget: (_, __, ___) => _buildFallbackBg(bgTheme),
      );
    }

    // Локальный файл из галереи/устройства
    final filePath = bgUrl.replaceFirst('file://', '');
    final file = File(filePath);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildFallbackBg(bgTheme),
      );
    }

    return _buildFallbackBg(bgTheme);
  }

  Widget _buildFallbackBg(SteamBackgroundTheme bgTheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: bgTheme.gradient.length >= 2
              ? bgTheme.gradient
              : const [Color(0xFF2A2B32), Color(0xFF16181F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          bgTheme.icon,
          size: 44,
          color: Colors.white.withValues(alpha: 0.15),
        ),
      ),
    );
  }
}
