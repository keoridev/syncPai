import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/core/theme/app_theme.dart';
import 'package:sync_pai/core/theme/theme_preset.dart';
import 'package:sync_pai/core/widgets/manga_panel_painter.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/desktop_catalog_widgets.dart';

double _relativeLuminance(Color c) {
  double channel(double v) {
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrastRatio(Color fg, Color bg) {
  final l1 = _relativeLuminance(fg);
  final l2 = _relativeLuminance(bg);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

Color? _resolveAncestorBackground(Element element, Color fallback) {
  Color? found;
  element.visitAncestorElements((ancestor) {
    final w = ancestor.widget;
    if (w is ColoredBox && w.color.a > 0.7) {
      found = w.color;
      return false;
    }
    if (w is Container && w.color != null && w.color!.a > 0.7) {
      found = w.color;
      return false;
    }
    if (w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color != null &&
        (w.decoration as BoxDecoration).color!.a > 0.7) {
      found = (w.decoration as BoxDecoration).color;
      return false;
    }
    if (w is Material && w.color != null && w.color!.a > 0.7) {
      found = w.color;
      return false;
    }
    return true;
  });
  return found ?? fallback;
}

void main() {
  const sampleTitle = AnimeTitle(
    id: 101,
    code: 'sample_101',
    russianTitle: 'Клинок, рассекающий демонов',
    englishTitle: 'Demon Slayer',
    posterSmall: '',
    posterMedium: '',
    posterOriginal: '',
    genres: ['Экшен', 'Фэнтези'],
    description: 'Тестовое описание тайтла для проверки контрастности.',
    status: 'Вышел',
    score: 8.7,
    episodesTotal: 26,
  );

  test('All ThemePreset tokens satisfy WCAG >= 3.0 contrast', () {
    for (final preset in ThemePreset.all) {
      final theme = AppTheme.fromPreset(preset);
      final scheme = theme.colorScheme;

      expect(
        _contrastRatio(scheme.onSurface, theme.scaffoldBackgroundColor),
        greaterThanOrEqualTo(3.0),
        reason: '${preset.id}: onSurface vs scaffoldBackgroundColor',
      );
      expect(
        _contrastRatio(scheme.onSurface, theme.cardColor),
        greaterThanOrEqualTo(3.0),
        reason: '${preset.id}: onSurface vs cardColor',
      );
      expect(
        _contrastRatio(scheme.onSurfaceVariant, theme.cardColor),
        greaterThanOrEqualTo(3.0),
        reason: '${preset.id}: onSurfaceVariant vs cardColor',
      );
      expect(
        _contrastRatio(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(3.0),
        reason: '${preset.id}: onPrimary vs primary',
      );
    }
  });

  test('Manga theme uses comfortable dark graphite & ink palette', () {
    final mangaPreset = ThemePreset.fromId('manga');
    final theme = AppTheme.fromPreset(mangaPreset);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0D0F12));
    expect(theme.cardColor, const Color(0xFF161920));
    expect(theme.colorScheme.primary, const Color(0xFFF1F5F9));
    expect(theme.colorScheme.onPrimary, const Color(0xFF0D0F12));
    expect(theme.colorScheme.onSurface, const Color(0xFFF8FAFC));
  });

  testWidgets('Rendered desktop catalog, settings & profile widgets pass WCAG >= 3.0 across all themes',
      (tester) async {
    for (final preset in ThemePreset.all) {
      final theme = AppTheme.fromPreset(preset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  DesktopCatalogHeroBanner(
                    title: sampleTitle,
                    onWatchTap: () {},
                    onWatchTogetherTap: () {},
                  ),
                  SizedBox(
                    height: 220,
                    child: DesktopTopWeekSidebar(
                      titles: const [sampleTitle],
                      onTitleTap: (_) {},
                    ),
                  ),
                  Card(
                    child: ListTile(
                      title: const Text('Настройка интерфейса'),
                      subtitle: const Text('Описание настройки'),
                      trailing: ElevatedButton(
                        onPressed: () {},
                        child: const Text('Применить'),
                      ),
                    ),
                  ),
                  Builder(
                    builder: (ctx) => Text(
                      isMangaPrintTheme(ctx) ? 'Манга режим' : 'Обычный режим',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final textFinder = find.byType(Text);
      for (final element in textFinder.evaluate()) {
        final textWidget = element.widget as Text;
        final style = DefaultTextStyle.of(element).style.merge(textWidget.style);
        final fg = style.color ?? theme.colorScheme.onSurface;
        final bg = _resolveAncestorBackground(element, theme.scaffoldBackgroundColor)!;
        final ratio = _contrastRatio(fg, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason:
              '${preset.id}: Text "${textWidget.data}" has low contrast $ratio (fg=$fg, bg=$bg)',
        );
      }
    }
  });
}

