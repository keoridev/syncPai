import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../sync_room/domain/entities/sync_protocol.dart';

/// Минималистичный оверлей чата комнаты в верхнем левом углу экрана.
/// Сообщения аккуратно всплывают в формате «Ник: Текст»,
/// не загораживают видеоряд и плавно затухают после показа.
class TwitchChatOverlay extends StatefulWidget {
  final List<ChatMessage> messages;
  final bool isVisible;
  final VoidCallback onToggleVisibility;

  const TwitchChatOverlay({
    super.key,
    required this.messages,
    required this.isVisible,
    required this.onToggleVisibility,
  });

  @override
  State<TwitchChatOverlay> createState() => _TwitchChatOverlayState();
}

class _TwitchChatOverlayState extends State<TwitchChatOverlay> {
  Timer? _fadeTimer;
  bool _isFaded = false;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _lastCount = widget.messages.length;
    _scheduleFade();
  }

  @override
  void didUpdateWidget(covariant TwitchChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length > _lastCount) {
      _lastCount = widget.messages.length;
      setState(() {
        _isFaded = false;
      });
      _scheduleFade();
    }
  }

  void _scheduleFade() {
    _fadeTimer?.cancel();
    if (widget.messages.isNotEmpty) {
      _fadeTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _isFaded = true;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Если чат скрыт пользователем или сообщений нет — на экране вообще ничего лишнего не рисуем
    if (!widget.isVisible || widget.messages.isEmpty) {
      return const SizedBox.shrink();
    }

    // Отображаем последние 3-4 сообщения, чтобы не загромождать кадр
    final displayMessages = widget.messages.length > 4
        ? widget.messages.sublist(widget.messages.length - 4)
        : widget.messages;

    return Align(
      alignment: Alignment.topLeft,
      child: AnimatedOpacity(
        opacity: _isFaded ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 600),
        child: Container(
          margin: const EdgeInsets.only(top: 56, left: 16),
          constraints: const BoxConstraints(maxWidth: 300, maxHeight: 180),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: displayMessages.length,
            itemBuilder: (context, index) {
              final msg = displayMessages[index];
              return _buildMessageItem(msg);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMessageItem(ChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    // Никнейм
                    TextSpan(
                      text: msg.isHost ? '👑 ${msg.sender}: ' : '${msg.sender}: ',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: msg.isHost ? const Color(0xFFFFB74D) : const Color(0xFF64B5F6),
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                    // Текст
                    TextSpan(
                      text: msg.text,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        height: 1.25,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
