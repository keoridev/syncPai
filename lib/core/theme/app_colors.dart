import 'package:flutter/material.dart';

/// Дизайн-система проекта SyncPai в стиле Cinema Dark / Nordic Dark.
/// Глубокий матовый графит без ядовитого неона и кислотных контрастов.
abstract final class AppColors {
  // Фоны (Nordic / Cinema Dark)
  static const background = Color(0xFF121316);       // Глубокий матовый графит
  static const surface = Color(0xFF1A1C22);          // Карточки и контейнеры
  static const surfaceElevated = Color(0xFF242730);  // Чипсы, модальные окна, плашки
  static const surfaceHighlight = Color(0xFF2C303B); // Состояния наведения / фокуса

  // Текст и иконки
  static const textPrimary = Color(0xFFECEFF4);      // Мягкий молочно-белый
  static const textSecondary = Color(0xFF8A909E);    // Приглушенный серо-дымчатый
  static const textMuted = Color(0xFF5E6472);        // Глубокий серый (подписи, неактивные элементы)

  // Акцент (Теплый ламповый терракотово-мандариновый)
  static const primary = Color(0xFFE06C53);
  static const primaryVariant = Color(0xFFC85840);
  static const primaryLight = Color(0xFFF18A74);
  static const accentPrimary = primary;

  // Вторичный акцент (мягкий лавандово-серый индиго для тегов или вторичных индикаторов)
  static const accentSecondary = Color(0xFF7C83FD);

  // Статусы синхронизации и воспроизведения
  static const syncActive = Color(0xFF4EAA7A);       // Деликатный шалфейно-зеленый (В синхроне)
  static const syncWaiting = Color(0xFFD49B42);      // Теплый янтарный (Ожидание / буферизация друга)
  static const syncError = Color(0xFFD65C5C);        // Мягкий карминный (Рассинхрон / ошибка)

  // Разделители, границы и затемнения
  static const stroke = Color(0x0DFFFFFF);           // 5% белого (едва заметный контур)
  static const strokeMedium = Color(0x1AFFFFFF);     // 10% белого
  static const strokeHigh = Color(0x33FFFFFF);       // 20% белого
  static const overlay = Color(0x80000000);          // 50% затемнение
  static const overlaySubtle = Color(0x4D000000);    // 30% затемнение (при буферизации у друга)
  static const frostedWhite = Color(0x14FFFFFF);     // rgba(255, 255, 255, 0.08) - матовое стекло
}
