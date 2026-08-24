// Differential fixture for weekKey: the JS function's own source, evaluated verbatim, over
// three years of dates. ISO week numbering is exactly the kind of arithmetic where a port
// looks right and is off by one at a year boundary, so the Dart side is checked against the
// original's output rather than against a second reading of the spec.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'

const src = readFileSync(new URL('../../openGym/frontend/src/lib/format.js', import.meta.url), 'utf8')
const fn = src.slice(src.indexOf('export function weekKey'), src.indexOf('export const localTZ'))
const weekKey = new Function(`${fn.replace('export function', 'function')}; return weekKey`)()

const out = {}
const d = new Date(2024, 0, 1)
while (d < new Date(2027, 0, 15)) {
  const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  out[iso] = weekKey(iso)
  d.setDate(d.getDate() + 1)
}

mkdirSync(new URL('../test/fixtures/', import.meta.url), { recursive: true })
writeFileSync(new URL('../test/fixtures/week_keys.json', import.meta.url), JSON.stringify(out))
console.log(`week_keys.json — ${Object.keys(out).length} dates, ${new Set(Object.values(out)).size} distinct weeks`)
console.log('spot checks:', ['2024-12-30', '2025-01-01', '2026-01-01', '2026-12-31'].map(k => `${k}=${out[k]}`).join('  '))
