/** Derived vehicle values — mirrors the design's DCLogic.renderVals(). */
export function deriveVehicle(battery: number) {
  const b = Math.round(battery)
  const deg = b * 3.6
  return {
    battery: b,
    rangeKm: Math.round(b * 5.03),
    ringBg: `conic-gradient(#d4b36a 0deg ${deg}deg, rgba(255,255,255,.08) ${deg}deg 360deg)`,
  }
}
