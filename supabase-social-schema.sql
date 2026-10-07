-- ============================================================
-- AguaEnLaBoca · Esquema unificado de red social de creadoras
-- Ejecutar en el SQL editor de Supabase, en orden, una sola vez.
-- ============================================================

-- ----------------------------------------------------------
-- 1. TABLA media: reemplaza user_photos, user_banners, photos
--    y posts con un solo modelo coherente.
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tipo          text NOT NULL CHECK (tipo IN ('photo','video','banner','avatar')),
  storage_key   text NOT NULL,
  public_url    text,
  bucket        text NOT NULL DEFAULT 'public' CHECK (bucket IN ('public','private')),
  es_privado    boolean NOT NULL DEFAULT false,
  titulo        text,
  descripcion   text,
  orden         integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS media_user_id_idx ON public.media (user_id);
CREATE INDEX IF NOT EXISTS media_user_tipo_idx ON public.media (user_id, tipo);
CREATE INDEX IF NOT EXISTS media_es_privado_idx ON public.media (es_privado);

ALTER TABLE public.media ENABLE ROW LEVEL SECURITY;

-- La dueña gestiona todo su contenido
CREATE POLICY "media owner all"
  ON public.media FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Cualquiera ve contenido público
CREATE POLICY "media public read"
  ON public.media FOR SELECT
  USING (es_privado = false);

-- Suscriptoras activas ven contenido privado de su creadora
CREATE POLICY "media subscriber read"
  ON public.media FOR SELECT
  USING (
    es_privado = true AND EXISTS (
      SELECT 1 FROM public.media_subscriptions ms
      WHERE ms.creator_id = media.user_id
        AND ms.subscriber_id = auth.uid()
        AND ms.status = 'activa'
        AND (ms.expires_at IS NULL OR ms.expires_at > now())
    )
  );

-- ----------------------------------------------------------
-- 2. TABLA media_subscriptions: suscripciones de fans a creadoras
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_subscriptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  subscriber_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status        text NOT NULL DEFAULT 'activa' CHECK (status IN ('activa','cancelada','expirada')),
  price         numeric(10,2),
  started_at    timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (creator_id, subscriber_id)
);

CREATE INDEX IF NOT EXISTS media_subscriptions_creator_idx ON public.media_subscriptions (creator_id);
CREATE INDEX IF NOT EXISTS media_subscriptions_subscriber_idx ON public.media_subscriptions (subscriber_id);

ALTER TABLE public.media_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "subscriptions owner read"
  ON public.media_subscriptions FOR SELECT
  USING (auth.uid() = subscriber_id OR auth.uid() = creator_id);

CREATE POLICY "subscriptions subscriber insert"
  ON public.media_subscriptions FOR INSERT
  WITH CHECK (auth.uid() = subscriber_id);

CREATE POLICY "subscriptions subscriber update"
  ON public.media_subscriptions FOR UPDATE
  USING (auth.uid() = subscriber_id);

-- ----------------------------------------------------------
-- 3. TABLA media_likes
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_likes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  media_id   uuid NOT NULL REFERENCES public.media(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (media_id, user_id)
);

CREATE INDEX IF NOT EXISTS media_likes_media_idx ON public.media_likes (media_id);
CREATE INDEX IF NOT EXISTS media_likes_user_idx ON public.media_likes (user_id);

ALTER TABLE public.media_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "media_likes read"
  ON public.media_likes FOR SELECT
  USING (true);

