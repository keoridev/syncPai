import 'package:flutter/material.dart';

import '../../../features/profile/presentation/widgets/achievement_badge_artwork.dart';
import '../../services/mascot_companion_service.dart';

/// Неблокирующий плавающий тост-компаньон Пай-тян:
/// - Desktop (`width >= 800`): закреплён в правом нижнем углу
/// - Mobile (`width < 800`): компактная верхняя плашка
/// Автоматически скрывается через 3.5 сек или по нажатию.
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
        final topPadding = MediaQuery.paddingOf(context).top;

        final card = Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('pai_companion_toast_card'),
            borderRadius: BorderRadius.circular(18),
            onTap: service.dismiss,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 350 : size.width - 28,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF121726).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF35D9D5).withValues(alpha: 0.45),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Image.asset(
                        reaction.expression.assetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF35D9D5),
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                  if (reaction.badgeId != null) ...[
                    const SizedBox(width: 8),
                    AchievementBadgeArtwork(
                      badgeId: reaction.badgeId!,
                      isUnlocked: true,
                      size: 34,
                    ),
                  ],
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Пай-тян • ${reaction.expression.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF35D9D5),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
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
                      ],
                    ),
                  ),
                  if (reaction.actionLabel != null &&
                      reaction.onAction != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      key: const ValueKey('pai_companion_action_btn'),
                      style: TextButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF35D9D5).withValues(alpha: 0.18),
                        foregroundColor: const Color(0xFF35D9D5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        final cb = reaction.onAction;
                        service.dismiss();
                        cb?.call();
                      },
                      child: Text(
                        reaction.actionLabel!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

        if (isDesktop) {
          return Positioned(
            right: 20,
            bottom: 20,
            child: card,
          );
        }

        return Positioned(
          top: topPadding + 10,
          left: 14,
          right: 14,
          child: Center(child: card),
        );
      },
    );
  }
}

