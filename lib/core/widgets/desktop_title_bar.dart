import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../theme/app_colors.dart';

/// Кастомный тёмный заголовок окна для Windows / macOS / Linux в стиле SyncPai.
/// Убирает стандартную белую системную рамку ОС и предоставляет:
/// - Перетаскивание окна (DragToMoveArea) и двойной клик для разворачивания
/// - Фирменный бейдж SyncPai с неоновым акцентом
/// - Кастомные кнопки Свернуть / Развернуть / Закрыть (с красным ховером как в Steam/Discord)
/// - Автоматическое скрытие при входе плеера в полноэкранный режим (F / Fullscreen)
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key});

  static bool get isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Реактивный флаг полноэкранного режима для синхронного скрытия заголовка окна
  static final ValueNotifier<bool> isFullScreenNotifier = ValueNotifier<bool>(false);

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _isMaximized = false;
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    DesktopTitleBar.isFullScreenNotifier.addListener(_onFullScreenNotifierChanged);
    if (DesktopTitleBar.isDesktopPlatform) {
      windowManager.addListener(this);
      _syncWindowState();
    }
  }

  void _onFullScreenNotifierChanged() {
    if (mounted) {
      setState(() {
        _isFullScreen = DesktopTitleBar.isFullScreenNotifier.value;
      });
    }
  }

  Future<void> _syncWindowState() async {
    try {
      final max = await windowManager.isMaximized();
      final fs = await windowManager.isFullScreen();
      if (mounted) {
        setState(() {
          _isMaximized = max;
          _isFullScreen = fs || DesktopTitleBar.isFullScreenNotifier.value;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    DesktopTitleBar.isFullScreenNotifier.removeListener(_onFullScreenNotifierChanged);
    if (DesktopTitleBar.isDesktopPlatform) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowEnterFullScreen() {
    DesktopTitleBar.isFullScreenNotifier.value = true;
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    DesktopTitleBar.isFullScreenNotifier.value = false;
    if (mounted) setState(() => _isFullScreen = false);
  }

  Future<void> _toggleMaximize() async {
    try {
      final isMax = await windowManager.isMaximized();
      if (isMax) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      await _syncWindowState();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!DesktopTitleBar.isDesktopPlatform ||
        _isFullScreen ||
        DesktopTitleBar.isFullScreenNotifier.value) {
      return const SizedBox.shrink();
    }

    final primary = Theme.of(context).colorScheme.primary;

    return Material(
      color: const Color(0xFF090910),
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              const Color(0xFF090910),
              Color.lerp(const Color(0xFF0D0D18), primary, 0.08) ?? const Color(0xFF0D0D18),
              const Color(0xFF090910),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withValues(alpha: 0.07),
              width: 1.0,
            ),
          ),
        ),
        child: Row(
          children: [
            // Область перетаскивания окна + логотип SyncPai
            Expanded(
              child: DragToMoveArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _toggleMaximize,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                primary,
                                AppColors.primaryLight,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.45),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'SyncPai',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: primary.withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            'DESKTOP',
                            style: TextStyle(
                              color: AppColors.primaryLight,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Кнопки управления окном (Свернуть, Развернуть/Восстановить, Закрыть)
            _WindowControlButton(
              icon: Icons.horizontal_rule_rounded,
              tooltip: 'Свернуть',
              onTap: () async {
                try {
                  await windowManager.minimize();
                } catch (_) {}
              },
            ),
            _WindowControlButton(
              icon: _isMaximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
              iconSize: _isMaximized ? 13 : 15,
              tooltip: _isMaximized ? 'Восстановить' : 'Развернуть',
              onTap: _toggleMaximize,
            ),
            _WindowControlButton(
              icon: Icons.close_rounded,
              tooltip: 'Закрыть',
              isCloseButton: true,
              onTap: () async {
                try {
                  await windowManager.close();
                } catch (_) {}
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowControlButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final VoidCallback onTap;
  final bool isCloseButton;

  const _WindowControlButton({
    required this.icon,
    this.iconSize = 16,
    required this.tooltip,
    required this.onTap,
    this.isCloseButton = false,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = _isHovered
        ? (widget.isCloseButton
            ? const Color(0xFFE81123)
            : Colors.white.withValues(alpha: 0.09))
        : Colors.transparent;

    final iconColor = _isHovered
        ? Colors.white
        : Colors.white.withValues(alpha: 0.72);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 44,
          height: 34,
          color: bgColor,
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

