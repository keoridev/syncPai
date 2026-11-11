import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../domain/entities/steam_profile_customization.dart';
import 'badge_details_sheet.dart';

/// Кастомный Steam Artwork Profile Header в стиле премиальных профилей Steam Community:
/// 1. Внешний стеклянный контейнер Steam Profile Backing с тонким контуром `Border.all(color: Colors.white10)`.
/// 2. Header:
///    - Слева: крупный КВАДРАТНЫЙ аватар (размер 84×84) с тяжелой рамкой (Steam Avatar Frame с уголками и декором).
///    - Справа: Никнейм (20sp, bold, белый, со статусом), флаг страны (🇰🇬 Kyrgyzstan 12sp),
///      кастомная плашка статуса со стилизованными разделителями `— ❖ — WELCOME — ❖ —`.
/// 3. Artwork Showcase (Главная витрина иллюстраций — Artwork):
///    - Располагается СРАЗУ под блоком аватара.
///    - Высокий вертикальный арт (~390dp) на всю ширину с паддингами 16dp.
///    - Стилизован под разрезанную витрину Steam (основная часть 74% + узкая боковая полоска 26%).
///    - На арт накладываются кандзи (侍 / 忍者) и никнейм в киберпанк стиле.
///    - Живой 3D-параллакс с гироскопа (`sensors_plus`) при покачивании телефона.
/// 4. Полная интеграция с базой Supabase через [AuthCubit.updateProfile].
class SteamStyleProfileHeader extends StatefulWidget {
  final UserProfile profile;
  final VoidCallback onCustomizerTap;
  final VoidCallback onEditProfileTap;
  final VoidCallback? onBackTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onArtworkTap;
  final bool showBackButton;
  final bool isCurrentUser;
  final String? countryFlag;
  final String? countryName;

  const SteamStyleProfileHeader({
    super.key,
    required this.profile,
    required this.onCustomizerTap,
    required this.onEditProfileTap,
    this.onBackTap,
    this.onSettingsTap,
    this.onArtworkTap,
    this.showBackButton = false,
    this.isCurrentUser = true,
    this.countryFlag,
    this.countryName,
  });

  @override
  State<SteamStyleProfileHeader> createState() => _SteamStyleProfileHeaderState();
}

