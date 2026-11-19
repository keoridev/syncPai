import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../../../../app/di/injection.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../auth/presentation/widgets/pai_chan_auth_gate.dart';
import '../../domain/entities/friend_models.dart';
import '../../services/friends_service.dart';
import 'friend_invite_dialog.dart';
import 'qr_invite_sheet.dart';
import 'qr_scanner_sheet.dart';

/// Открывает адаптивную панель управления друзьями (Sheet на мобилках, Dialog на десктопе)
Future<void> showFriendsManagementSheet(
  BuildContext context, {
  Color? accentColor,
  VoidCallback? onFriendsChanged,
  UserProfile? currentUserProfile,
}) {
  final isDesktop = MediaQuery.of(context).size.width >= 650;
  final accent = accentColor ?? Theme.of(context).colorScheme.primary;

  if (isDesktop) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
          child: FriendsManagementView(
            accentColor: accent,
            onFriendsChanged: onFriendsChanged,
            userProfile: currentUserProfile,
          ),
        ),
      ),
    );
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
        child: FriendsManagementView(
          accentColor: accent,
          onFriendsChanged: onFriendsChanged,
          userProfile: currentUserProfile,
        ),
      ),
    ),
  );
}

class FriendsManagementView extends StatefulWidget {
  final Color accentColor;
  final VoidCallback? onFriendsChanged;
  final UserProfile? userProfile;

  const FriendsManagementView({
    super.key,
    required this.accentColor,
    this.onFriendsChanged,
    this.userProfile,
  });

  /// Строгое извлечение кода приглашения из буфера обмена (игнорирует длинные тексты > 160 символов).
  static String? extractValidClipboardInvite(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > 160) return null;

    final friendCodeMatch =
        RegExp(r'\bSP-[A-Z0-9]{6}\b', caseSensitive: false).firstMatch(trimmed);
    if (friendCodeMatch != null) {
      return friendCodeMatch.group(0)!.toUpperCase();
    }

    final deepLinkMatch = RegExp(
      r'(?:syncpai://(?:room|friend)/|t\.me/syncpai_bot\?start=(?:link_|room_))([A-Za-z0-9_-]{4,20})',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (deepLinkMatch != null) {
      return deepLinkMatch.group(1)!;
    }

    final roomCodeMatch = RegExp(r'^\d{6}$').firstMatch(trimmed);
    if (roomCodeMatch != null) {
      return roomCodeMatch.group(0)!;
    }

    return null;
  }

  @override
  State<FriendsManagementView> createState() => _FriendsManagementViewState();
}

