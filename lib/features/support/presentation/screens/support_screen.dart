import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../data/support_config_service.dart';
import '../../domain/entities/supporter_tier.dart';

class SupportScreen extends StatefulWidget {
  final Future<SupportConfig> Function()? configLoader;

  const SupportScreen({
    super.key,
    this.configLoader,
  });

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  SupportConfig _config = SupportConfig.fallback;
  bool _isLoadingConfig = true;
  SupporterTier _selectedTier = SupporterTier.supporter;
  final GlobalKey _paymentSectionKey = GlobalKey();
  bool _hasInteracted = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await (widget.configLoader != null
          ? widget.configLoader!()
          : SupportConfigService.instance.fetchConfig());
      if (mounted) {
        setState(() {
          _config = cfg;
          _isLoadingConfig = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingConfig = false);
      }
    }
  }

  void _selectTier(SupporterTier tier) {
    setState(() {
      _selectedTier = tier;
      _hasInteracted = true;
    });
    final ctx = _paymentSectionKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _openExternalUrl(String url) async {
    setState(() => _hasInteracted = true);
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  void _openCryptoSheet({
    required String networkTitle,
    required String networkBadge,
    required String address,
    required Color accent,
  }) {
    setState(() => _hasInteracted = true);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          decoration: BoxDecoration(
            color: const Color(0xFF10131C),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accent.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        networkBadge,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        networkTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: QrImageView(
                    data: address,
                    version: QrVersions.auto,
                    size: 168,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: SelectableText(
                    address,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('crypto_copy_address_btn'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text(
                      'Скопировать адрес',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: address));
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Адрес скопирован'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final isDesktop = MediaQuery.of(context).size.width >= 820;

    UserProfile? currentProfile;
    try {
      final authState = context.watch<AuthCubit>().state;
      if (authState is Authenticated) {
        currentProfile = authState.profile;
      }
    } catch (_) {}
    final currentTier = currentProfile?.supporterTier ?? SupporterTier.free;
    final userHandle = currentProfile != null
        ? '${currentProfile.username} ${currentProfile.tag}'
        : 'Гость';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Поддержка SyncPai',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: false,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildMinimalHeader(currentTier, themePrimary),
                const SizedBox(height: 14),
                _buildGoalBar(themePrimary),
                const SizedBox(height: 22),
                const Text(
                  'Уровни поддержки',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _buildTierCards(isDesktop),
                const SizedBox(height: 22),
                Container(
                  key: _paymentSectionKey,
                  child: _buildPaymentSection(themePrimary, userHandle, isDesktop),
                ),
                const SizedBox(height: 22),
                _buildFoundersSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalHeader(SupporterTier currentTier, Color themePrimary) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Image.asset(
                _hasInteracted ? 'assets/stickers/pai_hype.png' : 'assets/stickers/pai_love.png',
                width: 44,
                height: 44,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Независимый проект без рекламы',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: currentTier.accentColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: currentTier.accentColor.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(currentTier.icon, size: 12, color: currentTier.accentColor),
                              const SizedBox(width: 4),
                              Text(
                                currentTier.title,
                                style: TextStyle(
                                  color: currentTier.accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _hasInteracted
                          ? 'Спасибо за поддержку. Выбранный уровень можно активировать ниже.'
                          : 'Все средства идут на оплату серверов синхронизации, CDN и новых релизов.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoalBar(Color themePrimary) {
    final pct = _config.goalPercent.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_rounded, size: 15, color: themePrimary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${_config.goalTitle}: $pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (_isLoadingConfig)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100.0,
              minHeight: 5,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation<Color>(themePrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCards(bool isDesktop) {
    final tiers = SupporterTier.paidTiers;
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < tiers.length; i++) ...[
            Expanded(child: _buildSingleTierCard(tiers[i])),
            if (i < tiers.length - 1) const SizedBox(width: 10),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (int i = 0; i < tiers.length; i++) ...[
          _buildSingleTierCard(tiers[i]),
          if (i < tiers.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildSingleTierCard(SupporterTier tier) {
    final isSelected = _selectedTier == tier;
    return GestureDetector(
      onTap: () => _selectTier(tier),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? tier.accentColor.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.028),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? tier.accentColor.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: tier.accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(tier.icon, size: 16, color: tier.accentColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tier.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  tier.priceLabel,
                  style: TextStyle(
                    color: tier.accentColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final perk in tier.perks)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 14, color: tier.accentColor),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        perk,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentSection(Color themePrimary, String userHandle, bool isDesktop) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.028),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Способы оплаты',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _selectedTier.accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _selectedTier.title,
                  style: TextStyle(
                    color: _selectedTier.accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Укажите ник ($userHandle) в комментарии к переводу для автоматической выдачи статуса.',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PaymentButton(
                key: const ValueKey('support_boosty_btn'),
                icon: Icons.rocket_launch_rounded,
                label: 'Boosty',
                accent: const Color(0xFFF15F2C),
                onTap: () => _openExternalUrl(_config.boostyUrl),
              ),
              _PaymentButton(
                key: const ValueKey('support_tribute_btn'),
                icon: Icons.send_rounded,
                label: 'Telegram Tribute',
                accent: const Color(0xFF38BDF8),
                onTap: () => _openExternalUrl(_config.tributeUrl),
              ),
              _PaymentButton(
                key: const ValueKey('support_ton_btn'),
                icon: Icons.qr_code_2_rounded,
                label: 'TON',
                accent: const Color(0xFF22D3EE),
                onTap: () => _openCryptoSheet(
                  networkTitle: 'TON Network',
                  networkBadge: 'TON',
                  address: _config.tonAddress,
                  accent: const Color(0xFF22D3EE),
                ),
              ),
              _PaymentButton(
                key: const ValueKey('support_usdt_btn'),
                icon: Icons.qr_code_2_rounded,
                label: 'USDT TRC-20',
                accent: const Color(0xFF26A17B),
                onTap: () => _openCryptoSheet(
                  networkTitle: 'USDT (TRC-20)',
                  networkBadge: 'TRC-20',
                  address: _config.usdtTrc20Address,
                  accent: const Color(0xFF26A17B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFoundersSection() {
    if (_config.hallOfFame.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_rounded, size: 15, color: Color(0xFFFBBF24)),
              SizedBox(width: 7),
              Text(
                'Founders Club',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final name in _config.hallOfFame)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _PaymentButton({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: accent.withValues(alpha: 0.08),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(icon, size: 16, color: accent),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}
