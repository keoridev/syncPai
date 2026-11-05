import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../cubit/player_cubit.dart';

/// Шторка быстрого набора сообщений и реакций для совместного просмотра.
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

  static const List<String> _quickReactions = ['🔥', '😂', '😱', '😭', '❤️'];
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

  void _sendReaction(String emoji) {
    widget.cubit.sendReaction(emoji);
    Navigator.of(context).pop();
  }

  void _sendQuickPhrase(String phrase) {
    widget.cubit.sendChatMessage(phrase);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.spacingLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Быстрые эмодзи-реакции
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _quickReactions.map((emoji) {
                      return InkWell(
                        onTap: () => _sendReaction(emoji),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    }).toList(),
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

                  // Поле ввода текста с кнопкой отправки
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          alignment: Alignment.center,
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                            cursorColor: AppColors.primary,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Сообщение в комнату…',
                              hintStyle: AppTypography.bodyMedium.copyWith(
                                color: AppColors.textMuted,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spacingSm),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          minimumSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.send_rounded, color: AppColors.textPrimary, size: 20),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

