-- Таблица точной истории чтения манги и манхвы (глава + страница)
CREATE TABLE IF NOT EXISTS public.user_manga_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  manga_id text NOT NULL,
  title text NOT NULL,
  cover_url text NOT NULL DEFAULT '',
  format_label text NOT NULL DEFAULT 'Манга',
  chapter_id text NOT NULL DEFAULT '',
  chapter_label text NOT NULL DEFAULT 'Глава 1',
  page_index integer NOT NULL DEFAULT 1,
  total_pages integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, manga_id)
);

ALTER TABLE public.user_manga_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own manga history" ON public.user_manga_history;
CREATE POLICY "Users can manage own manga history"
  ON public.user_manga_history
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

