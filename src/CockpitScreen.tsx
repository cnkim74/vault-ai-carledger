import { IOSDevice } from './IOSDevice'
import { ImageSlot } from './ImageSlot'
import { deriveVehicle } from './vehicle'
import { relativeDay, timeOf, won, type VaultData } from './lib/data'

/** 1a 콕핏형 — 차량 상태 히어로 + AI 인사이트 */
export function CockpitScreen({ battery, data }: { battery: number; data: VaultData }) {
  const { battery: bat, rangeKm, ringBg } = deriveVehicle(battery)
  const { vehicle, records } = data
  const leasePct =
    vehicle.leaseLimitKm && vehicle.leaseDrivenKm
      ? Math.round((vehicle.leaseDrivenKm / vehicle.leaseLimitKm) * 100)
      : null
  const charge = records.find((r) => r.kind === 'charge')
  const drive = records.find((r) => r.kind === 'drive')

  return (
    <IOSDevice>
      <div
        style={{
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          background: 'linear-gradient(180deg,#0a0a0c 0%,#101014 100%)',
          color: '#f2f2f4',
          fontFamily: 'Pretendard, sans-serif',
          overflow: 'hidden',
        }}
      >
        {/* 헤더 */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '62px 20px 6px' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            <span
              style={{
                fontFamily: 'Pretendard',
                fontWeight: 900,
                fontSize: 22,
                letterSpacing: 1,
                background: 'linear-gradient(120deg,#e9cd8d,#b78f3e)',
                WebkitBackgroundClip: 'text',
                backgroundClip: 'text',
                color: 'transparent',
              }}
            >
              VAULT
            </span>
            <span style={{ fontSize: 11, color: '#9a9ba3' }}>좋은 아침이에요, 지훈님</span>
          </div>
          <div style={{ display: 'flex', gap: 10 }}>
            <div
              style={{
                width: 34,
                height: 34,
                borderRadius: '50%',
                background: 'rgba(255,255,255,.06)',
                border: '1px solid rgba(255,255,255,.08)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#c9cdd4" strokeWidth="1.8">
                <path d="M18 8a6 6 0 10-12 0c0 7-3 9-3 9h18s-3-2-3-9" />
                <path d="M13.7 21a2 2 0 01-3.4 0" />
              </svg>
            </div>
            <div
              style={{
                width: 34,
                height: 34,
                borderRadius: '50%',
                background: 'rgba(255,255,255,.06)',
                border: '1px solid rgba(255,255,255,.08)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                fontSize: 12,
                fontWeight: 600,
                color: '#d4b36a',
              }}
            >
              JH
            </div>
          </div>
        </div>

        {/* 차량 히어로 */}
        <div
          style={{
            margin: '12px 16px 0',
            borderRadius: 20,
            background: 'linear-gradient(160deg,#17171d 0%,#101013 100%)',
            border: '1px solid rgba(255,255,255,.07)',
            padding: '18px 18px 16px',
            position: 'relative',
            overflow: 'hidden',
          }}
        >
          <div
            style={{
              position: 'absolute',
              inset: 'auto -40px -80px auto',
              width: 220,
              height: 220,
              borderRadius: '50%',
              background: 'radial-gradient(circle,rgba(212,179,106,.14),transparent 70%)',
            }}
          />
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
              <span style={{ fontFamily: 'GmarketSans', fontWeight: 500, fontSize: 17 }}>{vehicle.name}</span>
              <span style={{ fontSize: 11, color: '#8a8b93', letterSpacing: 0.5 }}>
                {vehicle.plate} · {vehicle.fuelType}
              </span>
            </div>
            <span
              style={{
                fontSize: 10.5,
                color: '#d4b36a',
                border: '1px solid rgba(212,179,106,.4)',
                borderRadius: 20,
                padding: '3px 9px',
              }}
            >
              주차 중
            </span>
          </div>
          <ImageSlot radius={14} placeholder="내 차 사진을 끌어다 놓으세요" style={{ width: '100%', height: 130, margin: '12px 0 4px' }} />
          <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginTop: 10 }}>
            <div style={{ position: 'relative', width: 74, height: 74, flex: 'none' }}>
              <div style={{ width: 74, height: 74, borderRadius: '50%', background: ringBg }} />
              <div
                style={{
                  position: 'absolute',
                  inset: 7,
                  borderRadius: '50%',
                  background: '#141419',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
              >
                <span style={{ fontFamily: 'GmarketSans', fontWeight: 700, fontSize: 16, color: '#d4b36a' }}>{bat}%</span>
              </div>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6, flex: 1 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12 }}>
                <span style={{ color: '#8a8b93' }}>주행 가능 거리</span>
                <span style={{ fontFamily: 'GmarketSans', fontWeight: 500 }}>{rangeKm} km</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12 }}>
                <span style={{ color: '#8a8b93' }}>누적 주행</span>
                <span style={{ fontFamily: 'GmarketSans', fontWeight: 500 }}>{vehicle.odometerKm.toLocaleString('ko-KR')} km</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12 }}>
                <span style={{ color: '#8a8b93' }}>완충까지</span>
                <span style={{ color: '#c9cdd4' }}>충전 중 아님</span>
              </div>
            </div>
          </div>
        </div>

        {/* AI 인사이트 */}
        <div
          style={{
            margin: '12px 16px 0',
            borderRadius: 16,
            padding: '14px 16px',
            background: 'linear-gradient(120deg,rgba(212,179,106,.12),rgba(212,179,106,.04))',
            border: '1px solid rgba(212,179,106,.35)',
            display: 'flex',
            gap: 12,
            alignItems: 'flex-start',
          }}
        >
          <div
            style={{
              width: 30,
              height: 30,
              flex: 'none',
              borderRadius: 10,
              background: 'linear-gradient(140deg,#e9cd8d,#b78f3e)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#141414" strokeWidth="2">
              <path d="M12 2l1.9 5.8L20 9.7l-5 4 1.7 6.3L12 16.4 7.3 20l1.7-6.3-5-4 6.1-1.9z" />
            </svg>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
            <span style={{ fontSize: 11, color: '#d4b36a', fontWeight: 600, letterSpacing: 0.5 }}>AI 인사이트</span>
            <span style={{ fontSize: 13, lineHeight: 1.45, color: '#e8e8ea' }}>
              심야 요금제로 충전 시간대를 옮기면 이번 달 <b style={{ color: '#d4b36a' }}>₩38,200</b> 절약할 수 있어요.
            </span>
          </div>
        </div>

        {/* 지출 + 약정거리 */}
        <div style={{ display: 'flex', gap: 10, margin: '12px 16px 0' }}>
          <div style={{ flex: 1, borderRadius: 16, background: '#141419', border: '1px solid rgba(255,255,255,.06)', padding: 14 }}>
            <span style={{ fontSize: 11, color: '#8a8b93' }}>7월 지출</span>
            <div style={{ fontFamily: 'GmarketSans', fontWeight: 700, fontSize: 19, marginTop: 4 }}>₩186,400</div>
            <span style={{ fontSize: 11, color: '#6fbf8a' }}>지난달 대비 −12%</span>
          </div>
          <div style={{ flex: 1, borderRadius: 16, background: '#141419', border: '1px solid rgba(255,255,255,.06)', padding: 14 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <span style={{ fontSize: 11, color: '#8a8b93' }}>약정거리</span>
              <span style={{ fontSize: 10, color: '#ff7a2f' }}>{leasePct ?? 0}%</span>
            </div>
            <div style={{ fontFamily: 'GmarketSans', fontWeight: 700, fontSize: 19, marginTop: 4 }}>
              {(vehicle.leaseDrivenKm ?? 0).toLocaleString('ko-KR')}
              <span style={{ fontSize: 11, color: '#8a8b93', fontWeight: 400 }}>
                {' '}
                /{(vehicle.leaseLimitKm ?? 0).toLocaleString('ko-KR')}km
              </span>
            </div>
            <div style={{ height: 4, borderRadius: 2, background: 'rgba(255,255,255,.08)', marginTop: 8, overflow: 'hidden' }}>
              <div style={{ width: `${leasePct ?? 0}%`, height: '100%', borderRadius: 2, background: 'linear-gradient(90deg,#d4b36a,#ff7a2f)' }} />
            </div>
          </div>
        </div>

        {/* 최근 기록 */}
        <div style={{ margin: '14px 16px 0', flex: 1, minHeight: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 8 }}>
            <span style={{ fontSize: 13, fontWeight: 600 }}>최근 기록</span>
            <span style={{ fontSize: 11, color: '#8a8b93' }}>전체 보기</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {charge && (
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 12,
                  background: '#141419',
                  border: '1px solid rgba(255,255,255,.06)',
                  borderRadius: 14,
                  padding: '11px 14px',
                }}
              >
                <div
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: 10,
                    background: 'rgba(255,122,47,.14)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flex: 'none',
                  }}
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="#ff7a2f">
                    <path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z" />
                  </svg>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 1, flex: 1 }}>
                  <span style={{ fontSize: 12.5, fontWeight: 500 }}>{charge.title}</span>
                  <span style={{ fontSize: 10.5, color: '#8a8b93' }}>
                    {relativeDay(charge.occurredAt)} {timeOf(charge.occurredAt)}
                    {charge.location && ` · ${charge.location}`}{' '}
                    {charge.aiLogged && <span style={{ color: '#d4b36a' }}>· AI 자동기록</span>}
                  </span>
                </div>
                {charge.amountWon !== null && (
                  <span style={{ fontFamily: 'GmarketSans', fontSize: 13, fontWeight: 500 }}>{won(charge.amountWon)}</span>
                )}
              </div>
            )}
            {drive && (
              <div
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 12,
                  background: '#141419',
                  border: '1px solid rgba(255,255,255,.06)',
                  borderRadius: 14,
                  padding: '11px 14px',
                }}
              >
                <div
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: 10,
                    background: 'rgba(201,205,212,.1)',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    flex: 'none',
                  }}
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#c9cdd4" strokeWidth="1.8">
                    <circle cx="12" cy="12" r="9" />
                    <path d="M12 7v5l3 3" />
                  </svg>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 1, flex: 1 }}>
                  <span style={{ fontSize: 12.5, fontWeight: 500 }}>{drive.title}</span>
                  <span style={{ fontSize: 10.5, color: '#8a8b93' }}>
                    {relativeDay(drive.occurredAt)}
                    {drive.distanceKm !== null && ` · ${drive.distanceKm}km`}
                    {drive.durationMin !== null && ` · ${drive.durationMin}분`}
                  </span>
                </div>
                {drive.tag && <span style={{ fontSize: 11, color: '#8a8b93' }}>{drive.tag}</span>}
              </div>
            )}
          </div>
        </div>

        {/* 탭바 */}
        <div
          style={{
            display: 'flex',
            alignItems: 'flex-end',
            justifyContent: 'space-around',
            padding: '8px 18px 30px',
            background: 'rgba(10,10,12,.9)',
            borderTop: '1px solid rgba(255,255,255,.06)',
          }}
        >
          <TabItem active label="홈">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#d4b36a" strokeWidth="1.8">
              <path d="M3 11l9-8 9 8v9a2 2 0 01-2 2H5a2 2 0 01-2-2z" />
            </svg>
          </TabItem>
          <TabItem label="기록">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8a8b93" strokeWidth="1.8">
              <path d="M4 6h16M4 12h16M4 18h10" />
            </svg>
          </TabItem>
          <div
            style={{
              width: 52,
              height: 52,
              borderRadius: '50%',
              marginTop: -22,
              background: 'linear-gradient(140deg,#e9cd8d,#b78f3e)',
              boxShadow: '0 6px 18px rgba(212,179,106,.35)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#141414" strokeWidth="2">
              <path d="M12 2l1.9 5.8L20 9.7l-5 4 1.7 6.3L12 16.4 7.3 20l1.7-6.3-5-4 6.1-1.9z" />
            </svg>
          </div>
          <TabItem label="통계">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8a8b93" strokeWidth="1.8">
              <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />
            </svg>
          </TabItem>
          <TabItem label="차고">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8a8b93" strokeWidth="1.8">
              <path d="M5 17h14M6 17l1.5-5h9L18 17M7.5 12l1-3h7l1 3" />
              <circle cx="7.5" cy="17" r="1.5" />
              <circle cx="16.5" cy="17" r="1.5" />
            </svg>
          </TabItem>
        </div>
      </div>
    </IOSDevice>
  )
}

function TabItem({ children, label, active = false }: { children: React.ReactNode; label: string; active?: boolean }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, minWidth: 48, padding: '4px 0' }}>
      {children}
      <span style={{ fontSize: 9.5, color: active ? '#d4b36a' : '#8a8b93' }}>{label}</span>
    </div>
  )
}
