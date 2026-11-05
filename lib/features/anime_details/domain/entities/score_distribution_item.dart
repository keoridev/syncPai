import 'package:equatable/equatable.dart';

/// Элемент распределения оценок пользователей (от 1 до 10 звезд).
class ScoreDistributionItem extends Equatable {
  final int score; // 1..10
  final int votes;
  final double percentage;

  const ScoreDistributionItem({
    required this.score,
    required this.votes,
    this.percentage = 0.0,
  });

  @override
  List<Object?> get props => [score, votes, percentage];
}

