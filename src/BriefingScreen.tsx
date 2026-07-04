import { IOSDevice } from './IOSDevice'
import { deriveVehicle } from './vehicle'
import { relativeDay, timeOf, won, type VaultData, type VaultRecord } from './lib/data'

const DOT_COLOR: Record<VaultRecord['kind'], string> = {
  charge: '#ff7a2f',
  drive: '#c9cdd4',
  maintenance: '#d4b36a',
}

/** 1b 브리핑형 — AI 브리핑 + 지출 중심 레저 */
export function BriefingScreen({ battery, showRent, data }: { battery: number; showRent: boolean; data: VaultData }) {
  const { battery: bat, rangeKm } = deriveVehicle(battery)
  const { vehicle, records } = data
  const shortName = vehicle.name.split(' ').slice(0, 2).join(' ')
  const leasePct =
    vehicle.leaseLimitKm && vehicle.leaseDrivenKm
      ? Math.round((vehicle.leaseDrivenKm / vehicle.leaseLimitKm) * 100)
      : 0
  const leaseRemain = (vehicle.leaseLimitKm ?? 0) - (vehicle.leaseDrivenKm ?? 0)

  return (
    <IOSDevice>
      <div
        style={{
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          background: '#0a0a0c',
          color: '#f2f2f4',
          fontFamily: 'Pretendard, sans-serif',
          overflow: 'hidden',
          position: 'relative',
        }}
      >
        {/* 헤더 */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '62px 20px 4px' }}>
          <span style={{ fontFamily: 'Pretendard', fontWeight: 900, fontSize: 20, letterSpacing: 1, color: '#f2f2f4' }}>
            VAULT<span style={{ color: '#d4b36a' }}>.</span>
          </span>
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              fontSize: 11,
              color: '#c9cdd4',
              background: 'rgba(255,255,255,.05)',
              border: '1px solid rgba(255,255,255,.08)',
              borderRadius: 20,
              padding: '5px 12px',
            }}
          >
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#6fbf8a' }} />
            {shortName} · {bat}% · {rangeKm}km
          </div>
        </div>

        {/* AI 브리핑 */}
        <div style={{ margin: '16px 16px 0', display: 'flex', gap: 10, alignItems: 'flex-start' }}>
          <div
            style={{
              width: 34,
              height: 34,
              flex: 'none',
              borderRadius: '50%',
              background: 'linear-gradient(140deg,#e9cd8d,#b78f3e)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              boxShadow: '0 4px 14px rgba(212,179,106,.3)',
            }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#141414" strokeWidth="2">
              <path d="M12 2l1.9 5.8L20 9.7l-5 4 1.7 6.3L12 16.4 7.3 20l1.7-6.3-5-4 6.1-1.9z" />
            </svg>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, flex: 1 }}>
            <div
              style={{
                background: '#16161b',
                border: '1px solid rgba(255,255,255,.07)',
                borderRadius: '4px 16px 16px 16px',
                padding: '13px 15px',
                fontSize: 13,
                lineHeight: 1.55,
                color: '#e8e8ea',
              }}
            >
              오늘 아침 브리핑이에요. 어제 <b style={{ color: '#d4b36a' }}>판교 왕복 76km</b>를 자동 기록했고, 약정거리 소진 속도가 빨라요.
              이대로면 <b style={{ color: '#ff7a2f' }}>11월 말 초과</b>가 예상돼요.
            </div>
            <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
              <span style={{ fontSize: 11, color: '#d4b36a', border: '1px solid rgba(212,179,106,.4)', borderRadius: 20, padding: '4px 11px' }}>
                절약 플랜 보기
              </span>
              <span style={{ fontSize: 11, color: '#c9cdd4', border: '1px solid rgba(255,255,255,.12)', borderRadius: 20, padding: '4px 11px' }}>
                자세히 물어보기
              </span>
            </div>
          </div>
        </div>

        {/* 월 지출 */}
        <div
          style={{
            margin: '22px 16px 0',
            borderRadius: 20,
            background: 'linear-gradient(160deg,#17171d,#101013)',
            border: '1px solid rgba(255,255,255,.07)',
            padding: '20px 18px',
          }}
        >
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
              <span style={{ fontSize: 11, color: '#8a8b93' }}>7월 총 지출</span>
              <span style={{ fontFamily: 'GmarketSans', fontWeight: 700, fontSize: 28 }}>₩186,400</span>
              <span style={{ fontSize: 11, color: '#6fbf8a' }}>지난달보다 ₩25,300 아꼈어요</span>
            </div>
            <div style={{ display: 'flex', alignItems: 'flex-end', gap: 5, height: 64, paddingTop: 6 }}>
              <div style={{ width: 12, height: 38, borderRadius: 4, background: 'rgba(255,255,255,.1)' }} />
              <div style={{ width: 12, height: 52, borderRadius: 4, background: 'rgba(255,255,255,.1)' }} />
              <div style={{ width: 12, height: 44, borderRadius: 4, background: 'rgba(255,255,255,.1)' }} />
              <div style={{ width: 12, height: 58, borderRadius: 4, background: 'rgba(255,255,255,.14)' }} />
              <div style={{ width: 12, height: 40, borderRadius: 4, background: 'linear-gradient(180deg,#e9cd8d,#b78f3e)' }} />
            </div>
          </div>
          <div
            style={{
              display: 'flex',
              gap: 14,
              marginTop: 14,
              paddingTop: 12,
              borderTop: '1px solid rgba(255,255,255,.06)',
            }}
          >
            <Legend color="#ff7a2f" label="충전 ₩96,200" />
            <Legend color="#d4b36a" label="주유 ₩41,000" />
            <Legend color="#c9cdd4" label="기타 ₩49,200" />
          </div>
        </div>

        {/* 약정거리 */}
        {showRent && (
          <div
            style={{
              margin: '12px 16px 0',
              borderRadius: 16,
              background: '#141419',
              border: '1px solid rgba(255,122,47,.25)',
              padding: '14px 16px',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <span style={{ fontSize: 12, fontWeight: 600 }}>렌트 약정거리</span>
              <span style={{ fontSize: 11, color: '#ff7a2f' }}>초과 위험 · 잔여 {leaseRemain.toLocaleString('ko-KR')}km</span>
            </div>
            <div style={{ height: 6, borderRadius: 3, background: 'rgba(255,255,255,.08)', marginTop: 10, overflow: 'hidden' }}>
              <div style={{ width: `${leasePct}%`, height: '100%', borderRadius: 3, background: 'linear-gradient(90deg,#d4b36a,#ff7a2f)' }} />
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: '#8a8b93', marginTop: 6 }}>
              <span>{(vehicle.leaseDrivenKm ?? 0).toLocaleString('ko-KR')}km 주행</span>
              <span>약정 {(vehicle.leaseLimitKm ?? 0).toLocaleString('ko-KR')}km</span>
            </div>
          </div>
        )}

        {/* 타임라인 */}
        <div style={{ margin: '22px 16px 0', flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
          <span style={{ fontSize: 13, fontWeight: 600 }}>이번 주 기록</span>
          <div style={{ display: 'flex', flexDirection: 'column', marginTop: 10 }}>
            {records.map((r, i) => {
              const isLast = i === records.length - 1
              return (
                <TimelineRow key={r.id} dot={DOT_COLOR[r.kind]} line={!isLast}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', flex: 1, paddingBottom: isLast ? 0 : 26 }}>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                      <span style={{ fontSize: 12.5, fontWeight: 500 }}>{r.title}</span>
                      <span style={{ fontSize: 10.5, color: '#8a8b93' }}>
                        {r.kind === 'maintenance' ? (
                          <>
                            {r.location}
                            {r.tag && ` · ${r.tag}`}
                          </>
                        ) : (
                          <>
                            {relativeDay(r.occurredAt)} {timeOf(r.occurredAt)}
                            {r.aiLogged ? <span style={{ color: '#d4b36a' }}> · AI 자동기록</span> : r.tag && ` · ${r.tag}`}
                          </>
                        )}
                      </span>
                    </div>
                    {r.kind === 'charge' && r.amountWon !== null && (
                      <span style={{ fontFamily: 'GmarketSans', fontSize: 13 }}>{won(r.amountWon)}</span>
                    )}
                    {r.kind === 'drive' && r.durationMin !== null && (
                      <span style={{ fontSize: 11, color: '#8a8b93' }}>{r.durationMin}분</span>
                    )}
                    {r.kind === 'maintenance' && <span style={{ fontSize: 11, color: '#d4b36a' }}>예약</span>}
                  </div>
                </TimelineRow>
              )
            })}
          </div>
        </div>

        {/* AI 입력 바 */}
        <div
          style={{
            margin: 'auto 16px 30px',
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            background: '#16161b',
            border: '1px solid rgba(212,179,106,.3)',
            borderRadius: 26,
            padding: '11px 16px',
          }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#d4b36a" strokeWidth="2">
            <path d="M12 2l1.9 5.8L20 9.7l-5 4 1.7 6.3L12 16.4 7.3 20l1.7-6.3-5-4 6.1-1.9z" />
          </svg>
          <span style={{ fontSize: 12.5, color: '#8a8b93', flex: 1 }}>이번 달 충전비 얼마 썼어?</span>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#c9cdd4" strokeWidth="1.8">
            <path d="M12 19V5M5 12l7-7 7 7" />
          </svg>
        </div>
      </div>
    </IOSDevice>
  )
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11.5, color: '#c9cdd4' }}>
      <span style={{ width: 8, height: 8, borderRadius: 2, background: color }} />
      {label}
    </div>
  )
}

function TimelineRow({ dot, line = false, children }: { dot: string; line?: boolean; children: React.ReactNode }) {
  return (
    <div style={{ display: 'flex', gap: 12 }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', flex: 'none', width: 20 }}>
        <div style={{ width: 8, height: 8, borderRadius: '50%', background: dot, marginTop: 5 }} />
        {line && <div style={{ width: 1, flex: 1, background: 'rgba(255,255,255,.1)' }} />}
      </div>
      {children}
    </div>
  )
}
