import type { SupabaseClient, Session, User } from '@supabase/supabase-js';

declare global {
	namespace App {
		interface Locals {
			supabase: SupabaseClient;
			session: Session | null;
			user: User | null;
			getSession: () => Promise<Session | null>;
		}
		interface PageData {
			session?: Session | null;
		}
	}
}

export {};
