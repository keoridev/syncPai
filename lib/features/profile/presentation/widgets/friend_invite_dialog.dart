import 'package:flutter/material.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../services/friends_service.dart';

/// Диалог подтверждения добавления в друзья при сканировании QR-кода или переходе по Deep Link
class FriendInviteConfirmationDialog extends StatefulWidget {
  final String inviteCode;
  final Color accentColor;
  final VoidCallback? onAccepted;

  const FriendInviteConfirmationDialog({
    super.key,
    required this.inviteCode,
    required this.accentColor,
    this.onAccepted,
  });

  static Future<void> show(
    BuildContext context, {
    required String inviteCode,
    Color? accentColor,
    VoidCallback? onAccepted,
  }) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;

    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: FriendInviteConfirmationDialog(
            inviteCode: inviteCode,
            accentColor: accent,
            onAccepted: onAccepted,
          ),
        ),
      ),
    );
  }

  @override
  State<FriendInviteConfirmationDialog> createState() => _FriendInviteConfirmationDialogState();
}

class _FriendInviteConfirmationDialogState extends State<FriendInviteConfirmationDialog> {
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  Map<String, dynamic>? _resolvedData;

  @override
  void initState() {
    super.initState();
    _loadInviteInfo();
  }

  Future<void> _loadInviteInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final data = await FriendsService.resolveInvite(widget.inviteCode);
    if (!mounted) return;

    if (data == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Приглашение не найдено или ссылка повреждена.';
      });
      return;
    }

    if (data['isExpired'] == true) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Срок действия этой ссылки-приглашения истек.';
      });
      return;
    }

    if (data['isLimitReached'] == true) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Лимит использований этой ссылки уже исчерпан.';
      });
      return;
    }

    setState(() {
      _resolvedData = data;
      _isLoading = false;
    });
  }

  Future<void> _acceptInvite() async {
    setState(() => _isSubmitting = true);
    final result = await FriendsService.acceptInvite(widget.inviteCode);
    if (!mounted) return;

    if (result['success'] == true) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      widget.onAccepted?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Заявка в друзья успешно отправлена!'),
          backgroundColor: const Color(0xFF00FF66).withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Не удалось принять приглашение'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentColor;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161822) : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_add_rounded, color: accent, size: 36),
          ),
          const SizedBox(height: 18),

          Text(
            'Приглашение в друзья',
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 6),

          if (_isLoading) ...[
            const SizedBox(height: 30),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Получение информации...', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 20),
          ] else if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHighest,
                  foregroundColor: scheme.onSurface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Закрыть'),
              ),
            ),
          ] else ...[
            Text(
              'Пользователь приглашает вас стать друзьями в SyncPai:',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // User Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  AppAvatar(
                    avatarUrl: _resolvedData?['avatarUrl'] as String?,
                    username: _resolvedData?['username'] as String? ?? 'User',
                    size: 48,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _resolvedData?['username'] as String? ?? 'Пользователь',
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              _resolvedData?['tag'] as String? ?? '',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        if (_resolvedData?['friendCode'] != null)
                          Text(
                            'Код: ${_resolvedData!['friendCode']}',
                            style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        if (_resolvedData?['customStatus'] != null)
                          Text(
                            _resolvedData!['customStatus'] as String,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurfaceVariant,
                      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Отклонить'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _acceptInvite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

