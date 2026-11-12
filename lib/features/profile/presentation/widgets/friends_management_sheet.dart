import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../services/friends_service.dart';

/// Открывает адаптивную панель управления друзьями (Sheet на мобилках, Dialog на десктопе)
Future<void> showFriendsManagementSheet(BuildContext context, {Color? accentColor, VoidCallback? onFriendsChanged}) {
  final isDesktop = MediaQuery.of(context).size.width >= 650;
  final accent = accentColor ?? const Color(0xFF6366F1);

  if (isDesktop) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
          child: FriendsManagementView(accentColor: accent, onFriendsChanged: onFriendsChanged),
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
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
        child: FriendsManagementView(accentColor: accent, onFriendsChanged: onFriendsChanged),
      ),
    ),
  );
}

class FriendsManagementView extends StatefulWidget {
  final Color accentColor;
  final VoidCallback? onFriendsChanged;

  const FriendsManagementView({
    super.key,
    required this.accentColor,
    this.onFriendsChanged,
  });

  @override
  State<FriendsManagementView> createState() => _FriendsManagementViewState();
}

class _FriendsManagementViewState extends State<FriendsManagementView> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoadingFriends = true;
  bool _isSearching = false;
  String _lastSearchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFriends();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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

  Future<void> _addFriend(Map<String, dynamic> user) async {
    final success = await FriendsService.addFriend(user);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('«${user['name']}» добавлен в список друзей!'),
          backgroundColor: const Color(0xFF00FF66).withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadFriends();
      widget.onFriendsChanged?.call();
      _tabController.animateTo(0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('«${user['name']}» уже в списке друзей'),
          backgroundColor: Colors.orangeAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _removeFriend(Map<String, dynamic> friend) async {
    final name = friend['name'] ?? '';
    final id = friend['id']?.toString() ?? name;
    await FriendsService.removeFriend(id);
    if (!mounted) return;
    await _loadFriends();
    widget.onFriendsChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('«$name» удален из друзей'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
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
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Друзья и Сообщество',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Смотрите аниме вместе и следите за статусами',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
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
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: accent.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.6)),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.group_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text('Мои друзья (${_friends.length})'),
                      ],
                    ),
                  ),
                  const Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_add_alt_1_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Найти / Добавить'),
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
                  _buildFriendsListTab(accent),
                  _buildSearchAndAddTab(accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendsListTab(Color accent) {
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
              Icon(Icons.group_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              const Text(
                'У вас пока нет друзей',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Перейдите на вкладку «Найти / Добавить», чтобы найти пользователя в Supabase или ввести его никнейм',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _tabController.animateTo(1),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.search_rounded, size: 16),
                label: const Text('Найти пользователей'),
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
        final friendName = friend['name'] ?? 'Друг';
        final status = friend['status'] ?? friend['statusText'] ?? (isOnline ? 'В сети' : 'Не в сети');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  AppAvatar(
                    avatarUrl: friend['avatar'] as String?,
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
                        color: isOnline ? const Color(0xFF00FF66) : Colors.white38,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF131722), width: 1.5),
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
                    Text(
                      friendName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
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
                      Navigator.of(context).pop();
                      context.push('/watch-together?pin=$roomCode');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent.withValues(alpha: 0.2),
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Войти', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.white54),
                color: const Color(0xFF1B2230),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  if (val == 'remove') {
                    _removeFriend(friend);
                  } else if (val == 'profile') {
                    Navigator.of(context).pop();
                    context.pushNamed('profile', queryParameters: {'userId': friendName});
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'profile',
                    child: Row(
                      children: const [
                        Icon(Icons.person_outline_rounded, size: 16, color: Colors.white70),
                        SizedBox(width: 8),
                        Text('Открыть профиль', style: TextStyle(color: Colors.white, fontSize: 12)),
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

  Widget _buildSearchAndAddTab(Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Поле ввода поиска
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Поиск по никнейму или ID в Supabase...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              prefixIcon: Icon(Icons.search_rounded, color: accent, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white54),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),

          // Результаты поиска или кнопка прямого добавления
          Expanded(
            child: _buildSearchResultsSection(accent),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsSection(Color accent) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _lastSearchQuery.trim();

    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search_rounded, size: 44, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            const Text(
              'Начните вводить никнейм',
              style: TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 4),
            const Text(
              'Поиск синхронизируется с базой аккаунтов Supabase',
              style: TextStyle(color: Colors.white38, fontSize: 11),
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
              Icon(Icons.search_off_rounded, size: 40, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 10),
              Text(
                'Пользователь «$query» не найден в облаке',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Вы можете добавить этот никнейм в свой локальный список друзей:',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () => _addFriend({
                  'name': query,
                  'avatar': 'cat',
                  'status': 'Пользователь SyncPai',
                  'isOnline': false,
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: Text('Добавить «$query»'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final user = _searchResults[index];
        final name = user['name'] ?? '';
        final status = user['status'] ?? 'В SyncPai';
        final isAlreadyFriend = _friends.any(
          (f) => (f['name'] ?? '').toString().toLowerCase() == name.toString().toLowerCase(),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              AppAvatar(
                avatarUrl: user['avatar'] as String?,
                username: name,
                size: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
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
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_rounded, size: 14, color: Color(0xFF00FF66)),
                      SizedBox(width: 4),
                      Text('В друзьях', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _addFriend(user),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
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

