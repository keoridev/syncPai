/// Константы сетевого слоя и актуального AniLibria (AniLiberty) API v1.
/// Старый домен api.anilibria.tv выведен из эксплуатации (HTTP 410 Gone).
abstract final class ApiConstants {
  static const String baseUrl = 'https://anilibria.top/api/v1';
  static const String posterBaseUrl = 'https://anilibria.top';

  // Резервный хост API
  static const String fallbackBaseUrl = 'https://api.anilibria.app/api/v1';
  static const String fallbackPosterBaseUrl = 'https://api.anilibria.app';

  // Актуальные эндпоинты API v1
  static const String latestReleases = '/anime/releases/latest';
  static const String searchReleases = '/app/search/releases';
  static const String catalogReleases = '/anime/catalog/releases';
  static const String releaseDetails = '/anime/releases';

  // Таймауты
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 15);

  // Supabase Realtime Gateway
  static const String supabaseUrl = 'https://lemaomwexnttytizamxl.supabase.co';
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
}
