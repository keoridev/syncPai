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

