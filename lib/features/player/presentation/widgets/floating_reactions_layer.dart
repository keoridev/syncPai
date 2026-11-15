import 'package:flutter/material.dart';
import '../../../sync_room/domain/entities/sync_protocol.dart';
import 'floating_pai_chan_reactions_overlay.dart';

/// Слой плавающих летящих стикер-реакций Пай-чан (Floating Pai-chan Reactions)
class FloatingReactionsLayer extends StatelessWidget {
  final List<FloatingReaction> reactions;

  const FloatingReactionsLayer({
    super.key,
    required this.reactions,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingPaiChanReactionsOverlay(reactions: reactions);
  }
}
