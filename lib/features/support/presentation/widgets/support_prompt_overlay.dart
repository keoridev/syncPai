import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../domain/entities/supporter_tier.dart';
import '../../services/session_support_timer_service.dart';

/// Ненавязчивая карточка Пай-тян, появляющаяся после 30 минут активного использования
/// для пользователей базового уровня (не блокирует клики и видеоплеер).
class SupportPromptOverlay extends StatefulWidget {
  final SessionSupportTimerService? service;
  final VoidCallback? onOpenSupport;

  const SupportPromptOverlay({
    super.key,
    this.service,
    this.onOpenSupport,
  });

  @override
  State<SupportPromptOverlay> createState() => _SupportPromptOverlayState();
}

class _SupportPromptOverlayState extends State<SupportPromptOverlay> {
  SessionSupportTimerService get _service =>
      widget.service ?? SessionSupportTimerService.instance;

  @override
  void initState() {
    super.initState();
    _service.start();
  }

  @override
  Widget build(BuildContext context) {
    SupporterTier tier = SupporterTier.free;
    try {
      final authState = context.watch<AuthCubit>().state;
      if (authState is Authenticated) {
        tier = authState.profile.supporterTier;
      }
    } catch (_) {}

    if (_service.supporterTier != tier) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _service.updateSupporterTier(tier);
        }
      });
    }

    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final visible = _service.shouldShowPrompt;
        return Positioned(
          right: isDesktop ? 20 : 16,
          left: isDesktop ? null : 16,
          bottom: 20,
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedSlide(
              offset: visible ? Offset.zero : const Offset(0, 0.25),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 240),
                child: Align(
                  alignment: isDesktop ? Alignment.bottomRight : Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10131C).withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Image.asset(
                                'assets/stickers/pai_love.png',
                                width: 48,
                                height: 48,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Нравится смотреть в SyncPai? Буду рада, если поддержишь проект — откроются рамки и кастомные арты для профиля.',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        height: 1.35,
                                        decoration: TextDecoration.none,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        FilledButton(
                                          key: const ValueKey('support_prompt_view_btn'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: const Color(0xFF22D3EE),
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
                                          onPressed: () async {
                                            await _service.markOpenedSupport();
                                            if (widget.onOpenSupport != null) {
                                              widget.onOpenSupport!();
                                            } else {
                                              appRouter.push('/support');
                                            }
                                          },
                                          child: const Text(
                                            'Посмотреть',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        TextButton(
                                          key: const ValueKey('support_prompt_later_btn'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppColors.textSecondary,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          onPressed: () => _service.snoozeFor72Hours(),
                                          child: const Text(
                                            'Позже',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
