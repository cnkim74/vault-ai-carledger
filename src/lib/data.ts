import { useEffect, useState } from 'react'
import { supabase } from './supabase'

// ── 타입 ──────────────────────────────────────────────
export interface Vehicle {
  name: string
  plate: string
  fuelType: string
  battery: number
  odometerKm: number
  leaseLimitKm: number | null
  leaseDrivenKm: number | null
}

export interface VaultRecord {
  id: string
  kind: 'charge' | 'drive' | 'maintenance'
  title: string
  occurredAt: Date
  amountWon: number | null
  distanceKm: number | null
  durationMin: number | null
  location: string | null
  tag: string | null
  aiLogged: boolean
}

export interface VaultData {
  vehicle: Vehicle
  records: VaultRecord[]
  /** true면 Supabase에서 로드된 실데이터 */
  live: boolean
}

// ── 목업 (디자인 원본과 동일) ─────────────────────────
const today = new Date()
const at = (dayOffset: number, h = 0, m = 0) => {
  const d = new Date(today)
  d.setDate(d.getDate() + dayOffset)
  d.setHours(h, m, 0, 0)
  return d
}

export const MOCK_DATA: VaultData = {
  live: false,
  vehicle: {
    name: 'Model Y Long Range',
    plate: '62가 3817',
    fuelType: '전기차',
    battery: 82,
    odometerKm: 24318,
    leaseLimitKm: 20000,
    leaseDrivenKm: 17200,
  },
  records: [
    {
      id: 'mock-1',
      kind: 'charge',
      title: '초급속 충전 · 42kWh',
      occurredAt: at(0, 7, 12),
      amountWon: 14900,
      distanceKm: null,
      durationMin: null,
      location: '이마트 성수',
      tag: null,
      aiLogged: true,
    },
    {
      id: 'mock-2',
      kind: 'drive',
      title: '주행 일지 · 서울 → 판교',
      occurredAt: at(-1, 8, 40),
      amountWon: null,
      distanceKm: 38.2,
      durationMin: 21,
      location: null,
      tag: '출퇴근',
      aiLogged: false,
    },
    {
      id: 'mock-3',
      kind: 'maintenance',
      title: '엔진오일 교체 알림',
      occurredAt: at(-2),
      amountWon: null,
      distanceKm: null,
      durationMin: null,
      location: '세컨카',
      tag: '2,000km 남음',
      aiLogged: false,
    },
  ],
}

// ── 표시 헬퍼 ─────────────────────────────────────────
export function relativeDay(d: Date): string {
  const startOf = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
  const diff = Math.round((startOf(new Date()) - startOf(d)) / 86400000)
  if (diff === 0) return '오늘'
  if (diff === 1) return '어제'
  return `${d.getMonth() + 1}/${d.getDate()}`
}

export function timeOf(d: Date): string {
  return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`
}

export const won = (n: number) => `₩${n.toLocaleString('ko-KR')}`

// ── 데이터 훅: Supabase 연결 시 실데이터, 아니면 목업 ──
export function useVaultData(): VaultData {
  const [data, setData] = useState<VaultData>(MOCK_DATA)

  useEffect(() => {
    if (!supabase) return
    let cancelled = false
    ;(async () => {
      const { data: v, error: ve } = await supabase
        .from('vehicles')
        .select('*')
        .order('created_at')
        .limit(1)
        .maybeSingle()
      if (ve || !v || cancelled) return

      const { data: recs, error: re } = await supabase
        .from('records')
        .select('*')
        .eq('vehicle_id', v.id)
        .order('occurred_at', { ascending: false })
        .limit(10)
      if (re || cancelled) return

      setData({
        live: true,
        vehicle: {
          name: v.name,
          plate: v.plate ?? '',
          fuelType: v.fuel_type,
          battery: v.battery,
          odometerKm: v.odometer_km,
          leaseLimitKm: v.lease_limit_km,
          leaseDrivenKm: v.lease_driven_km,
        },
        records: (recs ?? []).map((r) => ({
          id: r.id,
          kind: r.kind,
          title: r.title,
          occurredAt: new Date(r.occurred_at),
          amountWon: r.amount_won,
          distanceKm: r.distance_km === null ? null : Number(r.distance_km),
          durationMin: r.duration_min,
          location: r.location,
          tag: r.tag,
          aiLogged: r.ai_logged,
        })),
      })
    })()
    return () => {
      cancelled = true
    }
  }, [])

  return data
}
