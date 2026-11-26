import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/steam_avatar_frame.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../services/duo_sync_service.dart';
import '../../services/friends_service.dart';

class DuoDiptychThemeSpec {
  final String id;
  final String title;
  final bool isPlus;
  final bool isCustomSpread;
  final String? imageUrl;
  final List<Color> leftGradient;
  final List<Color> rightGradient;
  final Color accent;

  const DuoDiptychThemeSpec({
    required this.id,
    required this.title,
    this.isPlus = false,
    this.isCustomSpread = false,
    this.imageUrl,
    required this.leftGradient,
    required this.rightGradient,
    required this.accent,
  });

  static const List<DuoDiptychThemeSpec> all = [
    DuoDiptychThemeSpec(
      id: 'sunset_bridge',
      title: 'Закат у побережья',
      imageUrl:
          'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=1600&q=80',
      leftGradient: [Color(0xFF1A1428), Color(0xFF4A1D42), Color(0xFFFF6B4A)],
      rightGradient: [Color(0xFFFF6B4A), Color(0xFF4A1D42), Color(0xFF1A1428)],
      accent: Color(0xFFFF6B4A),
    ),
    DuoDiptychThemeSpec(
      id: 'shibuya_rain',
      title: 'Ночной Сибуя (Дождь)',
      imageUrl:
          'https://images.unsplash.com/photo-1542051841857-5f90071e7989?w=1600&q=80',
      leftGradient: [Color(0xFF0E1826), Color(0xFF1B2E48), Color(0xFF38BDF8)],
      rightGradient: [Color(0xFF38BDF8), Color(0xFF1B2E48), Color(0xFF0E1826)],
      accent: Color(0xFF38BDF8),
    ),
    DuoDiptychThemeSpec(
      id: 'cyber_neon_2099',
      title: 'Ночной Токио с крыши',
      isPlus: true,
      imageUrl:
          'https://images.unsplash.com/photo-1514565131-fce0801e5785?w=1600&q=80',
      leftGradient: [Color(0xFF0A1424), Color(0xFF132D4A), Color(0xFF22D3EE)],
      rightGradient: [Color(0xFF22D3EE), Color(0xFF3B1A54), Color(0xFF0F1320)],
      accent: Color(0xFF22D3EE),
    ),
    DuoDiptychThemeSpec(
      id: 'sakura_dawn',
      title: 'Сакура у реки',
      isPlus: true,
      imageUrl:
          'https://images.unsplash.com/photo-1522383225653-ed111181a951?w=1600&q=80',
      leftGradient: [Color(0xFF241322), Color(0xFF4F1D3D), Color(0xFFF472B6)],
      rightGradient: [Color(0xFFF472B6), Color(0xFF4F1D3D), Color(0xFF241322)],
      accent: Color(0xFFF472B6),
    ),
    DuoDiptychThemeSpec(
      id: 'shadow_monarch',
      title: 'Звёздное небо над городом',
      isPlus: true,
      imageUrl:
          'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=1600&q=80',
      leftGradient: [Color(0xFF0B0E1A), Color(0xFF22164A), Color(0xFF818CF8)],
      rightGradient: [Color(0xFF818CF8), Color(0xFF22164A), Color(0xFF0B0E1A)],
      accent: Color(0xFF818CF8),
    ),
    DuoDiptychThemeSpec(
      id: 'kyoto_bamboo',
      title: 'Летний Токио на закате',
      imageUrl:
          'https://images.unsplash.com/photo-1503899036084-c55cdd92da26?w=1600&q=80',
      leftGradient: [Color(0xFF10221C), Color(0xFF1E3A30), Color(0xFF34D399)],
      rightGradient: [Color(0xFF34D399), Color(0xFF1E3A30), Color(0xFF10221C)],
      accent: Color(0xFF34D399),
    ),
    DuoDiptychThemeSpec(
      id: 'custom_spread',
      title: 'Своя панорама (Wallhaven / фото)',
      isCustomSpread: true,
      leftGradient: [Color(0xFF141821), Color(0xFF1E2433)],
      rightGradient: [Color(0xFF1E2433), Color(0xFF141821)],
      accent: Color(0xFFFF6B4A),
    ),
  ];

  static DuoDiptychThemeSpec fromId(String id) {
    return all.firstWhere((e) => e.id == id, orElse: () => all.first);
  }
}

/// Рендерит левую (`0.0..0.5`) или правую (`0.5..1.0`) половину панорамного диптиха.
class DuoDiptychHalfBanner extends StatelessWidget {
  final String themeId;
  final bool isLeft;
  final String? customImageUrl;
  final double width;
  final double height;

