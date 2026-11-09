import type { SupabaseClient, Session, User } from '@supabase/supabase-js';

declare global {
	namespace App {
		interface Locals {
			supabase: SupabaseClient;
			/**
			 * Sesion SOLO si la identidad fue verificada en hooks.server.js
			 * (getClaims/getUser). `null` si no hay sesion, si la sesion es
			 * invalida o si la verificacion fallo temporalmente.
			 */
			session: Session | null;
			/** Como `session`, solo presentes con identidad verificada. */
			user: User | null;
			/** Delegado: devuelve la sesion ya verificada (o null). */
			getSession: () => Promise<Session | null>;
			/**
			 * Resultado de la verificacion de identidad de esta peticion.
			 * - none:     sin cookie de sesion.
			 * - verified: identidad confirmada; `userId` es el `sub` verificado.
			 * - invalid:  el token/refresh fue rechazado por Auth → 401.
			 * - error:    fallo temporal (red/5xx) → 503, nunca autoriza.
			 */
			auth: {
				status: 'none' | 'verified' | 'invalid' | 'error';
				userId: string | null;
			};
		}
		interface PageData {
			session?: Session | null;
		}
	}
}

export {};