class _FriendsManagementViewState extends State<FriendsManagementView> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _friends = [];
  List<FriendRequestItem> _incomingRequests = [];
  List<FriendRequestItem> _outgoingRequests = [];
  List<FriendProfile> _searchResults = [];

  bool _isLoadingFriends = true;
  bool _isLoadingRequests = true;
  bool _isSearching = false;
  String _lastSearchQuery = '';
  Timer? _debounceTimer;

  String? _detectedClipboardInvite;
  UserProfile? _profile;
  StreamSubscription<AuthState>? _authSub;

  bool get _isGuest {
    if (_profile != null) {
      return _profile!.isAnonymous;
    }
    return PaiChanAuthGate.isGuest(context);
  }

  @override
  void initState() {
    super.initState();
    _profile = widget.userProfile;
    _tabController = TabController(length: 3, vsync: this);
    _subscribeAuthChanges();
    _loadProfileIfNull();
    FriendsService.friendsNotifier.addListener(_onFriendsNotifierChanged);
    if (!_isGuest) {
      FriendsService.subscribeRealtime();
      _loadFriends();
      _loadRequests();
    } else {
      _isLoadingFriends = false;
      _isLoadingRequests = false;
    }
    _checkClipboardForInvite();
  }

  void _onFriendsNotifierChanged() {
    if (!mounted) return;
    setState(() {
      _friends = List<Map<String, dynamic>>.from(FriendsService.friendsNotifier.value);
    });
  }

  void _subscribeAuthChanges() {
    try {
      if (getIt.isRegistered<AuthCubit>()) {
        final cubit = getIt<AuthCubit>();
        if (_profile == null && cubit.state is Authenticated) {
          _profile = (cubit.state as Authenticated).profile;
        }
        _authSub = cubit.stream.listen((state) {
          if (state is Authenticated && mounted) {
            final wasGuest = _isGuest;
            setState(() => _profile = state.profile);
            if (wasGuest && !state.profile.isAnonymous) {
              _loadFriends();
              _loadRequests();
              widget.onFriendsChanged?.call();
            }
          }
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    FriendsService.friendsNotifier.removeListener(_onFriendsNotifierChanged);
    _authSub?.cancel();
    _debounceTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfileIfNull() async {
    if (_profile == null && getIt.isRegistered<AuthRepository>()) {
      try {
        final authRepo = getIt<AuthRepository>();
        final p = await authRepo.getCurrentProfile();
        if (mounted) {
          setState(() => _profile = p);
          if (!p.isAnonymous) {
            _loadFriends();
            _loadRequests();
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _checkClipboardForInvite() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final code = FriendsManagementView.extractValidClipboardInvite(clipboardData?.text);
      if (code != null && mounted) {
        setState(() {
          _detectedClipboardInvite = code;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadFriends() async {
    setState(() => _isLoadingFriends = true);
    final list = await FriendsService.getFriends();
    if (mounted) {
      setState(() {
        _friends = list;
        _isLoadingFriends = false;
      });
    }
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoadingRequests = true);
    final requests = await FriendsService.getFriendRequests();
    if (mounted) {
      setState(() {
        _incomingRequests = requests.where((r) => r.isIncoming).toList();
        _outgoingRequests = requests.where((r) => !r.isIncoming).toList();
        _isLoadingRequests = false;
      });
    }
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    final query = val.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _lastSearchQuery = '';
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _isSearching = true;
        _lastSearchQuery = query;
      });
      final results = await FriendsService.searchUsers(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _addFriendDirect(Map<String, dynamic> user) async {
    if (_isGuest) {
      await PaiChanAuthGate.show(
        context,
        currentProfile: _profile,
        accentColor: widget.accentColor,
        pendingFriendUser: user,
        onAuthenticated: () {
          _loadFriends();
          _loadRequests();
          widget.onFriendsChanged?.call();
        },
      );
      return;
    }

    final success = await FriendsService.addFriend(user);
    if (!mounted) return;

    final displayName = (user['username'] ?? user['name'] ?? 'Пользователь').toString().trim();
    if (success) {
      setState(() {
        _friends = List<Map<String, dynamic>>.from(FriendsService.friendsNotifier.value);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Друг $displayName добавлен'),
          backgroundColor: const Color(0xFF00FF66).withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadRequests();
      widget.onFriendsChanged?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('«$displayName» уже в списке друзей или запрос отправлен'),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _respondToRequest(String requestId, {required bool accept}) async {
    final success = await FriendsService.respondToFriendRequest(requestId, accept: accept);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Заявка принята!' : 'Заявка отклонена'),
          backgroundColor: accept ? const Color(0xFF00FF66).withValues(alpha: 0.9) : Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadFriends();
      await _loadRequests();
      widget.onFriendsChanged?.call();
    }
  }

  Future<void> _removeFriend(Map<String, dynamic> friend) async {
    final name = (friend['username'] ?? friend['name'] ?? 'Пользователь').toString().trim();
    final id = friend['id']?.toString() ?? name;
    // Мгновенное оптимистичное удаление в UI (0ms)
    setState(() {
      _friends.removeWhere((f) => (f['id']?.toString() ?? '') == id);
    });
    final ok = await FriendsService.removeFriend(id);
    if (!mounted) return;
    widget.onFriendsChanged?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '«$name» удален из друзей' : 'Не удалось удалить «$name»'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openQrInviteSheet() {
    if (_isGuest) {
      PaiChanAuthGate.show(
        context,
        currentProfile: _profile,
        accentColor: widget.accentColor,
        onAuthenticated: () {
          _loadProfileIfNull();
          _loadFriends();
          _loadRequests();
          widget.onFriendsChanged?.call();
        },
      );
      return;
    }
    String myId = 'me';
    try {
      myId = Supabase.instance.client.auth.currentUser?.id ?? 'me';
    } catch (_) {}
    final p = _profile ??
        UserProfile(
          id: myId,
          username: 'Kuro',
          createdAt: DateTime.now(),
        );
    QrInviteSheet.show(context, profile: p, accentColor: widget.accentColor);
  }

  void _openQrScannerSheet() {
    QrScannerSheet.show(
      context,
      accentColor: widget.accentColor,
      onCodeDetected: (code) {
        FriendInviteConfirmationDialog.show(
          context,
          inviteCode: code,
          accentColor: widget.accentColor,
          onAccepted: () {
            _loadFriends();
            _loadRequests();
            widget.onFriendsChanged?.call();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentColor;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // Header bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : scheme.surfaceContainerHigh.withValues(alpha: 0.4),
                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.people_alt_rounded, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Друзья и Сообщество',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Смотрите аниме вместе и делитесь QR-визиткой',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Кнопка «Мой QR»
                  IconButton(
                    onPressed: _openQrInviteSheet,
                    icon: Icon(Icons.qr_code_rounded, color: accent),
                    tooltip: 'Мой QR-код и инвайт-ссылка',
                  ),
                  // Кнопка «Сканировать»
                  IconButton(
                    onPressed: _openQrScannerSheet,
                    icon: Icon(Icons.qr_code_scanner_rounded, color: scheme.onSurface),
                    tooltip: 'Сканировать QR-код',
                  ),
                  IconButton(
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                    tooltip: 'Закрыть',
                  ),
                ],
              ),
            ),

            // Tab bar
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.6)),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: scheme.onSurface,
                unselectedLabelColor: scheme.onSurfaceVariant,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.group_rounded, size: 15),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Друзья (${_friends.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.mail_outline_rounded, size: 15),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Заявки${_incomingRequests.isNotEmpty ? " (${_incomingRequests.length})" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_search_rounded, size: 15),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Поиск и Код',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFriendsListTab(accent, scheme, isDark),
                  _buildRequestsTab(accent, scheme, isDark),
                  _buildSearchAndAddTab(accent, scheme, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsListTab(Color accent, ColorScheme scheme, bool isDark) {
    if (_isGuest) {
      return Center(
        child: PaiChanAuthGate(
          isEmbedded: true,
          currentProfile: _profile,
          accentColor: accent,
          pendingInviteCode: _detectedClipboardInvite,
          onAuthenticated: () {
            _loadProfileIfNull();
            _loadFriends();
            _loadRequests();
            widget.onFriendsChanged?.call();
          },
        ),
      );
    }

    if (_isLoadingFriends) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_off_rounded, size: 48, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'У вас пока нет друзей',
                style: TextStyle(color: scheme.onSurface, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Поделитесь своим QR-кодом или найдите друзей по тегу (#0001) / коду (SP-...)',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _openQrInviteSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: scheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.qr_code_rounded, size: 16),
                    label: const Text('Мой QR-код'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _tabController.animateTo(2),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.search_rounded, size: 16),
                    label: const Text('Найти по тегу'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: _friends.length,
      itemBuilder: (context, index) {
        final friend = _friends[index];
        final isOnline = friend['isOnline'] == true;
        final roomCode = friend['room'] ?? friend['roomCode'];
        final rawName = (friend['username'] ?? friend['name'] ?? '').toString().trim();
        final friendName = rawName.isEmpty ? 'Пользователь' : rawName;
        final tag = FriendProfile.normalizeTag(friend['tag']?.toString());
        final friendCode = friend['friend_code']?.toString();
        final avatarUrl = (friend['avatar_url'] ?? friend['avatar'])?.toString();
        final baseStatus = friend['custom_status'] ?? friend['status'] ?? friend['statusText'] ?? (isOnline ? 'В сети' : 'Не в сети');
        final status = (friendCode != null && friendCode.isNotEmpty)
            ? '$friendCode • $baseStatus'
            : baseStatus.toString();

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  AppAvatar(
                    avatarUrl: avatarUrl,
                    username: friendName,
                    size: 40,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isOnline ? accent : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                        border: Border.all(color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLowest, width: 1.5),
                      ),
                    ),
                  ),
                ],
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
                            friendName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (tag.isNotEmpty)
                          Text(
                            tag,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (roomCode != null && roomCode.toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ElevatedButton(
                    onPressed: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                      context.push('/watch-together?pin=$roomCode');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent.withValues(alpha: 0.18),
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Войти', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 18, color: scheme.onSurfaceVariant),
                color: scheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  if (val == 'remove') {
                    _removeFriend(friend);
                  } else if (val == 'profile') {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                    context.pushNamed('profile', queryParameters: {'userId': friend['id']?.toString() ?? friendName});
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(
                      children: [
                        Icon(Icons.person_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text('Открыть профиль', style: TextStyle(color: scheme.onSurface, fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: const [
                        Icon(Icons.person_remove_rounded, size: 16, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('Удалить из друзей', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRequestsTab(Color accent, ColorScheme scheme, bool isDark) {
    if (_isLoadingRequests) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_incomingRequests.isEmpty && _outgoingRequests.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mail_outline_rounded, size: 44, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                'Нет активных заявок',
                style: TextStyle(color: scheme.onSurface, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Здесь будут отображаться входящие и отправленные запросы в друзья',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        if (_incomingRequests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'ВХОДЯЩИЕ ЗАПРОСЫ (${_incomingRequests.length})',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ..._incomingRequests.map((req) {
            final p = req.profile;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  AppAvatar(avatarUrl: p.avatarUrl, username: p.username, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p.username}${p.tag}',
                          style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        if (p.customStatus != null)
                          Text(p.customStatus!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _respondToRequest(req.id, accept: false),
                    icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
                    tooltip: 'Отклонить',
                  ),
                  IconButton(
                    onPressed: () => _respondToRequest(req.id, accept: true),
                    icon: const Icon(Icons.check_rounded, color: Color(0xFF00FF66), size: 20),
                    tooltip: 'Принять',
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
        ],

        if (_outgoingRequests.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'ОТПРАВЛЕННЫЕ ЗАПРОСЫ (${_outgoingRequests.length})',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          ..._outgoingRequests.map((req) {
            final p = req.profile;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  AppAvatar(avatarUrl: p.avatarUrl, username: p.username, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p.username}${p.tag}',
                          style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        Text('Ожидает подтверждения', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _respondToRequest(req.id, accept: false),
                    child: const Text('Отменить', style: TextStyle(color: Colors.redAccent, fontSize: 11.5)),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildSearchAndAddTab(Color accent, ColorScheme scheme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner если в буфере обмена найдено приглашение
          if (_detectedClipboardInvite != null) ...[
            Container(
              key: const ValueKey('clipboard_invite_banner'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, color: accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Найдено приглашение в буфере обмена',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        Text(
                          'Код: $_detectedClipboardInvite',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final code = _detectedClipboardInvite!;
                      setState(() => _detectedClipboardInvite = null);
                      FriendInviteConfirmationDialog.show(
                        context,
                        inviteCode: code,
                        accentColor: accent,
                        onAccepted: () {
                          _loadFriends();
                          _loadRequests();
                          widget.onFriendsChanged?.call();
                        },
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Открыть', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],

          // Quick actions: Мой QR & Сканировать
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openQrInviteSheet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: Icon(Icons.qr_code_rounded, color: accent, size: 16),
                  label: const Text('Моя визитка QR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openQrScannerSheet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                  label: const Text('Сканировать QR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Поле ввода поиска
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: TextStyle(color: scheme.onSurface, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Поиск: Username#0001, SP-XXXXXX или никнейм...',
              hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 12.5),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : scheme.surfaceContainerHigh.withValues(alpha: 0.4),
              prefixIcon: Icon(Icons.search_rounded, color: accent, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded, size: 18, color: scheme.onSurfaceVariant),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Результаты поиска
          _buildSearchResultsSection(accent, scheme, isDark),
        ],
      ),
    );
  }

  Widget _buildSearchResultsSection(Color accent, ColorScheme scheme, bool isDark) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _lastSearchQuery.trim();

    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 44, color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 10),
            Text(
              'Введите никнейм, тег (#XXXX) или код (SP-XXXXXX)',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Поиск синхронизируется с базой аккаунтов Supabase в реальном времени',
              style: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 11),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 40, color: scheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 10),
              Text(
                'Пользователь «$query» не найден',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Убедитесь в правильности тега или попросите друга отправить QR-код/инвайт-ссылку',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final profile = _searchResults[index];
        final name = profile.username;
        final tag = profile.tag;
        final friendCode = profile.friendCode;
        final status = profile.customStatus ?? (profile.isOnline ? 'В сети' : 'Не в сети');
        final isAlreadyFriend = _friends.any(
          (f) => (f['id'] ?? '').toString() == profile.id,
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              AppAvatar(
                avatarUrl: profile.avatarUrl,
                username: name,
                size: 38,
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
                            name,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (tag.isNotEmpty)
                          Text(
                            tag,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      friendCode != null ? 'Код: $friendCode • $status' : status,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAlreadyFriend)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.08) : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Text('В друзьях', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _addFriendDirect(profile.toMap()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: scheme.onPrimary,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.person_add_rounded, size: 14),
                  label: const Text('Добавить', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        );
      },
    );
  }
}
