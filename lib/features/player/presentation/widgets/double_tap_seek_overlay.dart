import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_typography.dart';

enum _GestureType { none, brightness, volume, scrub }

/// Премиум слой управления жестами:
/// 1. Свайп по левой стороне — плавная регулировка яркости (0.05..1.0) с затемнением и индикатором-солнцем.
/// 2. Свайп по правой стороне — плавная регулировка громкости (0..100) с индикатором-динамиком.
/// 3. Горизонтальный свайп в любой точке — покадровая перемотка со всплывающей плашкой времени и дельтой (+0:30, 12:45 / 24:00).
/// 4. Умный двойной тап:
///    - Слева: перемотка назад на 10 сек (накапливается: -10, -20, -30).
///    - Справа: перемотка вперед на 10 сек (+10, +20, +30).
///    - По центру: мгновенная пауза / воспроизведение с пульсирующей иконкой.
/// 5. Одиночный тап: скрытие/показ контролов.
/// 6. Удержание (Long Press): режим 2X быстрой перемотки.
class DoubleTapSeekOverlay extends StatefulWidget {
  final VoidCallback onTap;
  final ValueChanged<int> onSeekRelative;
  final VoidCallback? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  final VoidCallback? onCenterDoubleTap;
  final ValueChanged<double>? onBrightnessChanged;
  final ValueChanged<double>? onVolumeChanged;
  final ValueChanged<Duration>? onScrubSeek;
  final Duration currentPosition;
  final Duration totalDuration;
  final double currentVolume;
  final double currentBrightness;

  const DoubleTapSeekOverlay({
    super.key,
    required this.onTap,
    required this.onSeekRelative,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onCenterDoubleTap,
    this.onBrightnessChanged,
    this.onVolumeChanged,
    this.onScrubSeek,
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.currentVolume = 100.0,
    this.currentBrightness = 1.0,
  });

  @override
  State<DoubleTapSeekOverlay> createState() => _DoubleTapSeekOverlayState();
}

class _DoubleTapSeekOverlayState extends State<DoubleTapSeekOverlay> with SingleTickerProviderStateMixin {
  int? _seekIndicatorSeconds;
  bool _isLeft = false;
  Timer? _dismissTimer;

  // Жестовые индикаторы
  _GestureType _activeGesture = _GestureType.none;
  late double _brightness;
  late double _volume;
  Timer? _hudDismissTimer;

  // Покадровая перемотка (Scrub)
  Duration _scrubStartPosition = Duration.zero;
  Duration _scrubTargetPosition = Duration.zero;

  // Пульсация центрального тапа (Play/Pause)
  bool _showCenterPulse = false;
  Timer? _centerPulseTimer;

  @override
  void initState() {
    super.initState();
    _brightness = widget.currentBrightness;
    _volume = widget.currentVolume;
  }

  @override
  void didUpdateWidget(covariant DoubleTapSeekOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentBrightness != oldWidget.currentBrightness && _activeGesture != _GestureType.brightness) {
      _brightness = widget.currentBrightness;
    }
    if (widget.currentVolume != oldWidget.currentVolume && _activeGesture != _GestureType.volume) {
      _volume = widget.currentVolume;
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _hudDismissTimer?.cancel();
    _centerPulseTimer?.cancel();
    super.dispose();
  }

