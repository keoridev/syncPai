import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/sync_pai_logo.dart';
import '../../data/repositories/sync_room_repository_impl.dart';
import '../../domain/repositories/sync_room_repository.dart';

/// Экран обработки диплинка (https://syncpai.app/room/:code или syncpai://room/:code)
/// Автоматически валидирует комнату, регистрирует гостя и переходит в совместный плеер в 1 клик.
class JoinRoomScreen extends StatefulWidget {
  final String code;

  const JoinRoomScreen({
    super.key,
    required this.code,
  });

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _joinRoom();
  }

  Future<void> _joinRoom() async {
    final rawCode = widget.code;
    final normalized = SyncRoomRepositoryImpl.normalizeCode(rawCode);

    try {
      final repository = getIt<SyncRoomRepository>();
      final room = await repository.joinRoom(
        code: normalized,
        peerName: 'Друг',
      );

      if (!mounted) return;

      // Мгновенный переход на экран плеера
      context.goNamed('player', extra: {
        'title': room.title,
        'episode': room.episode,
        'quality': room.quality,
        'roomCode': room.code,
        'isHost': false,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось найти комнату $normalized. Возможно, она была закрыта хостом.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalized = SyncRoomRepositoryImpl.normalizeCode(widget.code);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SyncPaiLogo(size: 72),
                  const SizedBox(height: 28),
                  if (_isLoading) ...[
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Подключение к комнате $normalized…',
                      textAlign: TextAlign.center,
                      style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Синхронизация тайтла и видеопотока',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ] else ...[
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.syncError,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ошибка подключения',
                      style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ?? 'Комната не найдена',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => context.goNamed('main'),
                      child: const Text('Перейти в каталог'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
