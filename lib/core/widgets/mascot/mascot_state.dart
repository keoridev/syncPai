/// Категории состояний маскота SyncPai
enum MascotCategory {
  general('Основное', 'General'),
  errors('Ошибки', 'Errors'),
  emptyStates('Пустые экраны', 'Empty States'),
  watchParty('Совместный просмотр', 'Watch Party'),
  loadingSuccess('Загрузка и Успех', 'Loading & Success');

  final String labelRu;
  final String labelEn;

  const MascotCategory(this.labelRu, this.labelEn);
}

/// Все 29 состояний маскота SyncPai с метаданными и путями к ассетам
enum MascotState {
  // A. Основные (General)
  welcome(
    id: 'welcome',
    title: 'Приветствие',
    description: 'Приветливая улыбка с дружеским жестом. Используется на экране входа и онбординга.',
    category: MascotCategory.general,
    assetPath: 'assets/mascot/general/mascot_welcome.png',
    defaultMessage: 'Добро пожаловать в SyncPai!',
    defaultDescription: 'Смотрите аниме синхронно вместе с друзьями.',
  ),
  idle(
    id: 'idle',
    title: 'Покой / Ожидание',
    description: 'Спокойное, дружелюбное выражение лица. Базовое состояние маскота.',
    category: MascotCategory.general,
    assetPath: 'assets/mascot/general/mascot_idle.png',
    defaultMessage: 'Готова к новым сериям',
    defaultDescription: 'Выберите любое аниме из каталога для старта.',
  ),
  happy(
    id: 'happy',
    title: 'Радость / Празднование',
    description: 'Восторженная улыбка и сияющие глаза. Отмечает успешное действие или событие.',
    category: MascotCategory.general,
    assetPath: 'assets/mascot/general/mascot_happy.png',
    defaultMessage: 'Отличная новость!',
    defaultDescription: 'Всё прошло как по маслу.',
  ),
  thinking(
    id: 'thinking',
    title: 'Размышления',
    description: 'Задумчивый вид с пальчиком у щеки. Рекомендации и подбор контента.',
    category: MascotCategory.general,
    assetPath: 'assets/mascot/general/mascot_thinking.png',
    defaultMessage: 'Подбираем для вас лучшее...',
    defaultDescription: 'Анализируем новинки и ваши любимые жанры.',
  ),
  sleeping(
    id: 'sleeping',
    title: 'Сон / AFK',
    description: 'Мирно спящая чиби с плавающими Z-Z-Z. Длительное отсутствие активности.',
    category: MascotCategory.general,
    assetPath: 'assets/mascot/general/mascot_sleeping.png',
    defaultMessage: 'Тссс... все отдыхают',
    defaultDescription: 'Здесь пока тихо и спокойно.',
  ),

  // B. Ошибки (Errors)
  error404(
    id: 'error-404',
    title: 'Страница 404',
    description: 'Озадаченная чиби с картой в руках. Заблудилась или страница не найдена.',
    category: MascotCategory.errors,
    assetPath: 'assets/mascot/errors/mascot_error_404.png',
    defaultMessage: 'Страница не найдена (404)',
    defaultDescription: 'Похоже, эта серия или страница улетела в другое измерение.',
  ),
  networkError(
    id: 'network-error',
    title: 'Сбой сети',
    description: 'Обеспокоенный взгляд на отключенный значок Wi-Fi. Потеря соединения с интернетом.',
    category: MascotCategory.errors,
    assetPath: 'assets/mascot/errors/mascot_network_error.png',
    defaultMessage: 'Нет подключения к сети',
    defaultDescription: 'Проверьте соединение с интернетом и попробуйте снова.',
  ),
  serverError(
    id: 'server-error',
    title: 'Ошибка сервера',
    description: 'Удивленный взгляд на мигающий серверный терминал с предупреждением.',
    category: MascotCategory.errors,
    assetPath: 'assets/mascot/errors/mascot_server_error.png',
    defaultMessage: 'Сервер временно недоступен',
    defaultDescription: 'Мы уже восстанавливаем связь с источниками видео.',
  ),
  timeout(
    id: 'timeout',
    title: 'Превышено время ожидания',
    description: 'Нетерпеливо поглядывает на миниатюрный секундомер. Запрос длился слишком долго.',
    category: MascotCategory.errors,
    assetPath: 'assets/mascot/errors/mascot_timeout.png',
    defaultMessage: 'Время ожидания истекло',
    defaultDescription: 'Поток загружался слишком долго. Повторите попытку.',
  ),
  accessDenied(
    id: 'access-denied',
    title: 'Доступ ограничен',
    description: 'Смущенный жест со значком замка. Требуется авторизация или особые права.',
    category: MascotCategory.errors,
    assetPath: 'assets/mascot/errors/mascot_access_denied.png',
    defaultMessage: 'Доступ ограничен',
    defaultDescription: 'Войдите в свой аккаунт SyncPai, чтобы открыть эту функцию.',
  ),
  unknownError(
    id: 'unknown-error',
    title: 'Неизвестная ошибка',
    description: 'Озадаченное лицо с летающим голографическим вопросительным знаком.',
    category: MascotCategory.errors,
    assetPath: 'assets/mascot/errors/mascot_unknown_error.png',
    defaultMessage: 'Что-то пошло не так',
    defaultDescription: 'Произошла непредвиденная ошибка. Мы уже изучаем логи.',
  ),
  maintenance(
    id: 'maintenance',
    title: 'Технические работы',
    description: 'Маскот с гаечным ключом и отверткой настраивает шестеренки.',
    category: MascotCategory.errors,
    assetPath: 'assets/mascot/errors/mascot_maintenance.png',
    defaultMessage: 'Технические работы',
    defaultDescription: 'Обновляем плеер и серверы синхронизации.',
  ),

