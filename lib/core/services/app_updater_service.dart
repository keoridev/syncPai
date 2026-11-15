import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/router/app_router.dart';
import '../widgets/update_available_dialog.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String? minRequiredVersion;
  final String changelog;
  final String downloadUrl;
  final bool isMandatory;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    this.minRequiredVersion,
    required this.changelog,
    required this.downloadUrl,
    required this.isMandatory,
  });
}

class AppUpdaterService {
  AppUpdaterService._();
  static final AppUpdaterService instance = AppUpdaterService._();

  bool _isChecking = false;

  /// Сравнивает две семантические версии (`1.0.2` vs `1.0.0+1`).
  /// Возвращает > 0 если [a] > [b], 0 если равны, < 0 если [a] < [b].
  static int compareVersions(String a, String b) {
    List<int> parse(String raw) {
      final noBuild = raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
      return noBuild
          .split('.')
          .map((part) => int.tryParse(part.replaceAll(RegExp(r'\D'), '')) ?? 0)
          .toList();
    }

    final pa = parse(a);
    final pb = parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  /// Разбирает строку из `public.app_config` с учётом платформы (Android / Windows).
  static AppUpdateInfo? parseConfigRow({
    required Map<String, dynamic> row,
    required String currentVersion,
    bool? isAndroidOverride,
    bool? isWindowsOverride,
  }) {
    final latestVersion = (row['latest_version'] as String?)?.trim() ?? '';
    if (latestVersion.isEmpty) return null;
    if (compareVersions(latestVersion, currentVersion) <= 0) return null;

    final isAndroid = isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);
    final isWindows = isWindowsOverride ?? (!kIsWeb && Platform.isWindows);

    String downloadUrl = '';
    if (isAndroid) {
      downloadUrl = (row['android_apk_url'] as String?)?.trim() ?? '';
    } else if (isWindows) {
      downloadUrl = (row['windows_exe_url'] as String?)?.trim() ?? '';
    }
    if (downloadUrl.isEmpty) return null;

    final minRequired = (row['min_required_version'] as String?)?.trim();
    final isMandatory = minRequired != null &&
        minRequired.isNotEmpty &&
        compareVersions(currentVersion, minRequired) < 0;
    final changelog = (row['changelog'] as String?)?.trim() ??
        'Исправления ошибок и улучшения стабильности.';

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      minRequiredVersion: minRequired,
      changelog: changelog,
      downloadUrl: downloadUrl,
      isMandatory: isMandatory,
    );
  }

  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '1.0.0';
    }
  }

  Future<void> checkForUpdates({
    BuildContext? context,
    bool manual = false,
  }) async {
    if (_isChecking || kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isWindows) {
      if (manual && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У вас установлена последняя версия')),
        );
      }
      return;
    }

    _isChecking = true;
    try {
      final currentVersion = await getCurrentVersion();
      final row = await Supabase.instance.client
          .from('app_config')
          .select()
          .eq('id', 1)
          .maybeSingle();

      if (row == null) {
        if (manual && context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('У вас установлена последняя версия')),
          );
        }
        return;
      }

      final updateInfo = parseConfigRow(
        row: row,
        currentVersion: currentVersion,
      );

      if (updateInfo != null) {
        final targetContext = (context != null && context.mounted)
            ? context
            : rootNavigatorKey.currentContext;
        if (targetContext != null && targetContext.mounted) {
          await UpdateAvailableDialog.show(targetContext, info: updateInfo);
        }
      } else if (manual && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У вас установлена последняя версия')),
        );
      }
    } catch (e) {
      debugPrint('[AppUpdater] checkForUpdates failed: $e');
      if (manual && context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось проверить обновления. Попробуйте позже.')),
        );
      }
    } finally {
      _isChecking = false;
    }
  }

  /// Скачивает APK/EXE во временную папку и запускает системный установщик.
  Future<void> downloadAndInstall({
    required AppUpdateInfo info,
    required void Function(double progress, int receivedBytes, int totalBytes) onProgress,
    CancelToken? cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final ext = Platform.isAndroid ? 'apk' : 'exe';
    final safeVer = info.latestVersion.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final savePath = '${tempDir.path}${Platform.pathSeparator}syncpai_update_$safeVer.$ext';

    final file = File(savePath);
    if (await file.exists()) {
      await file.delete();
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        followRedirects: true,
      ),
    );

    await dio.download(
      info.downloadUrl,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        onProgress(progress, received, total);
      },
    );

    final result = await OpenFilex.open(savePath);
    if (result.type != ResultType.done) {
      throw Exception('Не удалось открыть установщик: ${result.message}');
    }

    if (Platform.isWindows) {
      Future.delayed(const Duration(milliseconds: 500), () => exit(0));
    }
  }
}

