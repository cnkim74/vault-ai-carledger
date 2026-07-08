package com.cnkim74.wheelet.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// 브랜드 컬러 (iOS Theme와 동일 톤: 다크 + 골드)
val Gold = Color(0xFFC8962F)
val GoldLight = Color(0xFFE6C163)
val BgTop = Color(0xFF0D0D0F)
val BgBottom = Color(0xFF050506)
val CardBg = Color(0xFF16161A)
val CardBorder = Color(0x14FFFFFF)
val TextMain = Color(0xFFEDEDED)
val Muted = Color(0xFF8A8A8E)
val Green = Color(0xFF39C463)
val Orange = Color(0xFFE8933A)
val Red = Color(0xFFE5533B)

private val DarkColors = darkColorScheme(
    primary = Gold,
    onPrimary = Color(0xFF15130B),
    background = BgTop,
    onBackground = TextMain,
    surface = CardBg,
    onSurface = TextMain,
)

@Composable
fun WheeletTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = DarkColors, content = content)
}
