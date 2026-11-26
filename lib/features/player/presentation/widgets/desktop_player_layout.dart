import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../app/di/injection.dart';
import '../../../../core/network/image_cors_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/desktop_title_bar.dart';
import '../../../anime_lists/domain/entities/user_anime_entry.dart';
import '../../../anime_lists/presentation/cubit/anime_list_cubit.dart';
import '../../../anime_lists/presentation/cubit/anime_list_state.dart';
import '../../../catalog/domain/entities/anime_title.dart';
import '../../../kodik/presentation/cubit/kodik_cubit.dart';
import '../../../kodik/presentation/widgets/voiceover_selector_sheet.dart';
import '../../../sync_room/domain/entities/sync_protocol.dart';
import '../../../sync_room/presentation/widgets/in_room_anime_picker_sheet.dart';
import '../../../sync_room/presentation/widgets/sync_room_lobby_sheet.dart';
import '../../domain/entities/player_quality.dart';
import '../../services/global_mini_player_service.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import 'floating_pai_chan_reactions_overlay.dart';
import 'player_progress_bar.dart';

/// Десктопный интерфейс видеоплеера в стиле YouTube / Crunchyroll Web:
/// - Авто-скрытие контролов и курсора мыши при бездействии (3 секунды)
/// - Горячие клавиши (Space, Стрелки, F, M, Escape) с оверлеями обратной связи
/// - Двухколоночный театральный режим (74% видео 16:9 + 26% сайдбар эпизодов)
/// - Нижняя панель управления с толстым интерактивным таймлайном, слайдером громкости,
///   выбором качества, скорости, кнопками «Кинотеатр» и «На весь экран»
class DesktopPlayerLayout extends StatefulWidget {
  final PlayerCubit cubit;
  final PlayerState state;
  final VideoController videoController;
  final VoidCallback onBack;
  final VoidCallback onSaveProgress;
  final Widget? skipOverlay;
  final Widget? seasonFinaleOverlay;

  const DesktopPlayerLayout({
    super.key,
    required this.cubit,
    required this.state,
    required this.videoController,
    required this.onBack,
    required this.onSaveProgress,
    this.skipOverlay,
    this.seasonFinaleOverlay,
  });

  @override
  State<DesktopPlayerLayout> createState() => _DesktopPlayerLayoutState();
}

class _DesktopPlayerLayoutState extends State<DesktopPlayerLayout> {
  final FocusNode _focusNode = FocusNode();
  final FocusNode _chatInputFocusNode = FocusNode();
  final GlobalKey _desktopVideoKey = GlobalKey(debugLabel: 'PersistentDesktopVideoSurface');
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _selectedSidebarTab = 0; // 0 = Чат комнаты, 1 = Эпизоды
  Timer? _hideControlsTimer;
  bool _areControlsVisible = true;
  bool _isCursorVisible = true;
  bool _isVolumeSliderHovered = false;
  bool _isHoveringControls = false;
  bool _isDisposed = false;

  // Режимы экрана
  bool _isFullScreen = false;
  bool _isTheaterMode = false; // Скрывает сайдбар серий, расширяя видео

  // Оверлеи визуальной обратной связи клавиатурных шорткатов
  IconData? _flashIcon;
  String? _flashLabel;
  bool _isFlashBlue = false;
  Timer? _flashTimer;

  // Умная обработка клавиши Space (Tap < 250ms = Play/Pause, Hold >= 250ms = 2x Speed)
  DateTime? _spaceKeyDownAt;
  Timer? _spaceHoldTimer;
  bool _isSpaceHold2xActive = false;

  // Предыдущая громкость для Mute/Unmute
  double _savedVolumeBeforeMute = 100.0;

  @override
  void initState() {
    super.initState();
    _startHideTimer();
    _checkNativeFullScreen();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed && !_chatInputFocusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant DesktopPlayerLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.chatMessages.length > oldWidget.state.chatMessages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed && _chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  Future<void> _checkNativeFullScreen() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        final isFs = await windowManager.isFullScreen();
        if (mounted && !_isDisposed) {
          final binding = WidgetsBinding.instance;
          if (binding.schedulerPhase != SchedulerPhase.idle) {
            binding.addPostFrameCallback((_) {
              if (mounted && !_isDisposed) {
                setState(() {
                  _isFullScreen = isFs || DesktopTitleBar.isFullScreenNotifier.value;
                });
              }
            });
          } else {
            setState(() {
              _isFullScreen = isFs || DesktopTitleBar.isFullScreenNotifier.value;
            });
          }
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _hideControlsTimer?.cancel();
    _flashTimer?.cancel();
    _spaceHoldTimer?.cancel();
    _focusNode.dispose();
    _chatInputFocusNode.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    if (_isFullScreen) {
      Future.microtask(() {
        DesktopTitleBar.isFullScreenNotifier.value = false;
      });
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        try {
          windowManager.setFullScreen(false).catchError((_) {});
          defaultExitNativeFullscreen().catchError((_) {});
        } catch (_) {}
      }
    }
    super.dispose();
  }

