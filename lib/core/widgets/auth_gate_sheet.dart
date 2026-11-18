import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// Единый аккуратный bottom-sheet для гостевых ограничений (вместо тихих отказов).
class AuthGateSheet {
  static Future<void> show(
    BuildContext context, {
    String? customSubtitle,
  }) async {
    final themePrimary = Theme.of(context).colorScheme.primary;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF12161F),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: themePrimary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.lock_person_rounded,
                          color: themePrimary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Требуется профиль SyncPai',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    customSubtitle ??
                        'Войдите через Google или Email за 5 секунд, чтобы смотреть аниме с друзьями, сохранять облачный прогресс и открывать достижения.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    key: const ValueKey('auth_gate_login_btn'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themePrimary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      context.push('/auth');
                    },
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text(
                      'Войти в аккаунт',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                    child: const Text(
                      'Позже',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
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
}