  // C. Контент и Пустые состояния (Content / Empty)
  emptySearch(
    id: 'empty-search',
    title: 'Ничего не найдено',
    description: 'Маскот с лупой ищет аниме, но ничего не обнаружила.',
    category: MascotCategory.emptyStates,
    assetPath: 'assets/mascot/empty_states/mascot_empty_search.png',
    defaultMessage: 'Ничего не найдено',
    defaultDescription: 'Попробуйте изменить поисковый запрос или фильтры жанров.',
  ),
  emptyAnime(
    id: 'empty-anime',
    title: 'Список аниме пуст',
    description: 'Пожимает плечами перед пустым свитком каталога.',
    category: MascotCategory.emptyStates,
    assetPath: 'assets/mascot/empty_states/mascot_empty_anime.png',
    defaultMessage: 'Каталог пока пуст',
    defaultDescription: 'Тайтлы загружаются из источника, подождите минутку.',
  ),
  emptyFavorites(
    id: 'empty-favorites',
    title: 'Нет избранного',
    description: 'Слегка грустная чиби держит контур пустого сердечка.',
    category: MascotCategory.emptyStates,
    assetPath: 'assets/mascot/empty_states/mascot_empty_favorites.png',
    defaultMessage: 'В избранном пока пусто',
    defaultDescription: 'Нажмите на сердечко у любого аниме, чтобы добавить его сюда.',
  ),
  emptyHistory(
    id: 'empty-history',
    title: 'История просмотров пуста',
    description: 'Любопытно держит чистую видеокассету / дневник просмотров.',
    category: MascotCategory.emptyStates,
    assetPath: 'assets/mascot/empty_states/mascot_empty_history.png',
    defaultMessage: 'История просмотров пуста',
    defaultDescription: 'Серии, которые вы начнете смотреть, появятся прямо здесь.',
  ),
  noNotifications(
    id: 'no-notifications',
    title: 'Нет уведомлений',
    description: 'Спокойная и расслабленная чиби рядом с тихим колокольчиком.',
    category: MascotCategory.emptyStates,
    assetPath: 'assets/mascot/empty_states/mascot_no_notifications.png',
    defaultMessage: 'Нет новых уведомлений',
    defaultDescription: 'Вы в курсе всех событий и последних серий.',
  ),

