// Validates the nutrition overlay packs against the English key list.
// Run after editing tool/locales_nutrition/*.js:  node tool/check_i18n_nutrition.mjs
import { readdirSync, readFileSync, existsSync } from 'node:fs'

const dir = new URL('./locales_nutrition/', import.meta.url)
const keysUrl = new URL('./nutrition_keys.json', import.meta.url)
const expected = JSON.parse(readFileSync(keysUrl, 'utf8'))
const flat = Object.values(expected).flat()
const ph = s => (s.match(/\{\d\}/g) ?? []).sort().join(',')

// Each language must stay in its own script — a stray character from another alphabet is
// almost always a typo, and it is invisible in review. Latin-script packs must carry no
// Cyrillic/CJK/Hangul/Devanagari at all; the others must carry no alphabet but their own.
const strayScript = {
  de: /[\u0400-\u04FF\u0900-\u097F\u4E00-\u9FFF\uAC00-\uD7AF]/,
  es: /[\u0400-\u04FF\u0900-\u097F\u4E00-\u9FFF\uAC00-\uD7AF]/,
  fr: /[\u0400-\u04FF\u0900-\u097F\u4E00-\u9FFF\uAC00-\uD7AF]/,
  it: /[\u0400-\u04FF\u0900-\u097F\u4E00-\u9FFF\uAC00-\uD7AF]/,
  pt: /[\u0400-\u04FF\u0900-\u097F\u4E00-\u9FFF\uAC00-\uD7AF]/,
  pl: /[\u0400-\u04FF\u0900-\u097F\u4E00-\u9FFF\uAC00-\uD7AF]/,
  tr: /[\u0400-\u04FF\u0900-\u097F\u4E00-\u9FFF\uAC00-\uD7AF]/,
  ru: /[\u0900-\u097F\u4E00-\u9FFF\uAC00-\uD7AF]/,
  zh: /[\u0400-\u04FF\u0900-\u097F\uAC00-\uD7AF]/,
  ko: /[\u0400-\u04FF\u0900-\u097F]/,
  hi: /[\u0980-\u09FF\u0400-\u04FF\u4E00-\u9FFF\uAC00-\uD7AF]/,
}

let bad = 0
for (const f of readdirSync(dir).filter(f => f.endsWith('.js')).sort()) {
  const lang = f.replace(/\.js$/, '')
  const pack = (await import(new URL(f, dir))).default
  const errs = []
  const missing = flat.filter(k => !(k in pack))
  const extra = Object.keys(pack).filter(k => !flat.includes(k))
  if (missing.length) errs.push(`${missing.length} missing: ${missing.slice(0, 3).map(k => JSON.stringify(k)).join(', ')}${missing.length > 3 ? '…' : ''}`)
  if (extra.length) errs.push(`${extra.length} unknown: ${extra.slice(0, 3).map(k => JSON.stringify(k)).join(', ')}${extra.length > 3 ? '…' : ''}`)
  for (const [k, v] of Object.entries(pack)) {
    if (typeof v !== 'string' || !v.trim()) errs.push(`empty value for ${JSON.stringify(k)}`)
    else if (ph(k) !== ph(v)) errs.push(`placeholder mismatch ${JSON.stringify(k)} → ${JSON.stringify(v)}`)
    else if (strayScript[lang]?.test(v)) errs.push(`stray script in ${JSON.stringify(k)} → ${JSON.stringify(v)}`)
  }
  bad += errs.length ? 1 : 0
  console.log(errs.length ? `✗ ${lang}: ${errs.join(' | ')}` : `✓ ${lang}: ${Object.keys(pack).length} entries`)
}
const langs = ['de', 'es', 'fr', 'it', 'pt', 'pl', 'tr', 'ru', 'zh', 'ko', 'hi']
const absent = langs.filter(l => !existsSync(new URL(`${l}.js`, dir)))
if (absent.length) { console.log(`✗ no overlay for: ${absent.join(', ')}`); bad++ }
process.exit(bad ? 1 : 0)
