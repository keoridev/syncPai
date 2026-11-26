-- Duo Profiles Ecosystem (`duo_links`) + Row-Level Security
create table if not exists public.duo_links (
  id uuid primary key default gen_random_uuid(),
  user_a uuid references auth.users(id) on delete cascade not null,
  user_b uuid references auth.users(id) on delete cascade,
  invite_code text unique not null,
  status text not null default 'pending',
  relation_label text not null default 'Напарники по аниме',
  diptych_theme_id text not null default 'sunset_bridge',
  custom_left_art_url text,
  custom_right_art_url text,
  paired_avatar_preset text,
  shared_milestone_title text,
  paired_at timestamptz not null default now()
);

alter table public.duo_links enable row level security;

create policy "duo_links_select_own_or_pending_invite"
  on public.duo_links
  for select
  to authenticated
  using (
    auth.uid() = user_a
    or auth.uid() = user_b
    or status = 'pending'
  );

create policy "duo_links_insert_owner"
  on public.duo_links
  for insert
  to authenticated
  with check (auth.uid() = user_a);

create policy "duo_links_update_participants_or_accept"
  on public.duo_links
  for update
  to authenticated
  using (
    auth.uid() = user_a
    or auth.uid() = user_b
    or (status = 'pending' and user_b is null)
  );

