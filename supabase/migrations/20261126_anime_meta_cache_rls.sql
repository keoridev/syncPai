ALTER TABLE public.anime_meta_cache ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read/upsert on anime_meta_cache" ON public.anime_meta_cache;
DROP POLICY IF EXISTS "anime_meta_cache_read_all" ON public.anime_meta_cache;
CREATE POLICY "anime_meta_cache_read_all"
  ON public.anime_meta_cache
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "anime_meta_cache_write_authenticated" ON public.anime_meta_cache;
CREATE POLICY "anime_meta_cache_write_authenticated"
  ON public.anime_meta_cache
  FOR INSERT
  TO authenticated, anon
  WITH CHECK (true);

DROP POLICY IF EXISTS "anime_meta_cache_update_authenticated" ON public.anime_meta_cache;
CREATE POLICY "anime_meta_cache_update_authenticated"
  ON public.anime_meta_cache
  FOR UPDATE
  TO authenticated, anon
  USING (true)
  WITH CHECK (true);
