import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/steam_avatar_frame.dart';
import '../../../../core/widgets/vector_country_flag.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/widgets/pai_chan_auth_gate.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../domain/entities/steam_profile_customization.dart';
import '../../services/friends_service.dart';
import 'badge_details_sheet.dart';
import 'live_backgrounds/live_background_widget.dart';

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

  // Курированные готовые пресеты артворков в стиле Steam Artwork Showcase (статичные + живые аниме-сцены)
  static const List<SteamArtworkPreset> curatedPresets = [
    SteamArtworkPreset(
      title: 'Самурай',
      kanji: '侍',
      tagline: 'Киберпанк коллекция',
      imageUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=1200&auto=format&fit=crop&q=80',
    ),
    SteamArtworkPreset(
      title: 'EDGERUNNERS // LUCY & DAVID',
      kanji: '電脳',
      tagline: 'NIGHT CITY LEGENDS',
      imageUrl: 'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=1200&auto=format&fit=crop&q=80',
    ),
    SteamArtworkPreset(
      title: 'Поднятие уровня в одиночку',
      kanji: '影',
      tagline: 'SOLO LEVELING // ARISE',
      imageUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=1200&auto=format&fit=crop&q=80',
    ),
    SteamArtworkPreset(
      title: 'UCHIHA ITACHI // 万華鏡写輪眼 (LIVE)',
      kanji: '写輪',
      tagline: 'TSUKUYOMI // ANIMATED SHOWCASE',
      imageUrl: 'live:uchiha_sharingan_live',
    ),
    SteamArtworkPreset(
      title: 'DOMAIN EXPANSION // 領域展開 (LIVE)',
      kanji: '無量',
      tagline: 'INFINITE VOID // ANIMATED',
      imageUrl: 'live:gojo_hollow_purple',
    ),
    SteamArtworkPreset(
      title: 'FRIEREN // 葬送のフリーレン (LIVE)',
      kanji: '魔法',
      tagline: 'ASTRAL MANA BUTTERFLIES // LIVE',
      imageUrl: 'live:frieren_magic_live',
    ),
    SteamArtworkPreset(
      title: 'NEON SHINOBI // 忍者',
      kanji: '忍者',
      tagline: 'STEALTH CLAN // ZERO',
      imageUrl: 'https://images.unsplash.com/photo-1563089145-599997674d42?w=1200&auto=format&fit=crop&q=80',
    ),
    SteamArtworkPreset(
      title: 'SAKURA BLADE // 桜刀',
      kanji: '桜',
      tagline: 'CHERRY BLOSSOM RONIN',
      imageUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=1200&auto=format&fit=crop&q=80',
    ),
  ];

  @override
  State<SteamStyleProfileHeader> createState() => _SteamStyleProfileHeaderState();
}

