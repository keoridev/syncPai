import 'package:csv/csv.dart';
import '../../domain/entities/user_anime_entry.dart';
import 'anixart_backup_parser.dart';

/// Парсер официального CSV-экспорта списков Anixart
/// («Профиль» → «Экспорт списков» в приложении Anixart)
class AnixartCsvParser {
  /// Принимает сырую строку из выбранного .csv или .txt файла
  static List<UserAnimeEntry> parseCsv(String rawCsv, {String userId = ''}) {
    if (rawCsv.trim().isEmpty) return [];

    // Определяем разделитель: в Anixart обычно запятая, но может быть и ';'
    // Проверяем первую непустую строку (заголовок)
    final firstLine = rawCsv.split(RegExp(r'\r?\n')).firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        );
    final delimiter = (firstLine.contains(';') && !firstLine.contains(','))
        ? ';'
        : (firstLine.contains(';') && firstLine.split(';').length >= firstLine.split(',').length)
            ? ';'
            : ',';

    final rows = CsvToListConverter(
      shouldParseNumbers: false,
      allowInvalid: true,
      fieldDelimiter: delimiter,
      eol: '\n',
    ).convert(rawCsv.replaceAll('\r\n', '\n'));

    if (rows.isEmpty) return [];

    final List<UserAnimeEntry> entries = [];
    final now = DateTime.now();

    // Определяем, есть ли заголовок (первая строка содержит "title", "название", "статус", "status")
    int startIndex = 0;
    if (rows.isNotEmpty) {
      final headerStr = rows.first.join(' ').toLowerCase();
      if (headerStr.contains('title') ||
          headerStr.contains('название') ||
          headerStr.contains('status') ||
          headerStr.contains('статус') ||
          headerStr.contains('anime') ||
          headerStr.contains('аниме')) {
        startIndex = 1;
      }
    }

    for (int i = startIndex; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row[0].toString().trim().isEmpty) continue;

      final rawFirstCol = row[0].toString().trim();
      final title = cleanTitle(rawFirstCol);
      if (title.isEmpty) continue;

      String statusRaw = row.length > 1 ? row[1].toString().trim() : '';
      final episodesRaw = row.length > 2 ? row[2].toString().trim() : '0';

      // Если в строке содержались разделители " / " (характерный экспорт Anixart)
      if (rawFirstCol.contains(' / ')) {
        final slashParts = rawFirstCol.split(RegExp(r'\s*/\s*'));
        // Ищем категорию статуса среди частей строки
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

      // Маппим статус Anixart в модель SyncPai
      final status = mapStatus(statusRaw);

      // Извлекаем просмотренные серии и всего серий (например "12" или "12/24")
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

      // Числовой ID: если в начале строки был ID (например: '6 / ...'), берем его
      int? extractedId;
      final matchId = RegExp(r'^(\d+)\s*/').firstMatch(rawFirstCol);
      if (matchId != null) {
        extractedId = int.tryParse(matchId.group(1)!);
      }
      final animeId = extractedId ?? _generateAnimeId(title);

      entries.add(
        UserAnimeEntry(
          id: 'anixart_csv_${animeId}_${now.millisecondsSinceEpoch}_$i',
          userId: userId,
          animeId: animeId,
          titleRu: title,
          status: status,
          lastEpisode: watchedEpisodes > 0 ? watchedEpisodes : 1,
          episodesTotal: totalEpisodes,
          updatedAt: now,
        ),
      );
    }

    return entries;
  }

  /// Парсит CSV и оборачивает результат в AnixartImportResult с подсчетом статистики
  static AnixartImportResult parseToResult(String rawCsv, {required String userId}) {
    final entries = parseCsv(rawCsv, userId: userId);
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

  /// Очистка сырого названия тайтла из формата экспорта Anixart:
  /// - '6 / "Аля иногда кокетничает со мной по-русски 2" / "Tokidoki..." / ...' -> 'Аля иногда кокетничает со мной по-русски 2'
  /// - '99 / "Магическая битва 2: Рекап" / "..."' -> 'Магическая битва 2: Рекап'
  /// - '2 / "Адский рай" / "Jigokuraku"' -> 'Адский рай'
  /// - '"Магическая битва"' -> 'Магическая битва'
  static String cleanTitle(String rawTitle) {
    if (rawTitle.trim().isEmpty) return '';

    String cleaned = rawTitle.trim();

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
