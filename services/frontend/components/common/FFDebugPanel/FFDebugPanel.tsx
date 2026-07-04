import { FC, useState } from 'react'
import { useBooleanFlagValue, useStringFlagValue, useNumberFlagValue, useObjectFlagValue } from '@openfeature/react-sdk'

const FFDebugPanel: FC = () => {
  const [open, setOpen] = useState(false)

  // Read all 4 workshop flags
  const frustration = useBooleanFlagValue('product-card-frustration', false)
  const promo = useStringFlagValue('promo-banner-message', 'GET FREE SHIPPING WITH CODE SAGE')
  const gridCols = useNumberFlagValue('product-grid-columns', 3)
  const heroStyle = useObjectFlagValue('homepage-hero-style', { bgColor: '#632CA6', textColor: '#FFFFFF', badge: '' }) as any

  const flags = [
    { key: 'product-card-frustration', value: String(frustration), variant: frustration ? 'frustration' : 'control', active: frustration },
    { key: 'promo-banner-message', value: promo.length > 28 ? promo.slice(0, 28) + '…' : promo, variant: promo.includes('SUMMER') ? 'summer-sale' : 'control', active: promo.includes('SUMMER') },
    { key: 'product-grid-columns', value: String(gridCols), variant: gridCols === 4 ? 'compact' : 'standard', active: gridCols === 4 },
    { key: 'homepage-hero-style', value: heroStyle?.bgColor ?? '#632CA6', variant: heroStyle?.bgColor === '#FF6B35' ? 'vibrant' : 'control', active: heroStyle?.bgColor === '#FF6B35' },
  ]

  return (
    <div style={{ position: 'fixed', top: 12, right: 12, zIndex: 9999, fontFamily: 'monospace', fontSize: 12 }}>
      {/* Toggle button */}
      <button
        onClick={() => setOpen(o => !o)}
        style={{
          background: '#632CA6', color: '#fff', border: 'none', borderRadius: 6,
          padding: '6px 12px', cursor: 'pointer', fontWeight: 700, fontSize: 12,
          boxShadow: '0 2px 8px rgba(99,44,166,0.4)', marginLeft: 'auto', display: 'block'
        }}
        title="Feature Flags status"
      >
        🚩 FF
      </button>

      {/* Panel */}
      {open && (
        <div style={{
          marginTop: 6, background: '#1a0a2e', border: '1px solid #632CA6',
          borderRadius: 8, padding: '10px 14px', minWidth: 280,
          boxShadow: '0 4px 20px rgba(99,44,166,0.5)', color: '#e0d0f0'
        }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: '#9966cc', marginBottom: 8, textTransform: 'uppercase', letterSpacing: 1 }}>
            Feature Flags · dev env
          </div>
          {flags.map(f => (
            <div key={f.key} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6, gap: 8 }}>
              <span style={{ color: '#ccc', fontSize: 11, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 140 }}>
                {f.key}
              </span>
              <span style={{
                fontSize: 10, fontWeight: 700, padding: '2px 6px', borderRadius: 4,
                background: f.active ? 'rgba(255,107,53,0.25)' : 'rgba(99,44,166,0.3)',
                color: f.active ? '#FF6B35' : '#9966cc',
                border: `1px solid ${f.active ? '#FF6B35' : '#632CA6'}`,
                whiteSpace: 'nowrap'
              }}>
                {f.variant}
              </span>
            </div>
          ))}
          <div style={{ marginTop: 8, paddingTop: 8, borderTop: '1px solid #333', fontSize: 10, color: '#666' }}>
            RUM: @feature_flags.*
          </div>
        </div>
      )}
    </div>
  )
}

export default FFDebugPanel
