import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/mascot/mascot_state.dart';
import '../../../../core/widgets/mascot/sync_pai_mascot.dart';
import '../../../profile/services/pending_invite_storage.dart';
import '../../domain/entities/user_profile.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';
import '../utils/auth_error_formatter.dart';
import 'auth_modal_sheet.dart';

typedef MascotAuthGateDialog = PaiChanAuthGate;
typedef MascotAuthGateView = PaiChanAuthGate;

/// Дружелюбный экран/модалка авторизации с маскотом Пай-тян («Хочешь добавлять друзей?»)
/// для перехвата социальных действий (добавление друзей, QR-код, инвайт-ссылки) у гостей.
class PaiChanAuthGate extends StatefulWidget {
  final UserProfile? currentProfile;
  final Color? accentColor;
  final String? pendingInviteCode;
  final Map<String, dynamic>? pendingFriendUser;
  final String? customNotice;
  final bool isEmbedded;
  final VoidCallback? onAuthenticated;
  final VoidCallback? onDismiss;

  const PaiChanAuthGate({
    super.key,
    this.currentProfile,
    this.accentColor,
    this.pendingInviteCode,
    this.pendingFriendUser,
    this.customNotice,
    this.isEmbedded = false,
    this.onAuthenticated,
    this.onDismiss,
  });

  /// Проверяет, является ли текущий пользователь неавторизованным / анонимным гостем
  static bool isGuest(BuildContext? context, {UserProfile? profile}) {
    if (profile != null) {
      return profile.isAnonymous;
    }
    if (context != null) {
      try {
        final state = context.read<AuthCubit>().state;
        if (state is Authenticated) {
          return state.profile.isAnonymous;
        }
      } catch (_) {}
    }
    if (getIt.isRegistered<AuthCubit>()) {
      final state = getIt<AuthCubit>().state;
      if (state is Authenticated) {
        return state.profile.isAnonymous;
      }
    }
    return true;
  }

  /// Получает актуальный профиль пользователя (или создает гостевой fallback)
  static UserProfile resolveCurrentProfile(BuildContext? context, {UserProfile? fallback}) {
    if (fallback != null) return fallback;
    if (context != null) {
      try {
        final state = context.read<AuthCubit>().state;
        if (state is Authenticated) return state.profile;
      } catch (_) {}
    }
    if (getIt.isRegistered<AuthCubit>()) {
      final state = getIt<AuthCubit>().state;
      if (state is Authenticated) return state.profile;
    }
    return UserProfile.guest();
  }

  /// Открывает адаптивное модальное окно Pai-chan Auth Gate:
  /// - На Windows / Desktop: центрированный `Dialog` (`maxWidth: 420px`), закрываемый по `Esc`.
  /// - На Android / iOS: плавный `ModalBottomSheet`.
  static Future<bool?> show(
    BuildContext context, {
    UserProfile? currentProfile,
    Color? accentColor,
    String? pendingInviteCode,
    Map<String, dynamic>? pendingFriendUser,
    String? customNotice,
    VoidCallback? onAuthenticated,
  }) {
    if (pendingInviteCode != null && pendingInviteCode.trim().isNotEmpty) {
      PendingInviteStorage.savePendingInvite(pendingInviteCode);
    }
    if (pendingFriendUser != null) {
      PendingInviteStorage.savePendingFriendUser(pendingFriendUser);
    }

    final isDesktop = !kIsWeb &&
        (Platform.isWindows ||
            Platform.isMacOS ||
            Platform.isLinux ||
            MediaQuery.of(context).size.width >= 650);

    if (isDesktop) {
      return showDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.78),
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: PaiChanAuthGate(
              currentProfile: currentProfile,
              accentColor: accentColor,
              pendingInviteCode: pendingInviteCode,
              pendingFriendUser: pendingFriendUser,
              customNotice: customNotice,
              onAuthenticated: onAuthenticated,
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: PaiChanAuthGate(
          currentProfile: currentProfile,
          accentColor: accentColor,
          pendingInviteCode: pendingInviteCode,
          pendingFriendUser: pendingFriendUser,
          customNotice: customNotice,
          onAuthenticated: onAuthenticated,
        ),
      ),
    );
  }

  @override
  State<PaiChanAuthGate> createState() => _PaiChanAuthGateState();
}

class _PaiChanAuthGateState extends State<PaiChanAuthGate> {
  bool _isSubmittingGoogle = false;

  @override
  void initState() {
    super.initState();
    if (widget.pendingInviteCode != null && widget.pendingInviteCode!.trim().isNotEmpty) {
      PendingInviteStorage.savePendingInvite(widget.pendingInviteCode!);
    }
    if (widget.pendingFriendUser != null) {
      PendingInviteStorage.savePendingFriendUser(widget.pendingFriendUser!);
    }
  }

