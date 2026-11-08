import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/entities/episode_item.dart';
import '../../../player/domain/entities/player_quality.dart';

/// Шторка детальной настройки комнаты совместного просмотра перед запуском
/// Позволяет выбрать лимит участников (2-8 или безлимит), права управления,
/// качество и мгновенно сгенерировать диплинк-приглашение.
class SyncRoomConfigSheet extends StatefulWidget {
  final AnimeTitle title;
  final EpisodeItem episode;
  final PlayerQuality initialQuality;
  final void Function({
    required int maxPeers,
    required bool isHostControlOnly,
    required PlayerQuality quality,
    required String roomCode,
  }) onConfirm;

  const SyncRoomConfigSheet({
    super.key,
    required this.title,
    required this.episode,
    this.initialQuality = PlayerQuality.hd,
    required this.onConfirm,
  });

  static Future<void> show(
    BuildContext context, {
    required AnimeTitle title,
    required EpisodeItem episode,
    PlayerQuality initialQuality = PlayerQuality.hd,
    required void Function({
      required int maxPeers,
      required bool isHostControlOnly,
      required PlayerQuality quality,
      required String roomCode,
    }) onConfirm,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: SyncRoomConfigSheet(
          title: title,
          episode: episode,
          initialQuality: initialQuality,
          onConfirm: onConfirm,
        ),
      ),
    );
  }

  @override
  State<SyncRoomConfigSheet> createState() => _SyncRoomConfigSheetState();
}

class _SyncRoomConfigSheetState extends State<SyncRoomConfigSheet> {
  late int _maxPeers;
  late bool _isHostControlOnly;
  late PlayerQuality _selectedQuality;
  late String _generatedRoomCode;

  final List<int> _peerOptions = [2, 3, 4, 6, 8, 50];

  @override
  void initState() {
    super.initState();
    _maxPeers = 2; // По умолчанию для двоих
    _isHostControlOnly = true;
    _selectedQuality = widget.initialQuality;
    _generatedRoomCode = 'SP-${(1000 + DateTime.now().millisecondsSinceEpoch % 9000)}';
  }

  String get _deepLink => 'syncpai://room/$_generatedRoomCode';
  String get _webLink => 'https://syncpai.app/room/$_generatedRoomCode';

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _webLink));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ссылка скопирована: $_webLink'),
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareToTelegram() async {
    final text = Uri.encodeComponent(
      'Смотри «${widget.title.displayTitle}» вместе со мной в SyncPai!\nПодключайся к комнате: $_webLink',
    );
    final tgUri = Uri.parse('https://t.me/share/url?url=$_webLink&text=$text');
    if (await canLaunchUrl(tgUri)) {
      await launchUrl(tgUri, mode: LaunchMode.externalApplication);
    } else {
      _copyLink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Полоска свайпа шторки
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Заголовок
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Настройка совместной комнаты',
                        style: AppTypography.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${widget.title.displayTitle} • Серия ${widget.episode.episode}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 1. Выбор количества участников
            Text(
              'СКОЛЬКО ЧЕЛОВЕК МОЖЕТ ПОДКЛЮЧИТЬСЯ',
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _peerOptions.map((count) {
                final isSelected = _maxPeers == count;
                final label = count >= 50 ? '∞ Безлимит' : '$count чел.';
                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surfaceElevated,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected ? AppColors.primary : AppColors.strokeMedium,
                    ),
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _maxPeers = count);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // 2. Режим управления плеером
            Text(
              'УПРАВЛЕНИЕ ВОСПРОИЗВЕДЕНИЕМ',
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isHostControlOnly = true),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _isHostControlOnly
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isHostControlOnly ? AppColors.primary : AppColors.strokeMedium,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.admin_panel_settings_rounded,
                                size: 18,
                                color: _isHostControlOnly ? AppColors.primaryLight : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Только хост',
                                style: TextStyle(
                                  color: _isHostControlOnly ? Colors.white : AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Гости смотрят синхронно',
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _isHostControlOnly = false),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isHostControlOnly
                            ? AppColors.primary.withValues(alpha: 0.18)
                            : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: !_isHostControlOnly ? AppColors.primary : AppColors.strokeMedium,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.groups_rounded,
                                size: 18,
                                color: !_isHostControlOnly ? AppColors.primaryLight : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Демократия',
                                style: TextStyle(
                                  color: !_isHostControlOnly ? Colors.white : AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Все могут ставить паузу',
                            style: AppTypography.caption.copyWith(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 3. Диплинк и код комнаты
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'КОД КОМНАТЫ',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _generatedRoomCode,
                            style: TextStyle(
                              color: AppColors.primaryLight,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, color: AppColors.textPrimary, size: 20),
                            tooltip: 'Скопировать ссылку',
                            onPressed: _copyLink,
                          ),
                          IconButton(
                            icon: const Icon(Icons.send_rounded, color: Color(0xFF0088CC), size: 20),
                            tooltip: 'Поделиться в Telegram',
                            onPressed: _shareToTelegram,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  Text(
                    'Ссылка для друга: $_webLink\n(или откроется через диплинк $_deepLink)',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Кнопка подтверждения и старта
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 6,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text(
                  'Открыть лобби комнаты',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onConfirm(
                    maxPeers: _maxPeers,
                    isHostControlOnly: _isHostControlOnly,
                    quality: _selectedQuality,
                    roomCode: _generatedRoomCode,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
