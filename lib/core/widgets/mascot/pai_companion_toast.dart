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
        final isDesktop = size.width >= 800;
        final bottomPadding = MediaQuery.paddingOf(context).bottom;

        final card = Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('pai_companion_toast_card'),
            borderRadius: BorderRadius.circular(24),
            onTap: service.dismiss,
            child: Container(
              constraints: BoxConstraints(
                minHeight: 46,
                maxWidth: isDesktop ? 380 : size.width - 24,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF121726).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Image.asset(
                        reaction.expression.assetPath,
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
                  Flexible(
                    child: Text(
                      reaction.message,
                      maxLines: 2,
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
                ],
              ),
            ),
          ),
        );

        final swipeableCard = Dismissible(
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

        if (isDesktop) {
          return Positioned(
            right: 20,
            bottom: 20,
            child: swipeableCard,
          );
        }

        return Positioned(
          bottom: kBottomNavigationBarHeight + bottomPadding + 16,
          left: 12,
          right: 12,
          child: Center(child: swipeableCard),
        );
      },
    );
  }
}

