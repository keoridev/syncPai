import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/telegram_launcher.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/steam_avatar_frame.dart';
import '../../domain/services/achievement_service.dart';
import '../../services/friends_service.dart';
import 'achievement_badge_artwork.dart';
import 'duo_pairing_widgets.dart';
import 'pai_chan_artwork_banner.dart';

/// Steam-стиль меню действий при нажатии на друга в списке.
Future<void> showFriendActionSheet(
  BuildContext context, {
  required Map<String, dynamic> friend,
  required Color accentColor,
  VoidCallback? onFriendsChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _FriendActionSheet(
      friend: friend,
      accentColor: accentColor,
      onFriendsChanged: onFriendsChanged,
      parentContext: context,
    ),
  );
}

class _FriendActionSheet extends StatelessWidget {
  final Map<String, dynamic> friend;
  final Color accentColor;
  final VoidCallback? onFriendsChanged;
  final BuildContext parentContext;

  const _FriendActionSheet({
    required this.friend,
    required this.accentColor,
    required this.parentContext,
    this.onFriendsChanged,
  });

  String get _friendId => (friend['id'] ?? '').toString();
  String get _displayName {
    final raw = (friend['username'] ?? friend['name'] ?? '').toString().trim();
    return raw.isEmpty ? 'Пользователь' : raw;
  }

  String get _tag {
    final t = (friend['tag'] ?? '').toString().trim();
    if (t.isEmpty) return '';
    return t.startsWith('#') ? t : '#$t';
  }

  String get _friendCode {
    final code = (friend['friend_code'] ?? '').toString().trim();
    if (code.isNotEmpty) return code;
    return _friendId.length >= 6
        ? 'SP-${_friendId.substring(_friendId.length - 6).toUpperCase()}'
        : _displayName;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatarUrl = (friend['avatar_url'] ?? friend['avatar'])?.toString();
    final isOnline = friend['isOnline'] == true;
    final statusText = (friend['custom_status'] ??
            friend['status'] ??
            (isOnline ? 'В сети' : 'Не в сети'))
        .toString();
    final roomPin = (friend['room'] ?? '').toString().trim();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF12161F),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  AppAvatar(
                    avatarUrl: avatarUrl,
                    username: _displayName,
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (_tag.isNotEmpty)
                              Text(
                                ' $_tag',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isOnline ? accentColor : Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: Colors.white10),
              const SizedBox(height: 8),
              _ActionRow(
                key: const ValueKey('friend_action_open_profile'),
                icon: Icons.person_outline_rounded,
                iconColor: accentColor,
                title: 'Открыть профиль',
                onTap: () {
                  Navigator.of(context).pop();
                  showFriendProfileSheet(
                    parentContext,
                    friend: friend,
                    accentColor: accentColor,
                  );
                },
              ),
              _ActionRow(
                key: const ValueKey('friend_action_watch_together'),
                icon: Icons.live_tv_rounded,
                iconColor: const Color(0xFF38BDF8),
                title: 'Пригласить смотреть вместе',
                onTap: () {
                  Navigator.of(context).pop();
                  if (roomPin.isNotEmpty) {
                    parentContext.push('/watch-together?pin=$roomPin');
                  } else {
                    parentContext.push('/watch-together');
                  }
                },
              ),
              _ActionRow(
                key: const ValueKey('friend_action_gift_subscription'),
                icon: Icons.card_giftcard_rounded,
                iconColor: const Color(0xFFFBBF24),
                title: 'Подарить подписку (Plus / Pro)',
                onTap: () async {
                  Navigator.of(context).pop();
                  await TelegramLauncher.openBotStart(
                    parentContext,
                    'gift_$_friendCode',
                    fallbackMessage: 'Открыть @syncpai_bot для подарка: gift_$_friendCode',
                  );
                },
              ),
              _ActionRow(
                key: const ValueKey('friend_action_remove_friend'),
                icon: Icons.person_remove_outlined,
                iconColor: Colors.redAccent,
                title: 'Удалить из друзей',
                titleColor: Colors.redAccent,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _confirmRemoveFriend(parentContext);
                },
              ),
              _ActionRow(
                key: const ValueKey('friend_action_report'),
                icon: Icons.flag_outlined,
                iconColor: scheme.onSurfaceVariant,
                title: 'Пожаловаться',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showReportReasonSheet(parentContext);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveFriend(BuildContext ctx) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF141824),
        title: const Text(
          'Удалить из друзей?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Пользователь $_displayName будет удалён из вашего списка друзей.',
          style: const TextStyle(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(true),
            child: const Text(
              'Удалить',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FriendsService.removeFriend(_friendId.isNotEmpty ? _friendId : _displayName);
      onFriendsChanged?.call();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('$_displayName удалён из друзей')),
        );
      }
    }
  }

  Future<void> _showReportReasonSheet(BuildContext ctx) async {
    const reasons = [
      'Спам',
      'Оскорбления',
      'Неприемлемый профиль',
    ];
    final selected = await showModalBottomSheet<String>(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (rCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF12161F),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Жалоба на $_displayName',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final reason in reasons)
                  ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    title: Text(
                      reason,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 18),
                    onTap: () => Navigator.of(rCtx).pop(reason),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selected != null) {
      final ok = await FriendsService.reportUser(
        targetUserId: _friendId,
        targetUsername: _displayName,
        reason: selected,
      );
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Жалоба отправлена модераторам'
                  : 'Не удалось отправить жалобу. Попробуйте позже.',
            ),
          ),
        );
      }
    }
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final VoidCallback onTap;

  const _ActionRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: titleColor ?? Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
        onTap: onTap,
      ),
    );
  }
}

