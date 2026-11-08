import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/widgets/theme_selector_sheet.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/glass_container.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/network/smart_mirror_interceptor.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../anime_lists/presentation/cubit/anime_list_state.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../auth/presentation/widgets/auth_modal_sheet.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../../../catalog/presentation/cubit/catalog_cubit.dart';
import '../../../catalog/presentation/cubit/catalog_state.dart';
import '../../domain/entities/steam_profile_customization.dart';
import '../widgets/profile_activity_chart.dart';
import '../widgets/steam_profile_customizer_sheet.dart';
import '../widgets/steam_style_profile_header.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final bool showBackButton;

  const ProfileScreen({
    super.key,
    this.onBack,
    this.showBackButton = true,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _autoSkipOpenings = true;
  bool _autoPauseOnLeave = true;
  bool _liquidGlassEffects = true;
  bool _showActivityCharts = false;
  String _defaultQuality = '1080p FHD';
  static const List<String> _avatarPresets = [
    'cat', 'fox', 'panda', 'wolf', 'bolt', 'flower', 'shield', 'fire', 'gamer', 'star', 'bot'
  ];

  Future<void> _pickAndImportAnixart(BuildContext context, String userId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'json'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String content = '';

        if (file.bytes != null) {
          try {
            content = utf8.decode(file.bytes!);
          } catch (_) {
            content = String.fromCharCodes(file.bytes!);
          }
        } else if (file.path != null) {
          final ioFile = File(file.path!);
          try {
            content = await ioFile.readAsString(encoding: utf8);
          } catch (_) {
            final bytes = await ioFile.readAsBytes();
            content = utf8.decode(bytes, allowMalformed: true);
          }
        }

        if (content.isNotEmpty && context.mounted) {
          await context.read<AnimeListCubit>().importAnixartBackup(content, userId: userId);
          if (context.mounted) {
            final res = context.read<AnimeListCubit>().state.lastImportResult;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  res != null
                      ? 'Успешно импортировано ${res.totalParsed} тайтлов (${res.totalEpisodes} серий) • ${res.estimatedTimeSpent}'
                      : 'Списки Anixart успешно импортированы!',
                ),
                backgroundColor: AppColors.syncActive,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при импорте файла: $e'),
            backgroundColor: AppColors.syncError,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showOnlineImportDialog(BuildContext context, String userId) {
    final controller = TextEditingController();
    bool isSubmitting = false;
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppDimensions.spacingXl,
                right: AppDimensions.spacingXl,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.strokeMedium,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.cloud_download_outlined, color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Импорт профиля Anixart',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Введите цифровой ID (например, 482190) или логин в Anixart. Все закладки будут загружены прямо в SyncPai.',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'ID профиля или логин (например 123456)',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      filled: true,
                      fillColor: AppColors.surface,
                      prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.content_paste_rounded, color: AppColors.primary, size: 20),
                        tooltip: 'Вставить из буфера',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null && data!.text!.isNotEmpty) {
                            controller.text = data.text!.trim();
                          }
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.strokeMedium),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.syncError.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.syncError.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.syncError, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              localError!,
                              style: const TextStyle(color: AppColors.syncError, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.strokeMedium),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.privacy_tip_outlined, color: AppColors.syncWaiting, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ваш профиль в Anixart должен быть открытым: Настройки -> Приватность -> Списки аниме: Всем',
                            style: AppTypography.caption.copyWith(color: AppColors.textMuted, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final text = controller.text.trim();
                              if (text.isEmpty) {
                                setModalState(() => localError = 'Пожалуйста, укажите ID или логин.');
                                return;
                              }
                              setModalState(() {
                                isSubmitting = true;
                                localError = null;
                              });

                              try {
                                final cubit = context.read<AnimeListCubit>();
                                final res = await cubit.importAnixartOnline(text, userId: userId);
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (context.mounted && res != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppColors.syncActive,
                                      content: Text(
                                        'Успешно импортировано ${res.totalParsed} тайтлов (${res.totalEpisodes} серий)!',
                                        style: const TextStyle(color: AppColors.textPrimary),
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModalState(() {
                                  isSubmitting = false;
                                  localError = e.toString().replaceFirst('Exception: ', '');
                                });
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: AppColors.textPrimary, strokeWidth: 2),
                            )
                          : const Text(
                              'Начать импорт',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                    ),
                  ),
                ],
              ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditProfileSheet(BuildContext context, UserProfile profile) {
    final controller = TextEditingController(text: profile.username);
    String selectedAvatar = profile.avatarUrl ?? 'cat';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.spacingXl,
            AppDimensions.spacingLg,
            AppDimensions.spacingXl,
            MediaQuery.of(context).viewInsets.bottom + AppDimensions.spacingXl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.strokeMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Редактировать профиль',
                style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 16),
              Text(
                'Выберите аватар профиля',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _avatarPresets.map((av) {
                  final isSel = selectedAvatar == av;
                  return InkWell(
                    onTap: () => setSheetState(() => selectedAvatar = av),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSel ? AppColors.primary : Colors.transparent,
                          width: 2.0,
                        ),
                      ),
                      child: AppAvatar(
                        avatarUrl: av,
                        size: 38,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Никнейм',
                  labelStyle: const TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.strokeMedium),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    final newName = controller.text.trim();
                    if (newName.isNotEmpty) {
                      context.read<AuthCubit>().updateProfile(
                            username: newName,
                            avatarUrl: selectedAvatar,
                          );
                      Navigator.pop(sheetContext);
                    }
                  },
                  child: const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final themePrimaryLight = HSLColor.fromColor(themePrimary)
        .withLightness((HSLColor.fromColor(themePrimary).lightness + 0.15).clamp(0.0, 1.0))
        .toColor();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, authState) {
            final rawProfile = authState is Authenticated ? authState.profile : UserProfile.guest();
            // Если в профиле стандартный цвет, но тема приложения изменена — синхронизируем с темой
            final profile = rawProfile;

            return BlocBuilder<AnimeListCubit, AnimeListState>(
              builder: (context, listState) {
                final stats = listState.stats;

                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        // ШАПКА В СТИЛЕ STEAM (Арт/обои на 240dp + Аватарка в неоновой рамке + Статус + Кнопки)
                        SliverToBoxAdapter(
                          child: SteamStyleProfileHeader(
                            profile: profile,
                            showBackButton: widget.showBackButton,
                            onBackTap: widget.onBack ?? () => Navigator.of(context).maybePop(),
                            onCustomizerTap: () => SteamProfileCustomizerSheet.show(context, profile),
                            onEditProfileTap: () => _showEditProfileSheet(context, profile),
                          ),
                        ),

                    // КАРТОЧКА СИНХРОНИЗАЦИИ ПРОФИЛЯ (Гость / Облако)
                    if (profile.isAnonymous)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppDimensions.spacingXl,
                            AppDimensions.spacingMd,
                            AppDimensions.spacingXl,
                            0,
                          ),
                          child: InkWell(
                            onTap: () => AuthModalSheet.show(context, profile),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: themePrimary.withValues(alpha: 0.4),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: themePrimary.withValues(alpha: 0.08),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: themePrimary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.cloud_sync_rounded,
                                      color: themePrimaryLight,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Синхронизация профиля',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Привяжите Google или создайте аккаунт, чтобы перенести кастомный арт и списки',
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textMuted,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: AppColors.primary,
                                    size: 14,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppDimensions.spacingXl,
                            AppDimensions.spacingMd,
                            AppDimensions.spacingXl,
                            0,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.syncActive.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.syncActive.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    profile.provider == 'google'
                                        ? Icons.verified_user_rounded
                                        : Icons.cloud_done_rounded,
                                    color: AppColors.syncActive,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile.provider == 'google'
                                            ? 'Google аккаунт привязан'
                                            : 'Облачная синхронизация активна',
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (profile.email != null && profile.email!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          profile.email!,
                                          style: AppTypography.caption.copyWith(
                                            color: AppColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => context.read<AuthCubit>().signOut(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.textMuted,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('Выйти', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // ВИТРИНА ПРОФИЛЯ В СТИЛЕ STEAM (Любимый тайтл)
                    SliverToBoxAdapter(
                      child: _buildFavoriteAnimeShowcase(context, profile),
                    ),

                    // БЛОК СТАТИСТИКИ «КАК В ANIXART»
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.spacingXl,
                          AppDimensions.spacingLg,
                          AppDimensions.spacingXl,
                          AppDimensions.spacingMd,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.strokeMedium),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'СТАТИСТИКА ПРОСМОТРА',
                                    style: AppTypography.caption.copyWith(
                                      letterSpacing: 1.2,
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _showActivityCharts = !_showActivityCharts),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: themePrimary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: themePrimary.withValues(alpha: 0.3),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _showActivityCharts ? Icons.keyboard_arrow_up_rounded : Icons.bar_chart_rounded,
                                            size: 13,
                                            color: themePrimaryLight,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _showActivityCharts ? 'Скрыть график' : 'Графики',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: themePrimaryLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  _buildStatItem('Время', stats.formattedTime, 'потрачено', Icons.schedule_rounded, themePrimaryLight),
                                  _buildDivider(),
                                  _buildStatItem('Тайтлы', '${stats.totalTitles}', 'в списках', Icons.video_collection_outlined, themePrimaryLight),
                                  _buildDivider(),
                                  _buildStatItem('Серии', '${stats.totalEpisodesCompleted}', 'просмотрено', Icons.play_circle_outline_rounded, themePrimaryLight),
                                ],
                              ),
                              if (_showActivityCharts) ...[
                                const SizedBox(height: 16),
                                ProfileActivityChart(stats: stats),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    // КНОПКА ИМПОРТА ИЗ ANIXART
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: themePrimary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: themePrimary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: themePrimary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.file_upload_outlined, color: themePrimary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Импорт из Anixart',
                                      style: AppTypography.titleSmall.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'По логину / ID онлайн или из .csv / .json файла',
                                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              _buildGlassImportButton(
                                icon: Icons.cloud_download_outlined,
                                label: 'По ID',
                                onTap: () => _showOnlineImportDialog(context, profile.id),
                              ),
                              const SizedBox(width: 8),
                              _buildGlassImportButton(
                                icon: Icons.folder_open_rounded,
                                label: 'Файл',
                                onTap: () => _pickAndImportAnixart(context, profile.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // РАЗДЕЛ: «НАСТРОЙКИ ПРИЛОЖЕНИЯ И ПЛЕЕРА»
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.spacingXl,
                          AppDimensions.spacingXl,
                          AppDimensions.spacingXl,
                          AppDimensions.spacingSm,
                        ),
                        child: Text(
                          'НАСТРОЙКИ ПЛЕЕРА И СИСТЕМЫ',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),

                    // КАРТОЧКА НАСТРОЕК В СТИЛЕ ЖИДКОГО СТЕКЛА
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                        child: GlassContainer(
                          borderRadius: BorderRadius.circular(20),
                          blurSigma: 16,
                          backgroundOpacity: 0.08,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Тема оформления и палитра приложения
                              InkWell(
                                onTap: () => ThemeSelectorSheet.show(context),
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: themePrimary,
                                          border: Border.all(color: Colors.white30, width: 1.5),
                                        ),
                                        child: const Icon(Icons.palette_rounded, color: Colors.white, size: 16),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Цветовая палитра оформления',
                                              style: AppTypography.titleSmall.copyWith(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '8 дизайнерских тем (Мандарин, Неон, Сакура, Ева...)',
                                              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary),
                                    ],
                                  ),
                                ),
                              ),
                              const Divider(color: AppColors.strokeMedium, height: 18),

                              // Качество видео по умолчанию
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.hd_rounded, color: themePrimary, size: 20),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Качество видео',
                                        style: AppTypography.bodyMedium.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  DropdownButton<String>(
                                    value: _defaultQuality,
                                    dropdownColor: AppColors.surfaceElevated,
                                    underline: const SizedBox.shrink(),
                                    style: TextStyle(
                                      color: themePrimaryLight,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: '1080p FHD', child: Text('1080p FHD')),
                                      DropdownMenuItem(value: '720p HD', child: Text('720p HD')),
                                      DropdownMenuItem(value: '480p SD', child: Text('480p SD')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _defaultQuality = val);
                                    },
                                  ),
                                ],
                              ),
                              const Divider(color: AppColors.strokeMedium, height: 18),

                              // Авто-пропуск опенингов
                              _buildSettingSwitch(
                                title: 'Авто-пропуск опенингов',
                                subtitle: 'Умный таймкод-скип вступительных заставок',
                                value: _autoSkipOpenings,
                                onChanged: (val) => setState(() => _autoSkipOpenings = val),
                              ),
                              const Divider(color: AppColors.strokeMedium, height: 18),

                              // Авто-пауза при уходе друга
                              _buildSettingSwitch(
                                title: 'Авто-пауза при уходе друга',
                                subtitle: 'Останавливать плеер, если друг свернул приложение',
                                value: _autoPauseOnLeave,
                                onChanged: (val) => setState(() => _autoPauseOnLeave = val),
                              ),
                              const Divider(color: AppColors.strokeMedium, height: 18),

                              // Эффекты жидкого стекла
                              _buildSettingSwitch(
                                title: 'Эффекты жидкого стекла',
                                subtitle: 'Аппаратный блур BackdropFilter и световые блики',
                                value: _liquidGlassEffects,
                                onChanged: (val) => setState(() => _liquidGlassEffects = val),
                              ),
                              const Divider(color: AppColors.strokeMedium, height: 18),

                              // Умная ретрансляция и анти-блокировка (DoH Cloudflare)
                              _buildSettingSwitch(
                                title: 'Умная ретрансляция (Анти-блокировка)',
                                subtitle: SmartMirrorInterceptor.isAntiBlockEnabled
                                    ? 'DoH Cloudflare 1.1.1.1 и авто-ротация зеркал видео'
                                    : 'Прямое подключение к серверам',
                                value: SmartMirrorInterceptor.isAntiBlockEnabled,
                                onChanged: (val) {
                                  setState(() {
                                    SmartMirrorInterceptor.isAntiBlockEnabled = val;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        val
                                            ? 'Анти-блокировка включена: зеркала ротируются автоматически'
                                            : 'Анти-блокировка выключена',
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 16)),

                    // КНОПКА ОЧИСТКИ КЭША И ИСТОРИИ
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.syncError,
                            side: const BorderSide(color: AppColors.strokeMedium),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                          label: const Text('Очистить кэш плеера и историю', style: TextStyle(fontWeight: FontWeight.w600)),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Кэш плеера и временные файлы очищены!',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                                backgroundColor: const Color(0xFF242730),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
              ),
            );
          },
        );
          },
        ),
      ),
    );
  }

  Future<void> _openFavoriteAnimeDetails(BuildContext context, UserProfile profile) async {
    final favTitle = profile.favoriteAnimeTitle;
    if (favTitle == null || favTitle.isEmpty) return;

    AnimeTitle? matched;
    // 1. Поиск в каталоге в памяти
    try {
      final catalogState = getIt.isRegistered<CatalogCubit>()
          ? getIt<CatalogCubit>().state
          : (context.mounted ? context.read<CatalogCubit>().state : null);
      if (catalogState is CatalogLoaded) {
        matched = catalogState.titles.firstWhere(
          (t) =>
              (profile.favoriteAnimeId != null && t.id.toString() == profile.favoriteAnimeId) ||
              t.russianTitle.toLowerCase().trim() == favTitle.toLowerCase().trim() ||
              (t.englishTitle.isNotEmpty &&
                  t.englishTitle.toLowerCase().trim() == favTitle.toLowerCase().trim()),
        );
      }
    } catch (_) {}

    // 2. Поиск в сохраненных списках пользователя
    if (matched == null) {
      try {
        final listState = context.read<AnimeListCubit>().state;
        final savedMatch = listState.allEntries.firstWhere(
          (e) =>
              (profile.favoriteAnimeId != null && e.animeId.toString() == profile.favoriteAnimeId) ||
              e.cleanTitleRu.toLowerCase().trim() == favTitle.toLowerCase().trim() ||
              e.titleRu.toLowerCase().trim() == favTitle.toLowerCase().trim(),
        );
        matched = AnimeTitle(
          id: savedMatch.animeId,
          code: 'saved_${savedMatch.animeId}',
          russianTitle: savedMatch.cleanTitleRu,
          englishTitle: savedMatch.cleanTitleRu,
          posterSmall: savedMatch.posterUrl ?? '',
          posterMedium: savedMatch.posterUrl ?? '',
          posterOriginal: savedMatch.posterUrl ?? '',
          genres: const [],
          description: '',
          status: savedMatch.status.labelRu,
          episodesTotal: savedMatch.episodesTotal,
        );
      } catch (_) {}
    }

    // 3. Поиск через репозиторий каталога
    if (matched == null && getIt.isRegistered<CatalogRepository>()) {
      try {
        final results = await getIt<CatalogRepository>().searchTitles(favTitle, limit: 1);
        if (results.isNotEmpty) {
          matched = results.first;
        }
      } catch (_) {}
    }

    // 4. Fallback AnimeTitle
    final target = matched ??
        AnimeTitle(
          id: profile.favoriteAnimeId != null ? int.tryParse(profile.favoriteAnimeId!) ?? 0 : 0,
          code: 'showcase_${profile.favoriteAnimeId ?? favTitle}',
          russianTitle: favTitle,
          englishTitle: favTitle,
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          genres: const [],
          description: '',
          status: 'В эфире',
        );

    if (context.mounted) {
      context.pushNamed('details', extra: target);
    }
  }

  Widget _buildFavoriteAnimeShowcase(BuildContext context, UserProfile profile) {
    final accent = SteamProfileThemeAccent.fromHex(profile.accentColor).color;
    final favTitle = profile.favoriteAnimeTitle;

    // Приоритет: 1) сохранённый постер из профиля, 2) поиск в каталоге, 3) поиск в списках
    String? showcasePoster = profile.favoriteAnimePoster;

    if ((showcasePoster == null || showcasePoster.isEmpty) && favTitle != null && favTitle.isNotEmpty) {
      try {
        final catalogState = getIt.isRegistered<CatalogCubit>()
          ? getIt<CatalogCubit>().state
          : (context.mounted ? context.read<CatalogCubit>().state : null);
        if (catalogState is CatalogLoaded) {
          final m = catalogState.titles.firstWhere(
            (t) =>
                (profile.favoriteAnimeId != null && t.id.toString() == profile.favoriteAnimeId) ||
                t.russianTitle.toLowerCase().trim() == favTitle.toLowerCase().trim(),
          );
          showcasePoster = m.posterMedium.isNotEmpty ? m.posterMedium : m.posterOriginal;
        }
      } catch (_) {}
      if (showcasePoster == null || showcasePoster.isEmpty) {
        try {
          final listState = context.read<AnimeListCubit>().state;
          final m = listState.allEntries.firstWhere(
            (e) =>
                (profile.favoriteAnimeId != null && e.animeId.toString() == profile.favoriteAnimeId) ||
                e.cleanTitleRu.toLowerCase().trim() == favTitle.toLowerCase().trim(),
          );
          showcasePoster = m.posterUrl;
        } catch (_) {}
      }
      // Fallback: Shikimori poster via favoriteAnimeId
      if ((showcasePoster == null || showcasePoster.isEmpty) && profile.favoriteAnimeId != null) {
        showcasePoster = 'https://shikimori.one/system/animes/original/${profile.favoriteAnimeId}.jpg';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.spacingXl,
        AppDimensions.spacingMd,
        AppDimensions.spacingXl,
        0,
      ),
      child: InkWell(
        onTap: favTitle != null && favTitle.isNotEmpty
            ? () => _openFavoriteAnimeDetails(context, profile)
            : () => SteamProfileCustomizerSheet.show(context, profile),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: favTitle != null ? accent.withValues(alpha: 0.5) : AppColors.strokeMedium,
              width: favTitle != null ? 1.5 : 1.0,
            ),
            boxShadow: favTitle != null
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ВИТРИНА ПРОФИЛЯ • ЛЮБИМЫЙ ТАЙТЛ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        letterSpacing: 1.1,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => SteamProfileCustomizerSheet.show(context, profile),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        favTitle != null ? 'Изменить' : 'Настроить',
                        style: TextStyle(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (favTitle != null && favTitle.isNotEmpty)
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 52,
                        height: 68,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: accent.withValues(alpha: 0.4)),
                        ),
                        child: showcasePoster != null && showcasePoster.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: wrapCorsSafeUrl(showcasePoster),
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.high,
                                errorWidget: (_, __, ___) => Center(
                                  child: Icon(Icons.movie_creation_rounded, color: accent, size: 28),
                                ),
                              )
                            : Center(
                                child: Icon(Icons.movie_creation_rounded, color: accent, size: 28),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            favTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [
                              Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 16),
                              SizedBox(width: 4),
                              Text(
                                '10 / 10 • Личный выбор',
                                style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if (profile.customStatus != null && profile.customStatus!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '«${profile.customStatus}»',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.chevron_right_rounded, color: accent.withValues(alpha: 0.7), size: 22),
                  ],
                )
              else
                InkWell(
                  onTap: () => SteamProfileCustomizerSheet.show(context, profile),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.strokeMedium,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline_rounded, color: accent, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Выбрать любимый тайтл на витрину',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String title, String value, String subtitle, [IconData? icon, Color? accentColor]) {
    final effectiveAccent = accentColor ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: effectiveAccent),
          const SizedBox(height: 3),
        ],
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            color: effectiveAccent,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          subtitle,
          style: AppTypography.caption.copyWith(
            fontSize: 10.5,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.strokeMedium,
    );
  }

  Widget _buildSettingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeTrackColor: themePrimary,
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.white54;
          }),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildGlassImportButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: themePrimary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

