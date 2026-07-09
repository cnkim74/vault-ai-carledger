package com.cnkim74.wheelet.data

import io.ktor.client.request.get
import io.ktor.client.request.headers
import io.ktor.client.request.parameter
import io.ktor.client.statement.bodyAsText

/** Supabase PostgREST에서 차량/기록을 읽는다 (iOS VaultStore 대응). anon 접근 + RLS. */
class VaultRepository {

    private suspend fun rawGet(path: String, query: Map<String, String>): String {
        val resp = Net.client.get("${Config.SUPABASE_URL}/$path") {
            headers {
                append("apikey", Config.SUPABASE_ANON_KEY)
                append("Authorization", "Bearer ${Config.SUPABASE_ANON_KEY}")
            }
            query.forEach { (k, v) -> parameter(k, v) }
        }
        return resp.bodyAsText()
    }

    suspend fun vehicles(): List<Vehicle> = runCatching {
        val body = rawGet("rest/v1/vehicles", mapOf("select" to "*", "order" to "created_at"))
        Net.json.decodeFromString<List<Vehicle>>(body).ifEmpty { listOf(MockData.vehicle) }
    }.getOrElse { listOf(MockData.vehicle) }

    suspend fun records(vehicleId: String): List<VaultRecord> = runCatching {
        val body = rawGet(
            "rest/v1/records",
            mapOf(
                "select" to "*",
                "vehicle_id" to "eq.$vehicleId",
                "order" to "occurred_at.desc",
                "limit" to "10",
            )
        )
        Net.json.decodeFromString<List<VaultRecord>>(body)
    }.getOrElse { if (vehicleId == MockData.vehicle.id) MockData.records else emptyList() }
}
