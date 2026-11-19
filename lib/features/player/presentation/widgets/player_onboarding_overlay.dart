import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Интерактивный 4-шаговый визуальный гид по зонам сенсорного управления плеером (Mobile-only).
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
      _PlayerOnboardingOverlayState();
}

class _PlayerOnboardingOverlayState extends State<PlayerOnboardingOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _loopCtrl;
  int _currentStep = 0;
  bool _dismissing = false;

  static const int _totalSteps = 4;
  static const Color _cyan = Color(0xFF35D9D5);

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
    _fadeCtrl.dispose();
    _loopCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _loopCtrl.stop();
    await _fadeCtrl.reverse();
    widget.onDismiss();
  }

  void _nextStep() {
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
          'Яркость экрана',
          'Свайпайте вверх или вниз в левой части экрана, чтобы менять яркость',
        ),
      1 => (
          'Громкость звука',
          'Свайпайте вверх или вниз в правой части экрана, чтобы управлять громкостью',
        ),
      2 => (
          'Быстрая перемотка',
          'Дважды нажмите слева или справа для перемотки на ±10 сек, или тяните шкалу снизу',
        ),
      _ => (
          'Серии и навигация',
          'Здесь можно мгновенно перейти к следующей серии или открыть полный список эпизодов',
        ),
    };

    return FadeTransition(
      opacity: _fadeCtrl,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          key: const ValueKey('player_onboarding_backdrop'),
          fit: StackFit.expand,
          children: [
            // Полупрозрачный тёмный фон поверх видео
            Container(color: Colors.black.withValues(alpha: 0.72)),

            // Шаг 1: Левая 35% зона (Яркость)
            if (_currentStep == 0)
              Positioned(
                key: const ValueKey('onboarding_zone_brightness'),
                left: 0,
                top: 0,
                bottom: 0,
                width: zoneWidth,
                child: _SwipeZoneSpotlight(
                  animation: _loopCtrl,
                  icon: Icons.brightness_6_rounded,
                  accent: const Color(0xFFFFD54F),
                  isLeft: true,
                ),
              ),

            // Шаг 2: Правая 35% зона (Громкость)
            if (_currentStep == 1)
              Positioned(
                key: const ValueKey('onboarding_zone_volume'),
                right: 0,
                top: 0,
                bottom: 0,
                width: zoneWidth,
                child: _SwipeZoneSpotlight(
                  animation: _loopCtrl,
                  icon: Icons.volume_up_rounded,
                  accent: _cyan,
                  isLeft: false,
                ),
              ),

            // Шаг 3: Двойной тап ±10 сек + нижняя шкала перемотки
            if (_currentStep == 2) ...[
              Positioned(
                key: const ValueKey('onboarding_zone_seek_left'),
                left: size.width * 0.08,
                top: size.height * 0.34,
                child: _DoubleTapRipple(
                  animation: _loopCtrl,
                  label: '-10с',
                  icon: Icons.replay_10_rounded,
                ),
              ),
              Positioned(
                key: const ValueKey('onboarding_zone_seek_right'),
                right: size.width * 0.08,
                top: size.height * 0.34,
                child: _DoubleTapRipple(
                  animation: _loopCtrl,
                  label: '+10с',
                  icon: Icons.forward_10_rounded,
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 24,
                child: AnimatedBuilder(
                  animation: _loopCtrl,
                  builder: (context, _) {
                    return Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: _cyan.withValues(alpha: 0.25 + 0.35 * _loopCtrl.value),
                        border: Border.all(
                          color: _cyan.withValues(alpha: 0.8),
                          width: 1.2,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],

            // Шаг 4: Подсветка кнопок HUD (След. серия / Список серий)
            if (_currentStep == 3)
              Positioned(
                key: const ValueKey('onboarding_zone_hud_episodes'),
                right: 18,
                bottom: 58,
                child: AnimatedBuilder(
                  animation: _loopCtrl,
                  builder: (context, _) {
                    final pulse = 0.5 + 0.5 * _loopCtrl.value;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Transform.translate(
                          offset: Offset(0, -6 * _loopCtrl.value),
                          child: const Icon(
                            Icons.arrow_downward_rounded,
                            color: _cyan,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _cyan.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _cyan.withValues(alpha: 0.65 + 0.35 * pulse),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _cyan.withValues(alpha: 0.35 * pulse),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.playlist_play_rounded, color: _cyan, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Список серий  ·  След. серия',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.skip_next_rounded, color: _cyan, size: 18),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

            // Верхняя панель: Счётчик шагов (1 / 4) и кнопка «Пропустить»
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        key: const ValueKey('player_onboarding_step_counter'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF12161F).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Text(
                          '${_currentStep + 1} / $_totalSteps',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('player_onboarding_skip_btn'),
                        onPressed: _handleDismiss,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                        child: const Text(
                          'Пропустить',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Карточка-выноска (Callout) + кнопка «Далее» / «Понятно, смотреть»
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12161F).withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _currentStep < _totalSteps - 1
                                ? 'Далее'
                                : 'Понятно, смотреть',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
                    width: 48,
                    height: 48,
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
            width: 82,
            height: 82,
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
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
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
