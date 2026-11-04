import 'package:equatable/equatable.dart';

class EpisodeItem extends Equatable {
  final int episode;
  final String? name;
  final String? sdUrl;
  final String? hdUrl;
  final String? fhdUrl;

  const EpisodeItem({
    required this.episode,
    this.name,
    this.sdUrl,
    this.hdUrl,
    this.fhdUrl,
  });

  /// Получить URL наилучшего доступного качества (FHD -> HD -> SD)
  String? get bestAvailableUrl => fhdUrl ?? hdUrl ?? sdUrl;

  @override
  List<Object?> get props => [episode, name, sdUrl, hdUrl, fhdUrl];
}

