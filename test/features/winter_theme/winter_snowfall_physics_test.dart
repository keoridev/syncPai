import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/winter_theme/presentation/widgets/winter_snowfall_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WinterSnowfallPainter Delta-Time Physics Tests', () {
    test('Individual flakes wrap to -8 without resetting neighbor flakes', () {
      final flake1 = Snowflake(
        x: 100,
        y: 495, // Near bottom of 500px screen
        speedY: 100,
        radius: 2.0,
        alpha: 0.8,
        driftPhase: 0.0,
      );
      final flake2 = Snowflake(
        x: 200,
        y: 150, // Higher up in the screen
        speedY: 60,
        radius: 1.5,
        alpha: 0.5,
        driftPhase: 1.0,
      );

      final notifier = ChangeNotifier();
      final painter = WinterSnowfallPainter(
        repaint: notifier,
        flakes: [flake1, flake2],
      );

      // Create a canvas of size 300x500
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(300, 500);

      // Frame 1: Initial position check
      painter.paint(canvas, size);

      // Simulate a small tick (flake1 should move past 500 + 8 = 508, wrapping to -8)
      flake1.y = 510; // Trigger wrap condition
      painter.paint(canvas, size);

      expect(flake1.y, equals(-8.0)); // Wrapped back to -8
      expect(flake2.y, isNot(equals(-8.0))); // Flake 2 was NOT reset!
      expect(flake2.y, greaterThanOrEqualTo(150.0)); // Kept falling continuously
    });

    test('Clamped delta time prevents teleporting on sudden time jumps', () {
      final flake = Snowflake(
        x: 100,
        y: 50,
        speedY: 100,
        radius: 2.0,
        alpha: 0.8,
        driftPhase: 0.0,
      );

      final notifier = ChangeNotifier();
      final painter = WinterSnowfallPainter(
        repaint: notifier,
        flakes: [flake],
      );

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(300, 500);

      painter.paint(canvas, size);
      final initialY = flake.y;

      // Simulate next frame
      painter.paint(canvas, size);
      final diff = flake.y - initialY;

      // Max dt is clamped to 0.033 sec, so max diff is approx 100 * 0.033 = 3.3px
      expect(diff, lessThanOrEqualTo(5.0));
      expect(diff, greaterThan(0.0));
    });
  });
}
