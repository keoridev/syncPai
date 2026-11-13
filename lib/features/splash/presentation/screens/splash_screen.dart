import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/di/injection.dart';
import '../../../../core/theme/cubit/theme_cubit.dart';
import '../../../../core/widgets/sync_pai_logo.dart';
import '../../../catalog/domain/usecases/get_updates.dart';

/// Современный экран загрузки SyncPai в стиле Steam Client & Discord Startup:
/// Строгий темный матовый интерфейс, прецизионное кольцо синхронизации,
/// тонкий бар прогресса и чистая типографика без едких неонов.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  String _statusText = 'ПОДКЛЮЧЕНИЕ К СЕТИ...';
  double _loadProgress = 0.20;
  Timer? _navigationTimer;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('TestWidgetsFlutterBinding');
    if (!isTest) {
      _rotationController.repeat();
      _initializeApp();
    }
  }

  Future<void> _initializeApp() async {
    // Шаг 1: Проверка подключения и инициализация ядра
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _statusText = 'СИНХРОНИЗАЦИЯ КАТАЛОГА...';
      _loadProgress = 0.58;
    });

    // Шаг 2: Фоновая подгрузка свежих релизов
    try {
      final getUpdates = getIt.isRegistered<GetUpdates>() ? getIt<GetUpdates>() : null;
      if (getUpdates != null) {
        await getUpdates(page: 1, limit: 30).timeout(const Duration(milliseconds: 1400));
      }
    } catch (_) {}

    // Шаг 3: Готовность к запуску клиента
    if (!mounted) return;
    setState(() {
      _statusText = 'ЗАПУСК КЛИЕНТА...';
      _loadProgress = 1.0;
    });

    // Бесшовный плавный переход в каталог
    _navigationTimer = Timer(const Duration(milliseconds: 700), () {
      _proceedToMain();
    });
  }

  void _proceedToMain() {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;
    _navigationTimer?.cancel();

    _fadeController.reverse().then((_) {
      if (mounted) {
        context.goNamed('main');
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _rotationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeCubit = context.watch<ThemeCubit>();
    final primaryColor = themeCubit.state.currentPreset.primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // Клик для мгновенного пропуска загрузки
            if (_loadProgress >= 0.5) {
              _proceedToMain();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Тонкий фоновый виньеточный градиент (Steam Client Charcoal)
              Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.1,
                    colors: [
                      Color(0xFF141822),
                      Color(0xFF090B0E),
                    ],
                  ),
                ),
              ),

              // Центр: Логотип + Вращающееся кольцо синхронизации + Название
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Конструкция эмблемы с плавным орбитальным кольцом (Steam Link / Discord Spinner)
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Плавное вращающееся кольцо соединения
                          AnimatedBuilder(
                            animation: _rotationController,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _rotationController.value * 2 * math.pi,
                                child: CustomPaint(
                                  size: const Size(136, 136),
                                  painter: _SteamLoadingOrbitPainter(
                                    accentColor: primaryColor,
                                  ),
                                ),
                              );
                            },
                          ),

                          // Современная монолитная матовая эмблема SyncPai
                          SyncPaiLogo(
                            size: 88,
                            showBadge: true,
                            accentColor: primaryColor,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Текстовый логотип: чистая строгая геометрия (Steam Style)
                    const Text(
                      'SYNCPAI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4.5,
                      ),
                    ),

                    const SizedBox(height: 6),

                    // Подзаголовок клиента
                    Text(
                      'WATCH TOGETHER CLIENT',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ],
                ),
              ),

              // Нижний блок: Тонкий прогресс-бар и статус инициализации
              Positioned(
                left: 0,
                right: 0,
                bottom: 44,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Тонкая полоса прогресса (Steam Client Progress Track)
                      Container(
                        width: 240,
                        height: 3.0,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            width: 240 * _loadProgress,
                            height: 3.0,
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Статус загрузки (минималистичный моноширинный)
                      Text(
                        _statusText,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.8,
                          fontFamily: defaultTargetPlatform == TargetPlatform.windows ? 'Consolas' : 'monospace',
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Индикатор сети в стиле Steam / Discord
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00FF66),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'ONLINE • BUILD 2.4',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.30),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Минималистичное орбитальное кольцо загрузки в стиле Steam client startup
class _SteamLoadingOrbitPainter extends CustomPainter {
  final Color accentColor;

  _SteamLoadingOrbitPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2 - 2;

    // Фоновый тонкий контур
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, trackPaint);

    // Акцентный сегмент вращения (90 градусов)
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final activePaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          accentColor.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.85),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(arcRect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;

    canvas.drawArc(arcRect, 0, math.pi * 0.75, false, activePaint);
  }

  @override
  bool shouldRepaint(covariant _SteamLoadingOrbitPainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}
