-- ==============================================================================
-- Migration: 20261115_social_friends_and_invites.sql
-- Description: Social friend system: friend_invites table, friend codes, 
--              accept_friend_invite RPC, Realtime publication
-- ==============================================================================

-- 1. Добавляем friend_code и tag в profiles, если ещё нет
alter table public.profiles
  add column if not exists tag text default '#0001',
  add column if not exists friend_code text,
  add column if not exists auto_accept_invites boolean not null default true;

-- Функция и триггер для генерации уникального friend_code (SP-XXXXXX) и tag (#XXXX)
create or replace function public.generate_profile_friend_identifiers()
returns trigger as $$
declare
  candidate_code text;
  candidate_tag text;
  loop_count int := 0;
begin
  -- Если tag не задан
  if new.tag is null or new.tag = '' or new.tag = '#0001' then
    candidate_tag := '#' || lpad(floor(random() * 9000 + 1000)::text, 4, '0');
    new.tag := candidate_tag;
  end if;

  -- Если friend_code не задан
  if new.friend_code is null or new.friend_code = '' then
    loop
      candidate_code := 'SP-' || upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6));
      exit when not exists (select 1 from public.profiles where friend_code = candidate_code) or loop_count > 10;
      loop_count := loop_count + 1;
    end loop;
    new.friend_code := candidate_code;
  end if;

  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_generate_profile_identifiers on public.profiles;
create trigger trg_generate_profile_identifiers
  before insert on public.profiles
  for each row execute function public.generate_profile_friend_identifiers();

-- Генерируем friend_code для уже существующих записей profiles
update public.profiles
set friend_code = 'SP-' || upper(substring(md5(id::text || clock_timestamp()::text) from 1 for 6))
where friend_code is null or friend_code = '';

-- Индексы поиска профилей по tag, username и friend_code
create index if not exists idx_profiles_friend_code on public.profiles (friend_code);
create index if not exists idx_profiles_username_tag on public.profiles (username, tag);

-- 2. Таблица токенов приглашений (QR-коды и постоянные/одноразовые ссылки)
create table if not exists public.friend_invites (
  code text primary key,
  inviter_id uuid references public.profiles(id) on delete cascade not null,
  max_uses int, -- null = бесконечный (персональный QR-код), 1 = одноразовый
  uses_count int not null default 0,
  expires_at timestamptz, -- null = бессрочный
  created_at timestamptz default timezone('utc'::text, now()) not null
);

create index if not exists idx_friend_invites_inviter on public.friend_invites (inviter_id);
create index if not exists idx_friend_invites_code on public.friend_invites (code);

-- RLS для friend_invites
alter table public.friend_invites enable row level security;

drop policy if exists "Friend invites are viewable by everyone" on public.friend_invites;
create policy "Friend invites are viewable by everyone"
  on public.friend_invites for select
  using (true);

drop policy if exists "Users can create their own invites" on public.friend_invites;
create policy "Users can create their own invites"
  on public.friend_invites for insert
  with check (auth.uid() = inviter_id);

drop policy if exists "Users can update/delete their own invites" on public.friend_invites;
create policy "Users can update/delete their own invites"
  on public.friend_invites for all
  using (auth.uid() = inviter_id);

-- 3. Безопасная RPC-функция принятия приглашения в друзья
-- Принимает invite_code, проверяет срок годности и лимит, исключает добавление самого себя
create or replace function public.accept_friend_invite(invite_code text)
returns jsonb as $$
declare
  v_invite record;
  v_caller_id uuid;
  v_existing_status text;
  v_inviter_profile record;
  v_target_status text;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return jsonb_build_object('success', false, 'error', 'unauthorized', 'message', 'Требуется авторизация');
  end if;

  -- 1. Находим инвайт
  select * into v_invite from public.friend_invites
  where code = invite_code
  limit 1;

  if not found then
    return jsonb_build_object('success', false, 'error', 'not_found', 'message', 'Приглашение не найдено или удалено');
  end if;

  -- 2. Проверяем срок годности
  if v_invite.expires_at is not null and v_invite.expires_at < now() then
    return jsonb_build_object('success', false, 'error', 'expired', 'message', 'Срок действия приглашения истёк');
  end if;

  -- 3. Проверяем лимит использований
  if v_invite.max_uses is not null and v_invite.uses_count >= v_invite.max_uses then
    return jsonb_build_object('success', false, 'error', 'limit_reached', 'message', 'Лимит использований приглашения исчерпан');
  end if;

  -- 4. Защита от добавления самого себя
  if v_invite.inviter_id = v_caller_id then
    return jsonb_build_object('success', false, 'error', 'self_invite', 'message', 'Нельзя добавить самого себя');
  end if;

  -- Получаем профиль создателя инвайта
  select id, username, tag, avatar_url, auto_accept_invites into v_inviter_profile
  from public.profiles
  where id = v_invite.inviter_id;

  -- 5. Проверяем существующую связь в friendships
  select status into v_existing_status from public.friendships
  where (user_id = v_caller_id and friend_id = v_invite.inviter_id)
     or (user_id = v_invite.inviter_id and friend_id = v_caller_id)
  limit 1;

  if v_existing_status = 'accepted' then
    return jsonb_build_object(
      'success', true,
      'status', 'already_friends',
      'message', 'Вы уже друзья!',
      'friend', jsonb_build_object(
        'id', v_inviter_profile.id,
        'username', v_inviter_profile.username,
        'tag', v_inviter_profile.tag,
        'avatar_url', v_inviter_profile.avatar_url
      )
    );
  end if;

  -- Целевой статус: accepted (если auto_accept_invites включен) или pending
  v_target_status := case when coalesce(v_inviter_profile.auto_accept_invites, true) then 'accepted' else 'pending' end;

  -- Создаем или обновляем связь дружбы
  insert into public.friendships (user_id, friend_id, status, created_at)
  values (v_caller_id, v_invite.inviter_id, v_target_status, now())
  on conflict (user_id, friend_id) do update
  set status = v_target_status, created_at = now();

  -- Инкрементируем счетчик инвайта
  update public.friend_invites
  set uses_count = uses_count + 1
  where code = invite_code;

  return jsonb_build_object(
    'success', true,
    'status', v_target_status,
    'message', case when v_target_status = 'accepted' then 'Друг успешно добавлен!' else 'Заявка в друзья отправлена!' end,
    'friend', jsonb_build_object(
      'id', v_inviter_profile.id,
      'username', v_inviter_profile.username,
      'tag', v_inviter_profile.tag,
      'avatar_url', v_inviter_profile.avatar_url
    )
  );
end;
$$ language plpgsql security definer;

-- 4. Добавляем Realtime для friendships и friend_invites
do $$
begin
  alter publication supabase_realtime add table public.friendships;
exception when others then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.friend_invites;
exception when others then null;
end $$;

