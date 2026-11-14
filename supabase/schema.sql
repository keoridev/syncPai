-- ==============================================================================
-- SyncPai: Схема базы данных для Supabase (PostgreSQL)
-- Таблицы профилей, списков аниме, RLS политики и Realtime
-- ==============================================================================

-- 1. Таблица профилей пользователей (profiles)
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  username text not null default 'Анимешник',
  avatar_url text default '🐱',
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Включаем Row Level Security (RLS) для профилей
alter table public.profiles enable row level security;

create policy "Public profiles are viewable by everyone" 
  on public.profiles for select 
  using (true);

create policy "Users can insert their own profile" 
  on public.profiles for insert 
  with check (auth.uid() = id);

create policy "Users can update their own profile" 
  on public.profiles for update 
  using (auth.uid() = id);

-- 2. Таблица списков аниме пользователя (user_anime_lists)
-- Хранит списки: watching (смотрю), planned (в планах), completed (просмотрено), dropped (брошено)
create table if not exists public.user_anime_lists (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users on delete cascade not null,
  anime_id int not null,
  title_ru text not null,
  poster_url text,
  status text check (status in ('watching', 'planned', 'completed', 'dropped')) not null default 'watching',
  last_episode int default 1,
  position_ms bigint default 0,
  episodes_total int,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(user_id, anime_id)
);

-- Включаем Row Level Security (RLS) для списков аниме
alter table public.user_anime_lists enable row level security;

create policy "Users can only view and manage their own anime lists" 
  on public.user_anime_lists for all 
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 3. Индексы для сверхбыстрого чтения и сортировки
create index if not exists idx_user_anime_lists_user_status 
  on public.user_anime_lists (user_id, status);

create index if not exists idx_user_anime_lists_updated 
  on public.user_anime_lists (user_id, updated_at desc);

-- 4. Включение Realtime для таблицы списков (чтобы изменения сразу прилетали на все девайсы)
alter publication supabase_realtime add table public.user_anime_lists;

-- ==============================================================================
-- 5. Таблица кэшированного каталога аниме (anime_catalog)
-- Обеспечивает моментальную загрузку каталога во Flutter без внешних API
-- ==============================================================================
create table if not exists public.anime_catalog (
  id uuid default gen_random_uuid() primary key,
  shikimori_id int not null unique,
  title_ru text not null default '',
  title_en text not null default '',
  poster_url text,
  kind text, -- 'tv', 'movie', 'ova', 'ona', 'special'
  status text not null default 'ongoing', -- 'ongoing', 'released'
  score numeric(3, 1) default 0.0,
  episodes_total int default 0,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Индексы для сверхбыстрой фильтрации и сортировки каталога
create index if not exists idx_anime_catalog_status on public.anime_catalog (status);
create index if not exists idx_anime_catalog_score on public.anime_catalog (score desc);
create index if not exists idx_anime_catalog_shikimori_id on public.anime_catalog (shikimori_id);

-- RLS для anime_catalog: публичный просмотр
alter table public.anime_catalog enable row level security;

create policy "Public catalog is viewable by everyone" 
  on public.anime_catalog for select 
  using (true);

create policy "Service role can manage anime catalog" 
  on public.anime_catalog for all 
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- Включение Realtime для каталога
alter publication supabase_realtime add table public.anime_catalog;

-- ==============================================================================
-- 6. Таблица аниме-моментов (anime_moments) для ленты Shorts / Reels
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

create index if not exists idx_anime_moments_anime_id on public.anime_moments (anime_id);
create index if not exists idx_anime_moments_created_at on public.anime_moments (created_at desc);

alter table public.anime_moments enable row level security;

create policy "Public moments are viewable by everyone" 
  on public.anime_moments for select 
  using (true);

create policy "Service role can manage anime moments" 
  on public.anime_moments for all 
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

alter publication supabase_realtime add table public.anime_moments;

-- ==============================================================================
-- 7. Таблица комнат совместного просмотра (rooms)
-- Обеспечивает создание, поиск и подключение друзей через Supabase Realtime
-- ==============================================================================
create table if not exists public.rooms (
  id text primary key,                    -- Код комнаты: 'SP-123456'
  host_name text not null default 'Хост',
  peer_name text,                         -- Имя подключенного гостя
  guest_name text,                        -- Alias для peer_name (совместимость)
  status text not null default 'waiting'  -- 'waiting', 'connected', 'playing', 'closed'
    check (status in ('waiting', 'connected', 'playing', 'closed')),
  title_id int,                           -- ID тайтла AniLibria (опционально)
  title_name text,                        -- Название тайтла (кэш для быстрого показа)
  episode int default 1,                  -- Номер серии
  quality text default 'HD',              -- Качество воспроизведения
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create index if not exists idx_rooms_status on public.rooms (status);
create index if not exists idx_rooms_created_at on public.rooms (created_at desc);

alter table public.rooms enable row level security;

-- Безопасное переопределение политик RLS для публичного и гостевого доступа (anon, authenticated)
drop policy if exists "Anyone can view rooms" on public.rooms;
drop policy if exists "Allow public read rooms" on public.rooms;
create policy "Allow public read rooms"
  on public.rooms for select
  to anon, authenticated
  using (true);

drop policy if exists "Anyone can create rooms" on public.rooms;
drop policy if exists "Allow public insert rooms" on public.rooms;
create policy "Allow public insert rooms"
  on public.rooms for insert
  to anon, authenticated
  with check (true);

drop policy if exists "Anyone can update rooms" on public.rooms;
drop policy if exists "Allow public update rooms" on public.rooms;
create policy "Allow public update rooms"
  on public.rooms for update
  to anon, authenticated
  using (true)
  with check (true);

alter publication supabase_realtime add table public.rooms;

-- ==============================================================================
-- 8. Расширение схемы под Wrapped 2026, Winter Theme, Друзей и Отзывы
-- ==============================================================================

-- 8.1. Расширяем profiles (Steam-профиль, уровень, настройки зимней темы)
alter table public.profiles
  add column if not exists tag text default '#0001',
  add column if not exists bio text default 'В поисках годноты',
  add column if not exists xp int not null default 0,
  add column if not exists showcase_art_url text,
  add column if not exists favorite_anime_id int,
  add column if not exists winter_theme_enabled boolean not null default true,
  add column if not exists winter_snow_enabled boolean not null default true,
  add column if not exists winter_mascot_enabled boolean not null default true,
  add column if not exists last_seen_at timestamp with time zone default timezone('utc'::text, now());

-- 8.2. Расширяем user_anime_lists для точной аналитики Wrapped 2026 (без накрутки)
alter table public.user_anime_lists
  add column if not exists genres text[] default '{}',
  add column if not exists total_watched_ms bigint not null default 0,
  add column if not exists rewatch_count int not null default 0,
  add column if not exists completed_at timestamp with time zone;

-- 8.3. Лог сессий просмотра (для графиков по дням недели и Wrapped 2026)
create table if not exists public.watch_sessions (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users on delete cascade not null,
  anime_id int not null,
  episode int not null default 1,
  watched_ms bigint not null default 0 check (watched_ms >= 0 and watched_ms <= 14400000), -- защита от фейковых 999 часов
  room_id text, -- заполнено, если смотрели в комнате с друзьями
  watched_at timestamp with time zone default timezone('utc'::text, now()) not null
);

create index if not exists idx_watch_sessions_user_date on public.watch_sessions (user_id, watched_at desc);
alter table public.watch_sessions enable row level security;

drop policy if exists "Users manage own watch sessions" on public.watch_sessions;
create policy "Users manage own watch sessions"
  on public.watch_sessions for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 8.4. Дополняем rooms полями синхронизации плеера
alter table public.rooms
  add column if not exists host_id uuid references auth.users on delete set null,
  add column if not exists current_position_ms bigint not null default 0,
  add column if not exists is_playing boolean not null default false;

-- 8.5. Таблица друзей (убираем моковых Akira_99 и Sakura_Chan)
create table if not exists public.friendships (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.profiles(id) on delete cascade not null,
  friend_id uuid references public.profiles(id) on delete cascade not null,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'blocked')),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(user_id, friend_id),
  check (user_id <> friend_id)
);

