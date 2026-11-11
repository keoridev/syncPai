-- ==============================================================================
-- SyncPai: Таблица аниме-моментов (Shorts/Reels) и стартовые записи
-- ==============================================================================

create table if not exists public.anime_moments (
  id uuid default gen_random_uuid() primary key,
  anime_id text not null,       -- AniLibria ID для перехода к просмотру
  title text not null default '',         -- Название аниме
  description text not null default '',   -- Описание момента
  episode int not null default 1,         -- Номер серии
  start_timestamp int not null default 0, -- Таймкод момента в секундах
  video_url text not null default '',     -- Прямой URL к оптимизированному MP4 или HLS
  youtube_id text,                        -- Исходный ID YouTube Shorts
  likes_count int not null default 0,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Индексы для сверхбыстрой выборки и сортировки
create index if not exists idx_anime_moments_anime_id on public.anime_moments (anime_id);
create index if not exists idx_anime_moments_created_at on public.anime_moments (created_at desc);

-- RLS: публичное чтение
alter table public.anime_moments enable row level security;

create policy "Public moments are viewable by everyone" 
  on public.anime_moments for select 
  using (true);

create policy "Service role can manage anime moments" 
  on public.anime_moments for all 
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- Включение Realtime
alter publication supabase_realtime add table public.anime_moments;

-- Стартовые культовые моменты аниме (12 записей)
insert into public.anime_moments (anime_id, title, description, episode, start_timestamp, video_url, youtube_id, likes_count)
values
  (
    '8789',
    'Магическая битва 2',
    '⚡ Битва титанов в Сибуе: Король проклятий Сукуна раскрывает истинное пламя против генерала Махораги.',
    17,
    860,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    '0kFhyjHhQ9g',
    35190
  ),
  (
    '10344',
    'Поднятие уровня в одиночку',
    'Кульминация сезона! Сон Джин-ву произносит заветное «Восстань» и подчиняет тень рыцаря Игриса.',
    12,
    1115,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    '9g0H2gKqQ5Y',
    28420
  ),
  (
    '8542',
    'Клинок, рассекающий демонов: Квартал красных фонарей',
    '🔥 Невероятный финал битвы против Гютаро: Тандзиро и Удзуй Тенген на пределе человеческих возможностей.',
    10,
    780,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'vGQP_Fkhnfg',
    42150
  ),
  (
    '9380',
    'Провожающая в последний путь Фрирен',
    '✨ Высшая магия тысячелетней эльфийки: Фрирен снимает печать со своей колоссальной маны.',
    26,
    940,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'Q1N5Wd9_n58',
    19800
  ),
  (
    '8500',
    'Атака титанов: Финал',
    'Начало Гула Земли: Колоссальные титаны пробуждаются и начинают марш свободы.',
    28,
    1020,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'M_OauHnAFc8',
    38900
  ),
  (
    '8490',
    'Человек-бензопила',
    'Рев бензопилы на крыше поезда: Дэндзи против Самурайского меча.',
    12,
    660,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'dFlDRhvM4L0',
    21450
  ),
  (
    '8100',
    'Киберпанк: Бегущие по краю',
    'Дэвид Мартинес активирует Сандевистан в первый раз. Вспышка адреналина в Найт-Сити.',
    4,
    540,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'BnnbP7pCIvQ',
    17300
  ),
  (
    '9120',
    'Блич: Тысячелетняя кровавая война',
    'Занка но Тачи: Главнокомандующий Ямамото раскрывает свой испепеляющий Банкай.',
    6,
    810,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'yRj7V_d4uP0',
    25900
  ),
  (
    '8920',
    'Ван-Пис',
    'Барабаны освобождения: Луффи пробуждает Gear 5 и смеется в лицо Кайдо.',
    1071,
    720,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'q_HhB8pQvXg',
    49300
  ),
  (
    '9410',
    'Реинкарнация безработного 2',
    'Рудеус Грейрат призывает разрушительное заклинание молнии Кумулонимбус.',
    11,
    590,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'L3j9F8v_c8Y',
    14800
  ),
  (
    '8830',
    'Семья шпиона',
    'Элегантность превыше всего: Аня Форджер спасает ситуацию в школе Эдем.',
    5,
    420,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'dQw4w9WgXcQ',
    31200
  ),
  (
    '10210',
    'Дандадан',
    'Сверхскоростная погоня: Турбо-бабка против Момо и Окаруна.',
    3,
    650,
    'https://cache-rfn.libria.fun/videos/media/ts/10344/1/720/0b3818c221192a39044eb9156d648f1a.m3u8',
    'kJQP7kiw5Fk',
    22700
  )
on conflict do nothing;

