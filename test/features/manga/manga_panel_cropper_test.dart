import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_pai/features/manga/data/repositories/manga_progress_repository.dart';
import 'package:sync_pai/features/manga/presentation/widgets/manga_panel_cropper_sheet.dart';

void main() {
  group('MangaShowcasePanel model & persistence', () {
    test('toJson and fromJson preserve fields and clamp normalized bounds', () {
      const panel = MangaShowcasePanel(
        mangaId: 'remanga:solo-leveling',
        mangaTitle: 'Поднятие уровня в одиночку',
        chapterLabel: 'Глава 45',
        pageUrl: 'https://img.remanga.org/page_12.jpg',
        refererHeader: 'https://remanga.org/',
        cropX: 0.15,
        cropY: 0.25,
        cropWidth: 0.7,
        cropHeight: 0.35,
      );

      final restored = MangaShowcasePanel.fromJson(panel.toJson());
      expect(restored.mangaId, 'remanga:solo-leveling');
      expect(restored.mangaTitle, 'Поднятие уровня в одиночку');
      expect(restored.chapterLabel, 'Глава 45');
      expect(restored.pageUrl, 'https://img.remanga.org/page_12.jpg');
      expect(restored.refererHeader, 'https://remanga.org/');
      expect(restored.cropX, closeTo(0.15, 0.0001));
      expect(restored.cropY, closeTo(0.25, 0.0001));
      expect(restored.cropWidth, closeTo(0.7, 0.0001));
      expect(restored.cropHeight, closeTo(0.35, 0.0001));
      expect(restored.isValid, isTrue);
    });

    test('MangaProgressRepository saves, reads, and clears MangaShowcasePanel',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = MangaProgressRepository(prefs);

      const panel = MangaShowcasePanel(
        mangaId: 'desu:42',
        mangaTitle: 'Башня Бога',
        chapterLabel: 'Глава 10',
        pageUrl: 'https://desu.uno/img/10_3.jpg',
        refererHeader: 'https://desu.uno/',
        cropX: 0.1,
        cropY: 0.2,
        cropWidth: 0.8,
        cropHeight: 0.4,
      );

      await repo.saveShowcasePanel(panel);
      final loaded = await repo.getShowcasePanel();
      expect(loaded, isNotNull);
      expect(loaded!.mangaTitle, 'Башня Бога');
      expect(loaded.chapterLabel, 'Глава 10');

      await repo.clearShowcasePanel();
      final afterClear = await repo.getShowcasePanel();
      expect(afterClear, isNull);
    });
  });

  group('computeNormalizedCropRect', () {
    test('returns expected normalized coordinates for 2x zoom and pan', () {
      final matrix = Matrix4.identity()
        ..translateByDouble(-160.0, -70.0, 0.0, 1.0)
        ..scaleByDouble(2.0, 2.0, 1.0, 1.0);

      final rect = computeNormalizedCropRect(
        viewportSize: const Size(320, 140),
        contentSize: const Size(320, 420),
        transform: matrix,
      );

      expect(rect.cropWidth, closeTo(0.5, 0.001));
      expect(rect.cropHeight, closeTo(70.0 / 420.0, 0.001));
      expect(rect.cropX, closeTo(0.25, 0.001));
      expect(rect.cropY, closeTo(35.0 / 420.0, 0.001));
    });
  });

  group('MangaPanelCropperSheet & MangaShowcasePanelBanner widgets', () {
    testWidgets('MangaPanelCropperSheet renders 16:7 InteractiveViewer and save CTA',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MangaPanelCropperSheet(
              mangaId: 'remanga:1',
              mangaTitle: 'Клинок, рассекающий демонов',
              chapterLabel: 'Глава 12',
              pageUrl: 'https://example.com/page1.jpg',
            ),
          ),
        ),
      );

      expect(find.text('Кадрирование для витрины (16:7)'), findsOneWidget);
      expect(
        find.text('Клинок, рассекающий демонов • Глава 12'),
        findsOneWidget,
      );
      expect(find.text('Подпись / цитата (необязательно)'), findsOneWidget);
      expect(find.text('Поставить в витрину'), findsOneWidget);

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.minScale, 1.0);
      expect(viewer.maxScale, 5.0);

      final aspect = tester.widget<AspectRatio>(find.byType(AspectRatio));
      expect(aspect.aspectRatio, closeTo(16 / 7, 0.001));
    });

    testWidgets('MangaShowcasePanelBanner renders manga caption and tag',
        (tester) async {
      const panel = MangaShowcasePanel(
        mangaId: 'remanga:1',
        mangaTitle: 'Магическая битва',
        chapterLabel: 'Глава 88',
        pageUrl: 'https://example.com/page88.jpg',
        cropX: 0.0,
        cropY: 0.2,
        cropWidth: 1.0,
        cropHeight: 0.4,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 158,
              child: MangaShowcasePanelBanner(
                panel: panel,
                width: 360,
                height: 158,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Магическая битва • Глава 88'), findsOneWidget);
      expect(find.text('Вырезка из манги'), findsOneWidget);
    });
  });
}

