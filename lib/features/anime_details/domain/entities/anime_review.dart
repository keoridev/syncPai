import 'package:equatable/equatable.dart';

/// Отзыв зрителя с других аниме-ресурсов (Shikimori, AniLibria, MyAnimeList).
class AnimeReview extends Equatable {
  final String id;
  final String author;
  final String avatar;
  final double score; // Оценка от 1 до 10
  final String source; // 'Shikimori', 'AniLibria', 'MyAnimeList', 'World Art'
  final String text;
  final String date;
  final int likes;

  const AnimeReview({
    required this.id,
    required this.author,
    required this.avatar,
    required this.score,
    required this.source,
    required this.text,
    required this.date,
    this.likes = 0,
  });

  @override
  List<Object?> get props => [id, author, avatar, score, source, text, date, likes];
}

