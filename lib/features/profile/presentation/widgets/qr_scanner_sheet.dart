import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/friends_service.dart';

/// Адаптивный сканер QR-кодов SyncPai для добавления друзей
/// На мобильных (Android, iOS, macOS) использует камеру MobileScanner + анализ изображений из галереи.
/// На Desktop (Windows, Linux, Web) использует выбор картинки-скриншота через FilePicker + поле ручного ввода / вставки ссылки.
class QrScannerSheet extends StatefulWidget {
  final Color accentColor;
  final ValueChanged<String> onCodeDetected;

  const QrScannerSheet({
    super.key,
    required this.accentColor,
    required this.onCodeDetected,
  });

  static Future<void> show(
    BuildContext context, {
    Color? accentColor,
    required ValueChanged<String> onCodeDetected,
  }) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    final isDesktop = MediaQuery.of(context).size.width >= 650;

    if (isDesktop) {
      return showDialog(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.8),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440, maxHeight: 600),
            child: QrScannerSheet(accentColor: accent, onCodeDetected: onCodeDetected),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: QrScannerSheet(accentColor: accent, onCodeDetected: onCodeDetected),
      ),
    );
  }

  @override
  State<QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<QrScannerSheet> with WidgetsBindingObserver {
  MobileScannerController? _scannerController;
  final TextEditingController _manualInputController = TextEditingController();
  bool _isTorchOn = false;
  bool _isProcessing = false;
  bool _hasCameraSupport = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Проверяем поддержку мобильного сканера камеры
    _hasCameraSupport = !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
    if (_hasCameraSupport) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController?.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  void _handleDetectedRaw(String raw) {
    if (_isProcessing) return;
    final cleanCode = FriendsService.extractInviteCode(raw);
    if (cleanCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В QR-коде не найдено корректное приглашение SyncPai'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    widget.onCodeDetected(cleanCode);
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      setState(() => _isProcessing = true);

      if (_scannerController != null) {
        final capture = await _scannerController!.analyzeImage(path);
        if (capture != null && capture.barcodes.isNotEmpty) {
          final firstVal = capture.barcodes.first.rawValue;
          if (firstVal != null && firstVal.isNotEmpty) {
            _handleDetectedRaw(firstVal);
            return;
          }
        }
      }

      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось распознать QR-код на выбранном изображении'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error analyzing gallery image: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при сканировании изображения: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentColor;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161C) : scheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)).resolve(Directionality.of(context)),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.qr_code_scanner_rounded, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Сканировать QR-код',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Наведите камеру или выберите скриншот визитки',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // Camera View or Desktop Fallback
          Expanded(
            child: _hasCameraSupport && _scannerController != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(
                        controller: _scannerController!,
                        onDetect: (capture) {
                          final barcodes = capture.barcodes;
                          for (final barcode in barcodes) {
                            final raw = barcode.rawValue;
                            if (raw != null && raw.isNotEmpty) {
                              _handleDetectedRaw(raw);
                              break;
                            }
                          }
                        },
                      ),
                      // Scanner Aiming Box Overlay
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: accent, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.35),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      // Torch and controls overlay
                      Positioned(
                        bottom: 24,
                        child: Row(
                          children: [
                            IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black.withValues(alpha: 0.6),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                await _scannerController?.toggleTorch();
                                setState(() => _isTorchOn = !_isTorchOn);
                              },
                              icon: Icon(_isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded),
                              tooltip: 'Вспышка',
                            ),
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black.withValues(alpha: 0.7),
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _pickImageFromGallery,
                              icon: const Icon(Icons.photo_library_rounded, size: 18),
                              label: const Text('Из галереи'),
                            ),
                          ],
                        ),
                      ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  )
                : _buildDesktopFallback(accent, scheme, isDark),
          ),

          // Footer manual paste input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF181A22) : scheme.surfaceContainerHigh.withValues(alpha: 0.3),
              border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualInputController,
                    style: TextStyle(color: scheme.onSurface, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Вставьте ссылку или SP-код...',
                      hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 13),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : scheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: accent, width: 1.5),
                      ),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _handleDetectedRaw(val.trim());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    final txt = _manualInputController.text.trim();
                    if (txt.isNotEmpty) {
                      _handleDetectedRaw(txt);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Принять', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFallback(Color accent, ColorScheme scheme, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.qr_code_2_rounded, color: accent, size: 54),
            ),
            const SizedBox(height: 18),
            Text(
              'Сканирование на Desktop',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Выберите изображение с QR-кодом или вставьте инвайт-ссылку / персональный код в поле ниже.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _pickImageFromGallery,
              icon: const Icon(Icons.image_search_rounded, size: 18),
              label: const Text('Выбрать картинку с диска'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.onSurface,
                side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

