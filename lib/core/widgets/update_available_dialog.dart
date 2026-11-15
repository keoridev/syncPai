import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/app_updater_service.dart';
import '../theme/app_colors.dart';

class UpdateAvailableDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const UpdateAvailableDialog({
    super.key,
    required this.info,
  });

  static Future<void> show(
    BuildContext context, {
    required AppUpdateInfo info,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !info.isMandatory,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => UpdateAvailableDialog(info: info),
    );
  }

  @override
  State<UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<UpdateAvailableDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorText;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('Dialog closed');
    }
    super.dispose();
  }

  String _formatMb(int bytes) {
    if (bytes <= 0) return '0.0';
    return (bytes / (1024 * 1024)).toStringAsFixed(1);
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _errorText = null;
    });

    final token = CancelToken();
    _cancelToken = token;

    try {
      await AppUpdaterService.instance.downloadAndInstall(
        info: widget.info,
        cancelToken: token,
        onProgress: (progress, received, total) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _receivedBytes = received;
            _totalBytes = total;
          });
        },
      );
      if (mounted && !widget.info.isMandatory) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorText = 'Ошибка загрузки обновления. Проверьте соединение и попробуйте снова.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final percent = (_progress * 100).round().clamp(0, 100);

    return PopScope(
      canPop: !widget.info.isMandatory && !_isDownloading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF131722).withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: themePrimary.withValues(alpha: 0.22),
                      blurRadius: 28,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: themePrimary.withValues(alpha: 0.14),
                            border: Border.all(
                              color: themePrimary.withValues(alpha: 0.45),
                              width: 1.5,
                            ),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/mascot/general/mascot_happy.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.system_update_rounded,
                                color: themePrimary,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Доступно обновление!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: themePrimary.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: themePrimary.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  'v${widget.info.currentVersion} → v${widget.info.latestVersion}',
                                  style: TextStyle(
                                    color: themePrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          widget.info.changelog,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                    if (_isDownloading) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Загрузка обновления... $percent%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _totalBytes > 0
                                ? '${_formatMb(_receivedBytes)} / ${_formatMb(_totalBytes)} МБ'
                                : '${_formatMb(_receivedBytes)} МБ',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _totalBytes > 0 ? _progress : null,
                          minHeight: 7,
                          backgroundColor: Colors.white.withValues(alpha: 0.10),
                          valueColor: AlwaysStoppedAnimation<Color>(themePrimary),
                        ),
                      ),
                    ],
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorText!,
                        style: const TextStyle(
                          color: AppColors.syncError,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (!widget.info.isMandatory) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isDownloading
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Позже'),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          flex: widget.info.isMandatory ? 1 : 2,
                          child: ElevatedButton.icon(
                            onPressed: _isDownloading ? null : _startDownload,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themePrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.download_rounded, size: 19),
                            label: Text(
                              _isDownloading ? 'Скачивание...' : 'Обновить сейчас',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