class _SteamStyleProfileHeaderState extends State<SteamStyleProfileHeader>
    with SingleTickerProviderStateMixin {
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  double _targetTiltX = 0.0;
  double _targetTiltY = 0.0;
  AnimationController? _idleController;

  static List<SteamArtworkPreset> get curatedPresets =>
      SteamStyleProfileHeader.curatedPresets;

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

      // 2. Подписка на датчик гироскопа для 3D Parallax эффекта (только мобильные платформы iOS / Android)
      final isMobilePlatform = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
      if (isMobilePlatform) {
        try {
          _gyroSubscription = gyroscopeEventStream().listen((event) {
            if (!mounted) return;
            // Интегрируем угловую скорость гироскопа (rad/s) с затуханием к центру (spring centering)
            // event.y = поворот влево-вправо, event.x = наклон вперед-назад
            _targetTiltX = (_targetTiltX * 0.92 + event.y * 0.12).clamp(-1.0, 1.0);
            _targetTiltY = (_targetTiltY * 0.92 + event.x * 0.12).clamp(-1.0, 1.0);

            // Плавная интерполяция к целевому значению
            final newTiltX = _tiltX + (_targetTiltX - _tiltX) * 0.25;
            final newTiltY = _tiltY + (_targetTiltY - _tiltY) * 0.25;

            if ((newTiltX - _tiltX).abs() > 0.002 || (newTiltY - _tiltY).abs() > 0.002) {
              setState(() {
                _tiltX = newTiltX;
                _tiltY = newTiltY;
              });
            }
          }, onError: (_) {});
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _gyroSubscription?.cancel();
    _idleController?.dispose();
    super.dispose();
  }

  Color _resolveAccentColor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  String _resolveArtworkUrl() {
    // 1. Независимый арт витрины иллюстраций (Steam Artwork Showcase)
    final art = widget.profile.artworkUrl;
    if (art != null && art.trim().isNotEmpty) {
      return art.trim();
    }
    // 2. Дефолтный премиальный киберпанк-самурай арт
    return curatedPresets.first.imageUrl;
  }

  String _resolveArtworkTitle() {
    final title = widget.profile.artworkTitle;
    if (title != null && title.trim().isNotEmpty) {
      return title.trim();
    }
    return '';
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
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _resolveArtworkTitle(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(Icons.play_circle_fill_rounded, color: accent, size: 28),
                  title: Text('Открыть страницу аниме', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: scheme.surfaceContainer,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.pushNamed('anime-details', pathParameters: {'id': favId});
                  },
                ),
              ),
              if (widget.isCurrentUser) ...[
                const SizedBox(height: 10),
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: Icon(Icons.palette_rounded, color: scheme.onSurfaceVariant, size: 26),
                    title: Text('Сменить иллюстрацию витрины', style: TextStyle(color: scheme.onSurfaceVariant)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    tileColor: scheme.surfaceContainer,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _openArtworkSelectorSheet(context);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 10),
            ],
          ),
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

    // 3D Parallax расчеты:
    // Плавный idle-сдвиг при отсутствии активных движений устройства
    final idleVal = _idleController?.value ?? 0.0;
    final hasActiveTilt = _tiltX.abs() > 0.02 || _tiltY.abs() > 0.02;
    final effectiveTiltX = hasActiveTilt ? _tiltX : (math.sin(idleVal * 2 * math.pi) * 0.04);
    final effectiveTiltY = hasActiveTilt ? _tiltY : (math.cos(idleVal * 2 * math.pi) * 0.03);

    // Сдвиг фонового изображения внутри витрины
    final bgShiftX = -effectiveTiltX * 8.0;
    final bgShiftY = -effectiveTiltY * 6.0;

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? scheme.surfaceContainer.withValues(alpha: 0.88)
              : scheme.surfaceContainerLowest.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
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
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        if (widget.showBackButton) ...[
          IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: scheme.onSurface, size: 16),
            onPressed: widget.onBackTap ?? () => Navigator.of(context).maybePop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 8),
        ],

        // Плашка "Мой профиль" / "Профиль друга"
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
                    : scheme.surfaceContainerHigh.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.isCurrentUser ? 'Мой профиль' : 'Профиль друга',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(width: 6),

        // Бейдж саппортера SyncPai (Plus / Pro / Founder)
        if (widget.profile.supporterTier.badgeLabel != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              gradient: widget.profile.supporterTier.isProducer
                  ? const LinearGradient(
                      colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFEC4899)],
                    )
                  : null,
              color: widget.profile.supporterTier.isProducer
                  ? null
                  : widget.profile.supporterTier.accentColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.profile.supporterTier.accentColor.withValues(alpha: 0.7),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.profile.supporterTier.icon,
                  size: 12,
                  color: widget.profile.supporterTier.isProducer
                      ? Colors.black
                      : widget.profile.supporterTier.accentColor,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.profile.supporterTier.badgeLabel!,
                  style: TextStyle(
                    color: widget.profile.supporterTier.isProducer
                        ? Colors.black
                        : widget.profile.supporterTier.accentColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],

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
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.15 + ((_idleController?.value ?? 0.5) * 0.25)),
                        blurRadius: 8 + ((_idleController?.value ?? 0.5) * 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badge.icon, size: 12, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        'Ур. ${badge.level}',
                        style: TextStyle(
                          color: accent,
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
            icon: Icon(Icons.settings, color: scheme.onSurfaceVariant, size: 20),
            tooltip: 'Настройки',
            onPressed: widget.onSettingsTap ?? () => context.push('/settings'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ] else ...[
          IconButton(
            icon: Icon(Icons.person_add_alt_1_rounded, color: accent, size: 20),
            tooltip: 'Добавить в друзья',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () async {
              final friendUser = <String, dynamic>{
                'id': widget.profile.id,
                'username': widget.profile.username,
                'name': widget.profile.username,
                'tag': widget.profile.tag,
                'avatar_url': widget.profile.avatarUrl,
              };
              if (PaiChanAuthGate.isGuest(context)) {
                await PaiChanAuthGate.show(
                  context,
                  accentColor: accent,
                  pendingFriendUser: friendUser,
                );
                return;
              }
              await FriendsService.addFriend(friendUser);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Заявка отправлена пользователю ${widget.profile.username}! ✨'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: accent,
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  void _copyUserHandle(BuildContext context, Color accent) {
    final rawTag = widget.profile.tag.trim();
    final formattedTag = rawTag.isEmpty
        ? '#0001'
        : (rawTag.startsWith('#') ? rawTag : '#$rawTag');
    final fullHandle = '${widget.profile.username}$formattedTag';
    Clipboard.setData(ClipboardData(text: fullHandle));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Тег скопирован! Отправь его другу'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: accent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showQuickNicknameAndStatusDialog(BuildContext context, Color accent) async {
    if (!widget.isCurrentUser) {
      _copyUserHandle(context, accent);
      return;
    }

    final nicknameCtrl = TextEditingController(text: widget.profile.username);
    final statusCtrl = TextEditingController(
      text: widget.profile.customStatus?.trim().isNotEmpty == true
          ? widget.profile.customStatus!.trim()
          : 'WELCOME',
    );
    const presets = <String>[
      'Онлайн • Смотрю аниме',
      'В поиске тайтла на вечер',
      'Не беспокоить • Марафон',
      'WELCOME',
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setModalState) => Dialog(
            backgroundColor: const Color(0xFF151821),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: accent.withValues(alpha: 0.35), width: 1.2),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.badge_rounded, color: accent, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Никнейм и быстрый статус',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: nicknameCtrl,
                      maxLength: 24,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        labelText: 'Никнейм',
                        counterText: '',
                        prefixIcon: Icon(Icons.person_outline_rounded, color: accent, size: 18),
                        suffixText: widget.profile.tag.isNotEmpty ? widget.profile.tag : '#0001',
                        suffixStyle: TextStyle(color: accent, fontWeight: FontWeight.w700),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: accent, width: 1.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: statusCtrl,
                      maxLength: 36,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Статус в профиле',
                        counterText: '',
                        prefixIcon: Icon(Icons.bolt_rounded, color: accent, size: 18),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: accent, width: 1.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: presets.map((preset) {
                        final isSelected = statusCtrl.text.trim() == preset;
                        return InkWell(
                          onTap: () => setModalState(() => statusCtrl.text = preset),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? accent.withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? accent : Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              preset,
                              style: TextStyle(
                                color: isSelected ? accent : Colors.white70,
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(dialogCtx).pop();
                            widget.onEditProfileTap();
                          },
                          icon: Icon(Icons.tune_rounded, size: 15, color: scheme.onSurfaceVariant),
                          label: Text(
                            'Все настройки',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () async {
                            final nextName = nicknameCtrl.text.trim();
                            final nextStatus = statusCtrl.text.trim();
                            Navigator.of(dialogCtx).pop();
                            if (getIt.isRegistered<AuthCubit>()) {
                              await getIt<AuthCubit>().updateProfile(
                                username: nextName.isNotEmpty ? nextName : widget.profile.username,
                                customStatus: nextStatus.isNotEmpty ? nextStatus : 'WELCOME',
                              );
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: AppColors.onColor(accent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text(
                            'Сохранить',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileHeaderRow(BuildContext context, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final flag = widget.countryFlag ?? widget.profile.countryFlag ?? '🇰🇬';
    final country = widget.countryName ?? widget.profile.countryName ?? 'Kyrgyzstan';
    final statusText = widget.profile.customStatus?.trim().isNotEmpty == true
        ? widget.profile.customStatus!.trim()
        : 'WELCOME';
    final rawTag = widget.profile.tag.trim();
    final displayTag = rawTag.isEmpty
        ? (widget.profile.friendCode?.trim().isNotEmpty == true ? widget.profile.friendCode!.trim() : '#0001')
        : (rawTag.startsWith('#') ? rawTag : '#$rawTag');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ========================================================
        // СЛЕВА: АВАТАР (КВАДРАТНЫЙ STEAM 84×84 ИЛИ КРУГЛЫЙ DISCORD NITRO)
        // ========================================================
        _buildSteamAvatar(accent),

        const SizedBox(width: 16),

        // ========================================================
        // СПРАВА: НИКНЕЙМ, СТРАНА + #TAG, ПЛАШКА СТАТУСА
        // ========================================================
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Интерактивный никнейм (открывает быстрый редактор никнейма/статуса по клику)
              Tooltip(
                message: widget.isCurrentUser
                    ? 'Изменить никнейм и статус'
                    : 'Скопировать Ник#Тег',
                child: InkWell(
                  onTap: () => _showQuickNicknameAndStatusDialog(context, accent),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.profile.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                              letterSpacing: 0.2,
                              shadows: isDark
                                  ? const [Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2))]
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
                          ),
                          child: Icon(
                            widget.isCurrentUser ? Icons.edit_rounded : Icons.copy_rounded,
                            color: accent,
                            size: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Под ником: векторный флаг страны (20x14px, borderRadius: 3) + название страны + копируемый #tag
              Row(
                children: [
                  VectorCountryFlag(
                    countryFlag: flag,
                    countryName: country,
                    width: 20,
                    height: 14,
                    borderRadius: 3,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      country,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Скопировать ${widget.profile.username}$displayTag',
                    child: InkWell(
                      onTap: () => _copyUserHandle(context, accent),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayTag,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accent,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.copy_rounded,
                              size: 10.5,
                              color: accent.withValues(alpha: 0.85),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Под флагом: чистая строка статуса
              Text(
                statusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
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
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSteamAvatar(Color accent) {
    const avatarSize = 84.0;
    const cornerLength = 14.0;
    const cornerWidth = 2.4;
    final isCircle = widget.profile.avatarShape == 'circle';
    final hasFrame = widget.profile.frameId != null && widget.profile.frameId != 'none';

    return GestureDetector(
      onTap: widget.isCurrentUser ? widget.onEditProfileTap : null,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (isCircle) ...[
            // 1. Круглая рамка (Classic / Discord Nitro)
            if (hasFrame)
              SteamAvatarFrameWidget(
                frameId: widget.profile.frameId,
                size: avatarSize,
                shape: 'circle',
                child: AppAvatar(
                  avatarUrl: widget.profile.avatarUrl,
                  username: widget.profile.username,
                  size: avatarSize,
                  shape: BoxShape.circle,
                  borderColor: Colors.black,
                  borderWidth: 2.0,
                ),
              )
            else
              Container(
                width: avatarSize + 6,
                height: avatarSize + 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF181D27),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: AppAvatar(
                    avatarUrl: widget.profile.avatarUrl,
                    username: widget.profile.username,
                    size: avatarSize,
                    shape: BoxShape.circle,
                    borderColor: Colors.transparent,
                    borderWidth: 0,
                  ),
                ),
              ),
          ] else ...[
            // 1. Квадратная рамка Steam с внешним неоновым свечением
            if (hasFrame)
              SteamAvatarFrameWidget(
                frameId: widget.profile.frameId,
                size: avatarSize,
                shape: 'square',
                child: AppAvatar(
                  avatarUrl: widget.profile.avatarUrl,
                  username: widget.profile.username,
                  size: avatarSize,
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(12),
                  borderColor: Colors.black,
                  borderWidth: 2.0,
                ),
              )
            else ...[
              Container(
                width: avatarSize + 8,
                height: avatarSize + 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0xFF181D27),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 8,
                      offset: Offset(0, 3),
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
            ],
          ],

          // 4. Индикатор онлайн-статуса / Инкогнито (переключение в 1 тап для своего профиля)
          Positioned(
            bottom: -2,
            right: -2,
            child: ListenableBuilder(
              listenable: PresenceService.instance,
              builder: (context, _) {
                final scheme = Theme.of(context).colorScheme;
                final isIncognito =
                    widget.isCurrentUser && PresenceService.instance.isIncognito;
                final pillColor =
                    isIncognito ? const Color(0xFF94A3B8) : accent;

                return GestureDetector(
                  key: const ValueKey('profile_status_pill'),
                  onTap: widget.isCurrentUser
                      ? () => PresenceService.instance.toggleIncognito()
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isIncognito
                          ? const Color(0xFF1E2430)
                          : scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: pillColor.withValues(alpha: isIncognito ? 0.45 : 0.8),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: pillColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isIncognito ? 'ИНКОГНИТО' : 'ONLINE',
                          style: TextStyle(
                            color: pillColor,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isDesktopOS = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final double showcaseHeight = isDesktopOS ? 360.0 : 200.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Заголовок витрины в стиле Steam Showcase
        Row(
          children: [
            Icon(Icons.auto_awesome_mosaic_rounded, color: accent, size: 15),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'ВИТРИНА ИЛЛЮСТРАЦИЙ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                ),
              ),
            ),
            if (widget.isCurrentUser) ...[
              const SizedBox(width: 8),
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
                color: isDark ? scheme.surfaceContainer : scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // ЕДИНАЯ ВИТРИНА АРТА: Единое бесшовное изображение во всю ширину без вертикальной разделительной полосы
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final totalWidth = constraints.maxWidth;
                      return SizedBox(
                        width: totalWidth,
                        height: showcaseHeight,
                        child: _buildArtworkSlice(
                          imageUrl: artworkUrl,
                          totalWidth: totalWidth,
                          showcaseHeight: showcaseHeight,
                          bgShiftX: bgShiftX * 0.012 * totalWidth,
                          bgShiftY: bgShiftY * 0.012 * showcaseHeight,
                          accent: accent,
                          artworkTitle: artworkTitle,
                        ),
                      );
                    },
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

  Widget _buildArtworkMediaLayer(
    String imageUrl, {
    required double width,
    required double height,
  }) {
    final trimmed = imageUrl.trim();
    if (trimmed.startsWith('live:')) {
      final liveId = trimmed.substring(5);
      final bgTheme = SteamBackgroundTheme.fromId(liveId);
      return SizedBox(
        width: width,
        height: height,
        child: LiveBackgroundWidget(
          backgroundId: liveId,
          assetOrUrl: bgTheme.assetOrUrl,
          fallbackGradient: bgTheme.gradient,
          isPaused: _isTestEnv,
        ),
      );
    }

    final isLocalPath = !trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://') &&
        (trimmed.startsWith('/') ||
            trimmed.startsWith('file://') ||
            RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(trimmed));

    if (isLocalPath) {
      final cleanPath = trimmed.startsWith('file://')
          ? Uri.parse(trimmed).toFilePath()
          : trimmed;
      final file = File(cleanPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => LiveBackgroundWidget(
            backgroundId: widget.profile.backgroundId ?? 'cyberpunk_city',
            fallbackGradient: const [Color(0xFF14161F), Color(0xFF1E1338)],
            isPaused: true,
          ),
        );
      }
    }

    return CachedNetworkImage(
      imageUrl: wrapCorsSafeUrl(trimmed),
      width: width,
      height: height,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      placeholder: (_, __) => Container(
        color: const Color(0xFF14161F),
        child: const Center(
          child: Icon(Icons.image_outlined, color: Colors.white10, size: 28),
        ),
      ),
      errorWidget: (_, __, ___) => LiveBackgroundWidget(
        backgroundId: widget.profile.backgroundId ?? 'cyberpunk_city',
        fallbackGradient: const [Color(0xFF14161F), Color(0xFF1E1338)],
        isPaused: true,
      ),
    );
  }

  Widget _buildArtworkSlice({
    required String imageUrl,
    required double totalWidth,
    required double showcaseHeight,
    required double bgShiftX,
    required double bgShiftY,
    required Color accent,
    required String artworkTitle,
  }) {
    // Увеличенный масштаб медиа-слоя (+8% по ширине и высоте),
    // чтобы при смещении фона по параллаксу по краям никогда не появлялись черные полосы
    const bleedScale = 1.08;
    final bleedWidth = totalWidth * bleedScale;
    final bleedHeight = showcaseHeight * bleedScale;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Единое центрированное изображение без разрывов
        OverflowBox(
          minWidth: bleedWidth,
          maxWidth: bleedWidth,
          minHeight: bleedHeight,
          maxHeight: bleedHeight,
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(bgShiftX, bgShiftY),
            child: SizedBox(
              width: bleedWidth,
              height: bleedHeight,
              child: _buildArtworkMediaLayer(
                imageUrl,
                width: bleedWidth,
                height: bleedHeight,
              ),
            ),
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surfaceContainer.withValues(alpha: 0.92)
            : scheme.surfaceContainerLowest.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35), width: 1.0),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (title.isNotEmpty)
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            )
          else
            const Spacer(),
          const Spacer(),
          Icon(Icons.open_in_new_rounded, size: 13, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

class SteamArtworkPreset {
  final String title;
  final String kanji;
  final String tagline;
  final String imageUrl;

  const SteamArtworkPreset({
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
          artworkUrl: posterUrl,
          artworkTitle: title,
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
    return Material(
      color: Colors.transparent,
      child: Container(
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
    ),
    );
  }

  Widget _buildPresetsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _SteamStyleProfileHeaderState.curatedPresets.length,
      itemBuilder: (context, index) {
        final preset = _SteamStyleProfileHeaderState.curatedPresets[index];
        final isSelected = widget.profile.artworkUrl == preset.imageUrl;

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
                  if (preset.imageUrl.startsWith('live:'))
                    LiveBackgroundWidget(
                      backgroundId: preset.imageUrl.substring(5),
                      fallbackGradient: const [Color(0xFF14161F), Color(0xFF22143B)],
                      isPaused: true,
                    )
                  else
                    CachedNetworkImage(
                      imageUrl: wrapCorsSafeUrl(preset.imageUrl),
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: const Color(0xFF14161F)),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF14161F),
                        child: const Icon(Icons.broken_image_rounded, color: Colors.white24, size: 28),
                      ),
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
            return Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 64,
                    child: CachedNetworkImage(
                      imageUrl: wrapCorsSafeUrl(poster),
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: const Color(0xFF14161F)),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color(0xFF14161F),
                        child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 20),
                      ),
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
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCustomUrlTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
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
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: widget.accentColor, width: 1.4),
              ),
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
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: widget.accentColor, width: 1.4),
              ),
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
