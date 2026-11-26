-- SyncPai Sponsor & Priority Feature Pass («Своя фича за 7 дней»)

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS tier text NOT NULL DEFAULT 'basic';

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS sponsor_until timestamptz NULL;

CREATE TABLE IF NOT EXISTS public.feature_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  telegram_user_id bigint,
  telegram_username text,
  title text NOT NULL,
  description text NOT NULL,
  payment_method text CHECK (payment_method IN ('telegram_stars', 'transfer_qr')),
  payment_status text NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'refunded')),
  implementation_status text NOT NULL DEFAULT 'review' CHECK (implementation_status IN ('review', 'in_progress', 'completed', 'declined')),
  deadline_at timestamptz NULL,
  admin_note text NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feature_requests_user_id
  ON public.feature_requests (user_id, created_at DESC);

ALTER TABLE public.feature_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own feature requests" ON public.feature_requests;
CREATE POLICY "Users can read own feature requests"
  ON public.feature_requests
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage feature requests" ON public.feature_requests;
CREATE POLICY "Service role can manage feature requests"
  ON public.feature_requests
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

