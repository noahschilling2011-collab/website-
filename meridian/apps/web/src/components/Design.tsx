import { useState } from 'react';
import { PRESETS, DEFAULT_CUSTOM, paramsToFilter, saveDesign, type CustomParams } from '../lib/design';

export function Design({ current, onApply, onClose }: { current: string; onApply: (filter: string, label: string) => void; onClose: () => void }) {
  const [custom, setCustom] = useState<CustomParams>(DEFAULT_CUSTOM);
  const [mode, setMode] = useState<'presets' | 'custom'>('presets');

  function applyPreset(filter: string, label: string) {
    saveDesign({ label, filter });
    onApply(filter, label);
  }
  function applyCustom(next: CustomParams) {
    setCustom(next);
    const filter = paramsToFilter(next);
    saveDesign({ label: 'Eigenes', filter, custom: next });
    onApply(filter, 'Eigenes');
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <strong>Karten-Design <span className="premium">Premium</span></strong>
          <button onClick={onClose}>✕</button>
        </div>
        <div className="modal-body">
          <div className="tabs">
            <button className={mode === 'presets' ? 'on' : ''} onClick={() => setMode('presets')}>Vorlagen</button>
            <button className={mode === 'custom' ? 'on' : ''} onClick={() => setMode('custom')}>Eigenes Design</button>
          </div>

          {mode === 'presets' && (
            <div className="swatches">
              {PRESETS.map((p) => (
                <button key={p.id} className={current === p.filter ? 'swatch-card on' : 'swatch-card'} onClick={() => applyPreset(p.filter, p.name)}>
                  <span className="swatch" style={{ background: p.swatch }} />
                  {p.name}
                </button>
              ))}
            </div>
          )}

          {mode === 'custom' && (
            <div className="sliders">
              <Slider label="Farbton" value={custom.hue} min={0} max={360} onChange={(v) => applyCustom({ ...custom, hue: v })} suffix="°" />
              <Slider label="Sättigung" value={custom.saturation} min={0} max={200} onChange={(v) => applyCustom({ ...custom, saturation: v })} suffix="%" />
              <Slider label="Helligkeit" value={custom.brightness} min={50} max={150} onChange={(v) => applyCustom({ ...custom, brightness: v })} suffix="%" />
              <Slider label="Kontrast" value={custom.contrast} min={50} max={150} onChange={(v) => applyCustom({ ...custom, contrast: v })} suffix="%" />
              <div className="row2">
                <span>Invertieren (Dark)</span>
                <button className={custom.invert ? 'switch on' : 'switch'} onClick={() => applyCustom({ ...custom, invert: custom.invert ? 0 : 1 })}>
                  <span className="knob" />
                </button>
              </div>
            </div>
          )}
          <p className="small dim">Das Design wird lokal gespeichert und beim nächsten Start automatisch angewandt.</p>
        </div>
      </div>
    </div>
  );
}

function Slider({ label, value, min, max, onChange, suffix }: { label: string; value: number; min: number; max: number; onChange: (v: number) => void; suffix: string }) {
  return (
    <div className="slider">
      <label>{label}<em>{value}{suffix}</em></label>
      <input type="range" min={min} max={max} value={value} onChange={(e) => onChange(Number(e.target.value))} />
    </div>
  );
}
