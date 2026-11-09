import '../entities/translation_entity.dart';
import '../repositories/anime_catalog_repository.dart';

class GetPlayerLinksUseCase {
  final AnimeCatalogRepository repository;

  const GetPlayerLinksUseCase(this.repository);

  Future<List<TranslationEntity>> call(int releaseId, {String? title}) {
    return repository.getPlayerLinks(releaseId, title: title);
  }
}

