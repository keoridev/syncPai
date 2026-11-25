/// Контекстные выражения Пай-тян для живых реакций в интерфейсе.
enum MascotExpression {
  cozyNight(
    id: 'cozy_night',
    title: 'Ночной марафон',
    assetPath: 'assets/mascot/general/mascot_sleeping.png',
    defaultMessage: 'Ночной марафон? Устраивайтесь поудобнее.',
  ),
  cheering(
    id: 'cheering',
    title: 'Восторг',
    assetPath: 'assets/mascot/general/mascot_happy.png',
    defaultMessage: 'Отличный результат! Так держать.',
  ),
  speedster(
    id: 'speedster',
    title: 'Мастер перемотки',
    assetPath: 'assets/mascot/loading_success/mascot_uploading.png',
    defaultMessage: 'Молниеносный пропуск! Летим к сюжету.',
  ),
  popcornWatch(
    id: 'popcorn_watch',
    title: 'Киносеанс с друзьями',
    assetPath: 'assets/mascot/watch_party/mascot_friends_joined.png',
    defaultMessage: 'Отличная компания для просмотра!',
  ),
  curiousSearch(
    id: 'curious_search',
    title: 'Поиск годноты',
    assetPath: 'assets/mascot/empty_states/mascot_empty_search.png',
    defaultMessage: 'Ищем подходящие тайтлы...',
  ),
  proudCollector(
    id: 'proud_collector',
    title: 'Пополнение коллекции',
    assetPath: 'assets/mascot/loading_success/mascot_favorite_added.png',
    defaultMessage: 'Коллекция пополнена новым тайтлом!',
  ),
  afkDozing(
    id: 'afk_dozing',
    title: 'Режим ожидания',
    assetPath: 'assets/mascot/general/mascot_sleeping.png',
    defaultMessage: 'Режим ожидания... Коснитесь экрана, чтобы продолжить.',
  );

  final String id;
  final String title;
  final String assetPath;
  final String defaultMessage;

  const MascotExpression({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.defaultMessage,
  });

  /// Путь к манга-стилизованному ассету Пай-тян для контекста «Манга и манхва».
  String get mangaAssetPath {
    switch (this) {
      case MascotExpression.cheering:
      case MascotExpression.speedster:
      case MascotExpression.proudCollector:
        return 'assets/mascot/pai_manga_hype.png';
      case MascotExpression.curiousSearch:
        return 'assets/mascot/pai_manga_curious.png';
      case MascotExpression.cozyNight:
      case MascotExpression.afkDozing:
        return 'assets/mascot/pai_manga_sleepy.png';
      case MascotExpression.popcornWatch:
        return 'assets/mascot/pai_manga_reading.png';
    }
  }

  MascotState toMascotState() {
    switch (this) {
      case MascotExpression.cozyNight:
      case MascotExpression.afkDozing:
        return MascotState.sleeping;
      case MascotExpression.cheering:
        return MascotState.happy;
      case MascotExpression.speedster:
        return MascotState.uploading;
      case MascotExpression.popcornWatch:
        return MascotState.friendsJoined;
      case MascotExpression.curiousSearch:
        return MascotState.emptySearch;
      case MascotExpression.proudCollector:
        return MascotState.favoriteAdded;
    }
  }
}

