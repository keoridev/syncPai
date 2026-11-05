/// Режим отображения каталога:
/// [grid] - несколько рядом (сетка постеров)
/// [list] - целый список (подробные карточки в столбик)
enum CatalogViewMode {
  grid('Сетка (несколько в ряд)'),
  list('Список (подробно в столбик)');

  final String label;
  const CatalogViewMode(this.label);
}

/// Плотность сетки в режиме [CatalogViewMode.grid]
enum CatalogGridDensity {
  standard('2 в ряд (крупные постеры)', 2),
  compact('3 в ряд (компактно)', 3);

  final String label;
  final int mobileColumns;
  const CatalogGridDensity(this.label, this.mobileColumns);
}

