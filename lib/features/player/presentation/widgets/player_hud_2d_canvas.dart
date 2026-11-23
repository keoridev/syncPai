import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/cubit/settings_state.dart';

/// Выравнивающая сетка и магнитные центральные направляющие для 2D-редактора HUD.
class PlayerHudEditGridOverlay extends StatelessWidget {
  final bool snapXActive;
  final bool snapYActive;

  const PlayerHudEditGridOverlay({
    super.key,
    required this.snapXActive,
    required this.snapYActive,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          key: const ValueKey('hud_edit_grid_overlay'),
          painter: _HudGridPainter(
            snapXActive: snapXActive,
            snapYActive: snapYActive,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _HudGridPainter extends CustomPainter {
  final bool snapXActive;
  final bool snapYActive;

  const _HudGridPainter({
    required this.snapXActive,
    required this.snapYActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.8;

    const cols = 8;
    const rows = 6;
    for (int c = 1; c < cols; c++) {
      if (c == cols ~/ 2) continue;
      final x = size.width * (c / cols);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (int r = 1; r < rows; r++) {
      if (r == rows ~/ 2) continue;
      final y = size.height * (r / rows);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Границы SafeArea-зажима (0.06..0.94 по X, 0.08..0.88 по Y)
    final safeRect = Rect.fromLTRB(
      size.width * PlayerHudButtonConfig.minNx,
      size.height * PlayerHudButtonConfig.minNy,
      size.width * PlayerHudButtonConfig.maxNx,
      size.height * PlayerHudButtonConfig.maxNy,
    );
    final safePaint = Paint()
      ..color = const Color(0xFF35D9D5).withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(safeRect, const Radius.circular(14)),
      safePaint,
    );

    // Центральная вертикаль (nx == 0.5)
    final centerX = size.width * 0.5;
    final xGuidePaint = Paint()
      ..color = snapXActive
          ? const Color(0xFF35D9D5)
          : Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = snapXActive ? 1.8 : 0.9;
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.height), xGuidePaint);

    // Центральная горизонталь (ny == 0.5)
    final centerY = size.height * 0.5;
    final yGuidePaint = Paint()
      ..color = snapYActive
          ? const Color(0xFF35D9D5)
          : Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = snapYActive ? 1.8 : 0.9;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), yGuidePaint);
  }

  @override
  bool shouldRepaint(covariant _HudGridPainter oldDelegate) =>
      oldDelegate.snapXActive != snapXActive ||
      oldDelegate.snapYActive != snapYActive;
}

/// Обёртка для любой свободной 2D-кнопки HUD: в обычном режиме позиционирует и масштабирует,
/// в `isEditMode` добавляет выделение `#FF6B4A` и плавное перетаскивание 60/120 FPS.
class PlayerHudDraggableButton extends StatelessWidget {
  final PlayerHudButtonConfig config;
  final bool isEditMode;
  final bool isSelected;
  final Widget child;
  final VoidCallback onTapSelect;
  final VoidCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final VoidCallback onDragEnd;

  const PlayerHudDraggableButton({
    super.key,
    required this.config,
    required this.isEditMode,
    required this.isSelected,
    required this.child,
    required this.onTapSelect,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = Alignment(config.nx * 2.0 - 1.0, config.ny * 2.0 - 1.0);

    if (!isEditMode) {
      return Align(
        alignment: alignment,
        child: Transform.scale(
          scale: config.scale,
          child: child,
        ),
      );
    }

    return Align(
      alignment: alignment,
      child: Transform.scale(
        scale: config.scale,
        child: GestureDetector(
          key: ValueKey('hud_canvas_btn_${config.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTapSelect();
          },
          onPanStart: (_) {
            HapticFeedback.lightImpact();
            onDragStart();
          },
          onPanUpdate: onDragUpdate,
          onPanEnd: (_) => onDragEnd(),
          onPanCancel: onDragEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFF6B4A).withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.30),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFFF6B4A)
                    : const Color(0xFF35D9D5).withValues(alpha: 0.45),
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF6B4A).withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: IgnorePointer(child: child),
          ),
        ),
      ),
    );
  }
}

/// Компактная плавающая панель инспектора выбранной кнопки, пресетов и скрытых кнопок.
class PlayerHudInspectorPill extends StatelessWidget {
  final SettingsCubit? settingsCubit;
  final SettingsState settingsState;
  final String? selectedButtonId;
  final ValueChanged<String?> onSelectButton;
  final VoidCallback onDone;

