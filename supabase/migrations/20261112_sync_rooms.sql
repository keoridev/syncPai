-- ==============================================================================
-- SyncPai: Таблица комнат совместного просмотра (public.rooms)
-- Обеспечивает создание по 6-значному PIN-коду и синхронизацию плеера
-- ==============================================================================

-- 1. Таблица комнат совместного просмотра
create table if not exists public.rooms (
  id text primary key,                    -- 6-значный строковый PIN-код (например, '491023')
  anime_id text not null,                 -- ID тайтла AniLibria
  anime_title text,                       -- Название тайтла
  poster_url text,                        -- Ссылка на постер тайтла
  episode_index int4 default 0,           -- Номер серии
  current_time_sec float8 default 0.0,    -- Текущий таймкод плеера (сек)
  is_playing bool default false,          -- Флаг воспроизведения
  host_id uuid,                           -- UUID хоста (nullable)
  created_at timestamptz default timezone('utc'::text, now()) not null
);

-- 2. Индексы для быстрого поиска
create index if not exists idx_rooms_created_at on public.rooms (created_at desc);

-- 3. RLS: любой может видеть, создавать и обновлять комнаты (включая anon)
alter table public.rooms enable row level security;

drop policy if exists "Anyone can view rooms" on public.rooms;
create policy "Anyone can view rooms"
  on public.rooms for select
  to anon, authenticated
  using (true);

drop policy if exists "Anyone can create rooms" on public.rooms;
create policy "Anyone can create rooms"
  on public.rooms for insert
  to anon, authenticated
  with check (true);

drop policy if exists "Anyone can update rooms" on public.rooms;
create policy "Anyone can update rooms"
  on public.rooms for update
  to anon, authenticated
  using (true)
  with check (true);

-- 4. Включение Realtime для таблицы public.rooms
alter publication supabase_realtime add table public.rooms;


