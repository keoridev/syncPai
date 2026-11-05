import 'package:equatable/equatable.dart';
import '../../domain/entities/user_anime_entry.dart';
import '../../data/datasources/anixart_backup_parser.dart';

class AnimeListState extends Equatable {
  final List<UserAnimeEntry> allEntries;
  final AnimeListStatus selectedTab;
  final UserAnimeStats stats;
  final bool isLoading;
  final AnixartImportResult? lastImportResult;
  final String? errorMessage;

  const AnimeListState({
    this.allEntries = const [],
    this.selectedTab = AnimeListStatus.watching,
    required this.stats,
    this.isLoading = false,
    this.lastImportResult,
    this.errorMessage,
  });

  /// Отфильтрованные тайтлы по активной вкладке («Смотрю», «В планах» и т.д.)
  List<UserAnimeEntry> get currentTabEntries =>
      allEntries.where((e) => e.status == selectedTab).toList();

  /// Получить записи по определенному статусу
  List<UserAnimeEntry> entriesFor(AnimeListStatus status) =>
      allEntries.where((e) => e.status == status).toList();

  /// Количество записей в статусе
  int countFor(AnimeListStatus status) =>
      allEntries.where((e) => e.status == status).length;

  /// Получить запись для конкретного ID аниме
  UserAnimeEntry? getEntryFor(int animeId) {
    try {
      return allEntries.firstWhere((e) => e.animeId == animeId);
    } catch (_) {
      return null;
    }
  }

  AnimeListState copyWith({
    List<UserAnimeEntry>? allEntries,
    AnimeListStatus? selectedTab,
    UserAnimeStats? stats,
    bool? isLoading,
    AnixartImportResult? lastImportResult,
    String? errorMessage,
  }) {
    return AnimeListState(
      allEntries: allEntries ?? this.allEntries,
      selectedTab: selectedTab ?? this.selectedTab,
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      lastImportResult: lastImportResult,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        allEntries,
        selectedTab,
        stats,
        isLoading,
        lastImportResult,
        errorMessage,
      ];
}