CREATE POLICY "media_likes insert"
  ON public.media_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "media_likes delete"
  ON public.media_likes FOR DELETE
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------
-- 4. TABLA media_comments
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.media_comments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  media_id   uuid NOT NULL REFERENCES public.media(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  contenido  text NOT NULL CHECK (char_length(contenido) <= 1000),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS media_comments_media_idx ON public.media_comments (media_id);
CREATE INDEX IF NOT EXISTS media_comments_user_idx ON public.media_comments (user_id);

ALTER TABLE public.media_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "media_comments read"
  ON public.media_comments FOR SELECT
  USING (true);

CREATE POLICY "media_comments insert"
  ON public.media_comments FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "media_comments delete own"
  ON public.media_comments FOR DELETE
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------
-- 5. TABLA follows: quién sigue a quién
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.follows (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  following_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE INDEX IF NOT EXISTS follows_follower_idx ON public.follows (follower_id);
CREATE INDEX IF NOT EXISTS follows_following_idx ON public.follows (following_id);

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "follows read"
  ON public.follows FOR SELECT
  USING (true);

CREATE POLICY "follows insert"
  ON public.follows FOR INSERT
  WITH CHECK (auth.uid() = follower_id);

CREATE POLICY "follows delete"
  ON public.follows FOR DELETE
  USING (auth.uid() = follower_id);

-- ----------------------------------------------------------
-- 6. TABLA messages: mensajes directos entre usuarios
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  receiver_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  contenido   text NOT NULL CHECK (char_length(contenido) <= 2000),
  leido       boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (sender_id <> receiver_id)
);

CREATE INDEX IF NOT EXISTS messages_sender_idx ON public.messages (sender_id);
CREATE INDEX IF NOT EXISTS messages_receiver_idx ON public.messages (receiver_id);
CREATE INDEX IF NOT EXISTS messages_pair_idx ON public.messages (sender_id, receiver_id);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "messages read own"
  ON public.messages FOR SELECT
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "messages insert own"
  ON public.messages FOR INSERT
  WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "messages update read"
  ON public.messages FOR UPDATE
  USING (auth.uid() = receiver_id);

-- ----------------------------------------------------------
-- 7. TABLA notifications
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  actor_id    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  tipo        text NOT NULL CHECK (tipo IN ('like','comment','follow','subscribe','message')),
  media_id    uuid REFERENCES public.media(id) ON DELETE CASCADE,
  contenido   text,
  leido       boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_user_idx ON public.notifications (user_id);
CREATE INDEX IF NOT EXISTS notifications_leido_idx ON public.notifications (user_id, leido);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications read own"
  ON public.notifications FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "notifications insert any"
  ON public.notifications FOR INSERT
  WITH CHECK (true);

CREATE POLICY "notifications update own"
  ON public.notifications FOR UPDATE
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------
-- 8. Columna media_count en profiles para mostrar estadísticas
-- ----------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS followers_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS following_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS media_count integer NOT NULL DEFAULT 0;

-- ----------------------------------------------------------
-- 9. Función y triggers para contadores
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_follow_counts()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.profiles SET following_count = following_count + 1 WHERE id = NEW.follower_id;
    UPDATE public.profiles SET followers_count = followers_count + 1 WHERE id = NEW.following_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.profiles SET following_count = GREATEST(0, following_count - 1) WHERE id = OLD.follower_id;
    UPDATE public.profiles SET followers_count = GREATEST(0, followers_count - 1) WHERE id = OLD.following_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS follows_count_trigger ON public.follows;
CREATE TRIGGER follows_count_trigger
  AFTER INSERT OR DELETE ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.update_follow_counts();

CREATE OR REPLACE FUNCTION public.update_media_count()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.profiles SET media_count = media_count + 1 WHERE id = NEW.user_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.profiles SET media_count = GREATEST(0, media_count - 1) WHERE id = OLD.user_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS media_count_trigger ON public.media;
CREATE TRIGGER media_count_trigger
  AFTER INSERT OR DELETE ON public.media
  FOR EACH ROW EXECUTE FUNCTION public.update_media_count();

-- ----------------------------------------------------------
-- 10. Trigger de notificaciones automáticas
-- ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_on_like()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  owner uuid;
BEGIN
  SELECT user_id INTO owner FROM public.media WHERE id = NEW.media_id;
  IF owner IS NOT NULL AND owner <> NEW.user_id THEN
    INSERT INTO public.notifications (user_id, actor_id, tipo, media_id, contenido)
    VALUES (owner, NEW.user_id, 'like', NEW.media_id, 'le gustó tu publicación');
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS notify_like_trigger ON public.media_likes;
CREATE TRIGGER notify_like_trigger
  AFTER INSERT ON public.media_likes
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_like();

CREATE OR REPLACE FUNCTION public.notify_on_comment()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  owner uuid;
BEGIN
  SELECT user_id INTO owner FROM public.media WHERE id = NEW.media_id;
  IF owner IS NOT NULL AND owner <> NEW.user_id THEN
    INSERT INTO public.notifications (user_id, actor_id, tipo, media_id, contenido)
    VALUES (owner, NEW.user_id, 'comment', NEW.media_id, 'comentó tu publicación');
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS notify_comment_trigger ON public.media_comments;
CREATE TRIGGER notify_comment_trigger
  AFTER INSERT ON public.media_comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_comment();

CREATE OR REPLACE FUNCTION public.notify_on_follow()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.following_id <> NEW.follower_id THEN
    INSERT INTO public.notifications (user_id, actor_id, tipo, contenido)
    VALUES (NEW.following_id, NEW.follower_id, 'follow', 'te empezó a seguir');
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS notify_follow_trigger ON public.follows;
CREATE TRIGGER notify_follow_trigger
  AFTER INSERT ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_follow();

CREATE OR REPLACE FUNCTION public.notify_on_subscribe()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.creator_id <> NEW.subscriber_id THEN
    INSERT INTO public.notifications (user_id, actor_id, tipo, contenido)
    VALUES (NEW.creator_id, NEW.subscriber_id, 'subscribe', 'se suscribió a tu contenido');
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS notify_subscribe_trigger ON public.media_subscriptions;
CREATE TRIGGER notify_subscribe_trigger
  AFTER INSERT ON public.media_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_subscribe();

-- ----------------------------------------------------------
-- FIN. Ejecutar completo en el SQL editor de Supabase.
-- ----------------------------------------------------------