  const DuoDiptychHalfBanner({
    super.key,
    required this.themeId,
    required this.isLeft,
    this.customImageUrl,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final spec = DuoDiptychThemeSpec.fromId(themeId);
    final customUrl = customImageUrl?.trim() ?? '';
    final effectiveUrl =
        customUrl.isNotEmpty ? customUrl : (spec.imageUrl ?? '');

    if (effectiveUrl.isNotEmpty) {
      return ClipRect(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned(
                left: isLeft ? 0 : -width,
                top: 0,
                width: width * 2,
                height: height,
                child: effectiveUrl.startsWith('http')
                    ? CachedNetworkImage(
                        imageUrl: wrapCorsSafeUrl(effectiveUrl),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isLeft
                                  ? spec.leftGradient
                                  : spec.rightGradient,
                            ),
                          ),
                        ),
                      )
                    : Image.file(
                        File(effectiveUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isLeft
                                  ? spec.leftGradient
                                  : spec.rightGradient,
                            ),
                          ),
                        ),
                      ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        const Color(0x990B0E14),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isLeft ? spec.leftGradient : spec.rightGradient,
        ),
      ),
      child: Align(
        alignment: isLeft ? Alignment.bottomLeft : Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            isLeft ? 'Левая часть' : 'Правая часть',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Полноценный экран/шторка управления «Парный профиль (Duo)».
class DuoProfileSheet extends StatefulWidget {
  final UserProfile profile;
  final DuoLinkRecord? initialLink;
  final ValueChanged<DuoLinkRecord?>? onUpdated;

  const DuoProfileSheet({
    super.key,
    required this.profile,
    this.initialLink,
    this.onUpdated,
  });

  static Future<DuoLinkRecord?> show(
    BuildContext context, {
    required UserProfile profile,
    DuoLinkRecord? initialLink,
    ValueChanged<DuoLinkRecord?>? onUpdated,
  }) {
    return showModalBottomSheet<DuoLinkRecord?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DuoProfileSheet(
        profile: profile,
        initialLink: initialLink,
        onUpdated: onUpdated,
      ),
    );
  }

  @override
  State<DuoProfileSheet> createState() => _DuoProfileSheetState();
}

class _DuoProfileSheetState extends State<DuoProfileSheet> {
  final TextEditingController _partnerCodeCtrl = TextEditingController();
  final TextEditingController _customSpreadCtrl = TextEditingController();

  DuoLinkRecord? _link;
  bool _isLoading = true;
  bool _isBusy = false;
  String _selectedRelation = DuoSyncService.relationPresets.first;
  String _selectedThemeId = DuoDiptychThemeSpec.all.first.id;
  List<Map<String, dynamic>> _friends = const [];

  @override
  void initState() {
    super.initState();
    _link = widget.initialLink;
    if (_link != null) {
      _selectedRelation = _link!.relationLabel;
      _selectedThemeId = _link!.diptychThemeId;
      _customSpreadCtrl.text = _link!.customLeftArtUrl ?? '';
    }
    _initData();
  }

