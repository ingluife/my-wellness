// UI string packs + exercise-instruction packs → JSON assets, loaded on demand at runtime.
// Keys are the English source strings, exactly as lib/i18n.js uses them.
import { writeFileSync, readdirSync, existsSync } from 'node:fs'

// The nutrition feature has no upstream in openGym (see README), so its strings are maintained
// here in tool/locales_nutrition/ instead of in openGym's locales, and merged over the upstream
// pack for each language. Without this merge a re-run would drop every nutrition string.
const overlay = async lang => {
  const url = new URL(`./locales_nutrition/${lang}.js`, import.meta.url)
  return existsSync(url) ? (await import(url)).default : {}
}

const dump = async (srcDir, outDir, label, merge = false) => {
  const files = readdirSync(new URL(srcDir, import.meta.url)).filter(f => f.endsWith('.js'))
  for (const f of files.sort()) {
    const mod = await import(new URL(srcDir + f, import.meta.url))
    const lang = f.replace(/\.js$/, '')
    const extra = merge ? await overlay(lang) : {}
    const pack = { ...mod.default, ...extra }
    writeFileSync(new URL(`${outDir}${lang}.json`, import.meta.url), JSON.stringify(pack))
    const n = Object.keys(extra).length
    console.log(`  ${label}/${lang}.json — ${Object.keys(pack).length} entries${n ? ` (${n} nutrition)` : ''}`)
  }
}

await dump('../../openGym/frontend/src/locales/', '../assets/i18n/', 'i18n', true)
await dump('../../openGym/frontend/src/instr/', '../assets/instr/', 'instr')
