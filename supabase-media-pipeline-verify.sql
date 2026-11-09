-- Revision 18: verificaciones PREPARADAS para staging. NO EJECUTADAS.
-- Ejecutar solo despues de revisar/aplicar supabase-media-pipeline.sql.
-- No reemplaza los casos con JWT reales, concurrencia ni la comprobacion de R2.
-- La transaccion termina en ROLLBACK; no altera datos de negocio.
BEGIN;

DO $$
DECLARE v_table text; v_role text; v_function record; v_allowed boolean;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'media_assets', 'media_upload_intents', 'media_reviews', 'media_jobs',
    'storage_objects', 'media_audit_log', 'object_tombstones', 'media_staff', 'user_banners'
  ] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                   WHERE n.nspname = 'public' AND c.relname = v_table AND c.relrowsecurity) THEN
      RAISE EXCEPTION 'Falta RLS en %', v_table;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      IF has_table_privilege(v_role, format('public.%I', v_table), 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
         OR has_any_column_privilege(v_role, format('public.%I', v_table), 'SELECT,INSERT,UPDATE,REFERENCES') THEN
        RAISE EXCEPTION 'Privilegios directos inesperados: % en %', v_role, v_table;
      END IF;
    END LOOP;
  END LOOP;

  -- Inspecciona tambien TODAS las firmas antiguas, no solo las recien creadas.
  FOR v_function IN SELECT p.oid, p.proname, p.oid::regprocedure AS signature
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND (left(p.proname, 6) = 'media_'
      OR p.proname IN ('public_media_list', 'public_approved_media_count'))
  LOOP
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      v_allowed := v_function.oid = 'public.public_approved_media_count(uuid)'::regprocedure OR (
        v_role = 'authenticated' AND v_function.oid = ANY(ARRAY[
          'public.media_admin_role()'::regprocedure,
          'public.media_abort_upload_intent(uuid)'::regprocedure,
          'public.media_request_delete(uuid)'::regprocedure,
          'public.media_log_owner_original_access(uuid)'::regprocedure,
          'public.media_approve(uuid)'::regprocedure,
          'public.media_reject(uuid,text)'::regprocedure,
          'public.media_dead_jobs(integer)'::regprocedure,
          'public.media_retry_dead_job(uuid,text)'::regprocedure,
          'public.media_request_delete_cover(uuid)'::regprocedure
        ])
      );
      IF has_function_privilege(v_role, v_function.oid, 'EXECUTE') <> v_allowed THEN
        RAISE EXCEPTION 'EXECUTE inesperado: % en %', v_role, v_function.signature;
      END IF;
    END LOOP;
  END LOOP;

  IF NOT has_function_privilege('service_role', 'public.media_commit_upload(uuid,uuid,text,bigint,integer,integer,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.media_create_upload_intent(uuid,text,text,bigint,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Faltan permisos RPC del servidor';
  END IF;
END;
$$;

-- Reproduce el guard NULL del hallazgo recuperado sin JWT y sin tocar assets.
SELECT set_config('request.jwt.claims', '{}', true);
SELECT set_config('request.jwt.claim.sub', '', true);
DO $$
BEGIN
  BEGIN
    PERFORM public.media_require_staff();
    RAISE EXCEPTION 'Guard NULL abierto';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.media_require_actor_staff(NULL);
    RAISE EXCEPTION 'Guard de actor NULL abierto';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$$;

ROLLBACK;