/// Read-only карточка профиля друга с аватаркой, рамкой, витриной,
/// любимым аниме, часами просмотра и достижениями.
Future<void> showFriendProfileSheet(
  BuildContext context, {
  required Map<String, dynamic> friend,
  required Color accentColor,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _FriendProfileSheet(
      friend: friend,
      accentColor: accentColor,
    ),
  );
}

class _FriendProfileSheet extends StatefulWidget {
  final Map<String, dynamic> friend;
  final Color accentColor;

  const _FriendProfileSheet({
    required this.friend,
    required this.accentColor,
  });

  @override
  State<_FriendProfileSheet> createState() => _FriendProfileSheetState();
}

class _FriendProfileSheetState extends State<_FriendProfileSheet> {
  Map<String, dynamic>? _fullProfile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = (widget.friend['id'] ?? '').toString();
    final full = await FriendsService.fetchFriendFullProfile(id);
    if (mounted) {
      setState(() {
        _fullProfile = full;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = {...widget.friend, if (_fullProfile != null) ..._fullProfile!};
    final name = (data['username'] ?? data['name'] ?? 'Пользователь').toString().trim();
    final rawTag = (data['tag'] ?? '').toString().trim();
    final tag = rawTag.isEmpty ? '' : (rawTag.startsWith('#') ? rawTag : '#$rawTag');
    final frameId = (data['frame_id'] ?? data['avatar_frame_id'] ?? 'none').toString();
    final avatarUrl = (data['avatar_url'] ?? data['avatar'])?.toString();
    final artworkUrl = (data['artwork_url'] ?? '').toString();
    final favTitle = (data['favorite_anime_title'] ?? '').toString();
    final watchHours = ((data['watch_hours'] ?? data['hours_watched'] ?? 0) as num?)?.toDouble() ?? 0.0;
    final unlocked = (data['unlocked_badges'] is List)
        ? (data['unlocked_badges'] as List).map((e) => '$e').toList()
        : const <String>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.84,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF12161F),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SteamAvatarFrameWidget(
                      frameId: frameId,
                      size: 62,
                      child: AppAvatar(
                        avatarUrl: avatarUrl,
                        username: name,
                        size: 56,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$name${tag.isNotEmpty ? ' $tag' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (data['custom_status'] ?? 'В сети SyncPai').toString(),
                            style: TextStyle(
                              color: widget.accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (artworkUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 140,
                      child: LayoutBuilder(
                        builder: (_, c) {
                          if (artworkUrl.startsWith('duo_')) {
                            return DuoDiptychBanner(
                              themeId: artworkUrl,
                              width: c.maxWidth,
                              height: 140,
                            );
                          }
                          if (artworkUrl.startsWith('pai_')) {
                            return PaiChanArtworkBanner(
                              artworkId: artworkUrl,
                              width: c.maxWidth,
                              height: 140,
                            );
                          }
                          return Image.network(
                            artworkUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFF1A2030),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        icon: Icons.schedule_rounded,
                        label: 'Часов просмотра',
                        value: '${watchHours.toStringAsFixed(1)} ч',
                        color: widget.accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        icon: Icons.favorite_rounded,
                        label: 'Любимое аниме',
                        value: favTitle.isNotEmpty ? favTitle : 'Не выбрано',
                        color: const Color(0xFFFF6B4A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'ДОСТИЖЕНИЯ',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final badge in kSyncPaiAchievements.take(6))
                      AchievementBadgeArtwork(
                        badgeId: badge.id,
                        isUnlocked: unlocked.contains(badge.id),
                        size: 38,
                        rarity: badge.rarity,
                        accentColor: badge.color,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
