import '../../domain/entities/translation_entity.dart';
import 'translation_model.dart';

/// DTO ответа Edge Function get_anime_player_data
class AnimePlayerDataModel {
  final int shikimoriId;
  final List<TranslationModel> translations;
  final String? error;

  const AnimePlayerDataModel({
    required this.shikimoriId,
    required this.translations,
    this.error,
  });

  factory AnimePlayerDataModel.fromJson(Map<String, dynamic> json) {
    final rawTranslations = json['translations'] as List<dynamic>? ?? [];
    return AnimePlayerDataModel(
      shikimoriId: (json['shikimori_id'] as num?)?.toInt() ?? 0,
      translations: rawTranslations
          .whereType<Map<String, dynamic>>()
          .map((t) => TranslationModel.fromJson(t))
          .toList(),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shikimori_id': shikimoriId,
      'translations': translations.map((t) => t.toJson()).toList(),
      if (error != null) 'error': error,
    };
  }

  List<TranslationEntity> toDomain() {
    return translations.map((t) => t.toDomain()).toList();
  }
}