  const PlayerHudInspectorPill({
    super.key,
    required this.settingsCubit,
    required this.settingsState,
    required this.selectedButtonId,
    required this.onSelectButton,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final selectedConfig = selectedButtonId != null
        ? settingsState.hudConfigFor(selectedButtonId!)
        : null;
    final hiddenButtons = settingsState.hiddenHudButtons;

    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Container(
            key: const ValueKey('hud_edit_mode_banner'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F141E).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF35D9D5).withValues(alpha: 0.40),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Верхний ряд: заголовок, пресеты «Классика» / «Под правую руку» и кнопка «Готово»
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_with_rounded,
                          color: Color(0xFF35D9D5),
                          size: 15,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Режим настройки HUD',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _PresetChip(
                          key: const ValueKey('wysiwyg_preset_classic'),
                          label: HudLayoutPresetType.classic.label,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            settingsCubit?.applyHud2DPreset(
                              HudLayoutPresetType.classic,
                            );
                          },
                        ),
                        _PresetChip(
                          key: const ValueKey('wysiwyg_preset_right_thumb'),
                          label: HudLayoutPresetType.rightThumb.label,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            settingsCubit?.applyHud2DPreset(
                              HudLayoutPresetType.rightThumb,
                            );
                          },
                        ),
                        ElevatedButton.icon(
                          key: const ValueKey('wysiwyg_done_btn'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF35D9D5),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: onDone,
                          icon: const Icon(Icons.check_rounded, size: 14),
                          label: const Text(
                            'Готово',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Панель инспектора выбранной кнопки: название, масштаб 80–140%, скрыть/показать
                if (selectedConfig != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    key: const ValueKey('hud_selected_quick_bar'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B4A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF6B4A).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          hud2DButtonLabel(selectedConfig.id),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${(selectedConfig.scale * 100).round()}%',
                            style: const TextStyle(
                              color: Color(0xFFFF6B4A),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('hud_scale_down_btn'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          tooltip: 'Уменьшить',
                          icon: const Icon(
                            Icons.zoom_out_rounded,
                            size: 17,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            final nextScale = (selectedConfig.scale - 0.1)
                                .clamp(
                                  PlayerHudButtonConfig.minScale,
                                  PlayerHudButtonConfig.maxScale,
                                );
                            settingsCubit?.updateHudButtonConfig(
                              selectedConfig.id,
                              scale: nextScale,
                            );
                          },
                        ),
                        SizedBox(
                          width: 116,
                          height: 22,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2.5,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor: const Color(0xFFFF6B4A),
                              inactiveTrackColor: Colors.white24,
                              thumbColor: const Color(0xFFFF6B4A),
                            ),
                            child: Slider(
                              key: const ValueKey('hud_scale_slider'),
                              value: selectedConfig.scale.clamp(
                                PlayerHudButtonConfig.minScale,
                                PlayerHudButtonConfig.maxScale,
                              ),
                              min: PlayerHudButtonConfig.minScale,
                              max: PlayerHudButtonConfig.maxScale,
                              divisions: 12,
                              onChanged: (v) {
                                settingsCubit?.updateHudButtonConfig(
                                  selectedConfig.id,
                                  scale: v,
                                  persist: false,
                                );
                              },
                              onChangeEnd: (_) {
                                settingsCubit?.persistHudLayout();
                              },
                            ),
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('hud_scale_up_btn'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          tooltip: 'Увеличить',
                          icon: const Icon(
                            Icons.zoom_in_rounded,
                            size: 17,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            final nextScale = (selectedConfig.scale + 0.1)
                                .clamp(
                                  PlayerHudButtonConfig.minScale,
                                  PlayerHudButtonConfig.maxScale,
                                );
                            settingsCubit?.updateHudButtonConfig(
                              selectedConfig.id,
                              scale: nextScale,
                            );
                          },
                        ),
                        TextButton.icon(
                          key: const ValueKey('hud_toggle_vis_btn'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            final nextVis = !selectedConfig.visible;
                            settingsCubit?.updateHudButtonConfig(
                              selectedConfig.id,
                              visible: nextVis,
                            );
                            if (!nextVis) {
                              onSelectButton(null);
                            }
                          },
                          icon: Icon(
                            selectedConfig.visible
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 14,
                            color: const Color(0xFF35D9D5),
                          ),
                          label: Text(
                            selectedConfig.visible ? 'Скрыть' : 'Показать',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Компактная строка скрытых кнопок для восстановления в 1 тап
                if (hiddenButtons.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 26,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        const Center(
                          child: Text(
                            'Скрытые кнопки:',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        for (final hidden in hiddenButtons)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              key: ValueKey('hud_restore_chip_${hidden.id}'),
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                settingsCubit?.updateHudButtonConfig(
                                  hidden.id,
                                  visible: true,
                                );
                                onSelectButton(hidden.id);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.visibility_rounded,
                                      size: 12,
                                      color: Color(0xFF35D9D5),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      hud2DButtonLabel(hidden.id),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

