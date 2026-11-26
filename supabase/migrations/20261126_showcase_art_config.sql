-- Add showcase_art_config jsonb column to profiles for MangaShowcasePanel coordinate cropping
alter table public.profiles
  add column if not exists showcase_art_config jsonb;