/// Категории состояний маскота SyncPai
enum MascotCategory {
  general('Основное', 'General'),
  errors('Ошибки', 'Errors'),
  emptyStates('Пустые экраны', 'Empty States'),
  watchParty('Совместный просмотр', 'Watch Party'),
  loadingSuccess('Загрузка и Успех', 'Loading & Success'),
  winter('Новогодняя Пай-тян 2026', 'Winter Edition 2026');

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
  ),

  // F. Зимняя тема 2026 (Winter Edition)
  winterWelcome(
    id: 'winter-welcome',
    title: 'Зимнее приветствие',
    description: 'Пай-тян в шапочке Санты с новогодней улыбкой встречает пользователей.',
    category: MascotCategory.winter,
    assetPath: 'assets/mascot/winter/mascot_winter_welcome.png',
    defaultMessage: 'С наступающим Новым годом в SyncPai! ❄️',
    defaultDescription: 'Устраивайтесь поудобнее, заваривайте чай и смотрите аниме вместе.',
  ),
  winterIdle(
    id: 'winter-idle',
    title: 'Зимний уют',
    description: 'Пай-тян в праздничной шапочке отдыхает среди мягко падающих снежинок.',
    category: MascotCategory.winter,
    assetPath: 'assets/mascot/winter/mascot_winter_idle.png',
    defaultMessage: 'Зимнее настроение ❄️',
    defaultDescription: 'Идеальное время для уютного просмотра любимых тайтлов.',
  ),
  winterHappy(
    id: 'winter-happy',
    title: 'Зимний праздник',
    description: 'Восторженная новогодняя Пай-тян празднует и радуется зимней атмосфере.',
    category: MascotCategory.winter,
    assetPath: 'assets/mascot/winter/mascot_winter_happy.png',
    defaultMessage: 'Праздничное чудо!',
    defaultDescription: 'Сезон подарков, марафонов и приятных открытий.',
  ),
  winterEmpty(
    id: 'winter-empty',
    title: 'Зимняя пустота',
    description: 'Пай-тян в новогодней шапке заглядывает в открытый подарок.',
    category: MascotCategory.winter,
    assetPath: 'assets/mascot/winter/mascot_winter_empty.png',
    defaultMessage: 'Здесь пока пусто ❄️',
    defaultDescription: 'Самое время добавить первые зимние серии для просмотра.',
  ),
  winterLoading(
    id: 'winter-loading',
    title: 'Зимняя подготовка',
    description: 'Новогодняя Пай-тян готовит подарки и упаковывает серию для стрима.',
    category: MascotCategory.winter,
    assetPath: 'assets/mascot/winter/mascot_winter_loading.png',
    defaultMessage: 'Загружаем новогоднюю атмосферу...',
    defaultDescription: 'Готовим лучший видеопоток без подвисаний.',
  ),
  winterSuccess(
    id: 'winter-success',
    title: 'Зимний триумф',
    description: 'Пай-тян с праздничной лентой и поднятым пальцем вверх.',
    category: MascotCategory.winter,
    assetPath: 'assets/mascot/winter/mascot_winter_success.png',
    defaultMessage: 'Готово к празднику! ✨',
    defaultDescription: 'Все серии успешно сохранены и настроены.',
  );

  /// Семантические алиасы эмоций маскота для удобного вызова в UI
  static const MascotState sad = MascotState.emptyFavorites;
  static const MascotState surprised = MascotState.serverError;
  static const MascotState sleepy = MascotState.sleeping;
  static const MascotState excited = MascotState.friendsJoined;
  static const MascotState curious = MascotState.thinking;
  static const MascotState error = MascotState.networkError;

  /// Возвращает `sleeping` глубокой ночью (01:00–04:59), иначе `idle`
  static MascotState contextualIdle({DateTime? now}) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour >= 1 && hour < 5) {
      return MascotState.sleeping;
    }
    return MascotState.idle;
  }

  /// Преобразование базового состояния в сезонное зимнее.
  /// Важно: специфические эмоции (uploading, thinking, sleeping, emptySearch,
  /// emptyFavorites, emptyHistory, noNotifications, favoriteAdded, syncSuccess и др.)
  /// НЕ перезаписываются дефолтным зимним скином и всегда отображают свой уникальный ассет.
  MascotState toWinterState() {
    switch (this) {
      case MascotState.welcome:
        return MascotState.winterWelcome;
      case MascotState.idle:
        return MascotState.winterIdle;
      case MascotState.happy:
        return MascotState.winterHappy;
      case MascotState.emptyAnime:
        return MascotState.winterEmpty;
      case MascotState.loading:
        return MascotState.winterLoading;
      case MascotState.success:
        return MascotState.winterSuccess;
      default:
        return this;
    }
  }

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

