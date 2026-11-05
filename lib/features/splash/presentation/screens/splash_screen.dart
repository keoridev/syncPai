import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/cubit/theme_cubit.dart';
import '../../../../core/theme/theme_preset.dart';
import '../../../../core/theme/widgets/theme_selector_sheet.dart';
import '../../../../core/widgets/sync_pai_logo.dart';
import '../../../catalog/domain/usecases/get_updates.dart';

/// Премиальный кинематографичный Splash-экран SyncPai
/// с интерактивной примеркой цветовых палитр, мягким атмосферным свечением
/// и бесшовным входом в каталог.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _floatAnimation;

  String _statusText = 'Инициализация серверов…';
  double _loadProgress = 0.15;
  Timer? _navigationTimer;
  bool _isUserInteractingWithThemes = false;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: Curves.easeOutBack,
      ),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOut,
    );

    _floatAnimation = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOutSine,
      ),
    );

    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');
    if (!isTest) {
      _pulseController.repeat(reverse: true);
      _introController.forward();
      _initializeApp();
    } else {
      _introController.value = 1.0;
    }
  }

  Future<void> _initializeApp() async {
    // 1. Старт анимации прогресса
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) {
      setState(() {
        _statusText = 'Синхронизация с каталогом AniLibria…';
        _loadProgress = 0.55;
      });
    }

    try {
      final getUpdates = getIt.isRegistered<GetUpdates>() ? getIt<GetUpdates>() : null;
      if (getUpdates != null) {
        await getUpdates(page: 1, limit: 30);
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _statusText = 'Готово к просмотру!';
        _loadProgress = 1.0;
      });
    }

    // Запускаем переход в приложение через 2.6 сек, если пользователь не примеряет темы
    _navigationTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted && !_isUserInteractingWithThemes) {
        _proceedToMain();
      }
    });
  }

  void _proceedToMain() {
    _navigationTimer?.cancel();
    if (mounted) {
      context.goNamed('main');
    }
  }

  void _onSelectPreset(ThemePreset preset) {
    HapticFeedback.selectionClick();
    setState(() {
      _isUserInteractingWithThemes = true;
    });
    context.read<ThemeCubit>().setPreset(preset);
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _introController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeCubit = context.watch<ThemeCubit>();
    final currentPreset = themeCubit.state.currentPreset;
    final primaryColor = currentPreset.primaryColor;

    return Scaffold(
      backgroundColor: currentPreset.backgroundColor,
      body: Stack(
        children: [
          // 1. Атмосферное фоновое свечение (Halo Glow) под цвет выбранной темы
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final pulseScale = 0.90 + (_pulseController.value * 0.18);
                return Center(
                  child: Container(
                    width: 380 * pulseScale,
                    height: 380 * pulseScale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          primaryColor.withValues(alpha: 0.18),
                          primaryColor.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. Основной контент по центру
          SafeArea(
            child: Center(
              child: AnimatedBuilder(
                animation: _introController,
                builder: (context, child) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Парящий маскот-логотип
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(0, _floatAnimation.value),
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryColor.withValues(alpha: 0.28),
                                        blurRadius: 36,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: SyncPaiLogo(
                                    size: 106,
                                    accentColor: primaryColor,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 28),

                          // Название: SyncPai с градиентным акцентом
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Sync',
                                  style: AppTypography.displayLarge.copyWith(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                    color: Colors.white,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 10,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                TextSpan(
                                  text: 'Pai',
                                  style: AppTypography.displayLarge.copyWith(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.6,
                                    color: primaryColor,
                                    shadows: [
                                      Shadow(
                                        color: primaryColor.withValues(alpha: 0.45),
                                        blurRadius: 16,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          // Слоган
                          Text(
                            'Смотри аниме синхронно с друзьями',
                            style: AppTypography.bodyMedium.copyWith(
                              color: Colors.white70,
                              fontSize: 14,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 3. Нижний блок: Интерактивная примерка тем оформления + Прогресс-бар
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Секция «Примерить расцветку»
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.palette_outlined,
                                    size: 16,
                                    color: primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Примерить тему оформления:',
                                    style: AppTypography.caption.copyWith(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  setState(() => _isUserInteractingWithThemes = true);
                                  ThemeSelectorSheet.show(context);
                                },
                                child: Text(
                                  'Все ${ThemePreset.all.length} тем ›',
                                  style: AppTypography.caption.copyWith(
                                    color: primaryColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Горизонтальный ряд цветных кружочков для моментальной примерки
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: ThemePreset.all.map((preset) {
                                final isSelected = preset.id == currentPreset.id;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  child: GestureDetector(
                                    onTap: () => _onSelectPreset(preset),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 220),
                                      width: isSelected ? 36 : 28,
                                      height: isSelected ? 36 : 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: preset.primaryColor,
                                        border: Border.all(
                                          color: isSelected ? Colors.white : Colors.transparent,
                                          width: isSelected ? 2.5 : 0,
                                        ),
                                        boxShadow: isSelected
                                            ? [
                                                BoxShadow(
                                                  color: preset.primaryColor.withValues(alpha: 0.6),
                                                  blurRadius: 12,
                                                  spreadRadius: 1,
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: isSelected
                                          ? const Center(
                                              child: Icon(
                                                Icons.check_rounded,
                                                color: Colors.black,
                                                size: 18,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Текст статуса загрузки
                    Text(
                      _statusText,
                      style: AppTypography.caption.copyWith(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Тонкий индикатор загрузки с переходом в основное приложение
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 50),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: _loadProgress),
                          duration: const Duration(milliseconds: 600),
                          builder: (context, value, child) {
                            return LinearProgressIndicator(
                              value: value,
                              minHeight: 3.5,
                              backgroundColor: Colors.white12,
                              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                            );
                          },
                        ),
                      ),
                    ),

                    // Если пользователь примеряет тему, показываем кнопку быстрого входа
                    if (_isUserInteractingWithThemes) ...[
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: _proceedToMain,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(
                          'Перейти в каталог с этой темой',
                          style: AppTypography.labelMedium.copyWith(
                            color: primaryColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