  void _triggerSeek(int seconds, bool left) {
    widget.onSeekRelative(seconds);
    _dismissTimer?.cancel();
    setState(() {
      _seekIndicatorSeconds = (_seekIndicatorSeconds ?? 0) + seconds;
      _isLeft = left;
    });
    _dismissTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _seekIndicatorSeconds = null;
        });
      }
    });
  }

  void _triggerCenterDoubleTap() {
    widget.onCenterDoubleTap?.call();
    _centerPulseTimer?.cancel();
    setState(() => _showCenterPulse = true);
    _centerPulseTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showCenterPulse = false);
    });
  }

  void _startHudDismiss() {
    _hudDismissTimer?.cancel();
    _hudDismissTimer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) {
        setState(() {
          _activeGesture = _GestureType.none;
        });
      }
    });
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final height = size.height;

    // Вычисляем дельту покадровой перемотки
    final scrubDeltaSec = _scrubTargetPosition.inSeconds - _scrubStartPosition.inSeconds;
    final scrubSign = scrubDeltaSec >= 0 ? '+' : '';
    final deltaStr = '$scrubSign$scrubDeltaSec с';

    return Stack(
      children: [
        // 1. Аппаратное / визуальное затемнение при регулировке яркости
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              color: Colors.black.withValues(alpha: ((1.0 - _brightness) * 0.85).clamp(0.0, 0.85)),
            ),
          ),
        ),

        // 2. Детектор жестов свайпа по вертикали (яркость/громкость) и горизонтали (покадровая перемотка)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (details) {
              final x = details.localPosition.dx;
              if (x < width * 0.45) {
                setState(() => _activeGesture = _GestureType.brightness);
              } else if (x > width * 0.55) {
                setState(() => _activeGesture = _GestureType.volume);
              }
            },
            onVerticalDragUpdate: (details) {
              if (_activeGesture == _GestureType.brightness) {
                final delta = -details.primaryDelta! / (height * 0.7);
                final newB = (_brightness + delta).clamp(0.05, 1.0);
                setState(() => _brightness = newB);
                widget.onBrightnessChanged?.call(newB);
              } else if (_activeGesture == _GestureType.volume) {
                final delta = (-details.primaryDelta! / (height * 0.7)) * 100.0;
                final newV = (_volume + delta).clamp(0.0, 100.0);
                setState(() => _volume = newV);
                widget.onVolumeChanged?.call(newV);
              }
            },
            onVerticalDragEnd: (_) => _startHudDismiss(),
            onHorizontalDragStart: (details) {
              setState(() {
                _activeGesture = _GestureType.scrub;
                _scrubStartPosition = widget.currentPosition;
                _scrubTargetPosition = widget.currentPosition;
              });
            },
            onHorizontalDragUpdate: (details) {
              if (_activeGesture == _GestureType.scrub) {
                final totalSec = widget.totalDuration.inSeconds;
                final scale = totalSec > 1200 ? 0.35 : 0.2;
                final addedSec = (details.primaryDelta! * scale).round();
                final currentTargetSec = _scrubTargetPosition.inSeconds + addedSec;
                final clampedSec = currentTargetSec.clamp(0, totalSec);
                setState(() {
                  _scrubTargetPosition = Duration(seconds: clampedSec);
                });
              }
            },
            onHorizontalDragEnd: (_) {
              if (_activeGesture == _GestureType.scrub) {
                widget.onScrubSeek?.call(_scrubTargetPosition);
                Timer(const Duration(milliseconds: 350), () {
                  if (mounted) {
                    setState(() => _activeGesture = _GestureType.none);
                  }
                });
              }
            },
          ),
        ),

        // 3. 3-зонный детектор умных тапов (Лево: -10с, Центр: Play/Pause, Право: +10с)
        Positioned.fill(
          child: Row(
            children: [
              // Левая зона: перемотка назад на 10 сек
              Expanded(
                flex: 3,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onTap,
                  onDoubleTap: () => _triggerSeek(-10, true),
                  onLongPressStart: (_) => widget.onLongPressStart?.call(),
                  onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
                  onLongPressCancel: () => widget.onLongPressEnd?.call(),
                ),
              ),

              // Центральная зона: воспроизведение / пауза
              Expanded(
                flex: 4,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onTap,
                  onDoubleTap: _triggerCenterDoubleTap,
                  onLongPressStart: (_) => widget.onLongPressStart?.call(),
                  onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
                  onLongPressCancel: () => widget.onLongPressEnd?.call(),
                ),
              ),

              // Правая зона: перемотка вперед на 10 сек
              Expanded(
                flex: 3,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: widget.onTap,
                  onDoubleTap: () => _triggerSeek(10, false),
                  onLongPressStart: (_) => widget.onLongPressStart?.call(),
                  onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
                  onLongPressCancel: () => widget.onLongPressEnd?.call(),
                ),
              ),
            ],
          ),
        ),

        // 4. Стеклянный индикатор ЯРКОСТИ слева
        if (_activeGesture == _GestureType.brightness)
          Positioned(
            left: 32,
            top: height * 0.25,
            bottom: height * 0.25,
            child: _buildVerticalSliderHud(
              icon: _brightness > 0.6 ? Icons.wb_sunny_rounded : Icons.brightness_medium_rounded,
              value: _brightness,
              label: '${(_brightness * 100).round()}%',
              isSun: true,
            ),
          ),

        // 5. Стеклянный индикатор ГРОМКОСТИ справа
        if (_activeGesture == _GestureType.volume)
          Positioned(
            right: 32,
            top: height * 0.25,
            bottom: height * 0.25,
            child: _buildVerticalSliderHud(
              icon: _volume <= 0
                  ? Icons.volume_mute_rounded
                  : _volume < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              value: _volume / 100.0,
              label: '${_volume.round()}%',
              isSun: false,
            ),
          ),

        // 6. Стеклянная плашка ПОКАДРОВОЙ ПЕРЕМОТКИ по центру (YouTube/Netflix style)
        if (_activeGesture == _GestureType.scrub)
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            scrubDeltaSec >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                            color: scrubDeltaSec >= 0 ? Theme.of(context).colorScheme.primary : const Color(0xFFFF9800),
                            size: 28,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            deltaStr,
                            style: TextStyle(
                              color: scrubDeltaSec >= 0 ? Theme.of(context).colorScheme.primary : const Color(0xFFFF9800),
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_formatDuration(_scrubTargetPosition)} / ${_formatDuration(widget.totalDuration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Мини-таймлайн прогресса
                      SizedBox(
                        width: 140,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: widget.totalDuration.inSeconds > 0
                                ? (_scrubTargetPosition.inSeconds / widget.totalDuration.inSeconds).clamp(0.0, 1.0)
                                : 0.0,
                            minHeight: 4,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // 7. Анимированный индикатор двойного тапа (±10 сек)
        if (_seekIndicatorSeconds != null)
          Positioned(
            left: _isLeft ? 40 : null,
            right: !_isLeft ? 40 : null,
            top: 0,
            bottom: 0,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_seekIndicatorSeconds! > 0 ? '+' : ''}$_seekIndicatorSeconds сек',
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        // 8. Пульсирующая иконка при двойном тапе по центру (Play / Pause)
        if (_showCenterPulse)
          Center(
            child: AnimatedScale(
              scale: _showCenterPulse ? 1.15 : 0.8,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVerticalSliderHud({
    required IconData icon,
    required double value,
    required String label,
    required bool isSun,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          width: 48,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 10),
              // Вертикальный прогресс-бар
              Expanded(
                child: Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: isSun
                              ? [const Color(0xFFFFB300), const Color(0xFFFFE082)]
                              : [Theme.of(context).colorScheme.primary, const Color(0xFF64B5F6)],
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
