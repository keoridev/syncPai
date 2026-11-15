import 'package:supabase_flutter/supabase_flutter.dart';

/// Преобразует технические ошибки Supabase Auth (`AuthApiException`, `AuthException`)
/// и сетевые исключения в понятные дружелюбные сообщения на русском языке.
class AuthErrorFormatter {
  AuthErrorFormatter._();

  static bool isProviderDisabledError(Object error) {
    if (error is AuthApiException) {
      final code = error.code?.toLowerCase() ?? '';
      final msg = error.message.toLowerCase();
      if (code == 'validation_failed' &&
          (msg.contains('provider is not enabled') ||
              msg.contains('unsupported provider'))) {
        return true;
      }
      if (msg.contains('provider is not enabled') ||
          msg.contains('unsupported provider')) {
        return true;
      }
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('provider is not enabled') ||
        raw.contains('unsupported provider');
  }

  static bool isEmailNotConfirmedError(Object error) {
    if (error is AuthApiException) {
      final code = error.code?.toLowerCase() ?? '';
      final msg = error.message.toLowerCase();
      if (code == 'email_not_confirmed' ||
          msg.contains('email not confirmed')) {
        return true;
      }
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('email_not_confirmed') ||
        raw.contains('email not confirmed');
  }

  static String format(Object error) {
    if (isProviderDisabledError(error)) {
      return 'Вход через Google временно недоступен — используй вход по Email выше.';
    }

    if (isEmailNotConfirmedError(error)) {
      return 'Email не подтвержден. Проверь почту и перейди по ссылке в отправленном письме.';
    }

    final raw = error is AuthException ? error.message : error.toString();
    final lower = raw.toLowerCase();

    if (lower.contains('already registered') ||
        lower.contains('user already registered') ||
        lower.contains('user_already_exists')) {
      return 'Пользователь с таким email уже зарегистрирован. Переключись на «Вход».';
    }
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid_credentials')) {
      return 'Неверный email или пароль. Проверь правильность ввода.';
    }
    if (lower.contains('password should be at least') ||
        lower.contains('signup requires a valid password') ||
        lower.contains('weak_password')) {
      return 'Пароль должен содержать минимум 6 символов.';
    }
    if (lower.contains('over_email_send_rate_limit') ||
        lower.contains('rate limit') ||
        lower.contains('over_request_rate_limit')) {
      return 'Слишком много попыток. Подожди немного перед следующим запросом.';
    }
    if (lower.contains('socketexception') ||
        lower.contains('network error') ||
        lower.contains('failed host lookup') ||
        lower.contains('clientexception')) {
      return 'Ошибка сети. Проверь интернет-соединение.';
    }
    if (lower.contains('invalid email') || lower.contains('invalid_email')) {
      return 'Пожалуйста, введи корректный адрес электронной почты.';
    }

    return raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('AuthException: ', '')
        .replaceFirst('AuthApiException(', '')
        .trim();
  }
}

