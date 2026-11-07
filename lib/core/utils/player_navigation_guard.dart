import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Защита от спама и множественного параллельного запуска плеера (Debounce Guard).
/// Предотвращает случайный быстрый дабл-тап по карточкам и кнопкам,
/// блокируя создание конфликтующих инстансов MediaCodec и падение с PlayerBase::stop().
class PlayerNavigationGuard {
  static bool _isNavigating = false;
  static DateTime? _lastOpenTime;

  /// Проверяет, можно ли открыть плеер в данный момент
  static bool canOpen() {
    final now = DateTime.now();
    if (_isNavigating) return false;
    if (_lastOpenTime != null && now.difference(_lastOpenTime!).inMilliseconds < 900) {
      return false;
    }
    _isNavigating = true;
    _lastOpenTime = now;
    Future.delayed(const Duration(milliseconds: 900), () {
      _isNavigating = false;
    });
    return true;
  }

  /// Безопасный переход на экран плеера с защитой от двойного нажатия
  static void openPlayer(BuildContext context, {required Map<String, dynamic> extra}) {
    if (!canOpen()) return;
    context.pushNamed('player', extra: extra);
  }
}
