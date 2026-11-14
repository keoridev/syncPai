import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_avatar.dart';
import '../../../../core/widgets/mascot/mascot_state.dart';
import '../../../../core/widgets/mascot/sync_pai_mascot.dart';
import '../../../../core/widgets/sync_pai_logo.dart';
import '../../data/services/wrapped_service.dart';
import '../../domain/entities/wrapped_data.dart';
import '../widgets/wrapped_share_card.dart';

/// Полноэкранный сторис-слайдер в стиле Spotify Wrapped «SyncPai Wrapped 2026».
/// 10 интерактивных экранов с прогресс-баром, паузой по удержанию,
/// свайпами, адаптацией под десктоп и экспортом итоговой карточки в PNG.
class WrappedStoryScreen extends StatefulWidget {
  final WrappedData? initialData;

  const WrappedStoryScreen({
    super.key,
    this.initialData,
  });

  @override
  State<WrappedStoryScreen> createState() => _WrappedStoryScreenState();
}

class _WrappedStoryScreenState extends State<WrappedStoryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  final GlobalKey _shareCardKey = GlobalKey();

  WrappedData? _data;
  bool _isLoading = true;
  int _currentStoryIndex = 0;
  static const int _totalStories = 10;
  static const Duration _storyDuration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _storyDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextStory();
        }
      });

    if (widget.initialData != null) {
      _data = widget.initialData;
      _isLoading = false;
      _progressController.forward();
    } else {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final data = await WrappedService.instance.getWrappedData();
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
      _progressController.forward();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _nextStory() {
    if (_currentStoryIndex < _totalStories - 1) {
      setState(() {
        _currentStoryIndex++;
      });
      _progressController.forward(from: 0.0);
    } else {
      _progressController.stop();
    }
  }

  void _prevStory() {
    if (_currentStoryIndex > 0) {
      setState(() {
        _currentStoryIndex--;
      });
      _progressController.forward(from: 0.0);
    } else {
      _progressController.forward(from: 0.0);
    }
  }

  void _pauseStory() {
    _progressController.stop();
  }

  void _resumeStory() {
    _progressController.forward();
  }

  void _restartStories() {
    setState(() {
      _currentStoryIndex = 0;
    });
    _progressController.forward(from: 0.0);
  }

  Future<void> _shareRecapCard() async {
    try {
      HapticFeedback.mediumImpact();
      final boundary = _shareCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();

      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/syncpai_wrapped_2026.png');
        await file.writeAsBytes(bytes);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Карточка итогов сохранена: ${file.path}'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта карточки: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _data == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF090B10),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: SyncPaiMascot(state: MascotState.thinking),
              ),
              SizedBox(height: 16),
              Text(
                'Считаем ваши аниме-итоги 2026...',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 900;

    Widget storyContent = GestureDetector(
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox?;
        final width = box?.size.width ?? screenWidth;
        if (details.localPosition.dx < width * 0.35) {
          _prevStory();
        } else {
          _nextStory();
        }
      },
      onLongPressStart: (_) => _pauseStory(),
      onLongPressEnd: (_) => _resumeStory(),
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -150) {
            _nextStory();
          } else if (details.primaryVelocity! > 150) {
            _prevStory();
          }
        }
      },
      child: Container(
        color: const Color(0xFF0A0D14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Тело текущей сторис
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: KeyedSubtree(
                key: ValueKey<int>(_currentStoryIndex),
                child: _buildStorySlide(_currentStoryIndex, data),
              ),
            ),

            // Верхние сегментированные прогресс-бары
            Positioned(
              top: MediaQuery.paddingOf(context).top + 10,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  Row(
                    children: List.generate(_totalStories, (index) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: _buildStoryProgressBar(index),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  // Шапка: Иконка SyncPai и кнопка Закрыть
                  Row(
                    children: [
                      const SyncPaiLogo(size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'SyncPai Wrapped 2026',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // На больших экранах десктопа центрируем сторис в рамке
    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFF06080C),
        body: Center(
          child: Container(
            width: 440,
            height: 820,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: storyContent,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: storyContent,
    );
  }

  Widget _buildStoryProgressBar(int index) {
    if (index < _currentStoryIndex) {
      return Container(
        height: 3,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    } else if (index == _currentStoryIndex) {
      return AnimatedBuilder(
        animation: _progressController,
        builder: (context, _) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: _progressController.value,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              minHeight: 3,
            ),
          );
        },
      );
    } else {
      return Container(
        height: 3,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
  }

  Widget _buildStorySlide(int index, WrappedData data) {
    switch (index) {
      case 0:
        return _buildIntroSlide(data);
      case 1:
        return _buildWatchTimeSlide(data);
      case 2:
        return _buildEpisodesSlide(data);
      case 3:
        return _buildGenreSlide(data);
      case 4:
        return _buildTopAnimeSlide(data);
      case 5:
        return _buildRewatchSlide(data);
      case 6:
        return _buildSocialSlide(data);
      case 7:
        return _buildPartnerSlide(data);
      case 8:
        return _buildPersonalitySlide(data);
      case 9:
        return _buildFinalSummarySlide(data);
      default:
        return const SizedBox.shrink();
    }
  }

  // СЛАЙД 1: ИНТРО
  Widget _buildIntroSlide(WrappedData data) {
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF0F172A), const Color(0xFF0A0D14)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 190,
            height: 190,
            child: SyncPaiMascot(
              state: MascotState.welcome,
              size: MascotSize.large,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accentTurquoise.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.accentTurquoise.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'ИТОГИ 2026 ГОДА',
              style: TextStyle(
                color: AppColors.accentTurquoise,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${data.username},\nтвой год в аниме',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Один год. Десятки историй. Невероятные эмоции вместе с SyncPai.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // СЛАЙД 2: ВРЕМЯ ПРОСМОТРА
  Widget _buildWatchTimeSlide(WrappedData data) {
    final hours = (data.totalWatchTimeMinutes / 60.0).toStringAsFixed(1);
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF1E1B4B), const Color(0xFF0B0F19)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_rounded, size: 48, color: AppColors.accentTurquoise),
          const SizedBox(height: 20),
          const Text(
            'Ты провёл за просмотром',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            '$hours ч.',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          Text(
            '(${data.totalWatchTimeMinutes} минут)',
            style: TextStyle(color: AppColors.accentTurquoise, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Это время, прожитое в десятках миров, с любимыми героями и незабываемой атмосферой.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // СЛАЙД 3: СЕРИИ
  Widget _buildEpisodesSlide(WrappedData data) {
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF3B0764), const Color(0xFF0D0A1A)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.movie_filter_rounded, size: 52, color: AppColors.accentCoral),
          const SizedBox(height: 20),
          const Text(
            'Серий завершено в 2026 году',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            '${data.totalEpisodesWatched}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 72,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'в ${data.totalTitlesWatched} различных тайтлах',
            style: TextStyle(color: AppColors.accentCoral, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 28),
          const SizedBox(
            width: 140,
            height: 140,
            child: SyncPaiMascot(
              state: MascotState.happy,
              size: MascotSize.medium,
            ),
          ),
        ],
      ),
    );
  }

  // СЛАЙД 4: ЛЮБИМЫЙ ЖАНР
  Widget _buildGenreSlide(WrappedData data) {
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF14303B), const Color(0xFF09141A)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB300).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.category_rounded, size: 48, color: Color(0xFFFFB300)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Твой любимый жанр года',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            data.favoriteGenre,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Text(
              'Именно эти сюжетные линии и тропы держали тебя в напряжении больше всего!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // СЛАЙД 5: ТОП АНИМЕ
  Widget _buildTopAnimeSlide(WrappedData data) {
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF31101E), const Color(0xFF0D0609)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accentCoral.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'ГЛАВНЫЙ ТАЙТЛ ГОДА',
              style: TextStyle(color: AppColors.accentCoral, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 20),
          if (data.topAnimePoster.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                data.topAnimePoster,
                width: 140,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholderPoster(),
              ),
            )
          else
            _buildPlaceholderPoster(),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              data.topAnimeTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${data.topAnimeEpisodes} серий просмотрено',
            style: TextStyle(color: AppColors.accentCoral, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderPoster() {
    return Container(
      width: 140,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(Icons.movie_rounded, color: AppColors.textMuted, size: 48),
    );
  }

  // СЛАЙД 6: ПЕРЕСМОТР / АКТИВНОСТЬ
  Widget _buildRewatchSlide(WrappedData data) {
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF1E293B), const Color(0xFF0B101B)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.calendar_month_rounded, size: 48, color: AppColors.accentTurquoise),
          const SizedBox(height: 20),
          const Text(
            'Твой пик активности в 2026',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            data.mostActiveMonth,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Любимый день недели: ${data.mostActiveDayOfWeek}',
            style: TextStyle(color: AppColors.accentTurquoise, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (data.mostRewatchedTitle != null) ...[
            const SizedBox(height: 28),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  const Text('ИСТОРИЯ, К КОТОРОЙ ВОЗВРАЩАЛСЯ', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    data.mostRewatchedTitle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // СЛАЙД 7: ВМЕСТЕ С ДРУЗЬЯМИ (SOCIAL)
  Widget _buildSocialSlide(WrappedData data) {
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF064E3B), const Color(0xFF041A14)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 140,
            height: 140,
            child: SyncPaiMascot(
              state: MascotState.friendsJoined,
              size: MascotSize.medium,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Смотреть вместе — это база',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            '${data.totalWatchParties} сессий',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${data.formattedFriendsTime} синхронного просмотра',
            style: const TextStyle(color: Color(0xFF00E676), fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // СЛАЙД 8: НАПАРНИК ГОДА
  Widget _buildPartnerSlide(WrappedData data) {
    final partner = data.topWatchPartnerName ?? 'Сенпай';
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF4C0519), const Color(0xFF140207)],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppAvatar(
            avatarUrl: data.topWatchPartnerAvatar,
            username: partner,
            size: 80,
            borderWidth: 2,
          ),
          const SizedBox(height: 20),
          const Text(
            'Твой аниме-напарник года',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            partner,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'С кем разделили больше всего серий, спойлеров и ночных стримов!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // СЛАЙД 9: ТИПАЖ ЗРИТЕЛЯ (PERSONALITY)
  Widget _buildPersonalitySlide(WrappedData data) {
    final p = data.personality;
    return _buildSlideContainer(
      gradientColors: [
        p.color.withValues(alpha: 0.35),
        const Color(0xFF0A0D14),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: p.color.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(p.icon, size: 54, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              'ТВОЙ АНИМЕ-ТИПАЖ 2026',
              style: TextStyle(
                color: p.color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              p.titleRu,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              p.titleEn,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.color.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    p.tagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 100,
              height: 100,
              child: SyncPaiMascot(
                state: p.mascotState,
                size: MascotSize.small,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // СЛАЙД 10: ФИНАЛЬНЫЙ РЕКАП И ШЕРИНГ
  Widget _buildFinalSummarySlide(WrappedData data) {
    return _buildSlideContainer(
      gradientColors: [const Color(0xFF131722), const Color(0xFF090B10)],
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 70, 16, 24),
        child: Column(
          children: [
            RepaintBoundary(
              key: _shareCardKey,
              child: WrappedShareCard(data: data),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentTurquoise,
                      foregroundColor: const Color(0xFF0F1117),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text(
                      'Поделиться итогами',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    onPressed: _shareRecapCard,
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.replay_rounded, size: 20),
                  tooltip: 'Смотреть снова',
                  onPressed: _restartStories,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlideContainer({
    required List<Color> gradientColors,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradientColors,
        ),
      ),
      child: SafeArea(
        child: child,
      ),
    );
  }
}
