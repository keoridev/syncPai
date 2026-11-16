import 'package:flutter/material.dart';

/// Единый компактный переключатель режима отображения (Сетка / Список)
/// для экранов Каталога и Списков без ярких неоновых заливок.
class ViewModeToggle extends StatelessWidget {
  final bool isGrid;
  final ValueChanged<bool> onChanged;

  const ViewModeToggle({
    super.key,
    required this.isGrid,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF141822),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleItem(
            key: const ValueKey('view_mode_grid_btn'),
            icon: Icons.grid_view_rounded,
            tooltip: 'Сетка',
            isSelected: isGrid,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 2),
          _ToggleItem(
            key: const ValueKey('view_mode_list_btn'),
            icon: Icons.view_list_rounded,
            tooltip: 'Список',
            isSelected: !isGrid,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleItem({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 30,
          height: 28,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF222836) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 17,
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.48),
          ),
        ),
      ),
    );
  }
}

