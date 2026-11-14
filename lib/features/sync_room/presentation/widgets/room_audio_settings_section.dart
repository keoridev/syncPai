import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../services/room_audio_devices_service.dart';

/// Блок выбора микрофона (устройства ввода) и наушников/колонок (устройства вывода)
/// для комнат совместного просмотра «Вместе» на ПК и смартфонах.
class RoomAudioSettingsSection extends StatefulWidget {
  final Player? activePlayer;
  final bool compact;

  const RoomAudioSettingsSection({
    super.key,
    this.activePlayer,
    this.compact = false,
  });

  static Future<void> showModal(
    BuildContext context, {
    Player? activePlayer,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
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
                        color: AppColors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.headset_mic_rounded,
                        color: AppColors.primaryLight,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Микрофон и звук в комнате',
                            style: AppTypography.titleMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Выберите внешний микрофон, веб-камеру или Bluetooth-гарнитуру',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                RoomAudioSettingsSection(activePlayer: activePlayer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  State<RoomAudioSettingsSection> createState() => _RoomAudioSettingsSectionState();
}

class _RoomAudioSettingsSectionState extends State<RoomAudioSettingsSection> {
  final RoomAudioDevicesService _service = RoomAudioDevicesService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _service.refreshDevices(activePlayer: widget.activePlayer);
      }
    });
  }

  IconData _iconForDevice(AudioDeviceEndpoint dev) {
    switch (dev.iconType) {
      case 'bluetooth':
        return Icons.bluetooth_audio_rounded;
      case 'webcam':
        return Icons.videocam_rounded;
      case 'usb':
        return dev.isInput ? Icons.settings_voice_rounded : Icons.speaker_group_rounded;
      case 'hdmi':
        return Icons.tv_rounded;
      case 'jack':
        return dev.isInput ? Icons.mic_external_on_rounded : Icons.headphones_rounded;
      default:
        return dev.isInput ? Icons.mic_rounded : Icons.volume_up_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final selectedInput = _service.selectedInputDevice;
        final selectedOutput = _service.selectedOutputDevice;

        return Container(
          padding: EdgeInsets.all(widget.compact ? 12 : 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.09),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Заголовок блока + кнопка обновления подключенных устройств
              Row(
                children: [
                  Icon(Icons.headset_mic_rounded, size: 16, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'МИКРОФОН И АУДИОВЫХОД (ДЛЯ ПК / ГАРНИТУР)',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _service.isRefreshing
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            _service.refreshDevices(activePlayer: widget.activePlayer);
                          },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_service.isRefreshing)
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: primary,
                              ),
                            )
                          else
                            Icon(Icons.refresh_rounded, size: 14, color: primary),
                          const SizedBox(width: 4),
                          Text(
                            'Обновить',
                            style: TextStyle(
                              color: primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 1. Устройство ввода (Микрофон)
              _buildDeviceSelector(
                context: context,
                label: 'Устройство ввода (Микрофон):',
                selectedDevice: selectedInput,
                devices: _service.inputDevices,
                onSelected: (id) => _service.selectInputDevice(id),
                isInput: true,
                primaryColor: primary,
              ),

              const SizedBox(height: 10),

              // 2. Устройство вывода (Наушники / Динамики)
              _buildDeviceSelector(
                context: context,
                label: 'Устройство вывода (Наушники / Колонки):',
                selectedDevice: selectedOutput,
                devices: _service.outputDevices,
                onSelected: (id) => _service.selectOutputDevice(id, activePlayer: widget.activePlayer),
                isInput: false,
                primaryColor: primary,
              ),

              if (!widget.compact) ...[
                const SizedBox(height: 12),
                // Ползунок чувствительности микрофона и кнопка Mute
                Row(
                  children: [
                    InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _service.toggleMicMute();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _service.isMicMuted
                              ? AppColors.syncError.withValues(alpha: 0.16)
                              : const Color(0xFF00E676).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _service.isMicMuted
                                ? AppColors.syncError.withValues(alpha: 0.4)
                                : const Color(0xFF00E676).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _service.isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                              size: 15,
                              color: _service.isMicMuted ? AppColors.syncError : const Color(0xFF00E676),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _service.isMicMuted ? 'Выкл' : 'Вкл',
                              style: TextStyle(
                                color: _service.isMicMuted ? AppColors.syncError : const Color(0xFF00E676),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _service.isMicMuted ? 0.0 : _service.micVolume,
                          activeColor: primary,
                          inactiveColor: Colors.white.withValues(alpha: 0.14),
                          onChanged: (v) {
                            if (_service.isMicMuted && v > 0.05) {
                              _service.toggleMicMute();
                            }
                            _service.setMicVolume(v);
                          },
                        ),
                      ),
                    ),
                    Text(
                      '${((_service.isMicMuted ? 0.0 : _service.micVolume) * 100).round()}%',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                // Шумоподавление для микрофона (Krisp / WebRTC Noise Suppression)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Подавление шума и эха (Noise Suppression)',
                    style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Отсекает шум клавиатуры, кулеров ПК и звук аниме из колонок',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                  ),
                  value: _service.isNoiseSuppression,
                  activeThumbColor: primary,
                  onChanged: (v) => _service.setNoiseSuppression(v),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeviceSelector({
    required BuildContext context,
    required String label,
    required AudioDeviceEndpoint selectedDevice,
    required List<AudioDeviceEndpoint> devices,
    required ValueChanged<String> onSelected,
    required bool isInput,
    required Color primaryColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            return PopupMenuButton<String>(
              tooltip: '',
              position: PopupMenuPosition.under,
              offset: const Offset(0, 6),
              elevation: 12,
              shadowColor: Colors.black.withValues(alpha: 0.8),
              color: const Color(0xFF141722),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
              ),
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                maxWidth: constraints.maxWidth,
              ),
              onSelected: (newId) {
                HapticFeedback.selectionClick();
                if (newId == '__refresh__') {
                  _service.refreshDevices(activePlayer: widget.activePlayer);
                } else {
                  onSelected(newId);
                }
              },
              itemBuilder: (context) {
                final items = <PopupMenuEntry<String>>[];
                for (final dev in devices) {
                  final isSelected = dev.id == selectedDevice.id;
                  items.add(
                    PopupMenuItem<String>(
                      value: dev.id,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      height: 52,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected
                              ? Border.all(color: primaryColor.withValues(alpha: 0.35), width: 1)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: (isSelected ? primaryColor : Colors.white)
                                    .withValues(alpha: isSelected ? 0.2 : 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _iconForDevice(dev),
                                size: 16,
                                color: isSelected ? primaryColor : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    dev.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : AppColors.textPrimary,
                                      fontSize: 12.5,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                  if (dev.subtitle.isNotEmpty)
                                    Text(
                                      dev.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected
                                            ? primaryColor.withValues(alpha: 0.85)
                                            : AppColors.textMuted,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: primaryColor,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                items.add(
                  const PopupMenuDivider(height: 1),
                );
                items.add(
                  PopupMenuItem<String>(
                    value: '__refresh__',
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(Icons.refresh_rounded, size: 15, color: primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Обновить список устройств...',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                return items;
              },
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF141720),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _iconForDevice(selectedDevice),
                        size: 17,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            selectedDevice.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            selectedDevice.subtitle.isNotEmpty
                                ? selectedDevice.subtitle
                                : (isInput ? 'Микрофон' : 'Устройство воспроизведения'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_service.isRefreshing)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: primaryColor,
                        ),
                      )
                    else
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
