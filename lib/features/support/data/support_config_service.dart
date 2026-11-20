import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupportConfig {
  final String goalTitle;
  final int goalPercent;
  final String boostyUrl;
  final String tributeUrl;
  final String tonAddress;
  final String usdtTrc20Address;
  final List<String> hallOfFame;

  const SupportConfig({
    required this.goalTitle,
    required this.goalPercent,
    required this.boostyUrl,
    required this.tributeUrl,
    required this.tonAddress,
    required this.usdtTrc20Address,
    required this.hallOfFame,
  });

  static const SupportConfig fallback = SupportConfig(
    goalTitle: 'Оплата VDS и инфраструктуры на месяц',
    goalPercent: 48,
    boostyUrl: 'https://boosty.to/syncpai',
    tributeUrl: 'https://t.me/tribute/app?startapp=syncpai',
    tonAddress: 'UQSyncPaiTONWalletAddressReplaceInAppConfig0001',
    usdtTrc20Address: 'TSyncPaiUSDTTRC20WalletAddressReplaceInAppConfig1',
    hallOfFame: [
      'keori #5727',
      'PaiProducer #0001',
    ],
  );

  factory SupportConfig.fromRow(Map<String, dynamic> row) {
    final rawPercent = row['support_goal_percent'];
    final parsedPercent = rawPercent is int
        ? rawPercent
        : (rawPercent is num
            ? rawPercent.round()
            : int.tryParse(rawPercent?.toString() ?? '') ?? fallback.goalPercent);

    final rawHof = row['hall_of_fame'];
    final List<String> hofList;
    if (rawHof is List) {
      hofList = rawHof.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    } else if (rawHof is String && rawHof.trim().isNotEmpty) {
      hofList = rawHof.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    } else {
      hofList = fallback.hallOfFame;
    }

    String pickStr(String key, String def) {
      final v = (row[key] as String?)?.trim() ?? '';
      return v.isNotEmpty ? v : def;
    }

    return SupportConfig(
      goalTitle: pickStr('support_goal_title', fallback.goalTitle),
      goalPercent: parsedPercent.clamp(0, 100),
      boostyUrl: pickStr('boosty_url', fallback.boostyUrl),
      tributeUrl: pickStr('tribute_url', fallback.tributeUrl),
      tonAddress: pickStr('ton_address', fallback.tonAddress),
      usdtTrc20Address: pickStr('usdt_trc20_address', fallback.usdtTrc20Address),
      hallOfFame: hofList.isNotEmpty ? hofList : fallback.hallOfFame,
    );
  }
}

class SupportConfigService {
  SupportConfigService._();
  static final SupportConfigService instance = SupportConfigService._();

  Future<SupportConfig> fetchConfig() async {
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row != null) {
        return SupportConfig.fromRow(row);
      }
    } catch (e) {
      debugPrint('[SupportConfig] fallback used: $e');
    }
    return SupportConfig.fallback;
  }
}

