import 'package:csv/csv.dart';
import '../../domain/entities/user_anime_entry.dart';
import 'anixart_backup_parser.dart';
import 'shikimori_search_service.dart';

/// Модель предварительно распарсенной сырой записи из CSV
class AnixartRawEntry {
  final String title;
  final AnimeListStatus status;
  final int watchedEpisodes;
  final int? totalEpisodes;
  final int? extractedId;

  const AnixartRawEntry({
    required this.title,
    required this.status,
    this.watchedEpisodes = 0,
    this.totalEpisodes,
    this.extractedId,
  });
}

/// Высоконадежный парсер официального CSV-экспорта списков и закладок Anixart
/// Поддерживает:
/// - UTF-8, экранированные кавычки и запятые внутри названий
/// - Форматы: `#,Русское название` (индекс в 1-й колонке, название во 2-й)
/// - Форматы: `6 / "Название"`, `Смотрю`, `12/24`
/// - Умный матчинг с официальным Shikimori API для получения истинного shikimori_id и постера
class AnixartCsvParser {
  /// Извлекает сырые записи из CSV/TXT файла
  static List<AnixartRawEntry> extractRawTitles(
    String rawCsv, {
    AnimeListStatus defaultStatus = AnimeListStatus.planned,
  }) {
    if (rawCsv.trim().isEmpty) return [];

    final lines = rawCsv.split(RegExp(r'\r?\n'));

    // 1. Проверяем формат Anixart со слэш-разделителями (например: 1 / "Название" / "Ромадзи" / ... / В планах)
    final isSlashDelimited = lines.any((l) => l.contains(' / ') && (l.contains('"') || l.contains('В планах') || l.contains('Просмотрено') || l.contains('Брошено') || l.contains('Смотрю')));

    if (isSlashDelimited) {
      final List<AnixartRawEntry> slashResults = [];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        final parts = trimmed.split(RegExp(r'\s+/\s+'));
        if (parts.length < 2) continue;

        // Первая колонка - номер (например 1), вторая - русское название в кавычках
        final isFirstColNum = RegExp(r'^\d+$').hasMatch(parts[0].trim());
        final titlePart = isFirstColNum && parts.length > 1 ? parts[1] : parts[0];
        final clean = cleanTitle(titlePart);
        if (clean.isEmpty || clean.toLowerCase() == 'русское название') continue;

        // Ищем статус в частях строки с конца
        String foundStatus = '';
        for (int p = parts.length - 1; p >= (isFirstColNum ? 2 : 1); p--) {
          final sLower = parts[p].toLowerCase().trim();
          if (sLower.contains('просмотр') ||
              sLower.contains('заверш') ||
              sLower.contains('смотр') ||
              sLower.contains('план') ||
              sLower.contains('брош') ||
              sLower.contains('отлож')) {
            foundStatus = parts[p];
            break;
          }
        }

        final status = foundStatus.isNotEmpty ? mapStatus(foundStatus) : defaultStatus;
        slashResults.add(AnixartRawEntry(
          title: clean,
          status: status,
        ));
      }

      if (slashResults.isNotEmpty) {
        return slashResults;
      }
    }

