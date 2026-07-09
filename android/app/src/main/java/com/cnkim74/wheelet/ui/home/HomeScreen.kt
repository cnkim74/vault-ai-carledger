package com.cnkim74.wheelet.ui.home

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cnkim74.wheelet.data.Vehicle
import com.cnkim74.wheelet.data.VaultRecord
import com.cnkim74.wheelet.ui.theme.CardBg
import com.cnkim74.wheelet.ui.theme.CardBorder
import com.cnkim74.wheelet.ui.theme.Gold
import com.cnkim74.wheelet.ui.theme.Green
import com.cnkim74.wheelet.ui.theme.Muted
import com.cnkim74.wheelet.ui.theme.Red
import com.cnkim74.wheelet.ui.theme.TextMain
import androidx.compose.ui.graphics.Color
import java.text.NumberFormat
import java.util.Locale

private fun grouped(n: Int): String = NumberFormat.getInstance(Locale.KOREA).format(n)

@Composable
fun HomeScreen(vm: HomeViewModel = viewModel()) {
    val s by vm.state.collectAsState()

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp)
    ) {
        Text("Wheelet", color = Gold, fontSize = 24.sp, fontWeight = FontWeight.Black)
        Spacer(Modifier.height(14.dp))

        if (s.loading) {
            CircularProgressIndicator(color = Gold)
            return@Column
        }

        s.selected?.let { HeroCard(it) }
        Spacer(Modifier.height(12.dp))
        InsightCard(s.insight, s.insightLoading)
        Spacer(Modifier.height(18.dp))

        Text("최근 기록", color = TextMain, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        if (s.records.isEmpty()) {
            Text("아직 기록이 없어요", color = Muted, fontSize = 12.sp)
        } else {
            s.records.forEach { RecordRow(it); Spacer(Modifier.height(8.dp)) }
        }
    }
}

@Composable
private fun HeroCard(v: Vehicle) {
    val isEv = v.fuelType.contains("전기")
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(CardBg)
            .border(1.dp, CardBorder, RoundedCornerShape(20.dp))
            .padding(18.dp)
    ) {
        val sub = listOfNotNull(v.maker, v.model).joinToString(" ")
        Text(v.name, color = TextMain, fontSize = 18.sp, fontWeight = FontWeight.Medium)
        Text(
            listOfNotNull(v.plate, sub.ifEmpty { null }, v.fuelType).joinToString(" · "),
            color = Muted, fontSize = 11.sp
        )
        Spacer(Modifier.height(14.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                InfoRow("누적 주행", "${grouped(v.odometerKm)} km")
                if (isEv) InfoRow("주행 가능", "${(v.battery * 5)} km")
            }
            if (isEv) {
                Spacer(Modifier.width(14.dp))
                BatteryRing(v.battery)
            }
        }
    }
}

@Composable
private fun BatteryRing(pct: Int) {
    val color = when {
        pct >= 20 -> Green
        pct >= 10 -> Gold
        else -> Red
    }
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(74.dp)) {
        Canvas(Modifier.size(74.dp)) {
            val stroke = 7.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            drawArc(
                color = Color(0x14FFFFFF), startAngle = -90f, sweepAngle = 360f, useCenter = false,
                topLeft = androidx.compose.ui.geometry.Offset(inset, inset), size = arcSize,
                style = Stroke(stroke)
            )
            drawArc(
                color = color, startAngle = -90f, sweepAngle = 360f * pct / 100f, useCenter = false,
                topLeft = androidx.compose.ui.geometry.Offset(inset, inset), size = arcSize,
                style = Stroke(stroke, cap = StrokeCap.Round)
            )
        }
        Text("$pct%", color = color, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun InsightCard(tip: String?, loading: Boolean) {
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color(0x1FC8962F))
            .border(1.dp, Color(0x59C8962F), RoundedCornerShape(16.dp))
            .padding(16.dp),
        verticalAlignment = Alignment.Top
    ) {
        Column {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("AI 인사이트", color = Gold, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
                if (loading) {
                    Spacer(Modifier.width(6.dp))
                    CircularProgressIndicator(color = Gold, strokeWidth = 2.dp, modifier = Modifier.size(12.dp))
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                tip ?: "차량과 기록을 분석해 맞춤 인사이트를 보여드려요.",
                color = TextMain, fontSize = 13.sp, lineHeight = 18.sp
            )
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
        r.amountWon?.let {
            Text("₩${grouped(it)}", color = TextMain, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        }
    }
}
