import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_state.dart';
import 'package:go_router/go_router.dart';
import 'package:sync_pai/app/di/injection.dart';
import 'package:sync_pai/core/network/image_cors_helper.dart';
import 'package:sync_pai/core/theme/app_colors.dart';
import 'package:sync_pai/core/theme/app_typography.dart';
import 'package:sync_pai/core/widgets/sync_pai_logo.dart';
import 'package:sync_pai/core/widgets/mascot/mascot_state.dart';
import 'package:sync_pai/core/widgets/mascot/sync_pai_mascot.dart';
import 'package:sync_pai/features/catalog/domain/entities/anime_title.dart';
import 'package:sync_pai/features/catalog/domain/entities/episode_item.dart';
import 'package:sync_pai/features/catalog/presentation/cubit/catalog_cubit.dart';
import 'package:sync_pai/features/player/services/global_mini_player_service.dart';
import '../../data/repositories/sync_room_repository_impl.dart';
import '../../domain/entities/sync_event.dart';
import '../../domain/entities/sync_room.dart';
import '../../domain/repositories/sync_room_repository.dart';
import '../cubit/sync_room_cubit.dart';
import 'coop_match_screen.dart';

/// Экран обработки подключения к комнате (https://syncpai.app/room/:code или по пин-коду).
/// Отображает лобби с участниками («Кто есть в комнате») и автоматически переходит в плеер,
/// когда хост запускает совместный просмотр.
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
  SyncRoom? _joinedRoom;
  StreamSubscription<SyncEvent>? _eventSubscription;

  bool _isVoiceMuted = false;

  @override
  void initState() {
    super.initState();
    // Автоматически ставим на паузу и скрываем плавающий мини-плеер при входе в лобби (сохраняя сессию)
    GlobalMiniPlayerService.instance.pauseAndHide();
    _joinRoom();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
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

      setState(() {
        _isLoading = false;
        _joinedRoom = room;
      });

      // Подписываемся на команду одновременного старта от хоста
      await _eventSubscription?.cancel();
      _eventSubscription = repository.subscribeToRoom(room.code).listen((event) {
        if (event.type == SyncEventType.startPlayback) {
          _openPlayer(room);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Не удалось найти комнату $normalized. Возможно, она была закрыта хостом.';
      });
    }
  }

  void _openPlayer(SyncRoom room) {
    if (!mounted) return;
    final miniService = GlobalMiniPlayerService.instance;
    final canReuse = miniService.hasSessionFor(room.title.id, room.episode.episode);
    if (!canReuse) {
      miniService.close();
    }
    context.pushReplacementNamed('player', extra: {
      'title': room.title,
      'episode': room.episode,
      'quality': room.quality,
      'roomCode': room.code,
      'isHost': false,
      if (canReuse) 'reuseMiniPlayer': true,
    });
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SyncPaiLogo(size: 64),
                  const SizedBox(height: 20),

                  if (_isLoading) ...[
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
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
                      'Синхронизация тайтла и лобби',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ] else if (_joinedRoom != null) ...[
                    // ЛОББИ КОМНАТЫ: Участники и готовность
                    Builder(
                      builder: (context) {
                        final isDesktop = MediaQuery.of(context).size.width >= 900;
                        final room = _joinedRoom!;

                        return Container(
                          width: double.infinity,
                          constraints: BoxConstraints(maxWidth: isDesktop ? 780 : 420),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: isDesktop
                              ? _buildDesktopLobbyContent(context, room)
                              : _buildMobileLobbyContent(context, room),
                        );
                      },
                    ),
                  ] else ...[
                    SyncPaiMascot(
                      state: MascotState.error404,
                      size: MascotSize.small,
                      message: 'Ошибка подключения',
                      description: _errorMessage ?? 'Комната не найдена или закрыта хостом',
                      action: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surfaceElevated,
                          foregroundColor: AppColors.textPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => context.goNamed('catalog'),
                        child: const Text('Вернуться в каталог', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
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

  void _copyRoomCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Код комнаты $code скопирован в буфер обмена'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceElevated,
      ),
    );
  }

  /// Десктопное разделение на 2 колонки (flex: 55 и flex: 45)
  Widget _buildDesktopLobbyContent(BuildContext context, SyncRoom room) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Левая колонка (flex: 55): Шапка с кодом, тайтл, участники
        Expanded(
          flex: 55,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRoomHeader(context, room),
              const SizedBox(height: 14),
              _buildTitleCard(context, room),
              const SizedBox(height: 14),
              _buildParticipantsList(room),
            ],
          ),
        ),

        const SizedBox(width: 20),

        // Правая колонка (flex: 45): Голос, Anime Match, индикатор и кнопка
        Expanded(
          flex: 45,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildVoiceChatStatus(context),
              const SizedBox(height: 14),
              _buildInRoomAnimeMatchBanner(room),
              const SizedBox(height: 14),
              _buildHostWaitingNotice(context),
              const SizedBox(height: 16),
              _buildActionButtons(context, room),
            ],
          ),
        ),
      ],
    );
  }

  /// Мобильная классическая одноколоночная верстка
  Widget _buildMobileLobbyContent(BuildContext context, SyncRoom room) {
    return Column(
      children: [
        _buildRoomHeader(context, room),
        const SizedBox(height: 14),
        _buildTitleCard(context, room),
        const SizedBox(height: 16),
        _buildParticipantsList(room),
        const SizedBox(height: 14),
        _buildVoiceChatStatus(context),
        const SizedBox(height: 14),
        _buildInRoomAnimeMatchBanner(room),
        const SizedBox(height: 14),
        _buildHostWaitingNotice(context),
        const SizedBox(height: 18),
        _buildActionButtons(context, room),
      ],
    );
  }

  /// Шапка лобби с кодом комнаты и кнопкой быстрого копирования
  Widget _buildRoomHeader(BuildContext context, SyncRoom room) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'КОМНАТА ${room.code}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: 'Скопировать код комнаты',
                icon: Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: () => _copyRoomCode(room.code),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF00E676).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF00E676),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              const Text(
                '2/2 в сборе',
                style: TextStyle(
                  color: Color(0xFF00E676),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Карточка выбранного тайтла
  Widget _buildTitleCard(BuildContext context, SyncRoom room) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              wrapCorsSafeUrl(room.title.posterSmall),
              width: 48,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 48,
                height: 64,
                color: AppColors.surfaceElevated,
                child: const Icon(Icons.movie_creation_outlined, color: Colors.white30),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.title.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Серия ${room.episode.episode}  •  ${room.quality.label}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Список участников лобби («Кто в комнате»)
  Widget _buildParticipantsList(SyncRoom room) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, size: 18, color: Color(0xFFFFD700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  room.hostName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E676),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text('Хост • Готов', style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 16),
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 18, color: Color(0xFF64B5F6)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Вы (Гость)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E676),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text('Подключен', style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Статус связи и общения в комнате с кнопкой Mute/Unmute
  Widget _buildVoiceChatStatus(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isVoiceMuted
              ? Colors.white.withValues(alpha: 0.15)
              : const Color(0xFF00E676).withValues(alpha: 0.25),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isVoiceMuted
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFF00E676).withValues(alpha: 0.15),
            ),
            child: Icon(
              _isVoiceMuted ? Icons.mic_off_rounded : Icons.record_voice_over_rounded,
              color: _isVoiceMuted ? Colors.white60 : const Color(0xFF00E676),
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isVoiceMuted ? 'Микрофон отключен' : 'Связь в комнате активна',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _isVoiceMuted
                      ? 'Нажмите, чтобы включить передачу голоса'
                      : 'Вы можете разговаривать и переписываться в комнате',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              setState(() {
                _isVoiceMuted = !_isVoiceMuted;
              });
              HapticFeedback.lightImpact();
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isVoiceMuted
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFF00E676).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isVoiceMuted
                      ? Colors.white.withValues(alpha: 0.15)
                      : const Color(0xFF00E676).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isVoiceMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: _isVoiceMuted ? Colors.white70 : const Color(0xFF00E676),
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isVoiceMuted ? 'Mute' : 'Голос ON',
                    style: TextStyle(
                      color: _isVoiceMuted ? Colors.white70 : const Color(0xFF00E676),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Индикатор ожидания запуска от хоста
  Widget _buildHostWaitingNotice(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Ожидаем, пока хост запустит плеер… Плеер откроется автоматически.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  /// Кнопки действий: войти в плеер сейчас и покинуть комнату
  Widget _buildActionButtons(BuildContext context, SyncRoom room) {
    return Column(
      children: [
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 22),
          label: const Text(
            'Войти в плеер сейчас ▶',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          onPressed: () => _openPlayer(room),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => context.goNamed('catalog'),
          child: const Text('Покинуть комнату', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildInRoomAnimeMatchBanner(SyncRoom room) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF5E3A).withValues(alpha: 0.14),
            const Color(0xFFFF2A68).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF2A68).withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5E3A), Color(0xFFFF2A68)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF2A68).withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.style_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    const Text(
                      'Anime Match',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2A68).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'В комнате',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFFFF5E3A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Свайпайте карточки тайтлов вдвоем — первое совпадение сразу включит серию!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2A68),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => _startAnimeMatch(room),
            child: const Text(
              'Свайпать',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _startAnimeMatch(SyncRoom room) {
    List<AnimeTitle> deck = [];
    try {
      if (getIt.isRegistered<CatalogCubit>()) {
        final catalogState = getIt<CatalogCubit>().state;
        if (catalogState is CatalogLoaded && catalogState.titles.isNotEmpty) {
          deck = catalogState.titles;
        }
      }
    } catch (_) {}

    if (deck.isEmpty) {
      deck = [
        room.title,
        const AnimeTitle(
          id: 101,
          code: 'frieren',
          russianTitle: 'Провожающая в последний путь Фрирен',
          englishTitle: 'Sousou no Frieren',
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          genres: ['Приключения', 'Фэнтези'],
          description: 'История эльфийки-волшебницы Фрирен после победы над Королем демонов.',
          status: 'Онгоинг',
        ),
        const AnimeTitle(
          id: 102,
          code: 'jujutsu_kaisen',
          russianTitle: 'Магическая битва',
          englishTitle: 'Jujutsu Kaisen',
          posterSmall: '',
          posterMedium: '',
          posterOriginal: '',
          genres: ['Экшен', 'Сёнэн'],
          description: 'Юдзи Итадори проглатывает палец проклятого духа Сукуны.',
          status: 'Онгоинг',
        ),
      ];
    }

    CoopMatchScreen.open(
      context,
      deck: deck,
      roomCode: room.code,
      userName: room.peerName ?? 'Гость',
      syncRepository: getIt<SyncRoomRepository>(),
      onStartWatching: (matched) {
        if (getIt.isRegistered<SyncRoomCubit>()) {
          getIt<SyncRoomCubit>().startMatchedTitlePlayback(matched);
        }
        final ep = matched.episodes.isNotEmpty
            ? matched.episodes.first
            : const EpisodeItem(episode: 1);
        _openPlayer(room.copyWith(title: matched, episode: ep));
      },
    );
  }
}