create index if not exists idx_friendships_user on public.friendships (user_id, status);
alter table public.friendships enable row level security;

drop policy if exists "Users can view their friendships" on public.friendships;
create policy "Users can view their friendships"
  on public.friendships for select
  using (auth.uid() = user_id or auth.uid() = friend_id);

drop policy if exists "Users can manage their friendships" on public.friendships;
create policy "Users can manage their friendships"
  on public.friendships for all
  using (auth.uid() = user_id or auth.uid() = friend_id)
  with check (auth.uid() = user_id);

-- 8.6. Нативные отзывы на аниме + стена профиля
create table if not exists public.anime_reviews (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.profiles(id) on delete cascade not null,
  anime_id int not null,
  score int not null check (score between 1 and 10),
  content text not null check (char_length(content) between 3 and 4000),
  contains_spoiler boolean not null default false,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  unique(user_id, anime_id)
);

create index if not exists idx_anime_reviews_anime on public.anime_reviews (anime_id, created_at desc);
alter table public.anime_reviews enable row level security;

drop policy if exists "Public can read anime reviews" on public.anime_reviews;
create policy "Public can read anime reviews"
  on public.anime_reviews for select using (true);

drop policy if exists "Users can write own anime reviews" on public.anime_reviews;
create policy "Users can write own anime reviews"
  on public.anime_reviews for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 8.7. Удаленный конфиг приложения (даты Winter Theme и релиза Wrapped 2026)
create table if not exists public.app_config (
  key text primary key,
  value jsonb not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

alter table public.app_config enable row level security;
drop policy if exists "Public can read app_config" on public.app_config;
create policy "Public can read app_config" on public.app_config for select using (true);

insert into public.app_config (key, value) values
  ('winter_2026', '{"enabled": true, "start": "2026-12-01T00:00:00Z", "end": "2027-01-15T23:59:59Z"}'::jsonb),
  ('wrapped_2026', '{"release_at": "2026-12-31T00:00:00Z", "force_unlock": false}'::jsonb)
on conflict (key) do nothing;

-- 8.8. Безопасное добавление новых таблиц в Realtime без дубликатов
do $$
begin
  alter publication supabase_realtime add table public.friendships;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.anime_reviews;
exception when duplicate_object then null;
end $$;



