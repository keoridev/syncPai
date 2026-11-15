-- ==============================================================================
-- SyncPai: Персистентный чат комнат совместного просмотра (room_messages)
-- Доставка в реальном времени идет через Supabase Realtime Broadcast (канал room_<pin>),
-- таблица хранит историю, чтобы новые участники видели последние сообщения.
-- ==============================================================================

create table if not exists public.room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id text not null,                       -- PIN комнаты без префикса: '139173'
  user_id text,                                -- auth.uid() или локальный гостевой id
  sender_name text not null default 'Гость',
  content text not null check (char_length(content) between 1 and 500),
  type text not null default 'user' check (type in ('user', 'system')),
  is_host boolean not null default false,
  created_at timestamp with time zone not null default timezone('utc'::text, now())
);

create index if not exists idx_room_messages_room_created
  on public.room_messages (room_id, created_at desc);

alter table public.room_messages enable row level security;

drop policy if exists "Allow public read room_messages" on public.room_messages;
create policy "Allow public read room_messages"
  on public.room_messages for select
  to anon, authenticated
  using (true);

drop policy if exists "Allow public insert room_messages" on public.room_messages;
create policy "Allow public insert room_messages"
  on public.room_messages for insert
  to anon, authenticated
  with check (true);

-- Публикация для postgres_changes (опционально, клиент использует Broadcast)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'room_messages'
  ) then
    alter publication supabase_realtime add table public.room_messages;
  end if;
end $$;

