import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/cubit/settings_state.dart';

/// Живой редактор кнопок и пресетов HUD видеоплеера (0ms отклик).
class PlayerHudEditorSheet extends StatelessWidget {
  final SettingsCubit cubit;

  const PlayerHudEditorSheet({
    super.key,
    required this.cubit,
  });

  static IconData iconForButton(String id) {
    switch (id) {
      case 'back':
        return Icons.arrow_back_rounded;
      case 'title':
        return Icons.title_rounded;
      case 'play_pause':
        return Icons.play_arrow_rounded;
      case 'seek_10s':
        return Icons.replay_10_rounded;
      case 'skip_op_ed':
        return Icons.fast_forward_rounded;
      case 'timeline':
        return Icons.linear_scale_rounded;
      case 'quality':
        return Icons.hd_rounded;
      case 'next_episode':
        return Icons.skip_next_rounded;
      case 'fullscreen':
        return Icons.fullscreen_rounded;
      case 'settings_gear':
        return Icons.settings_outlined;
      case 'speed':
        return Icons.speed_rounded;
      case 'aspect_ratio':
        return Icons.aspect_ratio_rounded;
      case 'screenshot':
        return Icons.camera_alt_outlined;
      case 'sleep_timer':
        return Icons.bedtime_outlined;
      case 'pip':
        return Icons.picture_in_picture_alt_rounded;
      default:
        return Icons.tune_rounded;
    }
  }

  static Future<void> show(
    BuildContext context, {
    SettingsCubit? cubit,
  }) {
    final resolved = cubit ??
        (getIt.isRegistered<SettingsCubit>() ? getIt<SettingsCubit>() : null);
    if (resolved == null) return Future.value();

    final size = MediaQuery.of(context).size;
    final isLandscapeOrDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        size.width > size.height;

    if (isLandscapeOrDesktop) {
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'HUD Editor',
        barrierColor: Colors.black.withValues(alpha: 0.25),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, _, __) {
          return SafeArea(
            child: Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 390,
                  height: double.infinity,
                  margin: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12161F).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: PlayerHudEditorSheet(cubit: resolved),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (ctx, anim, _, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      isScrollControlled: true,
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.56,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF12161F).withValues(alpha: 0.95),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: PlayerHudEditorSheet(cubit: resolved),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final metaById = {for (final m in kDefaultPlayerHudButtons) m.id: m};

    return BlocBuilder<SettingsCubit, SettingsState>(
      bloc: cubit,
      builder: (context, s) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Настроить кнопки HUD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (s.playerHudPreset == PlayerHudPreset.custom)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: themePrimary.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Пользовательский',
                              style: TextStyle(
                                color: themePrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('hud_editor_reset_btn'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      cubit.resetPlayerHudToDefault();
                    },
                    child: Text(
                      'Сбросить',
                      style: TextStyle(
                        color: themePrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 3-pill preset bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  for (final p in const [
                    PlayerHudPreset.standard,
                    PlayerHudPreset.minimal,
                    PlayerHudPreset.advanced,
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          key: ValueKey('hud_editor_preset_${p.name}'),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            cubit.setPlayerHudPreset(p);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            decoration: BoxDecoration(
                              color: s.playerHudPreset == p
                                  ? themePrimary.withValues(alpha: 0.18)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: s.playerHudPreset == p
                                    ? themePrimary.withValues(alpha: 0.65)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              p.label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: s.playerHudPreset == p
                                    ? themePrimary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: s.playerButtonOrder.length,
                onReorderItem: (oldIdx, newIdx) => cubit.reorderPlayerButtons(
                  oldIdx,
                  newIdx,
                  adjustNewIndex: false,
                ),
                itemBuilder: (context, index) {
                  final id = s.playerButtonOrder[index];
                  final meta = metaById[id];
                  final visible = s.isHudButtonVisible(id);
                  final isLockoutGuarded = (id == 'back' &&
                          !s.isHudButtonVisible('settings_gear')) ||
                      (id == 'settings_gear' && !s.isHudButtonVisible('back'));

                  return ListTile(
                    key: ValueKey('live_hud_row_$id'),
                    dense: true,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.drag_indicator_rounded,
                          color: Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          iconForButton(id),
                          color: visible ? themePrimary : Colors.white38,
                          size: 18,
                        ),
                      ],
                    ),
                    title: Text(
                      meta?.label ?? id,
                      style: TextStyle(
                        color: visible ? Colors.white : Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLockoutGuarded)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message:
                                  'Нельзя скрыть одновременно «Назад» и «Настройки»',
                              child: Icon(
                                Icons.lock_outline_rounded,
                                size: 15,
                                color: Colors.white38,
                              ),
                            ),
                          ),
                        Switch(
                          value: visible,
                          activeThumbColor: themePrimary,
                          onChanged: isLockoutGuarded
                              ? null
                              : (val) => cubit.togglePlayerButton(id, val),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

