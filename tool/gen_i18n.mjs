// UI string packs + exercise-instruction packs → JSON assets, loaded on demand at runtime.
// Keys are the English source strings, exactly as lib/i18n.js uses them.
import { writeFileSync, readdirSync } from 'node:fs'

const dump = async (srcDir, outDir, label) => {
  const files = readdirSync(new URL(srcDir, import.meta.url)).filter(f => f.endsWith('.js'))
  for (const f of files.sort()) {
    const mod = await import(new URL(srcDir + f, import.meta.url))
    const lang = f.replace(/\.js$/, '')
    writeFileSync(new URL(`${outDir}${lang}.json`, import.meta.url), JSON.stringify(mod.default))
    console.log(`  ${label}/${lang}.json — ${Object.keys(mod.default).length} entries`)
  }
}

await dump('../../openGym/frontend/src/locales/', '../assets/i18n/', 'i18n')
await dump('../../openGym/frontend/src/instr/', '../assets/instr/', 'instr')