  Future<void> _initData() async {
    final loaded = _link ?? await DuoSyncService.instance.getCurrentDuoLink();
    final friends = FriendsService.getCachedFriends();
    if (!mounted) return;
    setState(() {
      _link = loaded;
      if (loaded != null) {
        _selectedRelation = loaded.relationLabel;
        _selectedThemeId = loaded.diptychThemeId;
        _customSpreadCtrl.text = loaded.customLeftArtUrl ?? '';
      }
      _friends = friends;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _partnerCodeCtrl.dispose();
    _customSpreadCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateCode() async {
    setState(() => _isBusy = true);
    final created = await DuoSyncService.instance.createOrGetPendingInvite(
      relationLabel: _selectedRelation,
      diptychThemeId: _selectedThemeId,
    );
    if (!mounted) return;
    setState(() {
      _link = created;
      _isBusy = false;
    });
    widget.onUpdated?.call(created);
  }

  Future<void> _acceptCode() async {
    final code = _partnerCodeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _isBusy = true);
    final accepted = await DuoSyncService.instance.acceptInviteCode(code);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (accepted == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Код не найден или уже использован'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _link = accepted);
    widget.onUpdated?.call(accepted);
  }

  Future<void> _saveSettings() async {
    final current = _link;
    if (current == null) return;
    setState(() => _isBusy = true);
    final spreadUrl = _customSpreadCtrl.text.trim();
    final updated = await DuoSyncService.instance.updateDuoSettings(
      current,
      relationLabel: _selectedRelation,
      diptychThemeId: _selectedThemeId,
      customLeftArtUrl: spreadUrl.isNotEmpty ? spreadUrl : null,
      customRightArtUrl: spreadUrl.isNotEmpty ? spreadUrl : null,
    );
    if (!mounted) return;
    setState(() {
      _link = updated;
      _isBusy = false;
    });
    widget.onUpdated?.call(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Настройки парного профиля сохранены'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _dissolveLink() async {
    final current = _link;
    if (current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B26),
        title: const Text(
          'Разорвать связь Duo?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Парный диптих и счётчик совместных дней будут сброшены.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B4A),
            ),
            child: const Text('Разорвать'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DuoSyncService.instance.dissolveDuoLink(current);
    if (!mounted) return;
    setState(() => _link = null);
    widget.onUpdated?.call(null);
  }

  Future<void> _pickCustomSpread() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.firstOrNull?.path;
    if (path != null && path.isNotEmpty && mounted) {
      setState(() {
        _customSpreadCtrl.text = path;
        _selectedThemeId = 'custom_spread';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return SafeArea(
      child: Container(
        height: maxH,
        margin: const EdgeInsets.fromLTRB(10, 20, 10, 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF11151E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  color: Color(0xFFFF6B4A),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Парный профиль (Duo)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(_link),
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_link == null || !_link!.isActive)
                            _buildUnpairedSection()
                          else
                            _buildPairedHeader(_link!),
                          const SizedBox(height: 16),
                          _buildDiptychEditor(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnpairedSection() {
    final pendingCode = _link?.inviteCode;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Пригласить партнёра по коду или ссылке',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (pendingCode != null && pendingCode.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF11151E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    pendingCode,
                    style: const TextStyle(
                      color: Color(0xFFFF6B4A),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: pendingCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Код скопирован'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        child: const Text('Скопировать код'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {
                          final url = Uri.parse(
                            'https://t.me/syncpai_bot?start=duo_$pendingCode',
                          );
                          launchUrl(url, mode: LaunchMode.externalApplication);
                        },
                        child: const Text('Поделиться ссылкой'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else
            FilledButton.icon(
              onPressed: _isBusy ? null : _generateCode,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B4A),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: const Text('Создать код приглашения'),
            ),
          const SizedBox(height: 14),
          const Text(
            'Или введите код партнёра',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _partnerCodeCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Ввести код партнёра (PAI-...)',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12.5),
                      filled: true,
                      fillColor: const Color(0xFF11151E),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _isBusy ? null : _acceptCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1C212E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Подтвердить пару'),
                ),
              ),
            ],
          ),
          if (_friends.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Быстрое приглашение друзей',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ..._friends.take(3).map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        AppAvatar(
                          avatarUrl: (f['avatar_url'] ?? '').toString(),
                          username: (f['username'] ?? 'Друг').toString(),
                          size: 30,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (f['username'] ?? 'Друг').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _isBusy ? null : _generateCode,
                          child: const Text('Пригласить'),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _buildPairedHeader(DuoLinkRecord link) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                children: [
                  AppAvatar(
                    avatarUrl: widget.profile.avatarUrl,
                    username: widget.profile.username,
                    size: 46,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.profile.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B4A).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _selectedRelation,
                      style: const TextStyle(
                        color: Color(0xFFFF6B4A),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Вместе в SyncPai: ${link.daysTogether} дн.',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  const AppAvatar(
                    avatarUrl: '',
                    username: 'Партнёр',
                    size: 46,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Партнёр',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: DuoSyncService.relationPresets.map((preset) {
              final selected = _selectedRelation == preset;
              return ChoiceChip(
                label: Text(preset),
                selected: selected,
                onSelected: (_) => setState(() => _selectedRelation = preset),
                selectedColor: const Color(0xFFFF6B4A).withValues(alpha: 0.22),
                backgroundColor: const Color(0xFF11151E),
                labelStyle: TextStyle(
                  color: selected ? const Color(0xFFFF6B4A) : Colors.white70,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _dissolveLink,
              style: TextButton.styleFrom(foregroundColor: Colors.white54),
              child: const Text('Разорвать связь'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiptychEditor() {
    final customUrl = _customSpreadCtrl.text.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Диптих-витрина (50/50 панорама)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          // Живое превью 50/50
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final halfW = (constraints.maxWidth - 2) / 2;
                return Row(
                  children: [
                    Stack(
                      children: [
                        DuoDiptychHalfBanner(
                          themeId: _selectedThemeId,
                          isLeft: true,
                          customImageUrl: customUrl,
                          width: halfW,
                          height: 86,
                        ),
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            color: const Color(0xCC11151E),
                            child: Text(
                              'Левый: ${widget.profile.username}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Container(width: 2, height: 86, color: const Color(0x33FFFFFF)),
                    Stack(
                      children: [
                        DuoDiptychHalfBanner(
                          themeId: _selectedThemeId,
                          isLeft: false,
                          customImageUrl: customUrl,
                          width: halfW,
                          height: 86,
                        ),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            color: const Color(0xCC11151E),
                            child: const Text(
                              'Правый: Партнёр',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          ...DuoDiptychThemeSpec.all.map((theme) {
            final selected = _selectedThemeId == theme.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedThemeId = theme.id),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.accent.withValues(alpha: 0.14)
                        : const Color(0xFF11151E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? theme.accent : const Color(0x14FFFFFF),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 18,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: LinearGradient(colors: theme.leftGradient),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          theme.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Text(
                        'Бесплатно',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (_selectedThemeId == 'custom_spread') ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _customSpreadCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText: 'URL или путь к развороту манги / фото...',
                        hintStyle:
                            const TextStyle(color: Colors.white38, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF11151E),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: _pickCustomSpread,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Выбрать'),
                  ),
                ),
              ],
            ),
          ],
          if (_link != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: _isBusy ? null : _saveSettings,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B4A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Сохранить настройки Duo',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Карточка «Парный профиль (Duo)» на `ProfileScreen` с аналитикой и экспортом PNG.
class DuoProfileCard extends StatefulWidget {
  final UserProfile profile;
  final DuoLinkRecord? duoLink;
  final VoidCallback onManageTap;
  final VoidCallback? onWatchTogetherTap;

  const DuoProfileCard({
    super.key,
    required this.profile,
    required this.duoLink,
    required this.onManageTap,
    this.onWatchTogetherTap,
  });

  @override
  State<DuoProfileCard> createState() => _DuoProfileCardState();
}

class _DuoProfileCardState extends State<DuoProfileCard> {
  final GlobalKey _exportKey = GlobalKey();
  DuoAnalyticsSummary? _analytics;
  Map<String, dynamic>? _partnerProfile;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  @override
  void didUpdateWidget(covariant DuoProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duoLink?.id != widget.duoLink?.id ||
        oldWidget.duoLink?.status != widget.duoLink?.status ||
        oldWidget.duoLink?.userB != widget.duoLink?.userB) {
      _loadAnalytics();
    }
  }

  Future<void> _loadAnalytics() async {
    final link = widget.duoLink;
    if (link == null || !link.isActive) return;
    final partnerId = link.partnerIdFor(widget.profile.id) ?? link.userB ?? '';
    if (partnerId.isEmpty) return;

    final myEntries = getIt.isRegistered<AnimeListCubit>()
        ? getIt<AnimeListCubit>().state.allEntries
        : const [];
    final results = await Future.wait<dynamic>([
      DuoSyncService.instance.computeSharedAnalytics(
        partnerId: partnerId,
        myEntries: List.from(myEntries),
      ),
      FriendsService.fetchFriendFullProfile(partnerId),
    ]);
    if (mounted) {
      setState(() {
        _analytics = results[0] as DuoAnalyticsSummary?;
        _partnerProfile = results[1] as Map<String, dynamic>?;
      });
    }
  }

  Future<void> _exportDuoCard() async {
    try {
      final boundary =
          _exportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final outPath =
          '${dir.path}${Platform.pathSeparator}syncpai_duo_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(outPath).writeAsBytes(byteData.buffer.asUint8List());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Парная карточка сохранена: $outPath'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {}
  }

  void _showSharedTitlesModal() {
    final titles = _analytics?.sharedTitles ?? const <DuoSharedTitleItem>[];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF11151E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Общие тайтлы (${titles.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (titles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Пока нет пересечений в списках аниме.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: titles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final t = titles[i];
                      return Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 36,
                              height: 50,
                              child: t.posterUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: wrapCorsSafeUrl(t.posterUrl),
                                      fit: BoxFit.cover,
                                    )
                                  : const ColoredBox(color: Color(0xFF161B26)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t.titleName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            t.statusLabel,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.duoLink;
    if (link == null || !link.isActive) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Container(
          key: const ValueKey('duo_profile_unpaired_card'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF11151E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x14FFFFFF)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.people_alt_rounded,
                color: Color(0xFFFF6B4A),
                size: 22,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Парный профиль (Duo)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Свяжите профиль с другом для общего диптиха и статистики',
                      style: TextStyle(color: Colors.white54, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: FilledButton(
                  key: const ValueKey('duo_open_sheet_btn'),
                  onPressed: widget.onManageTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B4A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Создать парный профиль',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final compat = _analytics?.compatibilityPercent ?? 78;
    final sharedCount = _analytics?.sharedTitlesCount ?? 0;
    final sharedHours = (_analytics?.sharedHours ?? 0.0).toStringAsFixed(1);
    final spec = DuoDiptychThemeSpec.fromId(link.diptychThemeId);
    final bannerUrl = link.resolvedBannerUrl ?? spec.imageUrl ?? '';

    final myName =
        widget.profile.username.trim().isNotEmpty ? widget.profile.username.trim() : 'Вы';
    final myFrameId = widget.profile.frameId ?? 'none';
    final myActivity = (widget.profile.customStatus ?? '').trim().isNotEmpty
        ? widget.profile.customStatus!.trim()
        : 'В сети';

    final partnerName =
        (_partnerProfile?['username'] ?? '').toString().trim().isNotEmpty
            ? _partnerProfile!['username'].toString().trim()
            : 'Напарник';
    final partnerAvatarUrl = _partnerProfile?['avatar_url']?.toString();
    final partnerFrameId = (_partnerProfile?['frame_id'] ??
            _partnerProfile?['avatar_frame_id'] ??
            _partnerProfile?['avatar_frame'] ??
            'none')
        .toString();
    final partnerStatusRaw =
        (_partnerProfile?['custom_status'] ?? '').toString().trim();
    final partnerActivity =
        partnerStatusRaw.isNotEmpty ? partnerStatusRaw : 'В сети';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: RepaintBoundary(
        key: _exportKey,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            key: const ValueKey('duo_profile_active_card'),
            decoration: BoxDecoration(
              color: const Color(0xFF11151E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x18FFFFFF)),
            ),
            child: Stack(
              children: [
                if (bannerUrl.isNotEmpty)
                  Positioned.fill(
                    child: bannerUrl.startsWith('http')
                        ? CachedNetworkImage(
                            imageUrl: wrapCorsSafeUrl(bannerUrl),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: spec.leftGradient,
                                ),
                              ),
                            ),
                          )
                        : Image.file(
                            File(bannerUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: spec.leftGradient,
                                ),
                              ),
                            ),
                          ),
                  )
                else
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: spec.leftGradient),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: const [
                          Color(0xCC0B0E14),
                          Color(0x330B0E14),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC0B0E14),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0x18FFFFFF)),
                            ),
                            child: Text(
                              'ПАРНЫЙ ПРОФИЛЬ • ${link.relationLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _exportDuoCard,
                            tooltip: 'Поделиться парной карточкой',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.share_rounded,
                              color: Colors.white70,
                              size: 16,
                            ),
                          ),
                          TextButton(
                            onPressed: widget.onManageTap,
                            style: TextButton.styleFrom(
                              backgroundColor: const Color(0xCC0B0E14),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(
                                  color: Color(0x18FFFFFF),
                                ),
                              ),
                            ),
                            child: const Text(
                              'Настроить',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SteamAvatarFrameWidget(
                                  frameId: myFrameId,
                                  size: 52,
                                  child: AppAvatar(
                                    avatarUrl: widget.profile.avatarUrl,
                                    username: myName,
                                    size: 46,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  myName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  myActivity,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xD90B0E14),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: const Color(0x18FFFFFF),
                                    ),
                                  ),
                                  child: Text(
                                    'Синхронизированы • ${link.daysTogether} дн.',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: widget.onWatchTogetherTap ??
                                      widget.onManageTap,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6B4A),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    minimumSize: Size.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Смотреть вместе',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                SteamAvatarFrameWidget(
                                  frameId: partnerFrameId,
                                  size: 52,
                                  child: AppAvatar(
                                    avatarUrl: partnerAvatarUrl,
                                    username: partnerName,
                                    size: 46,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  partnerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  partnerActivity,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _DuoMetricTile(
                              label: 'Совместимость',
                              value: '$compat%',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: _showSharedTitlesModal,
                              borderRadius: BorderRadius.circular(10),
                              child: _DuoMetricTile(
                                label: 'Общие тайтлы',
                                value: '$sharedCount',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DuoMetricTile(
                              label: 'Совместные часы',
                              value: '$sharedHours ч.',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DuoMetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _DuoMetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
