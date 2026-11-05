import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/widgets/sync_pai_logo.dart';

void main() {
  testWidgets('Generate SyncPai application launcher icons', (tester) async {
    await tester.runAsync(() async {
      Future<List<int>> renderIconPng(int size, {bool isAdaptiveForeground = false}) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final w = size.toDouble();
        final h = size.toDouble();

        if (!isAdaptiveForeground) {
          // 1. Dark Cinema Graphite background with rounded corners
          final bgPaint = Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              Offset(w, h),
              [
                const Color(0xFF242730),
                const Color(0xFF121316),
              ],
            );
          final rrect = RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h),
            Radius.circular(w * 0.26),
          );
          canvas.drawRRect(rrect, bgPaint);

          // Subtle glow
          final glowPaint = Paint()
            ..color = AppColors.primary.withValues(alpha: 0.18)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.18);
          canvas.drawCircle(Offset(w * 0.5, h * 0.55), w * 0.35, glowPaint);

          // Border
          final borderPaint = Paint()
            ..color = Colors.white.withValues(alpha: 0.12)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (w * 0.015).clamp(1.0, 4.0);
          canvas.drawRRect(rrect.deflate(borderPaint.strokeWidth / 2), borderPaint);
        }

        // Draw mascot logo
        // For adaptive foreground, scale down to fit safely inside Android adaptive mask
        final logoScale = isAdaptiveForeground ? 0.70 : 0.82;
        final logoSize = w * logoScale;
        final logoOffset = (w - logoSize) / 2;

        canvas.save();
        canvas.translate(logoOffset, logoOffset);
        final painter = SyncPaiAnimeLogoPainter(AppColors.primary);
        painter.paint(canvas, Size(logoSize, logoSize));
        canvas.restore();

        final picture = recorder.endRecording();
        final image = await picture.toImage(size, size);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData!.buffer.asUint8List();
      }

      final targets = {
        'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': 48,
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': 72,
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': 96,
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': 144,
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
        'web/icons/Icon-192.png': 192,
        'web/icons/Icon-512.png': 512,
        'web/icons/Icon-maskable-192.png': 192,
        'web/icons/Icon-maskable-512.png': 512,
        'web/favicon.png': 48,
        'assets/icon/app_icon.png': 512,
      };

      for (final entry in targets.entries) {
        final bytes = await renderIconPng(entry.value, isAdaptiveForeground: false);
        final file = File(entry.key);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }

      // Adaptive foregrounds
      final adaptiveTargets = {
        'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png': 108,
        'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png': 162,
        'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png': 216,
        'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png': 324,
        'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
      };

      for (final entry in adaptiveTargets.entries) {
        final bytes = await renderIconPng(entry.value, isAdaptiveForeground: true);
        final file = File(entry.key);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
    });
  });
}

