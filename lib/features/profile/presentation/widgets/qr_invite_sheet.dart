import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/widgets/pai_chan_auth_gate.dart';
import '../../domain/entities/friend_models.dart';
import '../../services/friends_service.dart';

/// Диалог / карточка персонального QR-кода и инвайт-ссылки («Мой QR-код» / «Моя визитка»)
class QrInviteSheet extends StatefulWidget {
  final UserProfile profile;
  final Color accentColor;

  const QrInviteSheet({
    super.key,
    required this.profile,
    required this.accentColor,
  });

  static Future<void> show(BuildContext context, {required UserProfile profile, Color? accentColor}) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    if (profile.isAnonymous) {
      return PaiChanAuthGate.show(
        context,
        currentProfile: profile,
        accentColor: accent,
        onAuthenticated: () {
          if (!context.mounted) return;
          final updated = PaiChanAuthGate.resolveCurrentProfile(context);
          if (!updated.isAnonymous) {
            QrInviteSheet.show(context, profile: updated, accentColor: accent);
          }
        },
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 650;

    if (isDesktop) {
      return showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.78),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: QrInviteSheet(profile: profile, accentColor: accent),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) => QrInviteSheet(profile: profile, accentColor: accent),
    );
  }

  @override
  State<QrInviteSheet> createState() => _QrInviteSheetState();
}

class _QrInviteSheetState extends State<QrInviteSheet> {
  final GlobalKey _cardRepaintKey = GlobalKey();
  FriendInvite? _invite;
  bool _isLoading = true;
  bool _isSavingImage = false;

  @override
  void initState() {
    super.initState();
    _fetchInvite();
  }

  Future<void> _fetchInvite() async {
    setState(() => _isLoading = true);
    final inv = await FriendsService.getOrCreatePersonalInvite(
      customCode: widget.profile.friendCode,
    );
    if (mounted) {
      setState(() {
        _invite = inv;
        _isLoading = false;
      });
    }
  }

  String get _inviteUrl {
    if (_invite != null) return _invite!.universalUrl;
    final code = widget.profile.friendCode ?? widget.profile.id;
    return 'https://syncpai.app/f/$code';
  }

  Future<void> _shareInviteUrl() async {
    final shareText =
        'Добавляйся ко мне в друзья в SyncPai, чтобы смотреть аниме синхронно! 👉 $_inviteUrl';
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: shareText,
          subject: 'Приглашение в друзья SyncPai',
        ),
      );
    } catch (_) {
      Clipboard.setData(ClipboardData(text: _inviteUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ссылка скопирована в буфер обмена!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _copyInviteUrl() async {
    await Clipboard.setData(ClipboardData(text: _inviteUrl));
    HapticFeedback.lightImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ссылка $_inviteUrl скопирована!'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: widget.accentColor.withValues(alpha: 0.95),
        ),
      );
    }
  }

  Future<void> _saveQrImage() async {
    try {
      setState(() => _isSavingImage = true);
      final boundary = _cardRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/syncpai_friend_card.png');
      await file.writeAsBytes(pngBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Мой QR-код SyncPai',
        ),
      );
    } catch (e) {
      debugPrint('Save QR error: $e');
    } finally {
      if (mounted) {
        setState(() => _isSavingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161F) : scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Заголовок
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.qr_code_2_rounded, color: widget.accentColor, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Мой QR-код SyncPai',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Покажите этот экран другу или поделитесь ссылкой',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 18),

          // Визитка с QR-кодом для экспорта (RepaintBoundary)
          RepaintBoundary(
            key: _cardRepaintKey,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.accentColor.withValues(alpha: 0.22),
                    const Color(0xFF1B1D28),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: widget.accentColor.withValues(alpha: 0.45), width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.18),
                    blurRadius: 28,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Аватар и ник
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppAvatar(
                        avatarUrl: widget.profile.avatarUrl ?? 'cat',
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                widget.profile.username,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                widget.profile.tag,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (widget.profile.friendCode != null) ...[
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: widget.accentColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.profile.friendCode!,
                                style: TextStyle(
                                  color: widget.accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Белый блок под QR-код для 100% контраста и надежного считывания
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 180,
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : QrImageView(
                            data: _inviteUrl,
                            version: QrVersions.auto,
                            size: 180,
                            errorCorrectionLevel: QrErrorCorrectLevel.H,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF0F1117),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF0F1117),
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),

                  // URL-подпись
                  Text(
                    _inviteUrl,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Кнопки управления: Копировать / Поделиться / Сохранить
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Копировать', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  onPressed: _copyInviteUrl,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Поделиться', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                  onPressed: _shareInviteUrl,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Дополнительное действие: Сохранить картинку карточки
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                visualDensity: VisualDensity.compact,
              ),
              icon: _isSavingImage
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.image_outlined, size: 17),
              label: const Text('Сохранить визитку как фото', style: TextStyle(fontSize: 12.5)),
              onPressed: _isSavingImage ? null : _saveQrImage,
            ),
          ),
        ],
      ),
    );
  }
}
