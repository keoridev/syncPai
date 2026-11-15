import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/qr_payload_router.dart';
import '../../../../core/utils/safe_haptics.dart';

/// Интерактивный сканер QR-кодов совместного просмотра SyncPai:
/// На мобильных (Android, iOS) — сканирование камерой + выбор из галереи.
/// На Desktop (Windows, macOS, Linux) — чистое двухкнопочное диалоговое окно:
/// 1. «Выбрать скриншот QR с диска»
/// 2. «Вставить ссылку или код из буфера»
class QrScannerSheet extends StatefulWidget {
  final ValueChanged<String> onCodeScanned;

  const QrScannerSheet({super.key, required this.onCodeScanned});

  static Future<void> show(BuildContext context, {required ValueChanged<String> onCodeScanned}) {
    final isDesktop = !kIsWeb &&
        (Platform.isWindows ||
            Platform.isMacOS ||
            Platform.isLinux ||
            MediaQuery.of(context).size.width >= 650);

    if (isDesktop) {
      return showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: QrScannerSheet(
              onCodeScanned: (code) {
                Navigator.of(ctx).pop();
                onCodeScanned(code);
              },
            ),
          ),
        ),
      );
    }

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
  MobileScannerController? _controller;
  final TextEditingController _pasteController = TextEditingController();
  bool _hasDetected = false;
  late final AnimationController _animController;
  bool _hasCameraSupport = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _hasCameraSupport = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (_hasCameraSupport) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller?.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  void _handleRawCode(String raw) {
    if (_hasDetected) return;
    final parsed = QrPayloadRouter.parse(raw);
    final cleanId = parsed.isValid
        ? parsed.cleanCode
        : RoomCodeParser.extractCleanRoomId(raw);
    debugPrint('[QR] Scanned raw: $raw -> clean: $cleanId');

    if (cleanId.length >= 4) {
      _hasDetected = true;
      SafeHaptics.heavyImpact();
      widget.onCodeScanned(cleanId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В коде не найдена комната SyncPai'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleBarcode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handleRawCode(raw);
        break;
      }
    }
  }

  Future<void> _pickImageFromDisk() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      if (_controller != null) {
        final capture = await _controller!.analyzeImage(path);
        if (capture != null && capture.barcodes.isNotEmpty) {
          final firstVal = capture.barcodes.first.rawValue;
          if (firstVal != null && firstVal.isNotEmpty) {
            _handleRawCode(firstVal);
            return;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось распознать QR-код на выбранном изображении'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при чтении изображения: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      _pasteController.text = text;
      _handleRawCode(text);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Буфер обмена пуст'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCameraSupport || _controller == null) {
      return _buildDesktopModal(context);
    }

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
              controller: _controller!,
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
                          style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Разрешите доступ к камере в настройках устройства',
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

          // Темные поля вокруг рамки сканирования
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
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: scanBoxSize,
                    height: scanBoxSize,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Бегающая неоновая линия сканирования
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              final topOffset = -scanBoxSize / 2 + (scanBoxSize * _animController.value);
              return Transform.translate(
                offset: Offset(0, topOffset),
                child: Container(
                  width: scanBoxSize - 20,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppColors.syncActive,
                        AppColors.syncActive,
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.syncActive.withValues(alpha: 0.8),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Угловые акцентные скобки
          SizedBox(
            width: scanBoxSize,
            height: scanBoxSize,
            child: Stack(
              children: [
                Positioned(top: 0, left: 0, child: _buildCorner(isTop: true, isLeft: true)),
                Positioned(top: 0, right: 0, child: _buildCorner(isTop: true, isLeft: false)),
                Positioned(bottom: 0, left: 0, child: _buildCorner(isTop: false, isLeft: true)),
                Positioned(bottom: 0, right: 0, child: _buildCorner(isTop: false, isLeft: false)),
              ],
            ),
          ),

          // Верхняя плашка и кнопка закрытия
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_scanner_rounded, color: AppColors.syncActive, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Наведите камеру на QR-код',
                        style: AppTypography.caption.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Нижняя панель действий (Фонарик + Галерея)
          Positioned(
            bottom: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(14),
                  ),
                  icon: Icon(
                    _isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _isTorchOn ? Colors.amberAccent : Colors.white,
                  ),
                  onPressed: () async {
                    await _controller?.toggleTorch();
                    if (mounted) setState(() => _isTorchOn = !_isTorchOn);
                  },
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.75),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                  onPressed: _pickImageFromDisk,
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: const Text('Из галереи'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopModal(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161F) : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 32,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.syncActive.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.syncActive, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Подключение к комнате',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Используйте скриншот или ссылку',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                tooltip: 'Закрыть (Esc)',
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Кнопка 1: Выбрать скриншот с диска
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickImageFromDisk,
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.image_search_rounded, size: 20, color: AppColors.syncActive),
              label: const Text(
                'Выбрать скриншот QR с диска',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Кнопка 2: Вставить ссылку или код из буфера
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pasteFromClipboard,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.syncActive,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.content_paste_rounded, size: 20),
              label: const Text(
                'Вставить ссылку или код из буфера',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Поле ввода вручную
          TextField(
            controller: _pasteController,
            style: TextStyle(color: scheme.onSurface, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Или введите SP-XXXXXX вручную...',
              hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : scheme.surfaceContainerLow,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                borderSide: BorderSide(color: scheme.primary, width: 1.4),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.syncActive),
                onPressed: () {
                  final txt = _pasteController.text.trim();
                  if (txt.isNotEmpty) _handleRawCode(txt);
                },
              ),
            ),
            onSubmitted: (val) {
              if (val.trim().isNotEmpty) _handleRawCode(val.trim());
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCorner({required bool isTop, required bool isLeft}) {
    const cornerSize = 24.0;
    const thickness = 4.0;
    const radius = 14.0;

    return Container(
      width: cornerSize,
      height: cornerSize,
      decoration: BoxDecoration(
        border: Border(
          top: isTop ? const BorderSide(color: AppColors.syncActive, width: thickness) : BorderSide.none,
          bottom: !isTop ? const BorderSide(color: AppColors.syncActive, width: thickness) : BorderSide.none,
          left: isLeft ? const BorderSide(color: AppColors.syncActive, width: thickness) : BorderSide.none,
          right: !isLeft ? const BorderSide(color: AppColors.syncActive, width: thickness) : BorderSide.none,
        ),
        borderRadius: BorderRadius.only(
          topLeft: (isTop && isLeft) ? const Radius.circular(radius) : Radius.zero,
          topRight: (isTop && !isLeft) ? const Radius.circular(radius) : Radius.zero,
          bottomLeft: (!isTop && isLeft) ? const Radius.circular(radius) : Radius.zero,
          bottomRight: (!isTop && !isLeft) ? const Radius.circular(radius) : Radius.zero,
        ),
      ),
    );
  }
}
