import 'dart:math';
import 'package:equatable/equatable.dart';

class TimestampedReaction extends Equatable {
  final double timestampSec;
  final String emoji;
  final String sender;

  const TimestampedReaction({
    required this.timestampSec,
    required this.emoji,
    this.sender = 'Друг',
  });

  Map<String, dynamic> toJson() => {
        'timestamp_sec': timestampSec,
        'emoji': emoji,
        'sender': sender,
      };

  factory TimestampedReaction.fromJson(Map<String, dynamic> json) {
    return TimestampedReaction(
      timestampSec: (json['timestamp_sec'] as num?)?.toDouble() ?? 0.0,
      emoji: json['emoji'] as String? ?? '🔥',
      sender: json['sender'] as String? ?? 'Друг',
    );
  }

  @override
  List<Object?> get props => [timestampSec, emoji, sender];
}

class ReactionHeatmap extends Equatable {
  final int titleId;
  final int episode;
  final int bucketCount;
  final List<int> buckets;
  final List<TimestampedReaction> reactions;

  const ReactionHeatmap({
    required this.titleId,
    required this.episode,
    this.bucketCount = 80,
    required this.buckets,
    this.reactions = const [],
  });

  factory ReactionHeatmap.initial({
    required int titleId,
    required int episode,
    int bucketCount = 80,
  }) {
    // Генерируем естественную тепловую карту эмоций с пиками на опенинге, экшене и развязке
    final generated = List<int>.filled(bucketCount, 1);
    final random = Random(titleId * 31 + episode);

    // Пик 1: Конец опенинга (~10% таймлайна)
    final opIndex = (bucketCount * 0.08).toInt().clamp(0, bucketCount - 1);
    generated[opIndex] += 12 + random.nextInt(8);

    // Пик 2: Середина серии / твист (~50% таймлайна)
    final midIndex = (bucketCount * 0.52).toInt().clamp(0, bucketCount - 1);
    generated[midIndex] += 18 + random.nextInt(12);
    if (midIndex + 1 < bucketCount) generated[midIndex + 1] += 10;

    // Пик 3: Кульминация / эпичный файт (~82% таймлайна)
    final climaxIndex = (bucketCount * 0.84).toInt().clamp(0, bucketCount - 1);
    generated[climaxIndex] += 25 + random.nextInt(15);
    if (climaxIndex - 1 >= 0) generated[climaxIndex - 1] += 14;
    if (climaxIndex + 1 < bucketCount) generated[climaxIndex + 1] += 16;

    return ReactionHeatmap(
      titleId: titleId,
      episode: episode,
      bucketCount: bucketCount,
      buckets: generated,
    );
  }

  ReactionHeatmap addReaction({
    required double timestampSec,
    required double totalDurationSec,
    required String emoji,
    String sender = 'Друг',
  }) {
    if (totalDurationSec <= 0) return this;

    final progress = (timestampSec / totalDurationSec).clamp(0.0, 0.999);
    final bucketIdx = (progress * bucketCount).floor().clamp(0, bucketCount - 1);

    final updatedBuckets = List<int>.from(buckets);
    updatedBuckets[bucketIdx] += 1;

    final updatedReactions = List<TimestampedReaction>.from(reactions)
      ..add(TimestampedReaction(timestampSec: timestampSec, emoji: emoji, sender: sender));

    return ReactionHeatmap(
      titleId: titleId,
      episode: episode,
      bucketCount: bucketCount,
      buckets: updatedBuckets,
      reactions: updatedReactions,
    );
  }

  List<double> get normalizedHeights {
    if (buckets.isEmpty) return const [];
    final maxVal = buckets.reduce(max);
    if (maxVal <= 0) return List.filled(buckets.length, 0.1);

    return buckets.map((count) {
      final ratio = count / maxVal;
      // Минимальная высота полоски 0.15 для красивого SoundCloud-эффекта
      return (ratio * 0.85 + 0.15).clamp(0.15, 1.0);
    }).toList();
  }

  int get totalReactionsCount => buckets.fold(0, (sum, count) => sum + count);

  @override
  List<Object?> get props => [titleId, episode, bucketCount, buckets, reactions];
}

