package com.cnkim74.wheelet

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.cnkim74.wheelet.ui.home.HomeScreen
import com.cnkim74.wheelet.ui.theme.BgTop
import com.cnkim74.wheelet.ui.theme.WheeletTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            WheeletTheme {
                Surface(
                    color = BgTop,
                    modifier = Modifier
                        .fillMaxSize()
                        .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.safeDrawing),
                ) {
                    HomeScreen()
                }
            }
        }
    }
}
