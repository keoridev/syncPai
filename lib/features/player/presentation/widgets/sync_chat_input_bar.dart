import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../cubit/player_cubit.dart';
import 'floating_pai_chan_reactions_overlay.dart';

/// Шторка быстрого набора сообщений и реакций для совместного просмотра.
/// Полностью адаптирована под горизонтальный (landscape) режим экрана
/// и предотвращает любые переполнения RenderFlex (желтые полосы).
class SyncChatInputSheet extends StatefulWidget {
  final PlayerCubit cubit;

  const SyncChatInputSheet({
    super.key,
    required this.cubit,
  });

  static Future<void> show(BuildContext context, {required PlayerCubit cubit}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SyncChatInputSheet(cubit: cubit),
    );
  }

  @override
  State<SyncChatInputSheet> createState() => _SyncChatInputSheetState();
}

class _SyncChatInputSheetState extends State<SyncChatInputSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const List<String> _quickPhrases = [
    'Опенинг пушка! 🔥',
    'Ха-ха, классика 😂',
    'Ого, вот это поворот 😱',
    'Стой, подожди секунду!',
    'Смотрим дальше ▶',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      widget.cubit.sendChatMessage(text);
      _controller.clear();
      Navigator.of(context).pop();
    }
  }

  void _sendStickerReaction(String stickerId) {
    widget.cubit.sendReaction(stickerId);
    Navigator.of(context).pop();
  }

  void _sendQuickPhrase(String phrase) {
    widget.cubit.sendChatMessage(phrase);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 14 : AppDimensions.spacingLg,
                vertical: isLandscape ? 8 : AppDimensions.spacingLg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLandscape) ...[
                    // В ландшафтном режиме: ультра-компактный ряд (стикеры Пай-чан + поле ввода)
                    Row(
                      children: [
                        PaiChanStickerReactionBar(
                          compact: true,
                          onStickerSelected: (sticker) => _sendStickerReaction(sticker.id),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildInputRow(context),
                        ),
                      ],
                    ),
                  ] else ...[
                    // В портретном режиме: полоска 6 стикер-реакций Пай-чан
                    PaiChanStickerReactionBar(
                      onStickerSelected: (sticker) => _sendStickerReaction(sticker.id),
                    ),

                    const SizedBox(height: AppDimensions.spacingMd),

                    // Быстрые фразы
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _quickPhrases.map((phrase) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              backgroundColor: Colors.white.withValues(alpha: 0.05),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              label: Text(
                                phrase,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 11.5,
                                ),
                              ),
                              onPressed: () => _sendQuickPhrase(phrase),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: AppDimensions.spacingMd),

                    _buildInputRow(context),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: ListenableBuilder(
            listenable: _focusNode,
            builder: (context, _) {
              final hasFocus = _focusNode.hasFocus;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: hasFocus ? 0.08 : 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasFocus
                        ? scheme.primary
                        : scheme.outlineVariant.withValues(alpha: 0.3),
                    width: hasFocus ? 1.4 : 1.0,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                  cursorColor: scheme.primary,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
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
                    hintText: 'Сообщение в комнату…',
                    hintStyle: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: AppDimensions.spacingSm),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: scheme.primary,
            minimumSize: const Size(44, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.send_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: _sendMessage,
        ),
      ],
    );
  }
}
