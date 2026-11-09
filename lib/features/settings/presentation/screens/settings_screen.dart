import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/network/smart_mirror_interceptor.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/widgets/theme_selector_sheet.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../anime_lists/data/datasources/anixart_csv_parser.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../anime_lists/presentation/widgets/import_progress_dialog.dart';
import '../../../anime_lists/presentation/widgets/import_status_selector_dialog.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoSkipOpenings = true;
  bool _autoPauseOnLeave = true;
  bool _liquidGlassEffects = true;
  String _defaultQuality = '1080p FHD';
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = getIt.isRegistered<SharedPreferences>()
        ? getIt<SharedPreferences>()
        : await SharedPreferences.getInstance();
    if (_prefs != null && mounted) {
      setState(() {
        _autoSkipOpenings = _prefs!.getBool('settings_auto_skip_openings') ?? true;
        _autoPauseOnLeave = _prefs!.getBool('settings_auto_pause_on_leave') ?? true;
        _liquidGlassEffects = _prefs!.getBool('settings_liquid_glass') ?? true;
        _defaultQuality = _prefs!.getString('settings_default_quality') ?? '1080p FHD';
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
          final totalCount = res?.totalParsed ?? detectedCount;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Успешно импортировано $totalCount тайтлов! Ваша коллекция синхронизирована.',
              ),
              backgroundColor: AppColors.syncActive,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
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
                                    localError = e.toString().replaceFirst('Exception: ', '');
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

  void _clearCache(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Кэш плеера и временные файлы очищены!',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFF242730),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
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
                      'Блюр BackdropFilter и блики интерфейса',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    value: _liquidGlassEffects,
                    activeThumbColor: themePrimary,
                    onChanged: (val) {
                      setState(() => _liquidGlassEffects = val);
                      _saveBool('settings_liquid_glass', val);
                    },
                  ),
                ]),

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
                ]),

                // 3. Секция "Плеер и система"
                _buildSectionHeader('НАСТРОЙКИ ПЛЕЕРА И СИСТЕМЫ'),
                _buildCard([
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
                  _buildDivider(),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_sweep_outlined, color: AppColors.textSecondary, size: 20),
                    ),
                    title: const Text(
                      'Очистить кэш плеера и историю',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Освободить временную память устройства',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    onTap: () => _clearCache(context),
                  ),
                ]),

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
                        profile.username,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: Text(
                        profile.email ?? 'Синхронизация активна',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.check_circle_rounded, color: AppColors.syncActive, size: 20),
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
                          color: themePrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.login_rounded, color: themePrimary, size: 20),
                      ),
                      title: const Text(
                        'Войти через Google',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Синхронизировать историю, списки и витрину профиля',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                      onTap: () => context.read<AuthCubit>().signInWithGoogle(),
                    ),
                  ],
                ]),

                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }
}
