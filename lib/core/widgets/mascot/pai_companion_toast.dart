import 'package:flutter/material.dart';

import '../../../features/profile/presentation/widgets/achievement_badge_artwork.dart';
import '../../services/mascot_companion_service.dart';

/// Неблокирующий плавающий тост-компаньон Пай-тян:
/// - Desktop (`width >= 800`): закреплён в правом нижнем углу (`width <= 380`)
/// - Mobile (`width < 800`): компактная нижняя пилюля над панелью навигации
/// Автоматически скрывается или закрывается свайпом / нажатием.
class PaiCompanionToast extends StatelessWidget {
  const PaiCompanionToast({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MascotCompanionService.instance,
      builder: (context, _) {
        final service = MascotCompanionService.instance;
        final reaction = service.currentReaction;
        if (!service.enabled ||
            reaction == null ||
            (service.isPlayerActive && reaction.isAfk)) {
          return const SizedBox.shrink();
        }

        final size = MediaQuery.sizeOf(context);
        if (!size.width.isFinite || size.width < 240 || size.height < 120) {
          return const SizedBox.shrink();
        }
        final isPortrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;
        // В портретном режиме плеера карточка продолжения манги/сезона
        // встраивается прямо над «Список серий» без перекрытия эпизодов.
        final reactionTitle = reaction.title ?? '';
        if (isPortrait &&
            service.isPlayerActive &&
            (reactionTitle.contains('Сезон') ||
                reactionTitle.contains('Финал'))) {
          return const SizedBox.shrink();
        }

        final isDesktop = size.width >= 800;
        final bottomPadding = MediaQuery.paddingOf(context).bottom;

        Widget buildToast(double toastWidth) {
          final card = Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('pai_companion_toast_card'),
              borderRadius: BorderRadius.circular(16),
              onTap: service.dismiss,
              child: SizedBox(
                width: toastWidth,
                child: LayoutBuilder(
                  builder: (context, boxConstraints) {
                    if (!boxConstraints.hasBoundedWidth ||
                        boxConstraints.maxWidth < 200) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                  constraints: const BoxConstraints(minHeight: 46),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141821),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x14FFFFFF)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Image.asset(
                            reaction.customAssetPath ??
                                (service.isMangaContext
                                    ? reaction.expression.mangaAssetPath
                                    : reaction.expression.assetPath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.auto_awesome_rounded,
                              color: Color(0xFF35D9D5),
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      if (reaction.badgeId != null) ...[
                        const SizedBox(width: 8),
                        AchievementBadgeArtwork(
                          badgeId: reaction.badgeId!,
                          isUnlocked: true,
                          size: 24,
                        ),
                      ],
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          reaction.message,
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (reaction.actionLabel != null &&
                          reaction.onAction != null) ...[
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            final accent =
                                reaction.actionColor ?? const Color(0xFF35D9D5);
                            final isPrimaryFill =
                                reaction.actionColor == const Color(0xFFFF6B4A);
                            return TextButton(
                              key: const ValueKey('pai_companion_action_btn'),
                              style: TextButton.styleFrom(
                                backgroundColor: isPrimaryFill
                                    ? accent
                                    : accent.withValues(alpha: 0.18),
                                foregroundColor:
                                    isPrimaryFill ? Colors.white : accent,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                final cb = reaction.onAction;
                                service.dismiss();
                                cb?.call();
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (reaction.actionIcon != null) ...[
                                    Icon(reaction.actionIcon, size: 13),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    reaction.actionLabel!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(width: 4),
                      GestureDetector(
                        key: const Key('pai_companion_close_btn'),
                        behavior: HitTestBehavior.opaque,
                        onTap: service.dismiss,
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0x14FFFFFF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                  },
                ),
              ),
            ),
          );

          return Dismissible(
            key: ValueKey(
              'pai_toast_dismissible_${reaction.createdAt.microsecondsSinceEpoch}',
            ),
            direction: DismissDirection.horizontal,
            onDismissed: (_) => service.dismissCurrentToast(),
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 150) {
                  service.dismissCurrentToast();
                }
              },
              child: card,
            ),
          );
        }

        if (isDesktop) {
          final maxToastWidth = (size.width - 40.0).clamp(0.0, 420.0);
          if (maxToastWidth < 200) return const SizedBox.shrink();
          return Positioned(
            right: 20,
            bottom: 20,
            width: maxToastWidth,
            child: buildToast(maxToastWidth),
          );
        }

        final maxMobileWidth = (size.width - 24.0).clamp(0.0, 420.0);
        if (maxMobileWidth < 200) return const SizedBox.shrink();
        return Positioned(
          bottom: kBottomNavigationBarHeight + bottomPadding + 16,
          left: 12,
          right: 12,
          child: Center(child: buildToast(maxMobileWidth)),
        );
      },
    );
  }
}

