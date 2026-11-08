import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Генеративный голографический аватар-монограмма из матового стекла (Glassmorphism)
/// с инициалами/символом клана и анимированным радужным градиентным переливом.
class HolographicMonogramAvatar extends StatefulWidget {
  final String text;
  final double size;
  final Color? accentColor;
  final bool animate;

  const HolographicMonogramAvatar({
    super.key,
    required this.text,
    required this.size,
    this.accentColor,
    this.animate = true,
  });

  @override
  State<HolographicMonogramAvatar> createState() => _HolographicMonogramAvatarState();
}

class _HolographicMonogramAvatarState extends State<HolographicMonogramAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (widget.animate && !isTest) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant HolographicMonogramAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (widget.animate && !isTest) {
      if (!_animController.isAnimating) _animController.repeat();
    } else {
      if (_animController.isAnimating) _animController.stop();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.text.isNotEmpty
        ? widget.text.trim()[0].toUpperCase()
        : 'S';
    final primary = widget.accentColor ?? const Color(0xFF00E5FF);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          final t = _animController.value;
          final angle = t * 2 * math.pi;

          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [
                  primary,
                  const Color(0xFFE040FB),
                  const Color(0xFFFF5252),
                  const Color(0xFF00E5FF),
                  primary,
                ],
                transform: GradientRotation(angle),
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF101216).withValues(alpha: 0.92),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 0.8,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: widget.size * 0.44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    foreground: Paint()
                      ..shader = LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: const [
                          Colors.white,
                          Color(0xFFE0E0E0),
                          Color(0xFFB0BEC5),
                        ],
                        transform: GradientRotation(angle),
                      ).createShader(Rect.fromLTWH(0, 0, widget.size, widget.size)),
                    shadows: [
                      Shadow(
                        color: primary.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

