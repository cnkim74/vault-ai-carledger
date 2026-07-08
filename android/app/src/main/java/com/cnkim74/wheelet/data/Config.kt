package com.cnkim74.wheelet.data

/**
 * Supabase 접속 설정 — iOS 앱과 동일한 백엔드.
 * anon(publishable) 키는 공개돼도 안전하며(데이터는 RLS로 보호), 클라이언트에 넣도록 설계된 키다.
 */
object Config {
    const val SUPABASE_URL = "https://ftcjeqqdzofuwcphzqnu.supabase.co"
    const val SUPABASE_ANON_KEY = "sb_publishable_P61uOUEr49DGoZFnVq4FkQ_bTdUI2zd"
}