  void _triggerFlash({required IconData icon, String? label, bool isBlue = false}) {
    if (_isDisposed) return;
    _flashTimer?.cancel();
    setState(() {
      _flashIcon = icon;
      _flashLabel = label;
      _isFlashBlue = isBlue;
    });
    _flashTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted && !_isDisposed) {
        setState(() {
          _flashIcon = null;
          _flashLabel = null;
          _isFlashBlue = false;
        });
      }
    });
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && !_isDisposed && widget.state.isPlaying && !_isVolumeSliderHovered && !_isHoveringControls) {
        setState(() {
          _areControlsVisible = false;
          _isCursorVisible = false;
        });
      }
    });
  }

  void _showControls() {
    if (_isDisposed) return;
    if (!_areControlsVisible || !_isCursorVisible) {
      setState(() {
        _areControlsVisible = true;
        _isCursorVisible = true;
      });
    }
    _startHideTimer();
  }

  void _onHover(PointerHoverEvent event) {
    _showControls();
  }

  void _onExit(PointerExitEvent event) {
    if (widget.state.isPlaying && !_isHoveringControls) {
      setState(() {
        _areControlsVisible = false;
        _isCursorVisible = true;
      });
    }
  }

  Future<void> _setFullScreen(bool next) async {
    if (_isFullScreen == next) return;
    setState(() {
      _isFullScreen = next;
    });
    DesktopTitleBar.isFullScreenNotifier.value = next;

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        await windowManager.setFullScreen(next);
      } catch (_) {}
      try {
        if (next) {
          await defaultEnterNativeFullscreen();
        } else {
          await defaultExitNativeFullscreen();
        }
      } catch (_) {}
    }

    _triggerFlash(
      icon: next ? Icons.fullscreen_rounded : Icons.fullscreen_exit_rounded,
      label: next ? 'Полноэкранный режим' : 'Оконный режим',
    );
    _showControls();
  }

  Future<void> _toggleFullScreen() async {
    await _setFullScreen(!_isFullScreen);
  }

  void _toggleMute() {
    final curVol = widget.state.volume;
    if (curVol > 0.01) {
      _savedVolumeBeforeMute = curVol;
      widget.cubit.setVolume(0.0);
      _triggerFlash(icon: Icons.volume_off_rounded, label: 'Звук выключен');
    } else {
      final restore = _savedVolumeBeforeMute > 0.05 ? _savedVolumeBeforeMute : 100.0;
      widget.cubit.setVolume(restore);
      _triggerFlash(
        icon: Icons.volume_up_rounded,
        label: '${restore.toInt()}%',
      );
    }
  }

  void _minimizeToMiniPlayer() {
    widget.onSaveProgress();
    GlobalMiniPlayerService.instance.minimize(
      cubit: widget.cubit,
      videoController: widget.videoController,
      onSaveProgress: widget.onSaveProgress,
    );
    _triggerFlash(
      icon: Icons.picture_in_picture_alt_rounded,
      label: 'Плавающее окно (PiP)',
    );
    widget.onBack();
  }

  void _showHotkeysDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14161F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            Icon(Icons.keyboard_outlined, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            const Text(
              'Горячие клавиши плеера',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHotkeyRow('Пробел (Space)', 'Пауза / Старт (удержание: 2x ускорение)'),
                _buildHotkeyRow('← / →', 'Перемотка на ±5 секунд'),
                _buildHotkeyRow('↑ / ↓', 'Громкость ±5%'),
                _buildHotkeyRow('F', 'Полноэкранный режим'),
                _buildHotkeyRow('M', 'Включить / Выключить звук'),
                _buildHotkeyRow('P', 'Плавающее окно (Картинка в картинке)'),
                _buildHotkeyRow('N', 'Следующая серия'),
                _buildHotkeyRow('S', 'Пропуск опенинга / эндинга'),
                _buildHotkeyRow('T', 'Театральный режим (скрыть сайдбар)'),
                _buildHotkeyRow('0 - 9', 'Перейти на 0% - 90% таймлайна'),
                _buildHotkeyRow('Esc', 'Выход из полноэкранного режима / Назад'),
                _buildHotkeyRow('? / H', 'Справка по горячим клавишам'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Понятно', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildHotkeyRow(String keyName, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Text(
              keyName,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleDesktopKeyEvent(FocusNode node, KeyEvent event) {
    // Если поле ввода сообщений активно, горячие клавиши плеера не перехватывают ввод
    if (_chatInputFocusNode.hasFocus) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
        _chatInputFocusNode.unfocus();
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Умная обработка клавиши Space:
    // Tap (< 250ms) = Play / Pause + Broadcast в комнату
    // Hold (>= 250ms) = 2x Speed (player.setRate(2.0)) + плашка «2x ⏩ Ускорение», возврат 1.0x при KeyUpEvent
    if (key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) {
        if (_spaceKeyDownAt == null) {
          _spaceKeyDownAt = DateTime.now();
          _spaceHoldTimer?.cancel();
          _spaceHoldTimer = Timer(const Duration(milliseconds: 250), () {
            if (mounted && !_isDisposed && _spaceKeyDownAt != null) {
              setState(() {
                _isSpaceHold2xActive = true;
              });
              widget.cubit.start2xFastForward();
            }
          });
        }
        return KeyEventResult.handled;
      }

      if (event is KeyRepeatEvent) {
        if (_spaceKeyDownAt != null && !_isSpaceHold2xActive) {
          final elapsedMs = DateTime.now().difference(_spaceKeyDownAt!).inMilliseconds;
          if (elapsedMs >= 250) {
            _spaceHoldTimer?.cancel();
            setState(() {
              _isSpaceHold2xActive = true;
            });
            widget.cubit.start2xFastForward();
          }
        }
        return KeyEventResult.handled;
      }

      if (event is KeyUpEvent) {
        _spaceHoldTimer?.cancel();
        _spaceHoldTimer = null;
        final downAt = _spaceKeyDownAt;
        _spaceKeyDownAt = null;

        if (_isSpaceHold2xActive || widget.state.is2xFastForwarding) {
          setState(() {
            _isSpaceHold2xActive = false;
          });
          widget.cubit.stop2xFastForward();
        } else if (downAt != null) {
          final willPlay = !widget.state.isPlaying;
          widget.cubit.togglePlayPause();
          _triggerFlash(
            icon: willPlay ? Icons.play_arrow_rounded : Icons.pause_rounded,
          );
        }
        return KeyEventResult.handled;
      }
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      // Стрелка вправо: +5 сек
      if (key == LogicalKeyboardKey.arrowRight) {
        widget.cubit.seekRelative(5);
        _triggerFlash(icon: Icons.forward_5_rounded, label: '+5 сек');
        return KeyEventResult.handled;
      }

      // Стрелка влево: -5 сек
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.cubit.seekRelative(-5);
        _triggerFlash(icon: Icons.replay_5_rounded, label: '-5 сек');
        return KeyEventResult.handled;
      }

      // Стрелка вверх: громкость +5% (с голубым HUD громкости)
      if (key == LogicalKeyboardKey.arrowUp) {
        final newVol = (widget.state.volume + 5.0).clamp(0.0, 100.0);
        widget.cubit.setVolume(newVol);
        _triggerFlash(
          icon: newVol > 50 ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          label: '${newVol.toInt()}%',
          isBlue: true,
        );
        return KeyEventResult.handled;
      }

      // Стрелка вниз: громкость -5% (с голубым HUD громкости)
      if (key == LogicalKeyboardKey.arrowDown) {
        final newVol = (widget.state.volume - 5.0).clamp(0.0, 100.0);
        widget.cubit.setVolume(newVol);
        _triggerFlash(
          icon: newVol == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
          label: '${newVol.toInt()}%',
          isBlue: true,
        );
        return KeyEventResult.handled;
      }
    }

    if (event is KeyDownEvent) {
      // KeyF: Полноэкранный режим
      if (key == LogicalKeyboardKey.keyF) {
        _toggleFullScreen();
        return KeyEventResult.handled;
      }

      // KeyM: Mute / Unmute
      if (key == LogicalKeyboardKey.keyM) {
        _toggleMute();
        return KeyEventResult.handled;
      }

      // KeyP: Плавающее окно (Picture-in-Picture / Mini-player)
      if (key == LogicalKeyboardKey.keyP) {
        _minimizeToMiniPlayer();
        return KeyEventResult.handled;
      }

      // KeyN: Следующая серия
      if (key == LogicalKeyboardKey.keyN) {
        final allEpisodes = widget.state.title.episodes;
        final curIdx = allEpisodes.indexWhere((e) => e.episode == widget.state.episode.episode);
        if (curIdx >= 0 && curIdx < allEpisodes.length - 1) {
          final nextEp = allEpisodes[curIdx + 1];
          widget.cubit.switchEpisode(nextEp);
          _triggerFlash(
            icon: Icons.skip_next_rounded,
            label: 'Серия ${nextEp.episode}',
          );
        } else {
          _triggerFlash(
            icon: Icons.skip_next_rounded,
            label: 'Последняя серия',
          );
        }
        return KeyEventResult.handled;
      }

      // KeyS: Пропуск опенинга / эндинга
      if (key == LogicalKeyboardKey.keyS) {
        widget.cubit.skipOpening();
        _triggerFlash(
          icon: Icons.fast_forward_rounded,
          label: 'Пропуск опенинга',
        );
        return KeyEventResult.handled;
      }

      // KeyT: Театральный режим
      if (key == LogicalKeyboardKey.keyT) {
        setState(() => _isTheaterMode = !_isTheaterMode);
        _triggerFlash(
          icon: _isTheaterMode ? Icons.crop_16_9_rounded : Icons.crop_landscape_rounded,
          label: _isTheaterMode ? 'Режим Кинотеатр' : 'Стандартный вид',
        );
        return KeyEventResult.handled;
      }

      // KeyH или Slash / Question: Подсказка по горячим клавишам
      if (key == LogicalKeyboardKey.keyH ||
          key == LogicalKeyboardKey.slash ||
          key == LogicalKeyboardKey.question) {
        _showHotkeysDialog(context);
        return KeyEventResult.handled;
      }

      // Цифры 0-9: Быстрый переход по таймлайну (0% - 90%)
      if (key.keyId >= LogicalKeyboardKey.digit0.keyId &&
          key.keyId <= LogicalKeyboardKey.digit9.keyId) {
        final digit = key.keyId - LogicalKeyboardKey.digit0.keyId;
        final fraction = digit * 0.1;
        final target = widget.state.duration * fraction;
        widget.cubit.seek(target);
        _triggerFlash(
          icon: Icons.timelapse_rounded,
          label: '${digit * 10}%',
        );
        return KeyEventResult.handled;
      }

      // Escape: Выход из фуллскрина или выход из плеера
      if (key == LogicalKeyboardKey.escape) {
        if (_isFullScreen) {
          _setFullScreen(false);
        } else {
          widget.onBack();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleDesktopKeyEvent,
      child: MouseRegion(
        cursor: _isCursorVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: _onHover,
        onExit: _onExit,
        child: Container(
          color: const Color(0xFF0A0B0E),
          child: _isFullScreen
              ? _buildVideoSurface(isFullScreen: true)
              : _buildTwoColumnLayout(),
        ),
      ),
    );
  }

  /// Двухколоночный десктопный макет (Театральный режим + Сайдбар эпизодов)
  Widget _buildTwoColumnLayout() {
    final showSidebar = !_isTheaterMode;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Левая колонка: 74% ширины (или 100% в режиме Кинотеатр)
        Expanded(
          flex: showSidebar ? 74 : 100,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Шапка с кнопкой «Назад» и бейджем текущего режима
                _buildDesktopTopBar(),
                const SizedBox(height: 14),

                // Видеоконтейнер строго 16:9 со скруглением и мягкой кинематографичной тенью
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: _buildVideoSurface(isFullScreen: false),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Метаданные под плеером: название аниме, номер серии, переключатель озвучки, закладки и совместный просмотр
                _buildMetadataPanel(),
              ],
            ),
          ),
        ),

        // Тонкий вертикальный разделитель
        if (showSidebar)
          Container(
            width: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),

        // Правая колонка: 26% ширины — стеклянный сайдбар (режим Solo: эпизоды; режим Комнаты: Чат + Эпизоды)
        if (showSidebar)
          Expanded(
            flex: 26,
            child: widget.state.isSyncRoom ? _buildRoomSidebar() : _buildEpisodesSidebar(),
          ),
      ],
    );
  }

  /// Верхняя плашка десктопа с кнопкой Назад и хлебными крошками
  Widget _buildDesktopTopBar() {
    final title = widget.state.title;
    final ep = widget.state.episode;

    return Row(
      children: [
        InkWell(
          onTap: widget.onBack,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF1A202E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded, size: 16, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'К тайтлу',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: title.displayTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                TextSpan(
                  text: '  /  Серия ${ep.episode}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.state.isSyncRoom) ...[
          Container(
            key: const ValueKey('desktop_player_role_pill'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: widget.state.isHost
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.state.isHost
                    ? AppColors.primaryLight.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.state.isHost
                      ? Icons.verified_user_rounded
                      : Icons.person_outline_rounded,
                  size: 14,
                  color: widget.state.isHost
                      ? AppColors.primaryLight
                      : Colors.white70,
                ),
                const SizedBox(width: 5),
                Text(
                  widget.state.isHost ? 'Хост комнаты' : 'Участник',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: widget.state.isHost
                        ? AppColors.primaryLight
                        : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('desktop_player_switch_anime_btn'),
            onPressed: () {
              InRoomAnimePickerSheet.show(
                context,
                roomCode: widget.state.roomCode,
                currentTitle: widget.state.title,
                onAnimeSelected: (newTitle) =>
                    widget.cubit.switchAnimeInRoom(newTitle),
              );
            },
            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
            label: const Text(
              'Сменить аниме',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const ValueKey('desktop_player_minimize_room_btn'),
            onPressed: widget.onBack,
            icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 15),
            label: const Text(
              'Свернуть',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryLight,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 14),
                const SizedBox(width: 6),
                Text(
                  widget.state.roomCode ?? 'Sync Room',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Полотно видеоплеера с кликами мыши, оверлеями обратной связи и нижней панелью контролов
  Widget _buildVideoSurface({required bool isFullScreen}) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Полотно libmpv видео на черном фоне (в RepaintBoundary для изоляции 60 FPS рендеринга от оверлея управления)
          // Защищено LayoutBuilder от нулевых размеров (0x0 D3D surface) и снабжено постоянным GlobalKey
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
                  return const SizedBox.shrink();
                }
                return RepaintBoundary(
                  child: Center(
                    child: Video(
                      key: _desktopVideoKey,
                      controller: widget.videoController,
                      controls: NoVideoControls,
                      fit: BoxFit.contain,
                      fill: Colors.black,
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. Прозрачный слой захвата мыши, колесика и контекстного меню поверх нативного окна Video
          Positioned.fill(
            child: Listener(
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  _showControls();
                  // Прокрутка колесика мыши: регулировка громкости (шаг 5%)
                  final delta = pointerSignal.scrollDelta.dy;
                  if (delta != 0) {
                    final currentVol = widget.state.volume;
                    final step = delta < 0 ? 5.0 : -5.0; // Вверх - громче, вниз - тише
                    final newVol = (currentVol + step).clamp(0.0, 100.0);
                    widget.cubit.setVolume(newVol);
                    _triggerFlash(
                      icon: newVol == 0
                          ? Icons.volume_off_rounded
                          : (newVol < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                      label: '${newVol.toInt()}%',
                    );
                  }
                }
              },
              child: MouseRegion(
                opaque: true,
                cursor: _isCursorVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
                onHover: (_) => _showControls(),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_chatInputFocusNode.hasFocus) {
                      _chatInputFocusNode.unfocus();
                    }
                    _focusNode.requestFocus();
                    final willPlay = !widget.state.isPlaying;
                    widget.cubit.togglePlayPause();
                    _triggerFlash(
                      icon: willPlay ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    );
                  },
                  onDoubleTap: () {
                    if (_chatInputFocusNode.hasFocus) {
                      _chatInputFocusNode.unfocus();
                    }
                    _focusNode.requestFocus();
                    _toggleFullScreen();
                  },
                  onSecondaryTap: () {
                    // Правый клик мыши — переключение Play / Pause либо показ контролов
                    if (_chatInputFocusNode.hasFocus) {
                      _chatInputFocusNode.unfocus();
                    }
                    _focusNode.requestFocus();
                    _showControls();
                    widget.cubit.togglePlayPause();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),

          // 2.5. Слой парящих стикер-реакций Пай-чан поверх видео (Windowed + Fullscreen)
          if (widget.state.isSyncRoom || widget.state.activeReactions.isNotEmpty)
            FloatingPaiChanReactionsOverlay(
              reactions: widget.state.activeReactions,
            ),

          // 2.6. Верхняя центральная HUD-плашка «2x ⏩ Ускорение» при зажатии Space
          if (_isSpaceHold2xActive || widget.state.is2xFastForwarding)
            Positioned(
              top: isFullScreen ? 68 : 16,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    key: const ValueKey('desktop_hold_space_2x_pill'),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141824).withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      '2x ⏩ Ускорение',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 3. Индикатор буферизации
          if (widget.state.isBuffering && widget.state.errorMessage == null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
            ),

          // 4. Всплывающий оверлей шортката (Space, Громкость, Перемотка)
          if (_flashIcon != null)
            Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _flashIcon != null ? 1.0 : 0.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  decoration: BoxDecoration(
                    color: _isFlashBlue
                        ? const Color(0xFF0E223D).withValues(alpha: 0.86)
                        : Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isFlashBlue
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _flashIcon,
                        color: _isFlashBlue ? const Color(0xFF38BDF8) : Colors.white,
                        size: 44,
                      ),
                      if (_flashLabel != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _flashLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // 5. Плавающий баннер пропуска опенинга / эндинга
          if (widget.skipOverlay != null) widget.skipOverlay!,

          // 5b. Встроенная карточка финала сезона внутри видеополотна
          if (widget.seasonFinaleOverlay != null) widget.seasonFinaleOverlay!,

          // 6. Нижняя панель управления (Control Bar) в стиле YouTube Web
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _areControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: IgnorePointer(
                ignoring: !_areControlsVisible,
                child: MouseRegion(
                  onEnter: (_) {
                    setState(() => _isHoveringControls = true);
                    _showControls();
                  },
                  onExit: (_) {
                    setState(() => _isHoveringControls = false);
                    _startHideTimer();
                  },
                  child: _buildDesktopControlBar(isFullScreen: isFullScreen),
                ),
              ),
            ),
          ),

          // 7. Информативный верхний бар в Fullscreen (стрелка назад + название аниме и номер серии)
          if (isFullScreen)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _areControlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: !_areControlsVisible,
                  child: MouseRegion(
                    onEnter: (_) {
                      setState(() => _isHoveringControls = true);
                      _showControls();
                    },
                    onExit: (_) {
                      setState(() => _isHoveringControls = false);
                      _startHideTimer();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.80),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 18, 24, 24),
                      child: Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: () => _setFullScreen(false),
                            tooltip: 'Выйти из полноэкранного режима (Esc / F)',
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              '${widget.state.title.displayTitle} • Серия ${widget.state.episode.episode}'
                              '${widget.state.episode.name != null && widget.state.episode.name!.isNotEmpty ? ' — ${widget.state.episode.name}' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Нижний десктопный Control Bar в стиле YouTube Web (единый бар без дублирования таймкодов)
  Widget _buildDesktopControlBar({required bool isFullScreen}) {
    final state = widget.state;
    final allEpisodes = state.title.episodes;
    final curIdx = allEpisodes.indexWhere((e) => e.episode == state.episode.episode);
    final hasNext = curIdx >= 0 && curIdx < allEpisodes.length - 1;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.85),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Первая строка: только одна полоса прогресса (SeekBar) на всю ширину без цифр под ней
          BlocSelector<PlayerCubit, PlayerState, ({Duration pos, Duration dur, Duration buf, bool isBuf})>(
            bloc: widget.cubit,
            selector: (s) => (
              pos: s.position,
              dur: s.duration,
              buf: s.buffer,
              isBuf: s.isBuffering,
            ),
            builder: (context, timing) => PlayerProgressBar(
              position: timing.pos,
              duration: timing.dur,
              buffer: timing.buf,
              onSeek: (pos) => widget.cubit.seek(pos),
              isLocked: state.isSyncRoom && !state.isHost,
              onLockedTap: () {
                widget.cubit.showGuestPlaybackLockedNotice();
                _triggerFlash(
                  icon: Icons.lock_clock_rounded,
                  label: 'Воспроизведением управляет хост',
                );
              },
              opening: widget.cubit.state.effectiveOpening,
              ending: widget.cubit.state.effectiveEnding,
              heatmap: widget.cubit.state.heatmap,
              isBuffering: timing.isBuf,
              showTimestamps: false,
            ),
          ),
          const SizedBox(height: 2),

          // 2. Вторая строка: единый ряд контролов (слева и справа)
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
              // Кнопка Play/Pause (36px)
              IconButton(
                iconSize: 32,
                tooltip: state.isPlaying ? 'Пауза (Space)' : 'Воспроизведение (Space)',
                icon: Icon(
                  state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  if (state.isSyncRoom && !state.isHost) {
                    widget.cubit.requestPauseFromHost();
                    _triggerFlash(
                      icon: Icons.lock_clock_rounded,
                      label: 'Запрос на паузу отправлен хосту',
                    );
                    return;
                  }
                  widget.cubit.togglePlayPause();
                  _triggerFlash(
                    icon: state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  );
                },
              ),

              // Кнопка Следующая серия
              IconButton(
                iconSize: 22,
                tooltip: hasNext ? 'Следующая серия' : 'Последняя серия',
                icon: Icon(
                  Icons.skip_next_rounded,
                  color: hasNext ? Colors.white : Colors.white24,
                ),
                onPressed: hasNext
                    ? () => widget.cubit.switchEpisode(allEpisodes[curIdx + 1])
                    : null,
              ),

              const SizedBox(width: 4),

              // Иконка звука + горизонтальный Slider громкости
              MouseRegion(
                onEnter: (_) => setState(() => _isVolumeSliderHovered = true),
                onExit: (_) => setState(() => _isVolumeSliderHovered = false),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      iconSize: 22,
                      tooltip: 'Звук (M)',
                      icon: Icon(
                        state.volume <= 0.01
                            ? Icons.volume_off_rounded
                            : (state.volume > 50 ? Icons.volume_up_rounded : Icons.volume_down_rounded),
                        color: Colors.white,
                      ),
                      onPressed: _toggleMute,
                    ),
                    if (constraints.maxWidth >= 680)
                      SizedBox(
                        width: 90,
                        child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: const Color(0xFFFF6B4A),
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                          thumbColor: const Color(0xFFFF6B4A),
                        ),
                        child: Slider(
                          value: state.volume.clamp(0.0, 100.0),
                          min: 0.0,
                          max: 100.0,
                          onChanged: (val) => widget.cubit.setVolume(val),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Крупный таймкод 01:58 / 24:00
              BlocSelector<PlayerCubit, PlayerState, ({int curSec, int totalSec})>(
                bloc: widget.cubit,
                selector: (s) => (
                  curSec: s.position.inSeconds,
                  totalSec: s.duration.inSeconds,
                ),
                builder: (context, t) => Text(
                  '${_formatDuration(Duration(seconds: t.curSec))} / ${_formatDuration(Duration(seconds: t.totalSec))}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),

                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),

              // Выбор скорости воспроизведения (1.0x)
              PopupMenuButton<double>(
                tooltip: 'Скорость',
                initialValue: state.playbackRate,
                onSelected: (rate) => widget.cubit.setPlaybackRate(rate),
                color: AppColors.surfaceElevated,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${state.playbackRate.toStringAsFixed(state.playbackRate.truncateToDouble() == state.playbackRate ? 0 : 2)}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                itemBuilder: (ctx) => [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
                    .map(
                      (r) => PopupMenuItem(
                        value: r,
                        child: Text(
                          '${r}x',
                          style: TextStyle(
                            color: state.playbackRate == r ? AppColors.primary : Colors.white,
                            fontWeight: state.playbackRate == r ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),

              const SizedBox(width: 8),

              // Выбор качества (1080p / 720p / 480p)
              PopupMenuButton<PlayerQuality>(
                tooltip: 'Качество видео',
                initialValue: state.selectedQuality,
                onSelected: (q) => widget.cubit.changeQuality(q),
                color: AppColors.surfaceElevated,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _qualityLabel(state.selectedQuality),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                itemBuilder: (ctx) => PlayerQuality.values
                    .map(
                      (q) => PopupMenuItem(
                        value: q,
                        child: Text(
                          _qualityLabel(q),
                          style: TextStyle(
                            color: state.selectedQuality == q ? AppColors.primary : Colors.white,
                            fontWeight: state.selectedQuality == q ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),

              const SizedBox(width: 12),

              // Кнопка «Кинотеатр» (скрывает сайдбар серий)
              if (!isFullScreen) ...[
                IconButton(
                  tooltip: _isTheaterMode ? 'Стандартный вид' : 'Театральный режим',
                  icon: Icon(
                    Icons.crop_16_9_rounded,
                    color: _isTheaterMode ? const Color(0xFFFF6B4A) : Colors.white,
                    size: 21,
                  ),
                  onPressed: () {
                    setState(() {
                      _isTheaterMode = !_isTheaterMode;
                    });
                  },
                ),
                const SizedBox(width: 12),
              ],

              // Кнопка «Плавающее окно (PiP)»
              IconButton(
                tooltip: 'Плавающее окно (P)',
                icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white, size: 20),
                onPressed: _minimizeToMiniPlayer,
              ),

              const SizedBox(width: 12),

              // Кнопка «На весь экран» (F)
              IconButton(
                tooltip: isFullScreen ? 'Выйти из полноэкранного режима (F)' : 'На весь экран (F)',
                icon: Icon(
                  isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: _toggleFullScreen,
              ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }

  String _formatEpisodeSubtitle(int episodeNumber, String? episodeName) {
    final rawName = (episodeName ?? '').trim();
    String? voiceover;
    String cleanSub = rawName;

    // Извлекаем озвучку из суффикса "(AniDUB)" или "• AniDUB"
    final parenMatch = RegExp(r'\(([^)]+)\)\s*$').firstMatch(cleanSub);
    if (parenMatch != null) {
      voiceover = parenMatch.group(1)?.trim();
      cleanSub = cleanSub.substring(0, parenMatch.start).trim();
    } else if (cleanSub.contains('•')) {
      final parts = cleanSub.split('•');
      if (parts.length >= 2) {
        voiceover = parts.last.trim();
        cleanSub = parts.sublist(0, parts.length - 1).join('•').trim();
      }
    }

    // Убираем дублирование вида "Серия 1"
    final epPrefix = RegExp(
      '^серия\\s*$episodeNumber(?:\\s*[-—:])?\\s*',
      caseSensitive: false,
    );
    cleanSub = cleanSub.replaceFirst(epPrefix, '').trim();

    final base = cleanSub.isNotEmpty
        ? 'Серия $episodeNumber: $cleanSub'
        : 'Серия $episodeNumber';
    if (voiceover != null && voiceover.isNotEmpty) {
      return '$base • $voiceover';
    }
    return base;
  }

  /// Метаданные и кнопки действий под плеером (полноширинная карточка)
  Widget _buildMetadataPanel() {
    final title = widget.state.title;
    final ep = widget.state.episode;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131722),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;
          final infoColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatEpisodeSubtitle(ep.episode, ep.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              if (title.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  title.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          );

          final actionsWrap = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: isWide ? WrapAlignment.end : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Переключатель озвучки
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A202E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0x14FFFFFF)),
                  ),
                ),
                onPressed: () => VoiceoverSelectorSheet.show(
                  context,
                  episodeNumber: ep.episode,
                  onVoiceoverChanged: (studio) => widget.cubit.switchVoiceoverStudio(studio),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentVoiceoverTitle(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: Color(0xFF94A3B8)),
                  ],
                ),
              ),

              // Кнопка «В закладки»
              _buildBookmarkButton(title),

              // Кнопка «Создать момент»
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1A202E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: Color(0x14FFFFFF)),
                  ),
                ),
                icon: const Icon(Icons.bookmark_border_rounded, size: 16, color: Color(0xFF94A3B8)),
                label: const Text(
                  'Создать момент',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  final pos = widget.cubit.state.position;
                  final ts = _formatDuration(pos);
                  Clipboard.setData(
                    ClipboardData(text: '${title.displayTitle} • Серия ${ep.episode} ($ts)'),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Момент сохранён ($ts)'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),

              // Кнопка «Смотреть вместе» (плоский коралловый акцент)
              if (!widget.state.isSyncRoom)
                FilledButton.icon(
                  key: const ValueKey('desktop_watch_together_metadata_btn'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B4A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.group_add_rounded, size: 17, color: Colors.white),
                  label: const Text(
                    'Смотреть вместе',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  onPressed: () {
                    SyncRoomLobbySheet.show(
                      context,
                      title: title,
                      episode: ep,
                      initialQuality: widget.state.selectedQuality,
                      onStartPlayback: (room, isHost) {
                        widget.cubit.attachRoomSession(room, isHost: isHost);
                      },
                    );
                  },
                ),
            ],
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: infoColumn),
                const SizedBox(width: 20),
                Flexible(child: actionsWrap),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              infoColumn,
              const SizedBox(height: 12),
              actionsWrap,
            ],
          );
        },
      ),
    );
  }

  /// Кнопка управления закладками тайтла
  Widget _buildBookmarkButton(AnimeTitle title) {
    if (!getIt.isRegistered<AnimeListCubit>()) {
      return const SizedBox.shrink();
    }

    return BlocBuilder<AnimeListCubit, AnimeListState>(
      bloc: getIt<AnimeListCubit>(),
      builder: (context, listState) {
        final entry = listState.getEntryFor(title.id);
        final isBookmarked = entry != null;

        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: isBookmarked ? AppColors.primary : Colors.white,
            side: BorderSide(
              color: isBookmarked ? AppColors.primary : Colors.white.withValues(alpha: 0.18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: Icon(
            isBookmarked ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
            size: 16,
            color: isBookmarked ? AppColors.primary : Colors.white,
          ),
          label: Text(
            isBookmarked ? (entry.status.labelRu) : 'В закладки',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          onPressed: () {
            final cubit = getIt<AnimeListCubit>();
            if (isBookmarked) {
              cubit.removeAnime(title.id);
            } else {
              cubit.setAnimeStatus(
                animeId: title.id,
                titleRu: title.russianTitle,
                posterUrl: title.posterMedium.isNotEmpty ? title.posterMedium : title.posterSmall,
                status: AnimeListStatus.watching,
                lastEpisode: widget.state.episode.episode,
                positionMs: widget.state.position.inMilliseconds,
                episodesTotal: title.episodesTotal,
                isUserInitiated: true,
              );
            }
          },
        );
      },
    );
  }

  /// Сайдбар для режима совместного просмотра: вкладки «Чат» и «Эпизоды»
  Widget _buildRoomSidebar() {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      color: const Color(0xFF0F1117),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Верхний компактный инфо-блок комнаты (код, статус, кнопка покинуть)
          _buildRoomHeader(primary),

          // 2. Селектор вкладок (Чат / Эпизоды)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedSidebarTab = 0),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _selectedSidebarTab == 0 ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15,
                            color: _selectedSidebarTab == 0 ? Colors.black : Colors.white70,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Чат',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _selectedSidebarTab == 0 ? Colors.black : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedSidebarTab = 1),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      decoration: BoxDecoration(
                        color: _selectedSidebarTab == 1 ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.format_list_numbered_rounded,
                            size: 15,
                            color: _selectedSidebarTab == 1 ? Colors.black : Colors.white70,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Эпизоды',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _selectedSidebarTab == 1 ? Colors.black : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // 3. Тело вкладки: Чат или Эпизоды
          Expanded(
            child: _selectedSidebarTab == 0
                ? _buildRoomChatTab(primary)
                : _buildEpisodesListOnly(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomHeader(Color primary) {
    final code = widget.state.roomCode ?? '';
    final isHost = widget.state.isHost;
    final peer = widget.state.peerPresence;
    final isOnline = peer?.status == PresenceStatus.online;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    color: primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                iconSize: 17,
                tooltip: 'Скопировать код комнаты',
                icon: const Icon(Icons.copy_rounded, color: Colors.white70),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Код комнаты $code скопирован!'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const Spacer(),
              // Кнопка покинуть / закрыть комнату
              if (isHost)
                PopupMenuButton<String>(
                  tooltip: 'Управление комнатой',
                  color: const Color(0xFF181D27),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 18),
                  onSelected: (choice) async {
                    if (choice == 'leave') {
                      widget.cubit.leaveRoom();
                    } else if (choice == 'close_all') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dlgCtx) => AlertDialog(
                          backgroundColor: const Color(0xFF181D27),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          title: const Text('Закрыть комнату?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          content: const Text(
                            'Комната будет закрыта и удалена для всех участников.',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dlgCtx, false),
                              child: const Text('Отмена', style: TextStyle(color: Colors.white60)),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2A68)),
                              onPressed: () => Navigator.pop(dlgCtx, true),
                              child: const Text('Закрыть для всех', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await widget.cubit.closeRoomForAll();
                      }
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'leave',
                      child: Row(
                        children: [
                          Icon(Icons.exit_to_app_rounded, color: Colors.white70, size: 18),
                          SizedBox(width: 8),
                          Text('Выйти (комната 24ч)', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'close_all',
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep_rounded, color: Color(0xFFFF5252), size: 18),
                          SizedBox(width: 8),
                          Text('Закрыть для всех', style: TextStyle(color: Color(0xFFFF5252), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                )
              else
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF5252),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.exit_to_app_rounded, size: 15),
                  label: const Text('Выйти', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  onPressed: () => widget.cubit.leaveRoom(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? const Color(0xFF00E676) : Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  isHost
                      ? 'Вы хост • ${peer != null ? (isOnline ? '${peer.name} в сети' : '${peer.name} не в сети') : 'Ожидание гостя...'}'
                      : 'В комнате • Хост ${peer?.name ?? 'в сети'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoomChatTab(Color primary) {
    final messages = widget.state.chatMessages;

    return Column(
      children: [
        // Список сообщений
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 36, color: Colors.white.withValues(alpha: 0.2)),
                      const SizedBox(height: 10),
                      Text(
                        'Чат комнаты пока пуст.\nОтправьте сообщение или реакцию!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return _buildDesktopChatMessageItem(msg, primary);
                  },
                ),
        ),

        // Полоска стикер-реакций Пай-чан (6 эмоций вместо обычных Unicode эмодзи)
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            border: const Border(top: BorderSide(color: Colors.white10)),
          ),
          child: PaiChanStickerReactionBar(
            onStickerSelected: (sticker) => widget.cubit.sendReaction(sticker.id),
          ),
        ),

        // Поле ввода сообщения
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: _chatInputFocusNode,
                  builder: (context, _) {
                    final hasFocus = _chatInputFocusNode.hasFocus;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: hasFocus ? 0.08 : 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasFocus ? primary : Colors.white.withValues(alpha: 0.12),
                          width: hasFocus ? 1.4 : 1.0,
                        ),
                      ),
                      child: TextField(
                        controller: _chatController,
                        focusNode: _chatInputFocusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendRoomMessage(),
                        decoration: InputDecoration(
                          hintText: 'Написать сообщение... (Enter)',
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12.5),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          filled: false,
                          hoverColor: Colors.transparent,
                          focusColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(Icons.send_rounded, color: primary, size: 20),
                tooltip: 'Отправить',
                onPressed: _sendRoomMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _sendRoomMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    widget.cubit.sendChatMessage(text);
    _chatController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildDesktopChatMessageItem(ChatMessage msg, Color primary) {
    if (msg.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              msg.text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    final timeStr = '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                msg.isHost ? '👑 ${msg.sender}' : msg.sender,
                style: TextStyle(
                  color: msg.isHost ? const Color(0xFFFFB74D) : primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                timeStr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            msg.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodesListOnly() {
    final allEpisodes = widget.state.title.episodes;
    final curEp = widget.state.episode.episode;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      itemCount: allEpisodes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = allEpisodes[index];
        final isCurrent = item.episode == curEp;

        return InkWell(
          onTap: () {
            if (!isCurrent) {
              widget.cubit.switchEpisode(item);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFFFF6B4A).withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent
                    ? const Color(0xFFFF6B4A).withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.06),
                width: isCurrent ? 1.4 : 1.0,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 84,
                    height: 48,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.previewUrl != null && item.previewUrl!.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: wrapCorsSafeUrl(item.previewUrl!),
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFF1B1D26),
                              child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 20),
                            ),
                          )
                        else
                          Container(
                            color: const Color(0xFF1B1D26),
                            child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 20),
                          ),
                        if (isCurrent)
                          Container(
                            color: Colors.black.withValues(alpha: 0.45),
                            child: Center(
                              child: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 24),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Серия ${item.episode}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? const Color(0xFFFF6B4A) : Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF6B4A),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'СЕЙЧАС',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.name != null && item.name!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.name!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Правая стеклянная колонка: Сайдбар со всеми сериями тайтла
  Widget _buildEpisodesSidebar() {
    final allEpisodes = widget.state.title.episodes;
    final curEp = widget.state.episode.episode;

    return Container(
      color: const Color(0xFF0F1117),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Шапка сайдбара
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(
              children: [
                Icon(Icons.format_list_numbered_rounded, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Эпизоды',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${allEpisodes.length} серий',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Список серий с превью и номерами
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: allEpisodes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = allEpisodes[index];
                final isCurrent = item.episode == curEp;

                return InkWell(
                  onTap: () {
                    if (!isCurrent) {
                      widget.cubit.switchEpisode(item);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0xFFFF6B4A).withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent
                            ? const Color(0xFFFF6B4A).withValues(alpha: 0.65)
                            : Colors.white.withValues(alpha: 0.06),
                        width: isCurrent ? 1.4 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Превью серии
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 84,
                            height: 48,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (item.previewUrl != null && item.previewUrl!.isNotEmpty)
                                  CachedNetworkImage(
                                    imageUrl: wrapCorsSafeUrl(item.previewUrl!),
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: const Color(0xFF1B1D26),
                                      child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 20),
                                    ),
                                  )
                                else
                                  Container(
                                    color: const Color(0xFF1B1D26),
                                    child: const Icon(Icons.movie_outlined, color: Colors.white24, size: 20),
                                  ),
                                if (isCurrent)
                                  Container(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: Center(
                                      child: Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 24),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Номер и название серии
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Серия ${item.episode}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCurrent ? const Color(0xFFFF6B4A) : Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF6B4A),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'СЕЙЧАС',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (item.name != null && item.name!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.name!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                              if (item.opening != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Опенинг: ${item.opening!.formattedRange}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _qualityLabel(PlayerQuality q) {
    switch (q) {
      case PlayerQuality.fhd:
        return '1080p';
      case PlayerQuality.hd:
        return '720p';
      case PlayerQuality.sd:
        return '480p';
    }
  }

  String _currentVoiceoverTitle() {
    if (getIt.isRegistered<KodikCubit>()) {
      final kState = getIt<KodikCubit>().state;
      return kState.activeVoiceoverTitle;
    }
    if (widget.state.currentTranslation != null) {
      return widget.state.currentTranslation!.studioName;
    }
    return 'AniLibria';
  }
}
