package com.cnkim74.wheelet.data

import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.Serializable

/** Claude 호출 (iOS AIProxy 대응). Supabase Edge Function `ai-proxy` 경유 — 키는 서버 시크릿. */
object AIProxy {

    @Serializable private data class Req(val model: String, val max_tokens: Int, val system: String, val messages: List<Msg>)
    @Serializable private data class Msg(val role: String, val content: String)
    @Serializable private data class Resp(val content: List<Block>? = null, val stop_reason: String? = null)
    @Serializable private data class Block(val type: String, val text: String? = null)

    suspend fun complete(system: String, user: String, maxTokens: Int = 300): String? = runCatching {
        val body = Req("claude-opus-4-8", maxTokens, system, listOf(Msg("user", user)))
        val resp = Net.client.post("${Config.SUPABASE_URL}/functions/v1/ai-proxy") {
            headers {
                append("apikey", Config.SUPABASE_ANON_KEY)
                append("Authorization", "Bearer ${Config.SUPABASE_ANON_KEY}")
            }
            contentType(ContentType.Application.Json)
            setBody(body)
        }
        val parsed = Net.json.decodeFromString<Resp>(resp.bodyAsText())
        if (parsed.stop_reason == "refusal") return null
        parsed.content?.firstOrNull { it.type == "text" }?.text?.trim()
    }.getOrNull()
}

/** 홈 AI 인사이트 생성 (iOS InsightService 대응, 간소화) */
object Insight {
    private const val SYSTEM =
        "너는 차계부 앱 Wheelet의 AI 비서다. 차량 정보와 최근 기록을 보고 비용 절약이나 관리에 " +
        "실질적으로 도움이 되는 인사이트를 정확히 한 문장의 한국어로 제안한다. 가능하면 구체적인 숫자를 포함하고, " +
        "네 자리 이상 숫자에는 천단위 쉼표를 넣는다(단 연도 제외). 인사말·설명 없이 그 한 문장만 출력한다."

    suspend fun generate(v: Vehicle, records: List<VaultRecord>): String? {
        val ctx = buildString {
            appendLine("차량: ${v.name} (${v.fuelType})")
            appendLine("누적 주행: ${v.odometerKm}km")
            if (records.isNotEmpty()) {
                appendLine("최근 기록:")
                records.take(8).forEach { r ->
                    append("- ${r.title}")
                    r.amountWon?.let { append(" · ${it}원") }
                    appendLine()
                }
            }
        }
        return AIProxy.complete(SYSTEM, ctx)
    }
}
