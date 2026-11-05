import '../../domain/entities/anime_clip.dart';
import '../../domain/repositories/anime_clips_repository.dart';
import '../datasources/anime_clips_datasource.dart';

class AnimeClipsRepositoryImpl implements AnimeClipsRepository {
  final AnimeClipsDataSource _dataSource;

  AnimeClipsRepositoryImpl(this._dataSource);

  @override
  Future<List<AnimeClip>> getClips({bool forceRefresh = false}) async {
    return _dataSource.getClips();
  }

  @override
  Future<bool> toggleLike(String clipId) async {
    return _dataSource.toggleLike(clipId);
  }

  @override
  Future<bool> toggleBookmark(String clipId) async {
    return _dataSource.toggleBookmark(clipId);
  }
}