  AuthCubit? _tryGetAuthCubit() {
    try {
      return context.read<AuthCubit>();
    } catch (_) {
      if (getIt.isRegistered<AuthCubit>()) {
        return getIt<AuthCubit>();
      }
      return null;
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isSubmittingGoogle) return;
    final cubit = _tryGetAuthCubit();
    final profile = PaiChanAuthGate.resolveCurrentProfile(context, fallback: widget.currentProfile);

    if (cubit == null) {
      _openEmailRegistration(initialTabIndex: 1);
      return;
    }

    setState(() => _isSubmittingGoogle = true);
    try {
      await cubit.signInWithGoogle();
      if (!mounted) return;

      final afterState = cubit.state;
      final signedIn = afterState is Authenticated && !afterState.profile.isAnonymous;
      if (signedIn) {
        await _completeAuthentication();
      } else {
        setState(() => _isSubmittingGoogle = false);
        await _showQuickGoogleLinkDialog(cubit, profile);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingGoogle = false);
      if (AuthErrorFormatter.isProviderDisabledError(e)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AuthErrorFormatter.format(e)),
            backgroundColor: Colors.orangeAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        await _showQuickGoogleLinkDialog(cubit, profile);
      }
    }
  }

  Future<void> _showQuickGoogleLinkDialog(AuthCubit cubit, UserProfile profile) async {
    final emailCtrl = TextEditingController();
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    final linked = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF161922),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: accent.withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text(
                'G',
                style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Вход через Google',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Укажите ваш Google Email. Весь ваш список аниме, история просмотра и никнейм (${profile.username}) сохранятся!',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'name@gmail.com',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.alternate_email_rounded, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.strokeMedium),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.strokeMedium),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: accent, width: 1.4),
                ),
              ),
              onSubmitted: (_) async {
                final email = emailCtrl.text.trim();
                if (email.contains('@')) {
                  await cubit.linkGoogleAccount(
                    email: email,
                    displayName: profile.username,
                    photoUrl: profile.avatarUrl,
                  );
                  if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final email = emailCtrl.text.trim();
              if (!email.contains('@')) return;
              await cubit.linkGoogleAccount(
                email: email,
                displayName: profile.username,
                photoUrl: profile.avatarUrl,
              );
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
            },
            child: const Text('Продолжить', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (linked == true && mounted) {
      await _completeAuthentication();
    }
  }

  Future<void> _openEmailRegistration({int initialTabIndex = 1}) async {
    final profile = PaiChanAuthGate.resolveCurrentProfile(context, fallback: widget.currentProfile);
    final rootCtx = Navigator.of(context, rootNavigator: true).context;

    if (!widget.isEmbedded && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    }

    await AuthModalSheet.show(
      rootCtx,
      profile,
      initialTabIndex: initialTabIndex,
      onSuccess: () {
        widget.onAuthenticated?.call();
      },
    );
  }

  Future<void> _completeAuthentication() async {
    final rootCtx = Navigator.of(context, rootNavigator: true).context;
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    if (!widget.isEmbedded && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }

    widget.onAuthenticated?.call();

    await PendingInviteStorage.resolvePendingActionsAfterAuth(
      rootCtx,
      accentColor: accent,
      onFriendsChanged: widget.onAuthenticated,
    );
  }

  void _handleDismiss() {
    if (widget.onDismiss != null) {
      widget.onDismiss!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentColor ?? scheme.primary;
    final hasPendingInvite = (widget.pendingInviteCode != null && widget.pendingInviteCode!.isNotEmpty) ||
        (PendingInviteStorage.pendingInviteCode != null &&
            PendingInviteStorage.pendingInviteCode!.isNotEmpty);
    final effectiveNotice = widget.customNotice ??
        (hasPendingInvite ? 'Почти готово! Войди в аккаунт, чтобы добавить этого друга' : null);

    final content = SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: widget.isEmbedded ? 20 : 24,
        vertical: widget.isEmbedded ? 18 : 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.isEmbedded) ...[
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],

          // Мягкое неоновое свечение за маскотом Пай-тян
          Container(
            width: 156,
            height: 156,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.24),
                  accent.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
            alignment: Alignment.center,
            child: const SyncPaiMascot(
              state: MascotState.inviteFriends,
              size: MascotSize.small,
              animated: false,
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 14),

          if (effectiveNotice != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_2_rounded, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      effectiveNotice,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Заголовок
          Text(
            'Хочешь добавлять друзей?',
            textAlign: TextAlign.center,
            style: AppTypography.titleLarge.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),

          // Описание с гарантией сохранения прогресса
          Text(
            'Чтобы отправлять заявки, делиться своим QR-кодом и сохранять друзей между телефоном и ПК, нужен аккаунт. Весь твой текущий список аниме и история просмотра сохранятся!',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),

          // 1. Primary CTA: Войти через Google
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isSubmittingGoogle ? null : _handleGoogleSignIn,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isSubmittingGoogle
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'G',
                        style: TextStyle(
                          color: Color(0xFF4285F4),
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
              label: const Text(
                'Войти через Google',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // 2. Secondary CTA: Регистрация по Email
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () => _openEmailRegistration(initialTabIndex: 1),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(Icons.alternate_email_rounded, size: 18, color: accent),
              label: const Text(
                'Регистрация по Email',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3. Dismiss Action: Позже
          TextButton(
            onPressed: _handleDismiss,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'Позже',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (widget.isEmbedded) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: content,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161F) : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: content,
    );
  }
}

