package com.cnkim74.wheelet.data

import io.ktor.client.HttpClient
import io.ktor.client.engine.android.Android
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

/** 공유 Ktor 클라이언트 + JSON (VaultRepository, AIProxy 공용) */
object Net {
    val json = Json { ignoreUnknownKeys = true }
    val client = HttpClient(Android) {
        install(ContentNegotiation) { json(json) }
    }
}
