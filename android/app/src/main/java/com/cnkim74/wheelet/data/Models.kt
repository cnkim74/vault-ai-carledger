package com.cnkim74.wheelet.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** 차량 (iOS Vehicle 대응, vehicles 테이블) */
@Serializable
data class Vehicle(
    val id: String = "",
    val name: String = "",
    val plate: String? = null,
    val maker: String? = null,
    val model: String? = null,
    @SerialName("fuel_type") val fuelType: String = "가솔린",
    @SerialName("odometer_km") val odometerKm: Int = 0,
    val battery: Int = 0,
    val year: Int? = null,
)

/** 기록 (iOS VaultRecord 대응, records 테이블) */
@Serializable
data class VaultRecord(
    val id: String = "",
    val kind: String = "fuel",
    val title: String = "",
    @SerialName("amount_won") val amountWon: Int? = null,
    @SerialName("occurred_at") val occurredAt: String = "",
    @SerialName("distance_km") val distanceKm: Double? = null,
    val location: String? = null,
)

/** 목업 (네트워크 실패 시 폴백 — iOS MockData 대응) */
object MockData {
    val vehicle = Vehicle(
        id = "mock", name = "Model 3 Long Range", plate = "05하 7288",
        maker = "테슬라", model = "Model 3", fuelType = "전기차", odometerKm = 39895, battery = 12, year = 2024
    )
    val records = listOf(
        VaultRecord(id = "1", kind = "charge", title = "고속충전 · 29.16kWh", amountWon = 10124, occurredAt = "2026-07-06T19:51:00"),
        VaultRecord(id = "2", kind = "drive", title = "출근", occurredAt = "2026-07-06T08:20:00", distanceKm = 18.4),
    )
}
