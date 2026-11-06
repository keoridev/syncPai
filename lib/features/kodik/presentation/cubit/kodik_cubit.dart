// ignore_for_file: prefer_initializing_formals
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/kodik_remote_datasource.dart';
import '../../data/datasources/kodik_stream_extractor.dart';
import '../../domain/entities/kodik_translation.dart';
import 'kodik_state.dart';

class KodikCubit extends Cubit<KodikState> {
  final KodikRemoteDataSource _dataSource;
  final KodikStreamExtractor _extractor;
  final SharedPreferences? _prefs;

  static const String _prefVoiceoverKey = 'sync_pai_preferred_voiceover';

  KodikCubit({
    required KodikRemoteDataSource dataSource,
    KodikStreamExtractor? extractor,
    SharedPreferences? prefs,
  })  : _dataSource = dataSource,
        _extractor = extractor ?? KodikStreamExtractor(),
        _prefs = prefs,
        super(KodikState.initial());

  /// Загрузка всех доступных переводов и озвучек для выбранного тайтла
  Future<void> loadVoiceovers({
    int? shikimoriId,
    String? title,
  }) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    try {
      final list = await _dataSource.getTranslationsForAnime(
        shikimoriId: shikimoriId,
        title: title,
      );

      final fullList = <KodikTranslation>[
        KodikTranslation.anilibria(),
        ...list,
      ];

      // Проверяем, есть ли сохранённая предпочтительная озвучка
      final savedVoiceover = _prefs?.getString(_prefVoiceoverKey);
      KodikTranslation initialSelected = fullList.first;

      if (savedVoiceover != null && savedVoiceover.isNotEmpty) {
        final matched = fullList.firstWhere(
          (t) => t.title.toLowerCase() == savedVoiceover.toLowerCase(),
          orElse: () => fullList.first,
        );
        initialSelected = matched;
      }

      emit(state.copyWith(
        translations: fullList,
        selectedTranslation: initialSelected,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Не удалось загрузить список озвучек: $e',
      ));
    }
  }

  /// Выбор студии озвучки (AniLibria, Dream Cast, StudioBand...)
  Future<String?> selectVoiceover(
    KodikTranslation translation, {
    int episodeNumber = 1,
    String quality = '720p',
  }) async {
    emit(state.copyWith(
      selectedTranslation: translation,
      resolvedStreamUrl: () => null,
    ));

    // Сохраняем выбор пользователя для следующих тайтлов и серий
    if (!translation.isAniLibria) {
      await _prefs?.setString(_prefVoiceoverKey, translation.title);
    } else {
      await _prefs?.setString(_prefVoiceoverKey, 'AniLibria');
    }

    if (translation.isAniLibria) {
      return null; // AniLibria использует стандартные URL серий тайтла
    }

    // Если выбрана озвучка Kodik, извлекаем прямую m3u8 ссылку
    final embedUrl = translation.episodeEmbedLinks[episodeNumber] ?? translation.embedLink;
    if (embedUrl != null && embedUrl.isNotEmpty) {
      final streamUrl = await _extractor.extractDirectStream(embedUrl, quality: quality);
      emit(state.copyWith(resolvedStreamUrl: () => streamUrl));
      return streamUrl;
    }

    return null;
  }

  /// Получить прямую ссылку на видеопоток для конкретной серии
  Future<String?> getStreamForEpisode(
    int episodeNumber, {
    String quality = '720p',
  }) async {
    if (state.isAniLibriaActive) return null;

    var embedUrl = state.selectedTranslation.episodeEmbedLinks[episodeNumber];
    if (embedUrl == null || embedUrl.isEmpty) {
      final base = state.selectedTranslation.embedLink;
      if (base != null && base.isNotEmpty) {
        embedUrl = '$base?season=1&episode=$episodeNumber';
      }
    }

    if (embedUrl != null && embedUrl.isNotEmpty) {
      final streamUrl = await _extractor.extractDirectStream(embedUrl, quality: quality);
      emit(state.copyWith(resolvedStreamUrl: () => streamUrl));
      return streamUrl;
    }
    return null;
  }
}
