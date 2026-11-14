/// Утилита очистки текста отзывов и рецензий от сырого BBCode (Shikimori/MAL) и HTML
class ReviewTextSanitizer {
  ReviewTextSanitizer._();

  /// Результат санитизации текста отзыва
  static SanitizedResult sanitize(String raw) {
    if (raw.isEmpty) {
      return const SanitizedResult(text: '', containsSpoiler: false);
    }

    var text = raw;
    var hasSpoiler = false;

    // 1. Проверяем спойлеры вида [spoiler=название]...[/spoiler] или [spoiler]...[/spoiler]
    final spoilerRegex = RegExp(r'\[spoiler(?:=[^\]]*)?\](.*?)\[/spoiler\]', caseSensitive: false, dotAll: true);
    if (spoilerRegex.hasMatch(text)) {
      hasSpoiler = true;
      // Заменяем блок спойлера на внутренний текст с маркером
      text = text.replaceAllMapped(spoilerRegex, (match) {
        final inner = match.group(1)?.trim() ?? '';
        return inner.isNotEmpty ? '[Спойлер: $inner]' : '';
      });
    }

    // 2. Ссылки на персонажей, аниме, мангу, авторов в Shikimori:
    // [character=123]Имя Персонажа[/character] -> Имя Персонажа
    // [anime=456]Название Тайтла[/anime] -> Название Тайтла
    // [manga=789]Манга[/manga] -> Манга
    // [person=111]Автор[/person] -> Автор
    // [user=222]Пользователь[/user] -> Пользователь
    final linkTagRegex = RegExp(
      r'\[(?:character|anime|manga|person|user|club|entry)(?:=\d+)?\](.*?)\[/(?:character|anime|manga|person|user|club|entry)\]',
      caseSensitive: false,
      dotAll: true,
    );
    text = text.replaceAllMapped(linkTagRegex, (match) => match.group(1)?.trim() ?? '');

    // 3. Цитаты вида [quote=...]текст[/quote] -> «текст»
    final quoteRegex = RegExp(r'\[quote(?:=[^\]]*)?\](.*?)\[/quote\]', caseSensitive: false, dotAll: true);
    text = text.replaceAllMapped(quoteRegex, (match) {
      final quoteText = match.group(1)?.trim() ?? '';
      return quoteText.isNotEmpty ? '«$quoteText»\n' : '';
    });

    // 4. Ссылки [url=http...]текст[/url] -> текст
    final urlRegex = RegExp(r'\[url=(?:[^\]]*)\](.*?)\[/url\]', caseSensitive: false, dotAll: true);
    text = text.replaceAllMapped(urlRegex, (match) => match.group(1)?.trim() ?? '');

    // 5. Картинки [image=...] или [img]...[/img] -> удаляем
    text = text.replaceAll(RegExp(r'\[image=\d+\]', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'\[img\](.*?)\[/img\]', caseSensitive: false), '');

    // 6. Ответы и упоминания Shikimori [replies=...], [comment=...], [ban=...]
    text = text.replaceAll(RegExp(r'\[(?:replies|comment|ban|mention)=[^\]]*\]', caseSensitive: false), '');

    // 7. Стилистические BB-коды: [b], [/b], [i], [/i], [u], [/u], [s], [/s], [size=...], [color=...]
    text = text.replaceAll(RegExp(r'\[/?[a-zA-Z0-9_=\-\s\.:/#]+\]'), '');

    // 8. Переносы строк HTML
    text = text.replaceAll(RegExp(r'<(?:br|br\s*/|p|/p)>', caseSensitive: false), '\n');

    // 9. Очистка всех остальных HTML-тегов
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    // 10. Декодирование распространенных HTML-сущностей
    text = text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '...');

    // 11. Удаление смайликов-кодов (например, :evil:, :lol:, :8):)
    text = text.replaceAll(RegExp(r':[a-zA-Z0-9_()\-+]+:'), '');

    // 12. Нормализация пробелов и переносов строк
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.trim();

    return SanitizedResult(
      text: text,
      containsSpoiler: hasSpoiler,
    );
  }
}

class SanitizedResult {
  final String text;
  final bool containsSpoiler;

  const SanitizedResult({
    required this.text,
    required this.containsSpoiler,
  });
}
