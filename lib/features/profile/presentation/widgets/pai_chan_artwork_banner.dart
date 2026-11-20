import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Виджет фирменных художественных витрин Пай-тян (Pai-chan Mascot Artwork Showcases)
/// для профиля Steam Showcase (`pai_chill`, `pai_winter`, `pai_celebrate`, `pai_hacker_art`).
class PaiChanArtworkBanner extends StatelessWidget {
  final String artworkId;
  final double width;
  final double height;
  final bool isSelected;

  const PaiChanArtworkBanner({
    super.key,
    required this.artworkId,
    required this.width,
    required this.height,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (artworkId) {
      case 'pai_winter':
        return _buildWinterBanner();
      case 'pai_celebrate':
        return _buildCelebrateBanner();
      case 'pai_hacker_art':
        return _buildHackerBanner();
      case 'pai_chill':
      default:
        return _buildChillBanner();
    }
  }

  // --- 1. ПАЙ-ТЯН • НОЧНОЙ МАРАФОН (pai_chill — Free) ---
  Widget _buildChillBanner() {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF070B16),
            Color(0xFF131A33),
            Color(0xFF241542),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Луна и звездное свечение
          Positioned(
            top: -height * 0.2,
            right: -width * 0.05,
            child: Container(
              width: height * 0.85,
              height: height * 0.85,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF90E0EF).withValues(alpha: 0.35),
                    const Color(0xFF6A0DAD).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. Иероглиф «Ночь» (夜) на заднем плане
          Positioned(
            right: 18,
            top: 10,
            child: Text(
              '夜',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: math.min(height * 0.55, 64),
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.07),
                letterSpacing: 2,
              ),
            ),
          ),

          // 3. Маскот Пай-тян (сонная / чилловая)
          Positioned(
            right: 14,
            bottom: 4,
            child: SizedBox(
              width: math.min(width * 0.38, 100),
              height: math.min(height * 0.78, 100),
              child: Image.asset(
                'assets/mascot/general/mascot_sleeping.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/stickers/pai_sleepy.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.bedtime_rounded,
                    color: Color(0xFF90E0EF),
                    size: 38,
                  ),
                ),
              ),
            ),
          ),

          // 4. Текстовый заголовок и теглайн витрины
          Positioned(
            left: 14,
            bottom: 12,
            right: width * 0.42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF35D9D5).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF35D9D5).withValues(alpha: 0.4),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'LOFI CHILL // FREE',
                    style: TextStyle(
                      color: Color(0xFF35D9D5),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Ночной марафон',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. ЗИМНЯЯ ПАЙ-ТЯН 2026 (pai_winter — Free) ---
  Widget _buildWinterBanner() {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF07192C),
            Color(0xFF0F3255),
            Color(0xFF1B4965),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Зимнее ледяное сияние
          Positioned(
            top: -height * 0.25,
            left: width * 0.1,
            child: Container(
              width: height * 0.9,
              height: height * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF80D8FF).withValues(alpha: 0.28),
                    const Color(0xFF00E5FF).withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. Иероглиф «Зима» (冬)
          Positioned(
            right: 18,
            top: 10,
            child: Text(
              '冬',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: math.min(height * 0.55, 64),
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.08),
                letterSpacing: 2,
              ),
            ),
          ),

          // 3. Зимняя Пай-тян в шарфике
          Positioned(
            right: 12,
            bottom: 4,
            child: SizedBox(
              width: math.min(width * 0.38, 100),
              height: math.min(height * 0.78, 100),
              child: Image.asset(
                'assets/mascot/winter/mascot_winter_happy.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/mascot/winter/mascot_winter_welcome.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.ac_unit_rounded,
                    color: Color(0xFF80D8FF),
                    size: 38,
                  ),
                ),
              ),
            ),
          ),

          // 4. Текстовый заголовок
          Positioned(
            left: 14,
            bottom: 12,
            right: width * 0.42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.45),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'WINTER 2026 // FREE',
                    style: TextStyle(
                      color: Color(0xFF80D8FF),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Зимняя Пай-тян',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 3. ПАЙ-ТЯН • АБСОЛЮТ КИНО (pai_celebrate — Plus) ---
  Widget _buildCelebrateBanner() {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF260538),
            Color(0xFF560059),
            Color(0xFFFF007F),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Золотисто-пурпурное неоновое свечение софитов
          Positioned(
            top: -height * 0.3,
            right: width * 0.1,
            child: Container(
              width: height * 0.95,
              height: height * 0.95,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFD700).withValues(alpha: 0.3),
                    const Color(0xFFFF007F).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. Иероглиф «Кино» (映)
          Positioned(
            right: 18,
            top: 10,
            child: Text(
              '映',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: math.min(height * 0.55, 64),
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.1),
                letterSpacing: 2,
              ),
            ),
          ),

          // 3. Празднующая Пай-тян
          Positioned(
            right: 12,
            bottom: 4,
            child: SizedBox(
              width: math.min(width * 0.38, 100),
              height: math.min(height * 0.78, 100),
              child: Image.asset(
                'assets/stickers/pai_hype.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/mascot/loading_success/mascot_success.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFFFFD700),
                    size: 38,
                  ),
                ),
              ),
            ),
          ),

          // 4. Текстовый заголовок
          Positioned(
            left: 14,
            bottom: 12,
            right: width * 0.42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'PLUS EXCLUSIVE // HERO',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Абсолют кино',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 4. ПАЙ-ТЯН • КОДИНГ-ХАКЕР (pai_hacker_art — Bug Hunter) ---
  Widget _buildHackerBanner() {
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF01140A),
            Color(0xFF052B16),
            Color(0xFF0B4626),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Изумрудное свечение матрицы
          Positioned(
            top: -height * 0.2,
            right: width * 0.05,
            child: Container(
              width: height * 0.9,
              height: height * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF00FF87).withValues(alpha: 0.25),
                    const Color(0xFF00F0FF).withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 2. Иероглиф «Электроника / Код» (電)
          Positioned(
            right: 18,
            top: 10,
            child: Text(
              '電',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: math.min(height * 0.55, 64),
                fontWeight: FontWeight.w900,
                color: const Color(0xFF00FF87).withValues(alpha: 0.09),
                letterSpacing: 2,
              ),
            ),
          ),

          // 3. Хакер Пай-тян
          Positioned(
            right: 14,
            bottom: 4,
            child: SizedBox(
              width: math.min(width * 0.38, 100),
              height: math.min(height * 0.78, 100),
              child: Image.asset(
                'assets/mascot/loading_success/mascot_uploading.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.bug_report_rounded,
                  color: Color(0xFF00FF87),
                  size: 38,
                ),
              ),
            ),
          ),

          // 4. Текстовый заголовок
          Positioned(
            left: 14,
            bottom: 12,
            right: width * 0.42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF87).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF00FF87).withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                  child: const Text(
                    'BUG HUNTER // ROOT',
                    style: TextStyle(
                      color: Color(0xFF00FF87),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Кодинг-хакер',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
