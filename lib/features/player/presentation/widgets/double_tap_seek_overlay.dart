import 'dart:async';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/domain/entities/episode_item.dart';

enum _GestureType { none, brightness, volume, scrub }

/// Премиум жестовые зоны плеера (Свайпы, Тапы, Индикаторы):
/// 1. Вертикальный свайп по левой стороне — плавная регулировка яркости (0.05..1.0) с полупрозрачным индикатором-солнцем.
/// 2. Вертикальный свайп по правой стороне — регулировка громкости (0..100) с индикатором-динамиком.
/// 3. Горизонтальный свайп в любой точке — покадровая перемотка со всплывающей плашкой времени, дельты и таймкодов (Опенинг / Эндинг).
/// 4. Умный двойной тап:
///    - Слева: перемотка назад на 10 сек (накапливается: -10, -20, -30 с анимированными стрелками).
///    - Справа: перемотка вперед на 10 сек (+10, +20, +30 с анимированными стрелками).
///    - По центру: пауза / воспроизведение с пульсирующей иконкой.
/// 5. Одиночный тап: скрытие/показ контролов плеера.
/// 6. Удержание (Long Press): режим 2X быстрой перемотки.
/// 7. Все всплывающие индикаторы плавно и автоматически исчезают.
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
  final TimecodeRange? opening;
  final TimecodeRange? ending;
  final String? previewUrl;
  final bool isLocked;
  final VoidCallback? onLockedTap;
  final bool isScreenLocked;
  final VoidCallback? onScreenLockedTap;

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
    this.opening,
    this.ending,
    this.previewUrl,
    this.isLocked = false,
    this.onLockedTap,
    this.isScreenLocked = false,
    this.onScreenLockedTap,
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
    if (widget.isScreenLocked) {
      widget.onScreenLockedTap?.call();
      return;
    }
    if (widget.isLocked) {
      widget.onLockedTap?.call();
      return;
    }
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
    if (widget.isScreenLocked) {
      widget.onScreenLockedTap?.call();
      return;
    }
    widget.onCenterDoubleTap?.call();
    _centerPulseTimer?.cancel();
    setState(() => _showCenterPulse = true);
    _centerPulseTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _showCenterPulse = false);
    });
  }

  void _startHudDismiss() {
    _hudDismissTimer?.cancel();
    _hudDismissTimer = Timer(const Duration(milliseconds: 600), () {
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

  bool _isInsideOpening(Duration pos) {
    final op = widget.opening;
    if (op == null) return false;
    final sec = pos.inSeconds;
    return sec >= op.start && sec <= op.stop;
  }

  bool _isInsideEnding(Duration pos) {
    final ed = widget.ending;
    if (ed == null) return false;
    final sec = pos.inSeconds;
    return sec >= ed.start && sec <= ed.stop;
  }

  void _onHorizontalStart() {
    if (widget.isScreenLocked) {
      widget.onScreenLockedTap?.call();
      return;
    }
    if (widget.isLocked) {
      widget.onLockedTap?.call();
      return;
    }
    _hudDismissTimer?.cancel();
    setState(() {
      _activeGesture = _GestureType.scrub;
      _scrubStartPosition = widget.currentPosition;
      _scrubTargetPosition = widget.currentPosition;
    });
  }

  void _onHorizontalUpdate(DragUpdateDetails details) {
    if (_activeGesture != _GestureType.scrub) return;
    final totalSec = widget.totalDuration.inSeconds;
    final scale = totalSec > 1200 ? 0.35 : 0.22;
    final addedSec = (details.primaryDelta! * scale).round();
    final currentTargetSec = _scrubTargetPosition.inSeconds + addedSec;
    final clampedSec = currentTargetSec.clamp(0, totalSec > 0 ? totalSec : 3600);
    setState(() {
      _scrubTargetPosition = Duration(seconds: clampedSec);
    });
  }

  void _onHorizontalEnd() {
    if (_activeGesture == _GestureType.scrub) {
      widget.onScrubSeek?.call(_scrubTargetPosition);
      _startHudDismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = size.height;

    // Вычисляем дельту покадровой перемотки
    final scrubDeltaSec = _scrubTargetPosition.inSeconds - _scrubStartPosition.inSeconds;
    final scrubSign = scrubDeltaSec >= 0 ? '+' : '';
    final deltaStr = '$scrubSign$scrubDeltaSec с';
    final inOpening = _isInsideOpening(_scrubTargetPosition);
    final inEnding = _isInsideEnding(_scrubTargetPosition);

    return Stack(
      children: [
        // 1. Аппаратное / визуальное плавное затемнение при регулировке яркости
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              color: Colors.black.withValues(alpha: ((1.0 - _brightness) * 0.85).clamp(0.0, 0.85)),
            ),
          ),
        ),

        // 2. Единая 3-зонная система жестового управления (Лево: Яркость / -10с, Центр: Пауза / Скраб, Право: Звук / +10с)
        Positioned.fill(
          child: Row(
            children: [
              // ЛЕВАЯ ЗОНА: Регулировка яркости (вертикально), перемотка назад -10с (двойной тап), скраб (горизонтально)
              Expanded(
                flex: 7,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (widget.isScreenLocked) {
                      widget.onScreenLockedTap?.call();
                    } else {
                      widget.onTap();
                    }
                  },
                  onDoubleTap: () => _triggerSeek(-10, true),
                  onLongPressStart: (_) {
                    if (widget.isScreenLocked) return;
                    if (widget.isLocked) {
                      widget.onLockedTap?.call();
                      return;
                    }
                    widget.onLongPressStart?.call();
                  },
                  onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
                  onLongPressCancel: () => widget.onLongPressEnd?.call(),
                  onVerticalDragStart: (_) {
                    _hudDismissTimer?.cancel();
                    setState(() => _activeGesture = _GestureType.brightness);
                  },
                  onVerticalDragUpdate: (details) {
                    if (_activeGesture == _GestureType.brightness) {
                      final delta = -details.primaryDelta! / (height * 0.65);
                      final newB = (_brightness + delta).clamp(0.05, 1.0);
                      setState(() => _brightness = newB);
                      widget.onBrightnessChanged?.call(newB);
                    }
                  },
                  onVerticalDragEnd: (_) => _startHudDismiss(),
                  onHorizontalDragStart: (_) => _onHorizontalStart(),
                  onHorizontalDragUpdate: _onHorizontalUpdate,
                  onHorizontalDragEnd: (_) => _onHorizontalEnd(),
                ),
              ),

              // ЦЕНТРАЛЬНАЯ ЗОНА: Пауза / Play (двойной тап), скраб (горизонтально), тап (меню)
              Expanded(
                flex: 6,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (widget.isScreenLocked) {
                      widget.onScreenLockedTap?.call();
                    } else {
                      widget.onTap();
                    }
                  },
                  onDoubleTap: _triggerCenterDoubleTap,
                  onLongPressStart: (_) {
                    if (widget.isScreenLocked) return;
                    if (widget.isLocked) {
                      widget.onLockedTap?.call();
                      return;
                    }
                    widget.onLongPressStart?.call();
                  },
                  onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
                  onLongPressCancel: () => widget.onLongPressEnd?.call(),
                  onHorizontalDragStart: (_) => _onHorizontalStart(),
                  onHorizontalDragUpdate: _onHorizontalUpdate,
                  onHorizontalDragEnd: (_) => _onHorizontalEnd(),
                ),
              ),

              // ПРАВАЯ ЗОНА: Регулировка звука (вертикально), перемотка вперед +10с (двойной тап), скраб (горизонтально)
              Expanded(
                flex: 7,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (widget.isScreenLocked) {
                      widget.onScreenLockedTap?.call();
                    } else {
                      widget.onTap();
                    }
                  },
                  onDoubleTap: () => _triggerSeek(10, false),
                  onLongPressStart: (_) {
                    if (widget.isScreenLocked) return;
                    if (widget.isLocked) {
                      widget.onLockedTap?.call();
                      return;
                    }
                    widget.onLongPressStart?.call();
                  },
                  onLongPressEnd: (_) => widget.onLongPressEnd?.call(),
                  onLongPressCancel: () => widget.onLongPressEnd?.call(),
                  onVerticalDragStart: (_) {
                    _hudDismissTimer?.cancel();
                    setState(() => _activeGesture = _GestureType.volume);
                  },
                  onVerticalDragUpdate: (details) {
                    if (_activeGesture == _GestureType.volume) {
                      final delta = (-details.primaryDelta! / (height * 0.65)) * 100.0;
                      final newV = (_volume + delta).clamp(0.0, 100.0);
                      setState(() => _volume = newV);
                      widget.onVolumeChanged?.call(newV);
                    }
                  },
                  onVerticalDragEnd: (_) => _startHudDismiss(),
                  onHorizontalDragStart: (_) => _onHorizontalStart(),
                  onHorizontalDragUpdate: _onHorizontalUpdate,
                  onHorizontalDragEnd: (_) => _onHorizontalEnd(),
                ),
              ),
            ],
          ),
        ),

        // 3. Стеклянный индикатор ЯРКОСТИ слева (с иконкой-солнцем)
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _activeGesture == _GestureType.brightness ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 32),
                child: SizedBox(
                  height: height * 0.45,
                  child: _buildVerticalSliderHud(
                    icon: _brightness > 0.6 ? Icons.wb_sunny_rounded : Icons.brightness_medium_rounded,
                    value: _brightness,
                    label: '${(_brightness * 100).round()}%',
                    isSun: true,
                  ),
                ),
              ),
            ),
          ),
        ),

        // 4. Стеклянный индикатор ГРОМКОСТИ справа (с иконкой-динамиком)
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _activeGesture == _GestureType.volume ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 32),
                child: SizedBox(
                  height: height * 0.45,
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
              ),
            ),
          ),
        ),

        // 5. Стеклянная плашка ПОКАДРОВОЙ ПЕРЕМОТКИ по центру (YouTube/Netflix style с миниатюрой и таймкодами)
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _activeGesture == _GestureType.scrub ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 160),
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: (inOpening
                                ? const Color(0xFFFFB300)
                                : inEnding
                                    ? const Color(0xFF00E5FF)
                                    : Theme.of(context).colorScheme.primary)
                            .withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.65),
                          blurRadius: 28,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Миниатюра кадра (если доступна)
                        if (widget.previewUrl != null && widget.previewUrl!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: wrapCorsSafeUrl(widget.previewUrl!),
                                width: 140,
                                height: 80,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          ),

                        // Значок таймкода Опенинга / Эндинга (если попали в таймкод)
                        if (inOpening || inEnding)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: inOpening
                                  ? const Color(0xFFFFB300).withValues(alpha: 0.22)
                                  : const Color(0xFF00E5FF).withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: inOpening ? const Color(0xFFFFB300) : const Color(0xFF00E5FF),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  inOpening ? Icons.music_note_rounded : Icons.star_rounded,
                                  size: 14,
                                  color: inOpening ? const Color(0xFFFFB300) : const Color(0xFF00E5FF),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  inOpening
                                      ? 'Опенинг (${widget.opening!.formattedRange})'
                                      : 'Эндинг (${widget.ending!.formattedRange})',
                                  style: TextStyle(
                                    color: inOpening ? const Color(0xFFFFB300) : const Color(0xFF00E5FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Дельта перемотки (+0:45 с)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              scrubDeltaSec >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                              color: scrubDeltaSec >= 0
                                  ? Theme.of(context).colorScheme.primary
                                  : const Color(0xFFFF9800),
                              size: 26,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              deltaStr,
                              style: TextStyle(
                                color: scrubDeltaSec >= 0
                                    ? Theme.of(context).colorScheme.primary
                                    : const Color(0xFFFF9800),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatDuration(_scrubTargetPosition)} / ${_formatDuration(widget.totalDuration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Индикатор позиции
                        SizedBox(
                          width: 160,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: widget.totalDuration.inSeconds > 0
                                  ? (_scrubTargetPosition.inSeconds / widget.totalDuration.inSeconds).clamp(0.0, 1.0)
                                  : 0.0,
                              minHeight: 4,
                              backgroundColor: Colors.white.withValues(alpha: 0.2),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                inOpening
                                    ? const Color(0xFFFFB300)
                                    : inEnding
                                        ? const Color(0xFF00E5FF)
                                        : Theme.of(context).colorScheme.primary,
                              ),
                            ),
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

        // 6. Анимированный индикатор двойного тапа (±10 сек с красивыми стрелочками)
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
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          blurRadius: 16,
                        ),
                      ],
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

        // 7. Пульсирующая иконка при двойном тапе по центру (Play / Pause)
        if (_showCenterPulse)
          Center(
            child: AnimatedScale(
              scale: _showCenterPulse ? 1.15 : 0.8,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 46,
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
          width: 50,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isSun ? const Color(0xFFFFB300).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.2),
              width: 1.2,
            ),
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
              Icon(
                icon,
                color: isSun ? const Color(0xFFFFB300) : Colors.white,
                size: 22,
              ),
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
                  fontSize: 10.5,
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
