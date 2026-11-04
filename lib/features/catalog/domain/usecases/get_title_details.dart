import '../entities/anime_title.dart';
import '../repositories/catalog_repository.dart';

class GetTitleDetails {
  final CatalogRepository repository;

  const GetTitleDetails(this.repository);

  Future<AnimeTitle> call({int? id, String? code}) {
    return repository.getTitleDetails(id: id, code: code);
  }
}