    // 2. Стандартный CSV-парсер (запятая или точка с запятой)
    final firstLine = lines.firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        );
    final delimiter = (firstLine.contains(';') && !firstLine.contains(','))
        ? ';'
        : (firstLine.contains(';') &&
                firstLine.split(';').length >= firstLine.split(',').length)
            ? ';'
            : ',';

    final rows = CsvToListConverter(
      shouldParseNumbers: false,
      allowInvalid: true,
      fieldDelimiter: delimiter,
      eol: '\n',
    ).convert(rawCsv.replaceAll('\r\n', '\n'));

    if (rows.isEmpty) return [];

    final List<AnixartRawEntry> result = [];

    // Определяем наличие заголовка
    int startIndex = 0;
    if (rows.isNotEmpty) {
      final headerStr = rows.first.join(' ').toLowerCase();
      if (headerStr.contains('title') ||
          headerStr.contains('название') ||
          headerStr.contains('status') ||
          headerStr.contains('статус') ||
          headerStr.contains('anime') ||
          headerStr.contains('аниме') ||
          headerStr.trim().startsWith('#')) {
        startIndex = 1;
      }
    }

    for (int i = startIndex; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      String rawTitle = '';
      String statusRaw = '';
      String episodesRaw = '0';
      int? extractedId;

      final firstColStr = row[0].toString().trim();
      final isFirstColNumeric = RegExp(r'^\d+$').hasMatch(firstColStr);

      if (isFirstColNumeric && row.length > 1) {
        // Пример структуры: 1,"100 девушек, которые очень-очень сильно тебя любят"
        // Первая колонка — это порядковый номер, вторая колонка — русское название
        rawTitle = row[1].toString().trim();
        statusRaw = row.length > 2 ? row[2].toString().trim() : '';
        episodesRaw = row.length > 3 ? row[3].toString().trim() : '0';
      } else {
        // Первая колонка содержит название (возможно с префиксом ID вроде '6 / ...')
        rawTitle = firstColStr;
        statusRaw = row.length > 1 ? row[1].toString().trim() : '';
        episodesRaw = row.length > 2 ? row[2].toString().trim() : '0';
      }

      // Если статус не найден в ожидаемой колонке, ищем в любой колонке строки с конца
      if (statusRaw.isEmpty) {
        for (int c = row.length - 1; c >= 1; c--) {
          final cStr = row[c].toString().toLowerCase().trim();
          if (cStr.contains('план') ||
              cStr.contains('смотр') ||
              cStr.contains('просмотр') ||
              cStr.contains('заверш') ||
              cStr.contains('брош') ||
              cStr.contains('отлож')) {
            statusRaw = row[c].toString().trim();
            break;
          }
        }
      }

      final title = cleanTitle(rawTitle);
      if (title.isEmpty || title == '#' || title.toLowerCase() == 'русское название') {
        continue;
      }

      // Извлекаем числовой ID, если он присутствовал в строке вида '6 / "Название"'
      final matchId = RegExp(r'^(\d+)\s*/').firstMatch(rawTitle);
      if (matchId != null) {
        extractedId = int.tryParse(matchId.group(1)!);
      }

      // Если в названии содержались слэши со статусом
      if (rawTitle.contains(' / ')) {
        final slashParts = rawTitle.split(RegExp(r'\s*/\s*'));
        if (statusRaw.isEmpty || statusRaw == '0') {
          for (final part in slashParts) {
            final lowerPart = part.toLowerCase();
            if (lowerPart.contains('план') ||
                lowerPart.contains('смотр') ||
                lowerPart.contains('просмотр') ||
                lowerPart.contains('заверш') ||
                lowerPart.contains('брош') ||
                lowerPart.contains('отлож')) {
              statusRaw = part;
              break;
            }
          }
        }
      }

      final status = statusRaw.isNotEmpty ? mapStatus(statusRaw) : defaultStatus;

      // Извлекаем серии
      int watchedEpisodes = 0;
      int? totalEpisodes;
      if (episodesRaw.contains('/')) {
        final parts = episodesRaw.split('/');
        watchedEpisodes = int.tryParse(parts.first.trim()) ?? 0;
        if (parts.length > 1) {
          totalEpisodes = int.tryParse(parts[1].trim());
        }
      } else {
        watchedEpisodes = int.tryParse(episodesRaw) ?? 0;
      }

      result.add(
        AnixartRawEntry(
          title: title,
          status: status,
          watchedEpisodes: watchedEpisodes,
          totalEpisodes: totalEpisodes,
          extractedId: extractedId,
        ),
      );
    }

    return result;
  }

  /// Быстрый синхронный парсинг в список UserAnimeEntry (для локального использования и обратной совместимости)
  static List<UserAnimeEntry> parseCsv(
    String rawCsv, {
    String userId = '',
    AnimeListStatus defaultStatus = AnimeListStatus.planned,
    AnimeListStatus? overrideStatus,
  }) {
    final rawEntries = extractRawTitles(rawCsv, defaultStatus: defaultStatus);
    final now = DateTime.now();

    return rawEntries.asMap().entries.map((item) {
      final i = item.key;
      final raw = item.value;
      final animeId = raw.extractedId ?? _generateAnimeId(raw.title);

      return UserAnimeEntry(
        id: 'anixart_csv_${animeId}_${now.millisecondsSinceEpoch}_$i',
        userId: userId,
        animeId: animeId,
        titleRu: raw.title,
        status: overrideStatus ?? raw.status,
        lastEpisode: raw.watchedEpisodes > 0 ? raw.watchedEpisodes : 1,
        episodesTotal: raw.totalEpisodes,
        updatedAt: now,
      );
    }).toList();
  }

  /// Умный импорт с поиском истинного shikimori_id, официального постера и прогрессом в реальном времени
  static Future<AnixartImportResult> parseWithShikimori(
    String rawCsv, {
    required String userId,
    AnimeListStatus defaultStatus = AnimeListStatus.planned,
    AnimeListStatus? overrideStatus,
    ShikimoriSearchService? searchService,
    void Function(int current, int total, String currentTitle)? onProgress,
  }) async {
    final service = searchService ?? ShikimoriSearchService();
    final rawEntries = extractRawTitles(rawCsv, defaultStatus: defaultStatus);
    final total = rawEntries.length;
    final List<UserAnimeEntry> resolvedEntries = [];
    final now = DateTime.now();

    for (int i = 0; i < total; i++) {
      final raw = rawEntries[i];
      onProgress?.call(i + 1, total, raw.title);

      int effectiveAnimeId;
      String? posterUrl;
      String finalTitle = raw.title;
      int? totalEpisodes = raw.totalEpisodes;

      // Ищем истинный тайтл на официальном Shikimori API
      final match = await service.findAnime(raw.title);
      if (match != null) {
        effectiveAnimeId = match.id;
        posterUrl = match.posterUrl.isNotEmpty ? match.posterUrl : null;
        if (match.russianTitle.isNotEmpty) {
          finalTitle = match.russianTitle;
        }
        totalEpisodes = match.episodesTotal ?? totalEpisodes;
      } else {
        effectiveAnimeId = raw.extractedId ?? _generateAnimeId(raw.title);
      }

      resolvedEntries.add(
        UserAnimeEntry(
          id: 'shikimori_${effectiveAnimeId}_${now.millisecondsSinceEpoch}_$i',
          userId: userId,
          animeId: effectiveAnimeId,
          titleRu: finalTitle,
          posterUrl: posterUrl,
          status: overrideStatus ?? raw.status,
          lastEpisode: raw.watchedEpisodes > 0 ? raw.watchedEpisodes : 1,
          episodesTotal: totalEpisodes,
          updatedAt: now,
        ),
      );

      // Микро-пауза для снижения нагрузки на сеть при большом числе тайтлов
      if (i % 5 == 0 && i > 0) {
        await Future.delayed(const Duration(milliseconds: 40));
      }
    }

    final stats = UserAnimeStats.compute(resolvedEntries);
    return AnixartImportResult(
      entries: resolvedEntries,
      totalParsed: resolvedEntries.length,
      totalEpisodes: stats.totalEpisodesCompleted,
      estimatedTimeSpent: stats.formattedTime,
    );
  }

  /// Парсит CSV и оборачивает результат в AnixartImportResult с подсчетом статистики
  static AnixartImportResult parseToResult(
    String rawCsv, {
    required String userId,
    AnimeListStatus defaultStatus = AnimeListStatus.planned,
  }) {
    final entries = parseCsv(rawCsv, userId: userId, defaultStatus: defaultStatus);
    final stats = UserAnimeStats.compute(entries);

    return AnixartImportResult(
      entries: entries,
      totalParsed: entries.length,
      totalEpisodes: stats.totalEpisodesCompleted,
      estimatedTimeSpent: stats.formattedTime,
    );
  }

  /// Маппинг названий статусов Anixart в модель SyncPai
  static AnimeListStatus mapStatus(String raw) {
    final lower = raw.toLowerCase().trim();
    if (lower.contains('просмотр') || lower.contains('completed') || lower.contains('заверш')) {
      return AnimeListStatus.completed;
    } else if (lower.contains('смотр') || lower.contains('watching')) {
      return AnimeListStatus.watching;
    } else if (lower.contains('план') || lower.contains('plan')) {
      return AnimeListStatus.planned;
    } else if (lower.contains('отлож') || lower.contains('hold')) {
      return AnimeListStatus.planned;
    } else if (lower.contains('брош') || lower.contains('dropped')) {
      return AnimeListStatus.dropped;
    }
    return AnimeListStatus.planned;
  }

  /// Детерминированный ID тайтла по его названию
  static int _generateAnimeId(String title) {
    int hash = 0;
    for (int i = 0; i < title.length; i++) {
      hash = (31 * hash + title.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash > 0 ? hash : 100000;
  }

  /// Очистка сырого названия тайтла из формата экспорта Anixart
  static String cleanTitle(String rawTitle) {
    if (rawTitle.trim().isEmpty) return '';

    String cleaned = rawTitle.trim();

    // 0. Убираем префикс порядкового номера в строке, например '1, "Тайтл"' или '1. Тайтл'
    cleaned = cleaned.replaceAll(RegExp(r'^\d+[\.,]\s*'), '').trim();

    // 1. Если в строке есть разделители " / " (экспорт списков Anixart)
    if (cleaned.contains(' / ') || cleaned.contains(' /"')) {
      final parts = cleaned.split(RegExp(r'\s*/\s*'));
      // Если первая часть - чисто числовой ID (например "6" или "99"), берем вторую часть
      if (parts.length > 1 && RegExp(r'^\d+$').hasMatch(parts[0].trim())) {
        cleaned = parts[1].trim();
      } else if (parts.isNotEmpty) {
        cleaned = parts[0].trim();
      }
    }

    // 2. Если строка начинается с префикса "число / " (например: '6 / "Название"')
    final idPrefixMatch = RegExp(r'^\d+\s*/\s*(.*)$').firstMatch(cleaned);
    if (idPrefixMatch != null) {
      cleaned = idPrefixMatch.group(1)!.trim();
      if (cleaned.contains(' / ')) {
        cleaned = cleaned.split(RegExp(r'\s*/\s*')).first.trim();
      }
    }

    // 3. Убираем внешние кавычки любого типа (двойные, одинарные, типографические)
    cleaned = cleaned.replaceAll(RegExp(r'''^["'«„\s]+|["'»”\s]+$'''), '').trim();

    // 4. Убираем экранированные кавычки
    cleaned = cleaned.replaceAll(r'\"', '"').replaceAll('""', '"').trim();
    while (cleaned.startsWith('"') || cleaned.startsWith("'") || cleaned.startsWith('«')) {
      cleaned = cleaned.substring(1).trim();
    }
    while (cleaned.endsWith('"') || cleaned.endsWith("'") || cleaned.endsWith('»')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }

    return cleaned.isNotEmpty ? cleaned : rawTitle.trim();
  }
}
