package com.cnkim74.wheelet.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cnkim74.wheelet.data.VaultRecord
import com.cnkim74.wheelet.ui.theme.BgTop
import com.cnkim74.wheelet.ui.theme.CardBg
import com.cnkim74.wheelet.ui.theme.CardBorder
import com.cnkim74.wheelet.ui.theme.Gold
import com.cnkim74.wheelet.ui.theme.Muted
import com.cnkim74.wheelet.ui.theme.TextMain
import java.text.NumberFormat
import java.util.Locale

private fun grouped(n: Int): String = NumberFormat.getInstance(Locale.KOREA).format(n)

@Composable
fun HomeScreen(vm: HomeViewModel = viewModel()) {
    val s by vm.state.collectAsState()

    Column(
        Modifier
            .fillMaxSize()
            .background(BgTop)
            .padding(horizontal = 16.dp, vertical = 20.dp)
    ) {
        Text("Wheelet", color = Gold, fontSize = 24.sp, fontWeight = FontWeight.Black)
        Spacer(Modifier.height(16.dp))

        if (s.loading) {
            CircularProgressIndicator(color = Gold)
            return@Column
        }

        s.selected?.let { v ->
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(CardBg)
                    .border(1.dp, CardBorder, RoundedCornerShape(18.dp))
                    .padding(16.dp)
            ) {
                val sub = listOfNotNull(v.maker, v.model).joinToString(" ")
                Text(v.name, color = TextMain, fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                Text(
                    listOfNotNull(v.plate, sub.ifEmpty { null }, v.fuelType).joinToString(" · "),
                    color = Muted, fontSize = 12.sp
                )
                Spacer(Modifier.height(12.dp))
                InfoRow("누적 주행", "${grouped(v.odometerKm)} km")
                if (v.fuelType.contains("전기")) InfoRow("배터리", "${v.battery}%")
            }
        }

        Spacer(Modifier.height(20.dp))
        Text("최근 기록", color = TextMain, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))

        if (s.records.isEmpty()) {
            Text("아직 기록이 없어요", color = Muted, fontSize = 12.sp)
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(s.records) { RecordRow(it) }
            }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = Muted, fontSize = 13.sp)
        Text(value, color = TextMain, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun RecordRow(r: VaultRecord) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(CardBg)
            .border(1.dp, CardBorder, RoundedCornerShape(14.dp))
            .padding(14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column {
            Text(r.title, color = TextMain, fontSize = 13.sp)
            Text(r.occurredAt.take(16).replace("T", " "), color = Muted, fontSize = 11.sp)
        }
        r.amountWon?.let { Text("₩${grouped(it)}", color = TextMain, fontSize = 13.sp, fontWeight = FontWeight.Medium) }
    }
}
