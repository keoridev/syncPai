import 'package:equatable/equatable.dart';
import '../../domain/entities/kodik_translation.dart';

class KodikState extends Equatable {
  final List<KodikTranslation> translations;
  final KodikTranslation selectedTranslation;
  final bool isLoading;
  final String? resolvedStreamUrl;
  final String? errorMessage;

  const KodikState({
    this.translations = const [],
    required this.selectedTranslation,
    this.isLoading = false,
    this.resolvedStreamUrl,
    this.errorMessage,
  });

  factory KodikState.initial() => KodikState(
        translations: [KodikTranslation.anilibria()],
        selectedTranslation: KodikTranslation.anilibria(),
      );

  bool get isAniLibriaActive => selectedTranslation.isAniLibria;

  String get activeVoiceoverTitle => selectedTranslation.title;

  KodikState copyWith({
    List<KodikTranslation>? translations,
    KodikTranslation? selectedTranslation,
    bool? isLoading,
    String? Function()? resolvedStreamUrl,
    String? errorMessage,
  }) {
    return KodikState(
      translations: translations ?? this.translations,
      selectedTranslation: selectedTranslation ?? this.selectedTranslation,
      isLoading: isLoading ?? this.isLoading,
      resolvedStreamUrl:
          resolvedStreamUrl != null ? resolvedStreamUrl() : this.resolvedStreamUrl,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        translations,
        selectedTranslation,
        isLoading,
        resolvedStreamUrl,
        errorMessage,
      ];
}
