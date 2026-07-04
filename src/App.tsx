import { useEffect, useState } from 'react'
import { CockpitScreen } from './CockpitScreen'
import { BriefingScreen } from './BriefingScreen'
import { useVaultData } from './lib/data'

type View = 'both' | '1a' | '1b'

export default function App() {
  const data = useVaultData()
  const [view, setView] = useState<View>('both')
  const [battery, setBattery] = useState(data.vehicle.battery)
  const [showRent, setShowRent] = useState(true)

  // Supabase 실데이터가 로드되면 슬라이더를 DB 배터리 값으로 동기화
  useEffect(() => {
    if (data.live) setBattery(data.vehicle.battery)
  }, [data.live, data.vehicle.battery])

  const showA = view === 'both' || view === '1a'
  const showB = view === 'both' || view === '1b'

  return (
    <div className="stage">
      <div className="controls">
        <span className="brand">VAULT — AI 차계부</span>
        <span
          style={{
            font: '600 10px Pretendard, sans-serif',
            padding: '3px 8px',
            borderRadius: 10,
            background: data.live ? 'rgba(111,191,138,.15)' : 'rgba(255,255,255,.07)',
            color: data.live ? '#6fbf8a' : '#8a8b93',
          }}
        >
          {data.live ? 'Supabase 연결됨' : '목업 데이터'}
        </span>

        <div className="seg" role="tablist">
          <button className={view === 'both' ? 'active' : ''} onClick={() => setView('both')}>
            둘 다
          </button>
          <button className={view === '1a' ? 'active' : ''} onClick={() => setView('1a')}>
            1a 콕핏형
          </button>
          <button className={view === '1b' ? 'active' : ''} onClick={() => setView('1b')}>
            1b 브리핑형
          </button>
        </div>

        <label className="ctl-group">
          배터리
          <input
            type="range"
            min={0}
            max={100}
            step={1}
            value={battery}
            onChange={(e) => setBattery(Number(e.target.value))}
          />
          <span className="ctl-val">{battery}%</span>
        </label>

        <div className="ctl-group" style={{ opacity: showB ? 1 : 0.4 }}>
          약정거리 카드
          <span
            className={`switch ${showRent ? 'on' : ''}`}
            role="switch"
            aria-checked={showRent}
            onClick={() => setShowRent((v) => !v)}
          />
        </div>
      </div>

      <div className="screens">
        {showA && (
          <div className="screen-wrap">
            <div className="screen-label">
              <span className="oid">1a</span>콕핏형 — 차량 상태 히어로 + AI 인사이트
            </div>
            <CockpitScreen battery={battery} data={data} />
          </div>
        )}
        {showB && (
          <div className="screen-wrap">
            <div className="screen-label">
              <span className="oid">1b</span>브리핑형 — AI 브리핑 + 지출 중심
            </div>
            <BriefingScreen battery={battery} showRent={showRent} data={data} />
          </div>
        )}
      </div>
    </div>
  )
}
