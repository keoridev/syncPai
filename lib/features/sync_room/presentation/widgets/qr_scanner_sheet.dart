import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../data/repositories/sync_room_repository_impl.dart';

/// Интерактивный сканер QR-кодов совместного просмотра через камеру устройства
class QrScannerSheet extends StatefulWidget {
  final ValueChanged<String> onCodeScanned;

  const QrScannerSheet({super.key, required this.onCodeScanned});

  static Future<void> show(BuildContext context, {required ValueChanged<String> onCodeScanned}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => QrScannerSheet(
        onCodeScanned: (code) {
          Navigator.of(ctx).pop();
          onCodeScanned(code);
        },
      ),
    );
  }

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet> with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _hasDetected = false;
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasDetected) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        // Парсим код комнаты из ссылки или чистого PIN
        String code = raw.trim();
        if (code.contains('/room/')) {
          code = code.split('/room/').last;
        } else if (code.contains('room=')) {
          code = code.split('room=').last;
        }
        code = code.split('?').first.split('#').first;
        final normalized = SyncRoomRepositoryImpl.normalizeCode(code);

        if (normalized.length >= 4) {
          _hasDetected = true;
          HapticFeedback.heavyImpact();
          widget.onCodeScanned(normalized);
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanBoxSize = (size.width * 0.72).clamp(220.0, 320.0);

    return SizedBox(
      height: size.height * 0.85,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Камера
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: MobileScanner(
              controller: _controller,
              onDetect: _handleBarcode,
              errorBuilder: (context, error) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off_rounded, color: AppColors.syncError, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Камера недоступна или нет разрешения',
                          textAlign: TextAlign.center,
                          style: AppTypography.titleSmall.copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Предоставьте доступ к камере в настройках устройства',
                          textAlign: TextAlign.center,
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Затемнение фона за пределами рамки
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.65),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Center(
                  child: Container(
                    width: scanBoxSize,
                    height: scanBoxSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Неоновая рамка видоискателя
          Container(
            width: scanBoxSize,
            height: scanBoxSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.syncActive, width: 2.0),
              boxShadow: [
                BoxShadow(
                  color: AppColors.syncActive.withValues(alpha: 0.35),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Stack(
              children: [
                // Анимированная лазерная линия
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    return Align(
                      alignment: Alignment(0, (_animController.value * 2) - 1),
                      child: Container(
                        height: 2,
                        width: scanBoxSize - 20,
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.syncActive.withValues(alpha: 0.1),
                              AppColors.syncActive,
                              AppColors.syncActive.withValues(alpha: 0.1),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.syncActive,
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Верхняя панель: закрыть и фонарик
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Text(
                  'Наведите на QR-код',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 24),
                  onPressed: () => _controller.toggleTorch(),
                ),
              ],
            ),
          ),

          // Нижняя подсказка
          Positioned(
            bottom: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.strokeMedium),
              ),
              child: const Text(
                'Подключение произойдет автоматически',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

