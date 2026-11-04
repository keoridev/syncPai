/// Константы сетевого слоя и AniLibria API v3.
abstract final class ApiConstants {
  static const String baseUrl = 'https://api.anilibria.tv/v3';
  static const String posterBaseUrl = 'https://anilibria.tv';
  
  // Резервный хост на случай проблем с основным доменом
  static const String fallbackBaseUrl = 'https://anilibria.top/api/v3';
  static const String fallbackPosterBaseUrl = 'https://anilibria.top';

  // Эндпоинты
  static const String updates = '/title/updates';
  static const String search = '/title/search';
  static const String title = '/title';
  static const String schedule = '/title/schedule';
  static const String genres = '/genres';

  // Таймауты
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 15);
}

