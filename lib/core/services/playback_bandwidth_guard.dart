import 'package:flutter/foundation.dart';

/// Глобальный флаг активности видеоплеера для эксклюзивного выделения
/// сетевой пропускной способности видеопотоку (пауза фоновых загрузок каталога и постеров).
abstract final class PlaybackBandwidthGuard {
  static final ValueNotifier<bool> isVideoPlaying = ValueNotifier<bool>(false);
}