  // D. Совместный просмотр (Watch Party / Social)
  creatingRoom(
    id: 'creating-room',
    title: 'Создание комнаты',
    description: 'Держит светящийся ключ-Play перед порталом комнаты просмотра.',
    category: MascotCategory.watchParty,
    assetPath: 'assets/mascot/watch_party/mascot_creating_room.png',
    defaultMessage: 'Создаем комнату для вас...',
    defaultDescription: 'Генерируем защищенный PIN-код и резервируем слот синхронизации.',
  ),
  waitingFriends(
    id: 'waiting-friends',
    title: 'Ожидание друзей',
    description: 'Сидит у виртуальной двери лобби, с надеждой поглядывая на время.',
    category: MascotCategory.watchParty,
    assetPath: 'assets/mascot/watch_party/mascot_waiting_friends.png',
    defaultMessage: 'Ждем подключения друга...',
    defaultDescription: 'Поделитесь кодом комнаты или QR-кодом с другом.',
  ),
  friendsJoined(
    id: 'friends-joined',
    title: 'Друзья подключились!',
    description: 'Праздничный восторг с поднятыми руками под конфетти.',
    category: MascotCategory.watchParty,
    assetPath: 'assets/mascot/watch_party/mascot_friends_joined.png',
    defaultMessage: 'Все в сборе!',
    defaultDescription: 'Друг присоединился. Нажмите «Старт» для одновременного просмотра.',
  ),
  syncing(
    id: 'syncing',
    title: 'Синхронизация потоков',
    description: 'Прижимает ладони к наушникам, вокруг пульсируют бирюзовые и коралловые волны.',
    category: MascotCategory.watchParty,
    assetPath: 'assets/mascot/watch_party/mascot_syncing.png',
    defaultMessage: 'Синхронизируем таймлайн...',
    defaultDescription: 'Выравниваем миллисекунды между вашими плеерами.',
  ),
  syncSuccess(
    id: 'sync-success',
    title: 'Синхронизация успешна',
    description: 'Победный жест V-sign двумя руками, идеально совмещенный значок воспроизведения.',
    category: MascotCategory.watchParty,
    assetPath: 'assets/mascot/watch_party/mascot_sync_success.png',
    defaultMessage: 'Синхронизация идеальна!',
    defaultDescription: 'Плееры воспроизводятся кадр-в-кадр.',
  ),
  friendDisconnected(
    id: 'friend-disconnected',
    title: 'Друг отключился',
    description: 'Сочувственный взгляд на разомкнувшийся неоновый кабель связи.',
    category: MascotCategory.watchParty,
    assetPath: 'assets/mascot/watch_party/mascot_friend_disconnected.png',
    defaultMessage: 'Связь с другом потеряна',
    defaultDescription: 'Воспроизведение временно приостановлено, ждем повторного входа.',
  ),
  inviteFriends(
    id: 'invite-friends',
    title: 'Пригласить друзей',
    description: 'Подмигивает и протягивает стильный неоновый билет в кинозал.',
    category: MascotCategory.watchParty,
    assetPath: 'assets/mascot/watch_party/mascot_invite_friends.png',
    defaultMessage: 'Позовите друзей!',
    defaultDescription: 'Вместе смотреть серии в разы интереснее.',
  ),

  // E. Загрузка и Успех (Loading & Success)
  loading(
    id: 'loading',
    title: 'Загрузка...',
    description: 'Любопытно раскручивает неоновое колесо буферизации как хулахуп.',
    category: MascotCategory.loadingSuccess,
    assetPath: 'assets/mascot/loading_success/mascot_loading.png',
    defaultMessage: 'Загружаем контент...',
    defaultDescription: 'Секундочку, готовим видеопоток в наилучшем качестве.',
  ),
  uploading(
    id: 'uploading',
    title: 'Отправка данных',
    description: 'Усердно толкает вверх светящуюся неоновую стрелку в облако.',
    category: MascotCategory.loadingSuccess,
    assetPath: 'assets/mascot/loading_success/mascot_uploading.png',
    defaultMessage: 'Отправка данных...',
    defaultDescription: 'Сохраняем ваш прогресс и списки в облако.',
  ),
  success(
    id: 'success',
    title: 'Успешно выполнено',
    description: 'Уверенно показывает большой палец вверх (thumbs up) со сверкающими искрами.',
    category: MascotCategory.loadingSuccess,
    assetPath: 'assets/mascot/loading_success/mascot_success.png',
    defaultMessage: 'Всё готово!',
    defaultDescription: 'Операция успешно завершена.',
  ),
  favoriteAdded(
    id: 'favorite-added',
    title: 'Добавлено в любимое',
    description: 'Нежно обнимает светящееся коралловое сердечко с румянцем на щечках.',
    category: MascotCategory.loadingSuccess,
    assetPath: 'assets/mascot/loading_success/mascot_favorite_added.png',
    defaultMessage: 'Тайтл добавлен в избранное ❤️',
    defaultDescription: 'Теперь вы не пропустите выход новых серий и озвучек.',
  ),
  profile(
    id: 'profile',
    title: 'Профиль / Портрет',
    description: 'Дружелюбный чиби-портрет крупным планом для карточек профиля и аватара.',
    category: MascotCategory.loadingSuccess,
    assetPath: 'assets/mascot/loading_success/mascot_profile.png',
    defaultMessage: 'Ваш спутник SyncPai',
    defaultDescription: 'Персонаж-компаньон для просмотра аниме.',
  );

  final String id;
  final String title;
  final String description;
  final MascotCategory category;
  final String assetPath;
  final String defaultMessage;
  final String defaultDescription;

  const MascotState({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.assetPath,
    required this.defaultMessage,
    required this.defaultDescription,
  });

  /// Поиск состояния по строковому идентификатору (e.g. 'network-error', 'error-404')
  static MascotState fromId(String id, {MascotState fallback = MascotState.idle}) {
    final cleanId = id.trim().toLowerCase().replaceAll('_', '-');
    for (final state in MascotState.values) {
      if (state.id == cleanId || state.name.toLowerCase() == cleanId) {
        return state;
      }
    }
    return fallback;
  }
}
