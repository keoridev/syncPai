-- ==============================================================================
-- SyncPai: Архитектура агрегации данных каталога и плеера (Supabase Edition)
-- Миграция: Таблица anime_catalog, индексы, RLS и cron-джоба для Shikimori
-- ==============================================================================

-- 1. Включение необходимых расширений
create extension if not exists "pg_net" with schema extensions;
create extension if not exists "pg_cron" with schema extensions;

-- 2. Создание таблицы кэшированного каталога аниме
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

-- 3. Индексы для сверхбыстрой фильтрации, пагинации и сортировки в UI
create index if not exists idx_anime_catalog_status 
  on public.anime_catalog (status);

create index if not exists idx_anime_catalog_score 
  on public.anime_catalog (score desc);

create index if not exists idx_anime_catalog_shikimori_id 
  on public.anime_catalog (shikimori_id);

create index if not exists idx_anime_catalog_updated_at 
  on public.anime_catalog (updated_at desc);

-- 4. Row Level Security (RLS): публичный доступ на чтение
alter table public.anime_catalog enable row level security;

create policy "Public catalog is viewable by everyone" 
  on public.anime_catalog for select 
  using (true);

-- Только сервисный ключ или база данных могут вставлять и обновлять каталог
create policy "Service role can manage anime catalog" 
  on public.anime_catalog for all 
  using (auth.role() = 'service_role')
  with check (auth.role() = 'service_role');

-- 5. Добавление таблицы в Realtime публикацию
alter publication supabase_realtime add table public.anime_catalog;

-- 6. Функция фонового опроса Shikimori API (pg_net)
create or replace function public.fetch_ongoing_anime()
returns bigint
language plpgsql
security definer
as $$
declare
  v_request_id bigint;
begin
  -- Отправка асинхронного GET-запроса через pg_net к Shikimori API
  select net.http_get(
    url := 'https://shikimori.me/api/animes?status=ongoing&limit=50&order=popularity',
    headers := jsonb_build_object(
      'User-Agent', 'SyncPai/1.0 (Supabase Cron Worker; mailto:support@syncpai.app)',
      'Accept', 'application/json'
    )
  ) into v_request_id;

  return v_request_id;
end;
$$;

-- 7. Функция разбора ответа Shikimori и upsert в anime_catalog
create or replace function public.process_shikimori_ongoing_response()
returns int
language plpgsql
security definer
as $$
declare
  v_resp record;
  v_anime jsonb;
  v_inserted_count int := 0;
  v_poster_path text;
  v_poster_full text;
begin
  -- Находим последний успешный HTTP-ответ от Shikimori
  for v_resp in
    select response
    from net._http_response
    where status_code = 200
      and url like '%shikimori.me/api/animes%'
    order by id desc
    limit 1
  loop
    if jsonb_typeof(v_resp.response::jsonb) = 'array' then
      for v_anime in select * from jsonb_array_elements(v_resp.response::jsonb)
      loop
        -- Извлекаем постер оригинального качества
        v_poster_path := v_anime->'image'->>'original';
        if v_poster_path is not null then
          if v_poster_path like 'http%' then
            v_poster_full := v_poster_path;
          else
            v_poster_full := 'https://shikimori.me' || v_poster_path;
          end if;
        else
          v_poster_full := null;
        end if;

        -- Upsert в таблицу anime_catalog
        insert into public.anime_catalog (
          shikimori_id,
          title_ru,
          title_en,
          poster_url,
          kind,
          status,
          score,
          episodes_total,
          updated_at
        )
        values (
          (v_anime->>'id')::int,
          coalesce(nullif(v_anime->>'russian', ''), v_anime->>'name', ''),
          coalesce(v_anime->>'name', ''),
          v_poster_full,
          v_anime->>'kind',
          coalesce(v_anime->>'status', 'ongoing'),
          coalesce((v_anime->>'score')::numeric, 0.0),
          coalesce((v_anime->>'episodes')::int, 0),
          timezone('utc'::text, now())
        )
        on conflict (shikimori_id) do update set
          title_ru = excluded.title_ru,
          title_en = excluded.title_en,
          poster_url = coalesce(excluded.poster_url, public.anime_catalog.poster_url),
          kind = excluded.kind,
          status = excluded.status,
          score = excluded.score,
          episodes_total = excluded.episodes_total,
          updated_at = timezone('utc'::text, now());

        v_inserted_count := v_inserted_count + 1;
      end loop;
    end if;
  end loop;

  return v_inserted_count;
end;
$$;

-- 8. Планирование ежечасного обновления через pg_cron
-- Примечание: на дашборде Supabase pg_cron запускается в схеме cron
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Удаляем предыдущий джоб с таким именем, если он был зарегистрирован
    perform cron.unschedule('update_shikimori_catalog')
    where exists (
      select 1 from cron.job where jobname = 'update_shikimori_catalog'
    );

    -- Каждый час опрашиваем Shikimori и сразу парсим свежий ответ
    perform cron.schedule(
      'update_shikimori_catalog',
      '0 * * * *',
      $$ 
        select public.fetch_ongoing_anime();
        select public.process_shikimori_ongoing_response();
      $$
    );
  end if;
end;
$$;
