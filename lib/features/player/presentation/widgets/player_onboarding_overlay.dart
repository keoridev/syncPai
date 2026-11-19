import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Интерактивный 4-шаговый hands-on гид по жестам плеера (Mobile-only).
/// Пропускает касания к живому плееру, чтобы пользователь сам попробовал каждый жест.
class PlayerOnboardingOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final ValueChanged<int>? onStepChanged;

  const PlayerOnboardingOverlay({
    super.key,
    required this.onDismiss,
    this.onStepChanged,
  });

  @override
  State<PlayerOnboardingOverlay> createState() =>
      PlayerOnboardingOverlayState();
}

class PlayerOnboardingOverlayState extends State<PlayerOnboardingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _loopCtrl;
  int _currentStep = 0;
  bool _dismissing = false;
  Timer? _autoAdvanceTimer;

  static const int _totalSteps = 4;
  static const Color _cyan = Color(0xFF35D9D5);

  int get currentStep => _currentStep;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onStepChanged?.call(_currentStep);
    });
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _fadeCtrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  /// Вызывается из PlayerScreen, когда пользователь реально свайпнул яркость слева.
  void notifyBrightnessSwiped() {
    if (_currentStep != 0) return;
    _scheduleAutoAdvance(toStep: 1);
  }

  /// Вызывается из PlayerScreen, когда пользователь реально свайпнул громкость справа.
  void notifyVolumeSwiped() {
    if (_currentStep != 1) return;
    _scheduleAutoAdvance(toStep: 2);
  }

  /// Вызывается из PlayerScreen, когда пользователь реально сделал двойной тап ±10с.
  void notifySeekDoubleTapped() {
    if (_currentStep != 2) return;
    _scheduleAutoAdvance(toStep: 3);
  }

  void _scheduleAutoAdvance({required int toStep}) {
    if (_autoAdvanceTimer?.isActive ?? false) return;
    _autoAdvanceTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _dismissing) return;
      if (_currentStep < toStep) {
        setState(() => _currentStep = toStep);
        widget.onStepChanged?.call(_currentStep);
      }
    });
  }

  Future<void> _handleDismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _autoAdvanceTimer?.cancel();
    _loopCtrl.stop();
    await _fadeCtrl.reverse();
    widget.onDismiss();
  }

  void _nextStep() {
    _autoAdvanceTimer?.cancel();
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      widget.onStepChanged?.call(_currentStep);
    } else {
      _handleDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final zoneWidth = size.width * 0.35;

    final (title, subtitle) = switch (_currentStep) {
      0 => (
          'Яркость — свайп слева',
          'Потяните вверх или вниз в левой зоне экрана',
        ),
      1 => (
          'Громкость — свайп справа',
          'Потяните вверх или вниз в правой зоне экрана',
        ),
      2 => (
          'Перемотка ±10с — двойной тап',
          'Дважды нажмите слева или справа для перемотки',
        ),
      _ => (
          'Следующая серия и настройки ⚙️',
          'Используйте кнопки HUD для серий и кастомизации',
        ),
    };

    return FadeTransition(
      opacity: _fadeCtrl,
      child: Stack(
        key: const ValueKey('player_onboarding_backdrop'),
        fit: StackFit.expand,
        children: [
          // Шаг 1: Левая 35% зона (Яркость) — полностью прозрачна для касаний!
          if (_currentStep == 0)
            Positioned(
              key: const ValueKey('onboarding_zone_brightness'),
              left: 0,
              top: 0,
              bottom: 0,
              width: zoneWidth,
              child: IgnorePointer(
                child: _SwipeZoneSpotlight(
                  animation: _loopCtrl,
                  icon: Icons.brightness_6_rounded,
                  accent: const Color(0xFFFFD54F),
                  isLeft: true,
                ),
              ),
            ),

          // Шаг 2: Правая 35% зона (Громкость) — полностью прозрачна для касаний!
          if (_currentStep == 1)
            Positioned(
              key: const ValueKey('onboarding_zone_volume'),
              right: 0,
              top: 0,
              bottom: 0,
              width: zoneWidth,
              child: IgnorePointer(
                child: _SwipeZoneSpotlight(
                  animation: _loopCtrl,
                  icon: Icons.volume_up_rounded,
                  accent: _cyan,
                  isLeft: false,
                ),
              ),
            ),

          // Шаг 3: Двойной тап ±10с — пропускает касания к DoubleTapSeekOverlay!
          if (_currentStep == 2) ...[
            Positioned(
              key: const ValueKey('onboarding_zone_seek_left'),
              left: size.width * 0.08,
              top: size.height * 0.36,
              child: IgnorePointer(
                child: _DoubleTapRipple(
                  animation: _loopCtrl,
                  label: '-10с',
                  icon: Icons.replay_10_rounded,
                ),
              ),
            ),
            Positioned(
              key: const ValueKey('onboarding_zone_seek_right'),
              right: size.width * 0.08,
              top: size.height * 0.36,
              child: IgnorePointer(
                child: _DoubleTapRipple(
                  animation: _loopCtrl,
                  label: '+10с',
                  icon: Icons.forward_10_rounded,
                ),
              ),
            ),
          ],

          // Шаг 4: Подсветка кнопок HUD (next_episode и settings_gear)
          if (_currentStep == 3) ...[
            Positioned(
              key: const ValueKey('onboarding_zone_hud_settings'),
              top: MediaQuery.paddingOf(context).top + 10,
              right: 14,
              child: IgnorePointer(
                child: _HudRingSpotlight(
                  animation: _loopCtrl,
                  icon: Icons.settings_rounded,
                  label: '⚙️ Настройки',
                ),
              ),
            ),
            Positioned(
              key: const ValueKey('onboarding_zone_hud_episodes'),
              right: 16,
              bottom: 54,
              child: IgnorePointer(
                child: _HudRingSpotlight(
                  animation: _loopCtrl,
                  icon: Icons.skip_next_rounded,
                  label: 'След. серия',
                ),
              ),
            ),
          ],

          // Компактный плавающий стеклянный баннер (maxHeight: 130px)
          SafeArea(
            child: Align(
              alignment: _currentStep == 3
                  ? Alignment.center
                  : Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 440,
                    maxHeight: 130,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      key: const ValueKey('player_onboarding_pill_banner'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF12161F).withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: _cyan.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                key: const ValueKey('player_onboarding_step_counter'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _cyan.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_currentStep + 1} / $_totalSteps',
                                  style: const TextStyle(
                                    color: _cyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              TextButton(
                                key: const ValueKey('player_onboarding_skip_btn'),
                                onPressed: _handleDismiss,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white60,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Пропустить',
                                  style: TextStyle(fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                key: ValueKey(
                                  _currentStep < _totalSteps - 1
                                      ? 'player_onboarding_next_btn'
                                      : 'player_onboarding_dismiss_btn',
                                ),
                                onPressed: _nextStep,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _cyan,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  _currentStep < _totalSteps - 1
                                      ? 'Далее'
                                      : 'Готово',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeZoneSpotlight extends StatelessWidget {
  final Animation<double> animation;
  final IconData icon;
  final Color accent;
  final bool isLeft;

  const _SwipeZoneSpotlight({
    required this.animation,
    required this.icon,
    required this.accent,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            accent.withValues(alpha: 0.22),
            accent.withValues(alpha: 0.04),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final dy = (animation.value - 0.5) * 44;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: accent.withValues(alpha: 0.9),
                  size: 28,
                ),
                const SizedBox(height: 4),
                Transform.translate(
                  offset: Offset(0, dy),
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.22),
                      border: Border.all(color: accent, width: 2),
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: accent.withValues(alpha: 0.9),
                  size: 28,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DoubleTapRipple extends StatelessWidget {
  final Animation<double> animation;
  final String label;
  final IconData icon;

  const _DoubleTapRipple({
    required this.animation,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final scale = 0.92 + 0.14 * animation.value;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF35D9D5).withValues(alpha: 0.18),
              border: Border.all(
                color: const Color(0xFF35D9D5).withValues(alpha: 0.85),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HudRingSpotlight extends StatelessWidget {
  final Animation<double> animation;
  final IconData icon;
  final String label;

  const _HudRingSpotlight({
    required this.animation,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    const cyan = Color(0xFF35D9D5);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final pulse = 0.5 + 0.5 * animation.value;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: cyan.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cyan.withValues(alpha: 0.65 + 0.35 * pulse),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: cyan.withValues(alpha: 0.35 * pulse),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: cyan, size: 16),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
