import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class FeatureRequestItem {
  final String id;
  final String title;
  final String description;
  final String paymentStatus;
  final String implementationStatus;
  final DateTime? deadlineAt;
  final String? adminNote;
  final DateTime createdAt;

  const FeatureRequestItem({
    required this.id,
    required this.title,
    required this.description,
    required this.paymentStatus,
    required this.implementationStatus,
    this.deadlineAt,
    this.adminNote,
    required this.createdAt,
  });

  factory FeatureRequestItem.fromMap(Map<String, dynamic> map) {
    return FeatureRequestItem(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      paymentStatus: (map['payment_status'] ?? 'pending').toString(),
      implementationStatus: (map['implementation_status'] ?? 'review').toString(),
      deadlineAt: map['deadline_at'] != null
          ? DateTime.tryParse(map['deadline_at'].toString())
          : null,
      adminNote: map['admin_note']?.toString(),
      createdAt: DateTime.tryParse((map['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  String get statusLabel {
    switch (implementationStatus) {
      case 'in_progress':
        if (deadlineAt != null) {
          final dd = deadlineAt!.day.toString().padLeft(2, '0');
          final mm = deadlineAt!.month.toString().padLeft(2, '0');
          return 'В работе • до $dd.$mm';
        }
        return 'В работе';
      case 'completed':
        return 'Готово';
      case 'declined':
        return 'Отклонено (возврат)';
      default:
        return 'На проверке';
    }
  }

  Color get statusColor {
    switch (implementationStatus) {
      case 'in_progress':
        return const Color(0xFF35D9D5);
      case 'completed':
        return const Color(0xFF2ED573);
      case 'declined':
        return const Color(0xFFFF6B6B);
      default:
        return const Color(0xFFFFB74D);
    }
  }
}

/// Flat matte модальный лист «SyncPai Sponsor & Своя фича за 7 дней».
class SupporterSheet extends StatefulWidget {
  final String? userIdOverride;
  final Future<List<FeatureRequestItem>> Function()? requestsLoaderOverride;
  final String botUsername;

  const SupporterSheet({
    super.key,
    this.userIdOverride,
    this.requestsLoaderOverride,
    this.botUsername = const String.fromEnvironment(
      'SYNCPAI_BOT_USERNAME',
      defaultValue: 'SyncPaiFeatureBot',
    ),
  });

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SupporterSheet(),
    );
  }

  @override
  State<SupporterSheet> createState() => _SupporterSheetState();
}

class _SupporterSheetState extends State<SupporterSheet> {
  static const Color _surface = Color(0xFF141821);
  static const Color _surfaceElevated = Color(0xFF1C212E);
  static const Color _tonalBorder = Color(0x14FFFFFF);
  static const Color _coralAccent = Color(0xFFFF6B4A);

  List<FeatureRequestItem> _requests = const [];
  bool _isLoadingRequests = true;

  String? get _currentUserId {
    if (widget.userIdOverride != null) return widget.userIdOverride;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (widget.requestsLoaderOverride != null) {
      final list = await widget.requestsLoaderOverride!();
      if (!mounted) return;
      setState(() {
        _requests = list;
        _isLoadingRequests = false;
      });
      return;
    }

    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _isLoadingRequests = false);
      return;
    }
    try {
      final rows = await Supabase.instance.client
          .from('feature_requests')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false);
      if (!mounted) return;
      final parsed = (rows as List)
          .whereType<Map>()
          .map((r) => FeatureRequestItem.fromMap(Map<String, dynamic>.from(r)))
          .toList();
      setState(() {
        _requests = parsed;
        _isLoadingRequests = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingRequests = false);
    }
  }

  Future<void> _launchFeatureBot() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Войдите в аккаунт, чтобы привязать заявку к профилю'),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://t.me/${widget.botUsername}?start=feat_$uid',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH, maxWidth: 560),
        child: Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            border: Border(top: BorderSide(color: _tonalBorder)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0x33FFFFFF),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Поддержать SyncPai',
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Развитие проекта без рекламы и навязчивых подписок',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                // Тир 1: SyncPai Sponsor
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _tonalBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.workspace_premium_rounded,
                            color: _coralAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'SyncPai Sponsor',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _coralAccent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Sponsor',
                              style: TextStyle(
                                color: _coralAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Эксклюзивные Steam-рамки профиля, манга/киберпанк-иллюстрации Пай-тян для витрины и значок Sponsor.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Тир 2: Priority Feature Pass — Своя фича за 7 дней
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surfaceElevated,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _coralAccent.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: _coralAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Своя фича за 7 дней',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2ED573).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Priority Pass',
                              style: TextStyle(
                                color: Color(0xFF2ED573),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Опишите нужную функцию или улучшение UI в официальном Telegram-боте SyncPai. После технической проверки мы реализуем её за 7 дней (или вернём 100% оплаты) и откроем полный доступ Sponsor.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          key: const ValueKey('supporter_order_feature_btn'),
                          onPressed: _launchFeatureBot,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _coralAccent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 17),
                          label: const Text(
                            'Заказать фичу в Telegram',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Мои заявки',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (_isLoadingRequests)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_requests.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _tonalBorder),
                    ),
                    child: const Text(
                      'У вас пока нет активных заявок на функции.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  )
                else
                  ..._requests.map((req) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _tonalBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  req.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: req.statusColor.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  req.statusLabel,
                                  style: TextStyle(
                                    color: req.statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (req.adminNote != null &&
                              req.adminNote!.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              req.adminNote!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

