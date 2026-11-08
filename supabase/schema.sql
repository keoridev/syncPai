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


