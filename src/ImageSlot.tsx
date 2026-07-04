import { useRef, useState, type CSSProperties } from 'react'

/**
 * User-fillable image placeholder — drag an image file onto it, or click to
 * browse. Reproduces the design bundle's <image-slot> empty state (dashed
 * ring + caption) adapted for the dark theme.
 */
export function ImageSlot({
  radius = 12,
  placeholder = 'Drop an image',
  style,
}: {
  radius?: number
  placeholder?: string
  style?: CSSProperties
}) {
  const [src, setSrc] = useState<string | null>(null)
  const [over, setOver] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  const load = (file?: File | null) => {
    if (!file || !file.type.startsWith('image/')) return
    setSrc(URL.createObjectURL(file))
  }

  return (
    <div
      onClick={() => inputRef.current?.click()}
      onDragOver={(e) => {
        e.preventDefault()
        setOver(true)
      }}
      onDragLeave={() => setOver(false)}
      onDrop={(e) => {
        e.preventDefault()
        setOver(false)
        load(e.dataTransfer.files?.[0])
      }}
      style={{
        position: 'relative',
        borderRadius: radius,
        overflow: 'hidden',
        cursor: 'pointer',
        background: src ? 'transparent' : 'rgba(255,255,255,0.03)',
        ...style,
      }}
    >
      {src ? (
        <img
          src={src}
          alt=""
          draggable={false}
          style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }}
        />
      ) : (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 6,
            textAlign: 'center',
            padding: 12,
          }}
        >
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="rgba(212,179,106,.7)" strokeWidth="1.6">
            <rect x="3" y="3" width="18" height="18" rx="3" />
            <circle cx="8.5" cy="8.5" r="1.6" />
            <path d="M21 15l-5-5L5 21" />
          </svg>
          <span style={{ fontSize: 11, lineHeight: 1.35, color: 'rgba(255,255,255,.45)' }}>{placeholder}</span>
        </div>
      )}
      {/* dashed ring */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          borderRadius: radius,
          pointerEvents: 'none',
          border: `1.5px dashed ${over ? '#d4b36a' : 'rgba(255,255,255,.18)'}`,
          transition: 'border-color .12s',
        }}
      />
      <input
        ref={inputRef}
        type="file"
        accept="image/*"
        hidden
        onChange={(e) => load(e.target.files?.[0])}
      />
    </div>
  )
}
