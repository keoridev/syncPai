import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sync_pai_logo.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

/// Полноценный кинематографичный экран авторизации (AuthScreen)
/// в тёмной аниме-эстетике с поддержкой Email/Password, Google Sign-In
/// и гостевого режима.
class AuthScreen extends StatefulWidget {
  final VoidCallback? onAuthSuccess;

  const AuthScreen({super.key, this.onAuthSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailAuth() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final cubit = context.read<AuthCubit>();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final isRegister = _tabController.index == 1;

    try {
      if (isRegister) {
        final username = _usernameController.text.trim();
        await cubit.signUpWithEmail(
          email: email,
          password: password,
          username: username.isNotEmpty ? username : null,
        );
      } else {
        await cubit.signInWithEmail(
          email: email,
          password: password,
        );
      }

      if (mounted) {
        widget.onAuthSuccess?.call();
        context.goNamed('main');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final cubit = context.read<AuthCubit>();
      await cubit.signInWithGoogle();

      if (mounted) {
        widget.onAuthSuccess?.call();
        context.goNamed('main');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка Google Sign-In: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _continueAsGuest() {
    FocusScope.of(context).unfocus();
    widget.onAuthSuccess?.call();
    context.goNamed('main');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          widget.onAuthSuccess?.call();
          context.goNamed('main');
        } else if (state is AuthError) {
          setState(() {
            _errorMessage = state.message;
            _isLoading = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0C0E14),
        body: Stack(
          children: [
            // 1. Атмосферное фоновое неоновое свечение
            Positioned(
              top: -80,
              right: -80,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      accent.withValues(alpha: 0.22),
                      accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -60,
              left: -60,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // 2. Основной контент
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Логотип SyncPai
                        Hero(
                          tag: 'sync_pai_logo',
                          child: SyncPaiLogo(size: 72, accentColor: accent),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'SyncPai',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Смотрите аниме синхронно с друзьями',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Карточка в стиле матового стекла
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: const Color(0xFF161822).withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 30,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // Переключатель «Вход / Регистрация»
                                    Container(
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.35),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                      ),
                                      child: TabBar(
                                        controller: _tabController,
                                        indicatorSize: TabBarIndicatorSize.tab,
                                        indicator: BoxDecoration(
                                          color: accent,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        labelColor: Colors.white,
                                        unselectedLabelColor: AppColors.textSecondary,
                                        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                        tabs: const [
                                          Tab(text: 'Вход'),
                                          Tab(text: 'Регистрация'),
                                        ],
                                        onTap: (_) => setState(() => _errorMessage = null),
                                      ),
                                    ),
                                    const SizedBox(height: 20),

                                    // Поле никнейма (только при регистрации)
                                    AnimatedBuilder(
                                      animation: _tabController,
                                      builder: (context, _) {
                                        if (_tabController.index == 1) {
                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: TextFormField(
                                              controller: _usernameController,
                                              style: const TextStyle(color: Colors.white, fontSize: 14),
                                              cursorColor: accent,
                                              decoration: _buildInputDecoration(
                                                label: 'Никнейм в приложении',
                                                hint: 'Например: Теневой Монарх',
                                                icon: Icons.person_outline_rounded,
                                                accent: accent,
                                              ),
                                              validator: (val) {
                                                if (_tabController.index == 1 &&
                                                    (val == null || val.trim().isEmpty)) {
                                                  return 'Укажите ваш никнейм';
                                                }
                                                return null;
                                              },
                                            ),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),

                                    // Поле Email
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                      cursorColor: accent,
                                      decoration: _buildInputDecoration(
                                        label: 'Email',
                                        hint: 'you@example.com',
                                        icon: Icons.alternate_email_rounded,
                                        accent: accent,
                                      ),
                                      validator: (val) {
                                        if (val == null || val.trim().isEmpty) {
                                          return 'Введите email';
                                        }
                                        if (!val.contains('@') || !val.contains('.')) {
                                          return 'Некорректный email';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 12),

                                    // Поле Пароль
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                      cursorColor: accent,
                                      decoration: _buildInputDecoration(
                                        label: 'Пароль',
                                        hint: '••••••••',
                                        icon: Icons.lock_outline_rounded,
                                        accent: accent,
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword
                                                ? Icons.visibility_outlined
                                                : Icons.visibility_off_outlined,
                                            color: AppColors.textSecondary,
                                            size: 18,
                                          ),
                                          onPressed: () {
                                            setState(() => _obscurePassword = !_obscurePassword);
                                          },
                                        ),
                                      ),
                                      validator: (val) {
                                        if (val == null || val.trim().length < 6) {
                                          return 'Минимум 6 символов';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),

                                    // Ошибка
                                    if (_errorMessage != null) ...[
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: AppColors.syncError.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: AppColors.syncError.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.error_outline_rounded,
                                                color: AppColors.syncError, size: 18),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _errorMessage!,
                                                style: const TextStyle(color: AppColors.syncError, fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                    ],

                                    // Кнопка входа по Email
                                    SizedBox(
                                      height: 46,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: accent,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          elevation: 0,
                                        ),
                                        onPressed: _isLoading ? null : _submitEmailAuth,
                                        child: _isLoading
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation(Colors.white),
                                                ),
                                              )
                                            : AnimatedBuilder(
                                                animation: _tabController,
                                                builder: (context, _) => Text(
                                                  _tabController.index == 0
                                                      ? 'Войти в аккаунт'
                                                      : 'Создать аккаунт',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14.5,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),

                                    // Разделитель «ИЛИ»
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            height: 1,
                                            color: Colors.white.withValues(alpha: 0.1),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          child: Text(
                                            'ИЛИ',
                                            style: TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            height: 1,
                                            color: Colors.white.withValues(alpha: 0.1),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),

                                    // БОЛЬШАЯ КНОПКА GOOGLE SIGN-IN
                                    SizedBox(
                                      height: 48,
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          backgroundColor: Colors.white.withValues(alpha: 0.05),
                                          side: BorderSide(
                                            color: Colors.white.withValues(alpha: 0.22),
                                            width: 1.2,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            // Логотип Google
                                            Container(
                                              width: 22,
                                              height: 22,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  'G',
                                                  style: TextStyle(
                                                    color: Colors.blue.shade700,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text(
                                              'Войти через Google',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 22),

                        // Кнопка продолжить как гость
                        TextButton(
                          onPressed: _continueAsGuest,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Продолжить как гость',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, size: 16),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    required Color accent,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.white70, size: 19),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.25),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.syncError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.syncError, width: 1.5),
      ),
    );
  }
}

