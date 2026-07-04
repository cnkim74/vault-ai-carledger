import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

/**
 * Supabase 클라이언트 — .env.local에 키가 없으면 null.
 * (null이면 앱은 디자인 목업 데이터로 동작한다.)
 */
export const supabase: SupabaseClient | null =
  url && anonKey ? createClient(url, anonKey) : null