class _SteamStyleProfileHeaderState extends State<SteamStyleProfileHeader>
    with SingleTickerProviderStateMixin {
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  AnimationController? _idleController;
  int _likesCount = 1337;
  bool _isLiked = false;

  // Курированные пресеты артворков в стиле Steam Artwork Showcase
  static const List<_ArtworkPreset> curatedPresets = [
    _ArtworkPreset(
      title: 'CYBERPUNK // 侍 SAMURAI',
      kanji: '侍',
      tagline: 'NEO KYOTO 2077 // EDITION',
      imageUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=1200&auto=format&fit=crop&q=80',
    ),
    _ArtworkPreset(
      title: 'EDGERUNNERS // LUCY & DAVID',
      kanji: '電脳',
      tagline: 'NIGHT CITY LEGENDS',
      imageUrl: 'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=1200&auto=format&fit=crop&q=80',
    ),
    _ArtworkPreset(
      title: 'SHADOW MONARCH // 影の君主',
      kanji: '影',
      tagline: 'ARISE // SOLO LEVELING',
      imageUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=1200&auto=format&fit=crop&q=80',
    ),
    _ArtworkPreset(
      title: 'NEON SHINOBI // 忍者',
      kanji: '忍者',
      tagline: 'STEALTH CLAN // ZERO',
      imageUrl: 'https://images.unsplash.com/photo-1563089145-599997674d42?w=1200&auto=format&fit=crop&q=80',
    ),
    _ArtworkPreset(
      title: 'SAKURA BLADE // 桜刀',
      kanji: '桜',
      tagline: 'CHERRY BLOSSOM RONIN',
      imageUrl: 'https://images.unsplash.com/photo-1528164344705-475426879c0d?w=1200&auto=format&fit=crop&q=80',
    ),
  ];

  bool get _isTestEnv {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
      if (WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding')) return true;
    } catch (_) {}
    return false;
  }

  @override
  void initState() {
    super.initState();

    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    // В тестах не запускаем бесконечный repeat() и гироскоп, чтобы pumpAndSettle не зависал
    if (!_isTestEnv) {
      _idleController?.repeat(reverse: true);

      // 2. Подписка на датчик гироскопа для 3D Parallax эффекта
      try {
        _gyroSubscription = gyroscopeEventStream().listen((event) {
          if (!mounted) return;
          setState(() {
            // event.y = поворот влево-вправо (roll), event.x = наклон вперед-назад (pitch)
            // Применяем фильтр низких частот (low-pass filter) для плавности
            _tiltX = (_tiltX * 0.82 + event.y * 0.18).clamp(-1.0, 1.0);
            _tiltY = (_tiltY * 0.82 + event.x * 0.18).clamp(-1.0, 1.0);
          });
        }, onError: (_) {});
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _gyroSubscription?.cancel();
    _idleController?.dispose();
    super.dispose();
  }

  Color _resolveAccentColor(BuildContext context) {
    final hex = widget.profile.accentColor;
    if (hex != null && hex.isNotEmpty && hex != '#E06C53') {
      return SteamProfileThemeAccent.fromHex(hex).color;
    }
    return Theme.of(context).colorScheme.primary;
  }

  String _resolveArtworkUrl() {
    // 1. Постер любимого тайтла (если выбран пользователем)
    final favPoster = widget.profile.favoriteAnimePoster;
    if (favPoster != null && favPoster.trim().isNotEmpty && favPoster.startsWith('http')) {
      return favPoster.trim();
    }
    // 2. Кастомный URL из био
    final bio = widget.profile.bio;
    if (bio != null && bio.trim().startsWith('http')) {
      return bio.trim();
    }
    // 3. Дефолтный премиальный киберпанк-самурай арт
    return curatedPresets.first.imageUrl;
  }

  String _resolveArtworkTitle() {
    if (widget.profile.favoriteAnimeTitle != null &&
        widget.profile.favoriteAnimeTitle!.isNotEmpty) {
      return widget.profile.favoriteAnimeTitle!.toUpperCase();
    }
    return curatedPresets.first.title;
  }

  void _handleShowcaseTap() {
    HapticFeedback.lightImpact();
    if (widget.onArtworkTap != null) {
      widget.onArtworkTap!();
      return;
    }

    final favId = widget.profile.favoriteAnimeId;
    if (favId != null && favId.isNotEmpty) {
      _showArtworkActionDialog(context);
    } else if (widget.isCurrentUser) {
      _openArtworkSelectorSheet(context);
    }
  }

  void _showArtworkActionDialog(BuildContext context) {
    final favId = widget.profile.favoriteAnimeId!;
    final accent = _resolveAccentColor(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF14161F),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _resolveArtworkTitle(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.play_circle_fill_rounded, color: accent, size: 28),
              title: const Text('Открыть страницу аниме', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.white.withValues(alpha: 0.05),
              onTap: () {
                Navigator.of(ctx).pop();
                context.pushNamed('anime-details', pathParameters: {'id': favId});
              },
            ),
            if (widget.isCurrentUser) ...[
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.palette_rounded, color: Colors.white70, size: 26),
                title: const Text('Сменить иллюстрацию витрины', style: TextStyle(color: Colors.white70)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: Colors.white.withValues(alpha: 0.05),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openArtworkSelectorSheet(context);
                },
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _openArtworkSelectorSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ArtworkSelectorSheet(
        profile: widget.profile,
        accentColor: _resolveAccentColor(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _resolveAccentColor(context);
    final artworkUrl = _resolveArtworkUrl();
    final artworkTitle = _resolveArtworkTitle();

    // 3D Parallax расчеты
    final idleVal = _idleController?.value ?? 0.0;
    final hasActiveTilt = _tiltX.abs() > 0.03 || _tiltY.abs() > 0.03;
    final effectiveTiltX = hasActiveTilt ? _tiltX : (math.sin(idleVal * 2 * math.pi) * 0.06);
    final effectiveTiltY = hasActiveTilt ? _tiltY : (math.cos(idleVal * 2 * math.pi) * 0.04);

    final bgShiftX = -effectiveTiltX * 10.0;
    final bgShiftY = -effectiveTiltY * 6.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101218).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 20,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ============================================================
              // ВЕРХНЯЯ СТРОКА: ТЕГИ, УПРАВЛЕНИЕ, НАСТРОЙКИ
              // ============================================================
              _buildTopBar(context, accent),

              const SizedBox(height: 16),

              // ============================================================
              // 1. STEAM HEADER: КВАДРАТНЫЙ АВАТАР 84×84 + ПРАВЫЙ БЛОК ИНФЫ
              // ============================================================
              _buildProfileHeaderRow(context, accent),

              const SizedBox(height: 18),

              // ============================================================
              // 2. ARTWORK SHOWCASE (ГЛАВНАЯ ВИТРИНА ИЛЛЮСТРАЦИЙ С 3D PARALLAX)
              // ============================================================
              _buildArtworkShowcase(
                context,
                accent: accent,
                artworkUrl: artworkUrl,
                artworkTitle: artworkTitle,
                bgShiftX: bgShiftX,
                bgShiftY: bgShiftY,
                tiltX: effectiveTiltX,
                tiltY: effectiveTiltY,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, Color accent) {
    return Row(
      children: [
        if (widget.showBackButton) ...[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
            onPressed: widget.onBackTap ?? () => Navigator.of(context).maybePop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 8),
        ],

        // Плашка "Мой профиль" / "Профиль друга"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF57CBDE), // Steam Cyan
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.isCurrentUser ? 'Мой профиль' : 'Профиль друга',
                style: AppTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // Уровень Steam / Значок профиля
        if (widget.profile.badgeId != null) ...[
          Builder(
            builder: (context) {
              final badge = SteamBadge.fromId(widget.profile.badgeId);
              return GestureDetector(
                onTap: () => BadgeDetailsSheet.show(context, badge: badge),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badge.color.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: badge.color.withValues(alpha: 0.7), width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badge.icon, size: 12, color: badge.color),
                      const SizedBox(width: 4),
                      Text(
                        'Ур. ${badge.level}',
                        style: TextStyle(
                          color: badge.color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],

        // Кнопка кастомизации Steam (Палитра)
        if (widget.isCurrentUser) ...[
          IconButton(
            icon: Icon(Icons.palette_outlined, color: accent, size: 21),
            tooltip: 'Магазин очков Steam (Кастомизация)',
            onPressed: widget.onCustomizerTap,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
            tooltip: 'Настройки',
            onPressed: widget.onSettingsTap ?? () => context.push('/settings'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ],
    );
  }

  Widget _buildProfileHeaderRow(BuildContext context, Color accent) {
    final flag = widget.countryFlag ?? '🇰🇬';
    final country = widget.countryName ?? 'Kyrgyzstan';
    final statusText = widget.profile.customStatus?.trim().isNotEmpty == true
        ? widget.profile.customStatus!.trim()
        : 'WELCOME';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ========================================================
        // СЛЕВА: КВАДРАТНЫЙ АВАТАР 84×84 С ТЯЖЕЛОЙ РАМКОЙ STEAM
        // ========================================================
        _buildSquareSteamAvatar(accent),

        const SizedBox(width: 16),

        // ========================================================
        // СПРАВА: НИКНЕЙМ, СТРАНА, ПЛАШКА СТАТУСА
        // ========================================================
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Никнейм (20sp, bold, белый, со стрелочкой/иконкой статуса)
              Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.profile.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.2,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Colors.white60,
                    size: 20,
                  ),
                ],
              ),

              const SizedBox(height: 3),

              // Под ником: флаг страны серым шрифтом 12sp
              Row(
                children: [
                  Text(flag, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                  Text(
                    country,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.65),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: Colors.white38,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SyncPai',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Под флагом: кастомная плашка статуса со стилизованными разделителями
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                    width: 0.9,
                  ),
                ),
                child: Text(
                  '— ❖ — $statusText — ❖ —',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),

              if (widget.profile.bio != null && widget.profile.bio!.trim().isNotEmpty && !widget.profile.bio!.startsWith('http')) ...[
                const SizedBox(height: 6),
                Text(
                  '«${widget.profile.bio!.trim()}»',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSquareSteamAvatar(Color accent) {
    const avatarSize = 84.0;
    const cornerLength = 14.0;
    const cornerWidth = 2.4;

    return GestureDetector(
      onTap: widget.isCurrentUser ? widget.onEditProfileTap : null,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 1. Золотая / Неоновая квадратная рамка Steam с внешним неоновым свечением
          Container(
            width: avatarSize + 12,
            height: avatarSize + 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: accent.withValues(alpha: 0.65),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),

          // 2. Декоративные металлические уголки (Steam Avatar Frame Brackets)
          Positioned(
            top: 0,
            left: 0,
            child: _buildCornerBracket(cornerLength, cornerWidth, accent, isTop: true, isLeft: true),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _buildCornerBracket(cornerLength, cornerWidth, accent, isTop: true, isLeft: false),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: _buildCornerBracket(cornerLength, cornerWidth, accent, isTop: false, isLeft: true),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: _buildCornerBracket(cornerLength, cornerWidth, accent, isTop: false, isLeft: false),
          ),

          // 3. Квадратный аватар 84×84 с легким скруглением
          AppAvatar(
            avatarUrl: widget.profile.avatarUrl,
            username: widget.profile.username,
            size: avatarSize,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(12),
            borderColor: Colors.black,
            borderWidth: 2.0,
          ),

          // 4. Индикатор онлайн-статуса Steam (В сети / Online)
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF14161F),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF57CBDE), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF57CBDE).withValues(alpha: 0.4),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF57CBDE), // Steam Cyan Online
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Text(
                    'ONLINE',
                    style: TextStyle(
                      color: Color(0xFF57CBDE),
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerBracket(double length, double width, Color color, {required bool isTop, required bool isLeft}) {
    return Container(
      width: length,
      height: length,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? BorderSide(color: color, width: width) : BorderSide.none,
          bottom: !isTop ? BorderSide(color: color, width: width) : BorderSide.none,
          left: isLeft ? BorderSide(color: color, width: width) : BorderSide.none,
          right: !isLeft ? BorderSide(color: color, width: width) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildArtworkShowcase(
    BuildContext context, {
    required Color accent,
    required String artworkUrl,
    required String artworkTitle,
    required double bgShiftX,
    required double bgShiftY,
    required double tiltX,
    required double tiltY,
  }) {
    const showcaseHeight = 390.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Заголовок витрины в стиле Steam Showcase
        Row(
          children: [
            const Icon(Icons.auto_awesome_mosaic_rounded, color: Colors.white70, size: 15),
            const SizedBox(width: 8),
            const Text(
              'ВИТРИНА ИЛЛЮСТРАЦИЙ',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
            const Spacer(),
            if (widget.isCurrentUser)
              GestureDetector(
                onTap: _handleShowcaseTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: accent.withValues(alpha: 0.45), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note_rounded, size: 12, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        'Сменить арт',
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(height: 10),

        // Основное полотно витрины: 3D Parallax Tilt + Разрезанная витрина Steam
        GestureDetector(
          onTap: _handleShowcaseTap,
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012) // перспектива глубины
              ..rotateX(tiltY * 0.06)
              ..rotateY(-tiltX * 0.06),
            alignment: FractionalOffset.center,
            child: Container(
              height: showcaseHeight,
              decoration: BoxDecoration(
                color: const Color(0xFF0C0D12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.8),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: accent.withValues(alpha: 0.15),
                    blurRadius: 18,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // РАЗРЕЗАННАЯ ВИТРИНА STEAM: Основная часть (74%) + Правая полоска (26%)
                  Row(
                    children: [
                      // 1. ОСНОВНАЯ ЧАСТЬ (MAIN SLICE)
                      Expanded(
                        flex: 74,
                        child: _buildArtworkSlice(
                          imageUrl: artworkUrl,
                          alignment: Alignment(-0.35 + (bgShiftX * 0.012), bgShiftY * 0.012),
                          isMain: true,
                          accent: accent,
                          artworkTitle: artworkTitle,
                        ),
                      ),

                      // Тонкий зазор между разрезами витрины Steam (4dp)
                      Container(
                        width: 4,
                        color: const Color(0xFF0C0D12),
                      ),

                      // 2. БОКОВАЯ ПОЛОСКА (SIDE SLICE)
                      Expanded(
                        flex: 26,
                        child: _buildArtworkSlice(
                          imageUrl: artworkUrl,
                          alignment: Alignment(1.0 + (bgShiftX * 0.012), bgShiftY * 0.012),
                          isMain: false,
                          accent: accent,
                          artworkTitle: artworkTitle,
                        ),
                      ),
                    ],
                  ),

                  // Нижняя панель действий (Лайки, комментарии, название)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildArtworkBottomBar(accent, artworkTitle),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtworkSlice({
    required String imageUrl,
    required Alignment alignment,
    required bool isMain,
    required Color accent,
    required String artworkTitle,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Фоновое изображение со сдвигом параллакса
        CachedNetworkImage(
          imageUrl: wrapCorsSafeUrl(imageUrl),
          fit: BoxFit.cover,
          alignment: alignment,
          placeholder: (_, __) => Container(
            color: const Color(0xFF14161F),
            child: const Center(
              child: Icon(Icons.image_outlined, color: Colors.white10, size: 28),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: const Color(0xFF14161F),
            child: const Icon(Icons.movie_creation_outlined, color: Colors.white24, size: 36),
          ),
        ),

        // Затемняющий градиент снизу для читаемости надписей
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),

        // Элементы оформления Steam Artwork
        if (isMain) ...[
          // Верхний левый стилизованный бейдж
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Text(
                'STEAM // ARTWORK_01',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 8.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),

          // Водяной знак Кандзи в верхнем правом углу
          Positioned(
            top: 12,
            right: 12,
            child: Text(
              '侍', // Самурай
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.28),
                fontSize: 48,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 18),
                ],
              ),
            ),
          ),

          // Никнейм в киберпанк стиле внизу слева
          Positioned(
            bottom: 42,
            left: 12,
            child: Text(
              '// ${widget.profile.username.toUpperCase()}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                shadows: const [
                  Shadow(color: Colors.black, blurRadius: 8),
                ],
              ),
            ),
          ),
        ] else ...[
          // Правая полоска: индекс среза // 02
          Positioned(
            top: 10,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Text(
                '// 02',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 8.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 42,
            right: 8,
            child: Text(
              'ART',
              style: TextStyle(
                color: accent,
                fontSize: 10.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],

        // Тонкий внутренний контур панели
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildArtworkBottomBar(Color accent, String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // Лайк (Steam Hearts)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isLiked = !_isLiked;
                _likesCount += _isLiked ? 1 : -1;
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 15,
                  color: _isLiked ? const Color(0xFFFF4081) : Colors.white60,
                ),
                const SizedBox(width: 4),
                Text(
                  '$_likesCount',
                  style: TextStyle(
                    color: _isLiked ? const Color(0xFFFF4081) : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Комментарии
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.chat_bubble_outline_rounded, size: 14, color: Colors.white60),
              SizedBox(width: 4),
              Text(
                '42',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),

          const SizedBox(width: 12),

          // Разделитель
          Container(width: 1, height: 12, color: Colors.white24),

          const SizedBox(width: 12),

          // Название тайтла
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),

          const SizedBox(width: 6),
          const Icon(Icons.open_in_new_rounded, size: 13, color: Colors.white54),
        ],
      ),
    );
  }
}

class _ArtworkPreset {
  final String title;
  final String kanji;
  final String tagline;
  final String imageUrl;

  const _ArtworkPreset({
    required this.title,
    required this.kanji,
    required this.tagline,
    required this.imageUrl,
  });
}

/// Модальный лист выбора иллюстрации для витрины с сохранением в Supabase
class _ArtworkSelectorSheet extends StatefulWidget {
  final UserProfile profile;
  final Color accentColor;

  const _ArtworkSelectorSheet({
    required this.profile,
    required this.accentColor,
  });

  @override
  State<_ArtworkSelectorSheet> createState() => _ArtworkSelectorSheetState();
}

class _ArtworkSelectorSheetState extends State<_ArtworkSelectorSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveArtworkToSupabase({
    required String posterUrl,
    required String title,
    String? animeId,
  }) async {
    setState(() => _isSaving = true);
    try {
      if (getIt.isRegistered<AuthCubit>()) {
        await getIt<AuthCubit>().updateProfile(
          username: widget.profile.username,
          favoriteAnimePoster: posterUrl,
          favoriteAnimeTitle: title,
          favoriteAnimeId: animeId,
          showcaseType: 'favorite_anime',
        );
      }
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Витрина «$title» сохранена в профиль!'),
            backgroundColor: widget.accentColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка сохранения: $e'),
            backgroundColor: AppColors.syncError,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF12141C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Настройка Steam Artwork Showcase',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            indicatorColor: widget.accentColor,
            labelColor: widget.accentColor,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: const [
              Tab(text: 'Пресеты'),
              Tab(text: 'Из каталога'),
              Tab(text: 'По ссылке'),
            ],
          ),
          Expanded(
            child: _isSaving
                ? Center(
                    child: CircularProgressIndicator(color: widget.accentColor),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // ВКЛАДКА 1: ПРЕСЕТЫ
                      _buildPresetsTab(),

                      // ВКЛАДКА 2: ИЗ КАТАЛОГА АНИМЕ
                      _buildCatalogTab(),

                      // ВКЛАДКА 3: ПО ССЫЛКЕ
                      _buildCustomUrlTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _SteamStyleProfileHeaderState.curatedPresets.length,
      itemBuilder: (context, index) {
        final preset = _SteamStyleProfileHeaderState.curatedPresets[index];
        final isSelected = widget.profile.favoriteAnimePoster == preset.imageUrl;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _saveArtworkToSupabase(
              posterUrl: preset.imageUrl,
              title: preset.title,
            ),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 90,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? widget.accentColor : Colors.white12,
                  width: isSelected ? 2.0 : 1.0,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: wrapCorsSafeUrl(preset.imageUrl),
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.black.withValues(alpha: 0.3),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 14,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          preset.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preset.tagline,
                          style: TextStyle(
                            color: widget.accentColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      right: 16,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Icon(Icons.check_circle_rounded, color: widget.accentColor, size: 24),
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

  Widget _buildCatalogTab() {
    if (!getIt.isRegistered<CatalogCubit>()) {
      return const Center(child: Text('Каталог недоступен', style: TextStyle(color: Colors.white60)));
    }

    return BlocBuilder<CatalogCubit, CatalogState>(
      bloc: getIt<CatalogCubit>(),
      builder: (context, catState) {
        if (catState is! CatalogLoaded || catState.titles.isEmpty) {
          return const Center(
            child: Text('Загрузка списка аниме...', style: TextStyle(color: Colors.white60)),
          );
        }

        final titles = catState.titles;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: titles.length,
          itemBuilder: (context, index) {
            final t = titles[index];
            final poster = t.posterUrl;
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 64,
                  child: CachedNetworkImage(
                    imageUrl: wrapCorsSafeUrl(poster),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              title: Text(t.displayTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
              subtitle: Text(t.genres.join(' • '), style: const TextStyle(color: Colors.white60, fontSize: 11)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              tileColor: Colors.white.withValues(alpha: 0.04),
              onTap: () => _saveArtworkToSupabase(
                posterUrl: poster,
                title: t.displayTitle,
                animeId: '${t.id}',
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCustomUrlTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Прямая ссылка на арт (URL картинки / GIF)',
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.link_rounded, color: Colors.white60),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Название иллюстрации (опционально)',
              labelStyle: const TextStyle(color: Colors.white60),
              prefixIcon: const Icon(Icons.title_rounded, color: Colors.white60),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.accentColor,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final url = _urlController.text.trim();
              if (url.isEmpty || !url.startsWith('http')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Введите корректный URL (http...)')),
                );
                return;
              }
              final title = _titleController.text.trim().isNotEmpty
                  ? _titleController.text.trim()
                  : 'CUSTOM ARTWORK';
              _saveArtworkToSupabase(posterUrl: url, title: title);
            },
            child: const Text('Применить и сохранить в Supabase', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
