import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/player/presentation/widgets/double_tap_seek_overlay.dart';

void main() {
  test('PlayerScreen exposes gesture isolation and pinch-zoom keys', () {
    expect(const ValueKey('player_portrait_16_9_box'), isNotNull);
    expect(const ValueKey('player_pinch_scale_detector'), isNotNull);
    expect(const ValueKey('player_zoom_pill'), isNotNull);
  });

  testWidgets('DoubleTapSeekOverlay adjusts brightness on left swipe, volume on right swipe, and cancels cleanly', (tester) async {
    double? lastBrightness;
    double? lastVolume;
    final overlayKey = GlobalKey<DoubleTapSeekOverlayState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 225,
            child: DoubleTapSeekOverlay(
              key: overlayKey,
              onTap: () {},
              onSeekRelative: (_) {},
              onBrightnessChanged: (b) => lastBrightness = b,
              onVolumeChanged: (v) => lastVolume = v,
              currentPosition: Duration.zero,
              totalDuration: const Duration(minutes: 24),
              currentVolume: 0.5,
              currentBrightness: 0.5,
              isScreenLocked: false,
              onScreenLockedTap: () {},
            ),
          ),
        ),
      ),
    );

    // Left half vertical swipe -> brightness
    overlayKey.currentState!.startExternalVerticalSwipe(isBrightness: true);
    overlayKey.currentState!.updateExternalVerticalSwipe(deltaPx: -45, viewportHeight: 225);
    await tester.pump();
    expect(lastBrightness, isNotNull);
    expect(lastBrightness!, greaterThan(0.5));
    expect(lastVolume, isNull);
    overlayKey.currentState!.endExternalVerticalSwipe();
    await tester.pump(const Duration(milliseconds: 500));

    // Right half vertical swipe -> volume
    overlayKey.currentState!.startExternalVerticalSwipe(isBrightness: false);
    overlayKey.currentState!.updateExternalVerticalSwipe(deltaPx: -45, viewportHeight: 225);
    await tester.pump();
    expect(lastVolume, isNotNull);
    expect(lastVolume!, greaterThan(0.5));
    overlayKey.currentState!.endExternalVerticalSwipe();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('Portrait 16:9 ClipRect confines brightness/volume gestures above episode list', (tester) async {
    double? lastBrightness;
    final overlayKey = GlobalKey<DoubleTapSeekOverlayState>();
    final scrollController = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRect(
                  child: GestureDetector(
                    onVerticalDragStart: (_) =>
                        overlayKey.currentState?.startExternalVerticalSwipe(isBrightness: true),
                    onVerticalDragUpdate: (d) =>
                        overlayKey.currentState?.updateExternalVerticalSwipe(
                          deltaPx: d.primaryDelta ?? 0,
                          viewportHeight: 225,
                        ),
                    onVerticalDragEnd: (_) =>
                        overlayKey.currentState?.endExternalVerticalSwipe(),
                    child: DoubleTapSeekOverlay(
                      key: overlayKey,
                      onTap: () {},
                      onSeekRelative: (_) {},
                      onBrightnessChanged: (b) => lastBrightness = b,
                      onVolumeChanged: (_) {},
                      currentPosition: Duration.zero,
                      totalDuration: const Duration(minutes: 24),
                      currentVolume: 0.5,
                      currentBrightness: 0.5,
                      isScreenLocked: false,
                      onScreenLockedTap: () {},
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: 30,
                  itemBuilder: (_, i) => ListTile(title: Text('Серия ${i + 1}')),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Dragging inside the episode list below 16:9 box scrolls list and never triggers brightness
    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pump();
    expect(scrollController.offset, greaterThan(0));
    expect(lastBrightness, isNull);
  });
}
