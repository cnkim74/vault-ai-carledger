package com.cnkim74.wheelet.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.cnkim74.wheelet.data.Insight
import com.cnkim74.wheelet.data.Vehicle
import com.cnkim74.wheelet.data.VaultRecord
import com.cnkim74.wheelet.data.VaultRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class HomeUiState(
    val loading: Boolean = true,
    val vehicles: List<Vehicle> = emptyList(),
    val selected: Vehicle? = null,
    val records: List<VaultRecord> = emptyList(),
    val insight: String? = null,
    val insightLoading: Boolean = false,
)

class HomeViewModel(
    private val repo: VaultRepository = VaultRepository(),
) : ViewModel() {

    private val _state = MutableStateFlow(HomeUiState())
    val state = _state.asStateFlow()

    init { load() }

    fun load() = viewModelScope.launch {
        val vs = repo.vehicles()
        val sel = vs.firstOrNull()
        val recs = sel?.let { repo.records(it.id) } ?: emptyList()
        _state.value = HomeUiState(loading = false, vehicles = vs, selected = sel, records = recs)
        sel?.let { loadInsight(it, recs) }
    }

    fun select(v: Vehicle) = viewModelScope.launch {
        val recs = repo.records(v.id)
        _state.update { it.copy(selected = v, records = recs, insight = null) }
        loadInsight(v, recs)
    }

    private fun loadInsight(v: Vehicle, records: List<VaultRecord>) = viewModelScope.launch {
        _state.update { it.copy(insightLoading = true) }
        val tip = Insight.generate(v, records)
        _state.update { it.copy(insight = tip, insightLoading = false) }
    }
}
