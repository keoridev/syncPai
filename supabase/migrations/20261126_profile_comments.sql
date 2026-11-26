-- Profile wall comments table for real user-to-user wall messages
CREATE TABLE IF NOT EXISTS public.profile_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_user_id UUID NOT NULL,
  author_id UUID NOT NULL,
  author_name TEXT NOT NULL,
  author_avatar TEXT,
  body TEXT NOT NULL CHECK (char_length(trim(body)) > 0 AND char_length(body) <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_profile_comments_profile_created
  ON public.profile_comments (profile_user_id, created_at DESC);

ALTER TABLE public.profile_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profile_comments_select_all" ON public.profile_comments;
CREATE POLICY "profile_comments_select_all"
  ON public.profile_comments
  FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "profile_comments_insert_own" ON public.profile_comments;
CREATE POLICY "profile_comments_insert_own"
  ON public.profile_comments
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "profile_comments_delete_own_or_owner" ON public.profile_comments;
CREATE POLICY "profile_comments_delete_own_or_owner"
  ON public.profile_comments
  FOR DELETE
  TO authenticated
  USING (auth.uid() = author_id OR auth.uid() = profile_user_id);

