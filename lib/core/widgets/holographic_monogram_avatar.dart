import 'package:flutter/material.dart';

/// Элегантный чистый аватар-монограмма по умолчанию на темной поверхности
/// без навязчивого радужного неонового кольца (Nordic Dark).
class HolographicMonogramAvatar extends StatelessWidget {
  final String text;
  final double size;
  final Color? accentColor;
  final bool animate;

  const HolographicMonogramAvatar({
    super.key,
    required this.text,
    required this.size,
    this.accentColor,
    this.animate = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = text.isNotEmpty ? text.trim()[0].toUpperCase() : 'S';

    return Container(
      width: size,
      height: size,
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
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: size * 0.44,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
