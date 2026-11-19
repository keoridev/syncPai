import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/smart_mirror_interceptor.dart';
import '../../../../core/services/app_updater_service.dart';
import '../../../../core/services/device_performance_service.dart';
import '../../../../core/services/discord_rpc_service.dart';
import '../../../../core/services/presence_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/cubit/theme_cubit.dart';
import '../../../../core/theme/theme_preset.dart';
import '../../../../core/theme/widgets/theme_selector_sheet.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/mascot/mascot_gallery_widget.dart';
import '../../../../core/widgets/telegram_link_tile.dart';
import '../../../anime_lists/data/datasources/anixart_csv_parser.dart';
import '../../../anime_lists/data/datasources/anixart_remote_datasource.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../anime_lists/presentation/widgets/import_progress_dialog.dart';
import '../../../anime_lists/presentation/widgets/import_status_selector_dialog.dart';
import '../../../player/presentation/widgets/player_hud_editor_sheet.dart';
import '../../../player/presentation/widgets/player_onboarding_overlay.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../auth/presentation/widgets/auth_modal_sheet.dart';
import '../../../settings/presentation/cubit/settings_cubit.dart';
import '../../../settings/presentation/cubit/settings_state.dart';
import '../../../watch_history/presentation/cubit/watch_history_cubit.dart';
import '../../../winter_theme/domain/services/winter_theme_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  PlayerHudPreset _playerHudPreset = PlayerHudPreset.standard;
  bool _autoSkipOpenings = true;
  bool _autoPauseOnLeave = true;
  bool _liquidGlassEffects = true;
  String _defaultQuality = '1080p FHD';
  String _appVersion = '1.0.0';
  bool _isCheckingUpdates = false;
  String _mobileSectionFilter = 'all';
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      try {
        context.read<AuthCubit>().refreshProfile();
      } catch (_) {}
    }
  }

  Future<void> _loadSettings() async {
    _prefs = getIt.isRegistered<SharedPreferences>()
        ? getIt<SharedPreferences>()
        : await SharedPreferences.getInstance();
    final ver = await AppUpdaterService.instance.getCurrentVersion();
    if (mounted) {
      setState(() {
        _appVersion = ver;
        if (getIt.isRegistered<SettingsCubit>()) {
          final s = getIt<SettingsCubit>().state;
          _playerHudPreset = s.playerHudPreset;
          _autoSkipOpenings = s.autoSkipOpenings;
          _autoPauseOnLeave = s.autoPauseOnLeave;
          _liquidGlassEffects = s.liquidGlassEffects;
          _defaultQuality = s.defaultQuality;
        } else if (_prefs != null) {
          _playerHudPreset = PlayerHudPreset.fromString(_prefs!.getString('settings_player_hud_preset'));
          _autoSkipOpenings = _prefs!.getBool('settings_auto_skip_openings') ?? true;
          _autoPauseOnLeave = _prefs!.getBool('settings_auto_pause_on_leave') ?? true;
          _liquidGlassEffects = _prefs!.getBool('settings_liquid_glass') ?? DevicePerformanceService.instance.isLiquidGlassBlurEnabled;
          _defaultQuality = _prefs!.getString('settings_default_quality') ?? '1080p FHD';
        }
      });
    }
  }

  Future<void> _saveBool(String key, bool val) async {
    await _prefs?.setBool(key, val);
  }

  Future<void> _saveString(String key, String val) async {
    await _prefs?.setString(key, val);
  }

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

        if (content.isEmpty || !context.mounted) return;

        final rawTitles = AnixartCsvParser.extractRawTitles(content);
        final detectedCount = rawTitles.isNotEmpty ? rawTitles.length : 1;

        final selection = await ImportStatusSelectorDialog.show(
          context,
          totalTitlesDetected: detectedCount,
          fileName: file.name,
        );

        if (selection == null || !context.mounted) return;

        final progressNotifier = ValueNotifier<ImportProgressData>(
          ImportProgressData(
            current: 0,
            total: detectedCount,
            currentTitle: 'Инициализация подключения...',
          ),
        );

        ImportProgressDialog.show(context, progressNotifier: progressNotifier);

        final cubit = context.read<AnimeListCubit>();
        dynamic importResult;

        try {
          if (selection.useShikimoriSearch) {
            importResult = await cubit.importAnixartCsvWithShikimori(
              content,
              userId: userId,
              defaultStatus: selection.defaultStatus,
              overrideStatus: selection.autoDistribute ? null : selection.defaultStatus,
              onProgress: (current, total, currentTitle) {
                progressNotifier.value = ImportProgressData(
                  current: current,
                  total: total,
                  currentTitle: currentTitle,
                );
              },
            );
          } else {
            await cubit.importAnixartBackup(content, userId: userId);
            importResult = cubit.state.lastImportResult;
          }
        } finally {
          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        }

        if (context.mounted) {
          final res = importResult ?? cubit.state.lastImportResult;
          final stats = cubit.state.stats;
          final added = res?.addedCount ?? (res?.totalParsed ?? detectedCount);
          final updated = res?.updatedCount ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Импорт завершён: добавлено $added, обновлено $updated дубликатов '
                '(Смотрю: ${stats.watchingTitles}, В планах: ${stats.plannedTitles}, Просмотрено: ${stats.completedTitles})',
              ),
              backgroundColor: AppColors.syncActive,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
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
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.strokeMedium),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.strokeMedium),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primary),
                        ),
                        hoverColor: Colors.transparent,
                        focusColor: Colors.transparent,
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
                          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ваш профиль в Anixart должен быть открытым (Настройки -> Конфиденциальность -> Кто видит мой список -> Все).',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                                height: 1.35,
                              ),
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
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final text = controller.text.trim();
                                if (text.isEmpty) {
                                  setModalState(() => localError = 'Введите ID профиля или логин');
                                  return;
                                }

                                setModalState(() {
                                  isSubmitting = true;
                                  localError = null;
                                });

                                try {
                                  final cubit = sheetContext.read<AnimeListCubit>();
                                  final res = await cubit.importAnixartOnline(text, userId: userId);
                                  if (sheetContext.mounted) {
                                    FocusScope.of(sheetContext).unfocus();
                                    Navigator.pop(sheetContext);
                                  }
                                  if (sheetContext.mounted && res != null) {
                                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppColors.syncActive,
                                        content: Text(
                                          'Успешно импортировано ${res.totalParsed} тайтлов (${res.totalEpisodes} серий)!',
                                          style: const TextStyle(color: AppColors.textPrimary),
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  setModalState(() {
                                    isSubmitting = false;
                                    localError = AnixartRemoteDataSourceImpl.mapUserFriendlyError(e);
                                  });
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
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

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Выйти из аккаунта?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'Вы вернетесь в гостевой режим. Ваши локальные списки останутся на устройстве.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.syncError,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<AuthCubit>().signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Вы вышли из профиля SyncPai'),
                  backgroundColor: AppColors.surfaceElevated,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Выйти', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _showMascotGallerySheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final maxH = MediaQuery.sizeOf(sheetCtx).height * 0.85;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Галерея маскота Пай-тян',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                const Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: MascotGalleryWidget(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showClearCacheAndDataSheet(BuildContext context, String userId) async {
    bool clearCache = true;
    bool clearHistory = false;
    bool clearLists = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12161F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final themePrimary = Theme.of(ctx).colorScheme.primary;
            final hasSelection = clearCache || clearHistory || clearLists;

            Future<void> performClear() async {
              final messenger = ScaffoldMessenger.of(this.context);
              AnimeListCubit? listCubit;
              WatchHistoryCubit? historyCubit;
              if (getIt.isRegistered<AnimeListCubit>()) {
                listCubit = getIt<AnimeListCubit>();
              } else {
                try {
                  listCubit = this.context.read<AnimeListCubit>();
                } catch (_) {}
              }
              if (getIt.isRegistered<WatchHistoryCubit>()) {
                historyCubit = getIt<WatchHistoryCubit>();
              } else {
                try {
                  historyCubit = this.context.read<WatchHistoryCubit>();
                } catch (_) {}
              }

              Navigator.of(sheetCtx).pop();

              if (clearCache) {
                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();
              }
              if (clearLists && listCubit != null) {
                await listCubit.clearAllLists(userId: userId);
              }
              if (clearHistory && historyCubit != null) {
                await historyCubit.clearAllHistory();
              }

              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Выбранные данные и кэш очищены',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: const Color(0xFF242730),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            }

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Очистка кэша и данных',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Выберите категории, которые хотите очистить:',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      key: const ValueKey('clear_opt_cache'),
                      value: clearCache,
                      activeColor: themePrimary,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Кэш картинок и плеера',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Временные буферы постеров и видео',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      onChanged: (v) => setSheetState(() => clearCache = v ?? false),
                    ),
                    CheckboxListTile(
                      key: const ValueKey('clear_opt_history'),
                      value: clearHistory,
                      activeColor: const Color(0xFFEF5350),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'История просмотров',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Прогресс серий и недавно открытые тайтлы',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      onChanged: (v) => setSheetState(() => clearHistory = v ?? false),
                    ),
                    CheckboxListTile(
                      key: const ValueKey('clear_opt_lists'),
                      value: clearLists,
                      activeColor: const Color(0xFFEF5350),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Списки закладок',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        '«Смотрю», «В планах», «Просмотрено» и др.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      onChanged: (v) => setSheetState(() => clearLists = v ?? false),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            key: const ValueKey('confirm_clear_cache_data_btn'),
                            style: FilledButton.styleFrom(
                              backgroundColor: (clearHistory || clearLists)
                                  ? const Color(0xFFEF5350)
                                  : themePrimary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: hasSelection ? performClear : null,
                            child: const Text(
                              'Очистить',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildPlayerHudPresetBlock(BuildContext context, Color themePrimary) {
    final cubit = getIt.isRegistered<SettingsCubit>() ? getIt<SettingsCubit>() : null;

    Widget buildBody(PlayerHudPreset currentPreset) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themePrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.dashboard_customize_outlined, color: themePrimary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Пресет плеера',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          if (currentPreset == PlayerHudPreset.custom) ...[
                            const SizedBox(width: 8),
                            Container(
                              key: const ValueKey('hud_custom_badge'),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: themePrimary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Пользовательский',
                                style: TextStyle(
                                  color: themePrimary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentPreset.description,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final p in const [
                  PlayerHudPreset.standard,
                  PlayerHudPreset.minimal,
                  PlayerHudPreset.advanced,
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        key: ValueKey('hud_preset_${p.name}'),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() => _playerHudPreset = p);
                          _saveString('settings_player_hud_preset', p.name);
                          cubit?.setPlayerHudPreset(p);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                          decoration: BoxDecoration(
                            color: currentPreset == p
                                ? themePrimary.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: currentPreset == p
                                  ? themePrimary.withValues(alpha: 0.65)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            p.label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: currentPreset == p ? themePrimary : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('hud_customize_buttons_btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: cubit == null
                        ? null
                        : () => _showPlayerButtonsEditorSheet(context, cubit, themePrimary),
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: const Text(
                      'Настроить кнопки HUD',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('hud_reset_default_btn'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _playerHudPreset = PlayerHudPreset.standard);
                      _saveString('settings_player_hud_preset', PlayerHudPreset.standard.name);
                      cubit?.resetPlayerHudToDefault();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text(
                      'Сбросить',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (cubit == null) {
      return buildBody(_playerHudPreset);
    }

    return BlocBuilder<SettingsCubit, SettingsState>(
      bloc: cubit,
      builder: (context, settingsState) => buildBody(settingsState.playerHudPreset),
    );
  }

  Future<void> _showPlayerButtonsEditorSheet(
    BuildContext context,
    SettingsCubit cubit,
    Color themePrimary,
  ) {
    return PlayerHudEditorSheet.show(context, cubit: cubit);
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        title,
        style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildWinterSection(BuildContext context, Color themePrimary) {
    final winter = WinterThemeService.instance;
    return ListenableBuilder(
      listenable: winter,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('ЗИМНЯЯ СКАЗКА 2026 (WINTER EXPERIENCE)'),
            _buildCard([
              // 1. Включить зимнюю тему
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF35D9D5).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.ac_unit_rounded, color: Color(0xFF35D9D5), size: 20),
                ),
                title: const Text(
                  'Зимняя тема SyncPai',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Праздничное оформление и морозные акценты',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                value: winter.isWinterThemeEnabled,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  winter.setWinterTheme(val);
                },
              ),
              _buildDivider(),

              // 2. Падающий снег
              SwitchListTile(
                key: const ValueKey('settings_snowfall_switch'),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.grain_rounded, color: Colors.white, size: 20),
                ),
                title: const Text(
                  'Падающий снег',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Плотный снегопад на всех экранах приложения',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                value: winter.isSnowfallEnabled,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  winter.setSnowfall(val);
                },
              ),
              _buildDivider(),

              // 2.1. Снег во время просмотра аниме
              SwitchListTile(
                key: const ValueKey('settings_snow_in_player_switch'),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: winter.isSnowfallEnabled ? 0.08 : 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.movie_filter_rounded,
                    color: winter.isSnowfallEnabled
                        ? Colors.white.withValues(alpha: 0.9)
                        : AppColors.textSecondary.withValues(alpha: 0.4),
                    size: 20,
                  ),
                ),
                title: Text(
                  'Снег во время просмотра аниме',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: winter.isSnowfallEnabled
                        ? null
                        : AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
                subtitle: Text(
                  'Показывать падающий снег поверх видеоплеера',
                  style: TextStyle(
                    color: winter.isSnowfallEnabled
                        ? AppColors.textSecondary
                        : AppColors.textSecondary.withValues(alpha: 0.45),
                    fontSize: 12,
                  ),
                ),
                value: winter.isSnowInPlayerEnabled,
                onChanged: winter.isSnowfallEnabled
                    ? (val) {
                        HapticFeedback.lightImpact();
                        winter.setSnowInPlayer(val);
                      }
                    : null,
              ),
              _buildDivider(),

              // 3. Новогодний маскот Пай-тян
              SwitchListTile(
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF806D).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.celebration_rounded, color: Color(0xFFFF806D), size: 20),
                ),
                title: const Text(
                  'Новогодняя Пай-тян',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: const Text(
                  'Сезонный праздничный скин с шапочкой Санты',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                value: winter.isWinterMascotEnabled,
                onChanged: (val) {
                  HapticFeedback.lightImpact();
                  winter.setWinterMascot(val);
                },
              ),
              _buildDivider(),

              // 4. Кнопки «Примерить зимнюю тему» и «Сбросить тему»
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF35D9D5),
                          side: BorderSide(color: const Color(0xFF35D9D5).withValues(alpha: 0.4)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.remove_red_eye_rounded, size: 16),
                        label: const Text('Примерить тему', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          await winter.enableFullWinterExperience();
                          if (context.mounted) {
                            final preset = ThemePreset.all.firstWhere(
                              (p) => p.id == 'winter_2026',
                              orElse: () => ThemePreset.all.first,
                            );
                            context.read<ThemeCubit>().setPreset(preset);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('❄️ Новогодняя тема «Зимняя сказка 2026» активирована!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          'Сбросить тему',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () async {
                          HapticFeedback.lightImpact();
                          await winter.resetToDefault();
                          if (context.mounted) {
                            final defaultPreset = ThemePreset.all.firstWhere(
                              (p) => p.id == 'sunset_orange',
                              orElse: () => ThemePreset.all.first,
                            );
                            context.read<ThemeCubit>().setPreset(defaultPreset);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Оформление сброшено к стандартной теме.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ],
        );
      },
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: Colors.white.withValues(alpha: 0.06),
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Настройки',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, authState) {
            final profile = authState is Authenticated ? authState.profile : UserProfile.guest();
            final isMobile = MediaQuery.sizeOf(context).width < 700;
            bool showSection(String key) =>
                !isMobile || _mobileSectionFilter == 'all' || _mobileSectionFilter == key;

            const filters = [
              ('all', 'Все'),
              ('player', 'Плеер'),
              ('appearance', 'Внешний вид'),
              ('data', 'Данные'),
              ('account', 'Аккаунт'),
            ];

            return Column(
              children: [
                if (isMobile)
                  SizedBox(
                    key: const ValueKey('settings_mobile_filter_bar'),
                    height: 46,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      itemCount: filters.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final (key, label) = filters[index];
                        final selected = _mobileSectionFilter == key;
                        return ChoiceChip(
                          key: ValueKey('settings_filter_$key'),
                          label: Text(label),
                          selected: selected,
                          onSelected: (_) => setState(() => _mobileSectionFilter = key),
                          selectedColor: themePrimary.withValues(alpha: 0.22),
                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                          side: BorderSide(
                            color: selected
                                ? themePrimary.withValues(alpha: 0.65)
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : AppColors.textSecondary,
                            fontSize: 12.5,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      },
                    ),
                  ),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      if (showSection('appearance')) ...[
                        // 0. Новогодняя зимняя сказка 2026
                        _buildWinterSection(context, themePrimary),

                        // 1. Секция "Внешний вид"
                        _buildSectionHeader('ВНЕШНИЙ ВИД'),
                _buildCard([
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.palette_outlined, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Цветовое оформление',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Темы приложения и акцентные оттенки',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () => ThemeSelectorSheet.show(context),
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.auto_awesome_outlined, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Эффекты жидкого стекла',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Полупрозрачные панели и мягкое размытие',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    value: _liquidGlassEffects,
                    activeThumbColor: themePrimary,
                    onChanged: (val) {
                      setState(() => _liquidGlassEffects = val);
                      _saveBool('settings_liquid_glass', val);
                      DevicePerformanceService.instance.setLiquidGlassBlurEnabled(val, persist: true);
                    },
                  ),
                  _buildDivider(),
                  ListenableBuilder(
                    listenable: PresenceService.instance,
                    builder: (context, _) {
                      final isIncognito = PresenceService.instance.isIncognito;
                      return SwitchListTile(
                        key: const ValueKey('settings_incognito_switch'),
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isIncognito
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_outlined,
                            color: isIncognito ? Colors.white : AppColors.textSecondary,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Режим инкогнито',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: const Text(
                          'Скрыть статус «В сети» и текущее аниме от друзей',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        value: isIncognito,
                        activeThumbColor: themePrimary,
                        onChanged: (val) => PresenceService.instance.setIncognito(val),
                      );
                    },
                  ),
                  _buildDivider(),
                  ListenableBuilder(
                    listenable: DevicePerformanceService.instance,
                    builder: (context, _) {
                      final service = DevicePerformanceService.instance;
                      final tier = service.tier;
                      final ramStr = service.totalRamMb != null ? ' (${service.totalRamMb} МБ ОЗУ)' : '';
                      final cacheMb = PaintingBinding.instance.imageCache.maximumSizeBytes >> 20;

                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: themePrimary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.speed_rounded, color: themePrimary, size: 20),
                        ),
                        title: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(
                                text: 'Режим производительности: ',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              TextSpan(
                                text: tier.shortLabelRu,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: tier == DeviceTier.low
                                      ? const Color(0xFFFFB74D)
                                      : (tier == DeviceTier.mid ? Colors.lightBlueAccent : const Color(0xFF66BB6A)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        subtitle: Text(
                          'Авто-оптимизация рендеринга$ramStr. Буфер постеров: $cacheMb МБ.',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            await service.resetToRecommendedDefaults();
                            setState(() {
                              _liquidGlassEffects = service.isLiquidGlassBlurEnabled;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Сброшено на рекомендуемые настройки (${tier.shortLabelRu})'),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: AppColors.surfaceElevated,
                                ),
                              );
                            }
                          },
                          child: const Text('Сбросить', style: TextStyle(fontSize: 12)),
                        ),
                      );
                    },
                  ),
                ]),
                      ],

                      if (showSection('data')) ...[
                        // 2. Секция "Данные и синхронизация"
                        _buildSectionHeader('ДАННЫЕ И СИНХРОНИЗАЦИЯ'),
                _buildCard([
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.download_for_offline_rounded, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Менеджер офлайн-загрузок',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Управление скачанными сериями и локальным хранилищем',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () => context.push('/downloads'),
                  ),
                  _buildDivider(),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF806D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFF806D), size: 20),
                    ),
                    title: const Text(
                      'SyncPai Wrapped 2026',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Персональные годовые итоги просмотра аниме в стиле Spotify',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () => context.push('/wrapped'),
                  ),
                  _buildDivider(),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.cloud_download_outlined, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Импорт из Anixart по ID',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Синхронизация по цифровому ID или логину',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () => _showOnlineImportDialog(context, profile.id),
                  ),
                  _buildDivider(),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.folder_open_outlined, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Импорт из файла',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Загрузка резервной копии .csv / .json / .txt',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () => _pickAndImportAnixart(context, profile.id),
                  ),
                  _buildDivider(),
                  ListTile(
                    key: const ValueKey('settings_clear_cache_data_tile'),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF5350).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF5350), size: 20),
                    ),
                    title: const Text(
                      'Очистка кэша и данных',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Кэш картинок и плеера, история просмотров и списки закладок',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () => _showClearCacheAndDataSheet(context, profile.id),
                  ),
                ]),
                      ],

                      if (showSection('player')) ...[
                        // 3. Секция "Плеер и система"
                        _buildSectionHeader('НАСТРОЙКИ ПЛЕЕРА И СИСТЕМЫ'),
                _buildCard([
                  _buildPlayerHudPresetBlock(context, themePrimary),
                  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) ...[
                    _buildDivider(),
                    ListTile(
                      key: const ValueKey('settings_player_onboarding_tile'),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: themePrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.touch_app_rounded, color: themePrimary, size: 20),
                      ),
                      title: const Text(
                        'Обучение и жесты плеера',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Посмотреть жесты и подсказки интерфейса',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (getIt.isRegistered<SettingsCubit>()) {
                          getIt<SettingsCubit>().resetPlayerOnboarding();
                        }
                        showGeneralDialog<void>(
                          context: context,
                          barrierDismissible: true,
                          barrierLabel: 'Обучение плеера',
                          barrierColor: Colors.transparent,
                          pageBuilder: (dialogCtx, _, __) => Material(
                            color: Colors.transparent,
                            child: PlayerOnboardingOverlay(
                              onDismiss: () {
                                if (getIt.isRegistered<SettingsCubit>()) {
                                  getIt<SettingsCubit>().completePlayerOnboarding();
                                }
                                Navigator.of(dialogCtx).pop();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  _buildDivider(),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.hd_outlined, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Качество видео',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Качество по умолчанию при старте серии',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: DropdownButton<String>(
                      value: _defaultQuality,
                      dropdownColor: AppColors.surfaceElevated,
                      underline: const SizedBox.shrink(),
                      style: TextStyle(
                        color: themePrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      items: const [
                        DropdownMenuItem(value: '1080p FHD', child: Text('1080p FHD')),
                        DropdownMenuItem(value: '720p HD', child: Text('720p HD')),
                        DropdownMenuItem(value: '480p SD', child: Text('480p SD')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _defaultQuality = val);
                          _saveString('settings_default_quality', val);
                          if (getIt.isRegistered<SettingsCubit>()) {
                            getIt<SettingsCubit>().setDefaultQuality(val);
                          }
                        }
                      },
                    ),
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.fast_forward_outlined, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Авто-пропуск опенингов',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Автоматический скип заставок по таймкодам',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    value: _autoSkipOpenings,
                    activeThumbColor: themePrimary,
                    onChanged: (val) {
                      setState(() => _autoSkipOpenings = val);
                      _saveBool('settings_auto_skip_openings', val);
                      if (getIt.isRegistered<SettingsCubit>()) {
                        getIt<SettingsCubit>().setAutoSkipOpenings(val);
                      }
                    },
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.pause_circle_outline_rounded, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Авто-пауза при уходе друга',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Останавливать воспроизведение в совместной комнате',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    value: _autoPauseOnLeave,
                    activeThumbColor: themePrimary,
                    onChanged: (val) {
                      setState(() => _autoPauseOnLeave = val);
                      _saveBool('settings_auto_pause_on_leave', val);
                      if (getIt.isRegistered<SettingsCubit>()) {
                        getIt<SettingsCubit>().setAutoPauseOnLeave(val);
                      }
                    },
                  ),
                  _buildDivider(),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.shield_outlined, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Умная ретрансляция (Анти-блокировка)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      SmartMirrorInterceptor.isAntiBlockEnabled
                          ? 'DoH Cloudflare 1.1.1.1 и авто-ротация зеркал'
                          : 'Прямое подключение к серверам',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    value: SmartMirrorInterceptor.isAntiBlockEnabled,
                    activeThumbColor: themePrimary,
                    onChanged: (val) {
                      setState(() => SmartMirrorInterceptor.isAntiBlockEnabled = val);
                    },
                  ),
                  if (Platform.isWindows) ...[
                    _buildDivider(),
                    ListenableBuilder(
                      listenable: DiscordRpcService.instance,
                      builder: (context, _) {
                        return SwitchListTile(
                          key: const ValueKey('settings_discord_rpc_switch'),
                          secondary: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5865F2).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.sports_esports_rounded,
                              color: Color(0xFF5865F2),
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Discord Rich Presence',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: const Text(
                            'Показывать текущее аниме, серию и комнату в статусе Discord',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                          value: DiscordRpcService.instance.isEnabled,
                          onChanged: (val) {
                            HapticFeedback.lightImpact();
                            DiscordRpcService.instance.setEnabled(val);
                          },
                        );
                      },
                    ),
                  ],
                ]),
                      ],

                      if (showSection('account')) ...[
                        // 4. Секция "Аккаунт"
                        _buildSectionHeader('АККАУНТ'),
                _buildCard([
                  if (!profile.isAnonymous) ...[
                    ListTile(
                      leading: AppAvatar(
                        avatarUrl: profile.avatarUrl,
                        username: profile.username,
                        size: 40,
                      ),
                      title: Text(
                        '${profile.username} ${profile.tag}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: Text(
                        profile.provider == 'google' || (profile.email?.contains('@gmail.com') ?? false)
                            ? 'Синхронизировано с Google (${profile.email ?? "активно"})'
                            : (profile.email ?? 'Синхронизация активна'),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.check_circle_rounded, color: AppColors.syncActive, size: 20),
                    ),
                    _buildDivider(),
                    TelegramLinkTile(
                      profile: profile,
                      themePrimary: themePrimary,
                    ),
                    _buildDivider(),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.syncError.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.logout_rounded, color: AppColors.syncError, size: 20),
                      ),
                      title: const Text(
                        'Выйти из аккаунта',
                        style: TextStyle(
                          color: AppColors.syncError,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: const Text(
                        'Вернуться в гостевой режим',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                      onTap: () => _confirmSignOut(context),
                    ),
                  ] else ...[
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.cloud_sync_rounded, color: Color(0xFF4285F4), size: 20),
                      ),
                      title: const Text(
                        'Войти через Google',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Мгновенная облачная синхронизация истории и списков',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                      onTap: () => AuthModalSheet.show(context, profile),
                    ),
                    _buildDivider(),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: themePrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.login_rounded, color: themePrimary, size: 20),
                      ),
                      title: const Text(
                        'Войти или зарегистрироваться',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Вход по Email, Google, сохранение списков и кастомизации',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                      onTap: () => AuthModalSheet.show(context, profile),
                    ),
                  ],
                ]),
                      ],

                      if (showSection('appearance')) ...[
                        // 5. Секция "SyncPai Mascot" (Mascot Gallery)
                        _buildSectionHeader('МАСКОТ ПРИЛОЖЕНИЯ'),
                _buildCard([
                  ListTile(
                    key: const ValueKey('settings_mascot_gallery_tile'),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.pets_rounded, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Галерея маскота Пай-тян',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      '35 эмоций и сезонных образов',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: () => _showMascotGallerySheet(context),
                  ),
                ]),
                      ],

                      if (showSection('account')) ...[
                        // 6. Секция "Обновления и версия"
                        _buildSectionHeader('О ПРИЛОЖЕНИИ'),
                _buildCard([
                  ListTile(
                    key: const ValueKey('settings_check_updates_tile'),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: themePrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.system_update_rounded, color: themePrimary, size: 20),
                    ),
                    title: const Text(
                      'Проверить обновления',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    subtitle: Text(
                      'SyncPai v$_appVersion',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: _isCheckingUpdates
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                    onTap: _isCheckingUpdates
                        ? null
                        : () async {
                            setState(() => _isCheckingUpdates = true);
                            try {
                              await AppUpdaterService.instance.checkForUpdates(
                                context: context,
                                manual: true,
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _isCheckingUpdates = false);
                              }
                            }
                          },
                  ),
                  _buildDivider(),
                  ListTile(
                    key: const ValueKey('settings_bug_report_tile'),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.bug_report_rounded,
                        color: Color(0xFF00E676),
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      'Нашли баг? Получите бейдж «Кодинг-хакер»',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Отправить репорт в @syncpai_bot (v$_appVersion • ${Platform.isWindows ? 'Windows' : 'Android'})',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded, color: AppColors.textSecondary, size: 18),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      final rawCode = profile.friendCode?.trim();
                      final token = (rawCode != null && rawCode.isNotEmpty)
                          ? rawCode
                          : profile.id;
                      final uri = Uri.parse(
                        'https://t.me/syncpai_bot?start=bug_${Uri.encodeComponent(token)}',
                      );
                      launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                  ),
                ]),

                const SizedBox(height: 18),
                      ],

                // Ненавязчивая строка поддержки в самом низу настроек над версией приложения
                _buildCard([
                  ListTile(
                    key: const ValueKey('settings_open_support_tile'),
                    dense: true,
                    leading: Icon(
                      Icons.favorite_outline_rounded,
                      color: AppColors.textSecondary,
                      size: 19,
                    ),
                    title: const Text(
                      'Поддержать развитие SyncPai',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    onTap: () => context.push('/support'),
                  ),
                ]),

                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'SyncPai v$_appVersion',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
