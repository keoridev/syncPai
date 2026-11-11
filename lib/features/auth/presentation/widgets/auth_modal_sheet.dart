import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/user_profile.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

/// Модальное окно входа и регистрации с сохранением и бесшовным переносом данных
class AuthModalSheet extends StatefulWidget {
  final UserProfile currentProfile;

  const AuthModalSheet({super.key, required this.currentProfile});

  static Future<void> show(BuildContext context, UserProfile currentProfile) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => AuthModalSheet(currentProfile: currentProfile),
    );
  }

  @override
  State<AuthModalSheet> createState() => _AuthModalSheetState();
}

class _AuthModalSheetState extends State<AuthModalSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late TextEditingController _usernameController;

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() => _errorMessage = null);
    });

    final defaultNick = widget.currentProfile.username.startsWith('Сенпай #')
        ? ''
        : widget.currentProfile.username;
    _usernameController = TextEditingController(text: defaultNick);
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final isRegister = _tabController.index == 1;
      if (isRegister) {
        await context.read<AuthCubit>().signUpWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
              username: _usernameController.text.trim().isNotEmpty
                  ? _usernameController.text.trim()
                  : null,
            );
      } else {
        await context.read<AuthCubit>().signInWithEmail(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRegister
                  ? '✨ Аккаунт создан! Профиль, арты и закладки перенесены.'
                  : '✨ Вход выполнен успешно!',
            ),
            backgroundColor: AppColors.syncActive,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _parseErrorMessage(e.toString());
          _isLoading = false;
        });
      }
    }
  }

  String _parseErrorMessage(String raw) {
    if (raw.contains('already registered') || raw.contains('User already registered')) {
      return 'Пользователь с таким email уже зарегистрирован. Переключитесь на «Вход».';
    }
    if (raw.contains('Invalid login credentials') || raw.contains('invalid_credentials')) {
      return 'Неверный email или пароль. Проверьте правильность ввода.';
    }
    if (raw.contains('Password should be at least') || raw.contains('Signup requires a valid password')) {
      return 'Пароль должен содержать минимум 6 символов.';
    }
    if (raw.contains('Email not confirmed')) {
      return 'Email не подтвержден. Пожалуйста, перейдите по ссылке в отправленном письме.';
    }
    if (raw.contains('over_email_send_rate_limit') || raw.contains('rate limit')) {
      return 'Слишком много попыток. Пожалуйста, подождите немного.';
    }
    if (raw.contains('SocketException') || raw.contains('Network error') || raw.contains('Failed host lookup')) {
      return 'Ошибка сети. Проверьте интернет-соединение.';
    }
    if (raw.contains('Invalid email') || raw.contains('invalid_email')) {
      return 'Пожалуйста, введите корректный адрес электронной почты.';
    }
    return raw.replaceFirst('Exception: ', '').replaceFirst('AuthException: ', '');
  }

  Future<void> _handleGoogleAuth() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await context.read<AuthCubit>().signInWithGoogle();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ Профиль успешно синхронизирован с Google!'),
            backgroundColor: AppColors.syncActive,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showDirectGoogleLinkDialog();
      }
    }
  }

  void _showDirectGoogleLinkDialog() {
    final googleEmailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                'G',
                style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Привязка Google',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Укажите ваш Google Email для привязки. Все ваши кастомные арты, оформление, списки и никнейм будут сохранены!',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: googleEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'name@gmail.com',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                prefixIcon: const Icon(Icons.alternate_email_rounded, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.strokeMedium),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Отмена', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = googleEmailCtrl.text.trim();
              if (email.isEmpty || !email.contains('@')) return;
              Navigator.of(dialogCtx).pop();
              if (!mounted) return;
              setState(() => _isLoading = true);
              try {
                await context.read<AuthCubit>().linkGoogleAccount(
                      email: email,
                      displayName: widget.currentProfile.username,
                      photoUrl: widget.currentProfile.avatarUrl,
                    );
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✨ Google аккаунт ($email) успешно привязан! Все данные сохранены.'),
                      backgroundColor: AppColors.syncActive,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _errorMessage = 'Ошибка привязки: $e';
                    _isLoading = false;
                  });
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Привязать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthError && mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = state.message;
          });
        }
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spacingXl),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.strokeMedium,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Заголовок
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.cloud_sync_rounded,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Синхронизация профиля',
                              style: AppTypography.titleLarge.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Сохраните свой арт, списки и статус в облаке',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Баннер гарантии сохранения кастомизации
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.12),
                          const Color(0xFF00E5FF).withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          color: AppColors.primaryLight,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ваш текущий кастомный арт, рамка, никнейм и история просмотра сохранятся и привяжутся к новому аккаунту!',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textPrimary,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Табы: Вход / Регистрация
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.strokeMedium),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textSecondary,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                      tabs: const [
                        Tab(text: 'Вход'),
                        Tab(text: 'Регистрация'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Ошибка если есть
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.syncError.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.syncError.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: AppColors.syncError, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Поле: Никнейм (только при регистрации)
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      if (_tabController.index == 0) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Никнейм в приложении',
                              style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _usernameController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Например: Тень Монарха',
                              hintStyle: const TextStyle(color: AppColors.textMuted),
                              prefixIcon: const Icon(Icons.person_outline_rounded,
                                  color: AppColors.textSecondary),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.strokeMedium),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.strokeMedium),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      );
                    },
                  ),

                  // Поле: Email
                  Text('Email',
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Введите email';
                      if (!v.contains('@') || !v.contains('.')) return 'Некорректный email';
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: 'name@example.com',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.alternate_email_rounded,
                          color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.strokeMedium),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.strokeMedium),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Поле: Пароль
                  Text('Пароль',
                      style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    validator: (v) {
                      if (v == null || v.length < 6) {
                        return 'Пароль должен быть не менее 6 символов';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.lock_outline_rounded,
                          color: AppColors.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.strokeMedium),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppColors.strokeMedium),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Поле: Повтор пароля (при регистрации)
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      if (_tabController.index == 0) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Повторите пароль',
                              style: AppTypography.caption.copyWith(color: AppColors.textMuted)),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white),
                            validator: (v) {
                              if (_tabController.index == 1 && v != _passwordController.text) {
                                return 'Пароли не совпадают';
                              }
                              return null;
                            },
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              hintStyle: const TextStyle(color: AppColors.textMuted),
                              prefixIcon: const Icon(Icons.lock_reset_rounded,
                                  color: AppColors.textSecondary),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.strokeMedium),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(color: AppColors.strokeMedium),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // Основная кнопка отправки
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : AnimatedBuilder(
                            animation: _tabController,
                            builder: (context, _) => Text(
                              _tabController.index == 0
                                  ? 'Войти в аккаунт'
                                  : 'Зарегистрироваться и перенести профиль',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                  ),

                  const SizedBox(height: 14),

                  // Разделитель «или»
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.strokeMedium)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'ИЛИ',
                          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                      const Expanded(child: Divider(color: AppColors.strokeMedium)),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Кнопка Google
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleGoogleAuth,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.strokeMedium, width: 1.2),
                      backgroundColor: AppColors.surface,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'G',
                        style: TextStyle(
                          color: Color(0xFF4285F4),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    label: const Text(
                      'Продолжить через Google',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

