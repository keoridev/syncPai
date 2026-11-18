import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_pai/features/catalog/presentation/widgets/anime_poster_card.dart';
import 'package:sync_pai/features/downloads/domain/entities/download_task.dart';
import 'package:sync_pai/features/downloads/presentation/cubit/download_state.dart';

String formatEpisodesRussian(int count) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) {
    return '$count серия';
  } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
    return '$count серии';
  } else {
    return '$count серий';
  }
}

void main() {
  group('Grid Card Badge & Pluralization Polish Tests', () {
    test('Russian pluralization works for 1, 2, 5, 11, 21, 22, 25', () {
      expect(formatEpisodesRussian(1), equals('1 серия'));
      expect(formatEpisodesRussian(2), equals('2 серии'));
      expect(formatEpisodesRussian(3), equals('3 серии'));
      expect(formatEpisodesRussian(4), equals('4 серии'));
      expect(formatEpisodesRussian(5), equals('5 серий'));
      expect(formatEpisodesRussian(11), equals('11 серий'));
      expect(formatEpisodesRussian(12), equals('12 серий'));
      expect(formatEpisodesRussian(21), equals('21 серия'));
      expect(formatEpisodesRussian(22), equals('22 серии'));
      expect(formatEpisodesRussian(25), equals('25 серий'));
      expect(formatEpisodesRussian(0), equals('0 серий'));
    });

    test('Compact badge formatting transforms long strings to concise numbers', () {
      expect(
        UnifiedAnimeCard.formatBadgeText('1 / 12 эп.', isCompact: true),
        equals('1/12'),
      );
      expect(
        UnifiedAnimeCard.formatBadgeText('12 эп.', isCompact: true),
        equals('12'),
      );
      expect(
        UnifiedAnimeCard.formatBadgeText('Онгоинг • 1 / 12 эп.', isCompact: true),
        equals('1/12'),
      );
      expect(
        UnifiedAnimeCard.formatBadgeText('Онгоинг', isCompact: true),
        equals('Онгоинг'),
      );
      expect(
        UnifiedAnimeCard.formatBadgeText('1 / 12 эп.', isCompact: false),
        equals('1 / 12 эп.'),
      );
    });

    test('DownloadTask effectiveBytes reads disk length when totalBytes is 0', () {
      // Create a temporary file to test real disk size reading
      final tempFile = File('${Directory.systemTemp.path}/test_download_file.bin');
      tempFile.writeAsBytesSync(List<int>.filled(1024 * 1024 * 25, 0)); // 25 MB

      final task = DownloadTask(
        id: '123_1',
        titleId: 123,
        titleName: 'Test Anime',
        posterUrl: '',
        episode: 1,
        episodeName: 'Episode 1',
        quality: '1080p',
        sourceUrl: '',
        localPath: tempFile.path,
        totalBytes: 0,
        createdAt: DateTime.now(),
      );

      expect(task.effectiveBytes, equals(1024 * 1024 * 25));
      expect(task.formattedSize, equals('25 МБ'));

      final state = DownloadState(
        tasks: {task.id: task.copyWith(status: DownloadStatus.completed)},
      );
      expect(state.totalBytesUsed, equals(1024 * 1024 * 25));
      expect(state.formattedTotalBytesUsed, equals('25 МБ'));

      // Clean up
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
    });
  });
}
