// Builds assets/data/foods.json from the curated seed and USDA FoodData Central.
//
// The nutrition feature needs a food catalogue, and the app has no network: like the 1,324
// exercises, the foods are generated once and bundled. The numbers come from USDA SR Legacy,
// which is US federal work and therefore public domain — no attribution obligation and no
// share-alike, which is why it is used here rather than Open Food Facts (ODbL data, CC-BY-SA
// images). See NOTICE.md.
//
// Curation lives in tool/foods_seed.tsv, not in this script. SR Legacy has 7,793 records and
// most of them are brand-name products, restaurant dishes and 954 cuts of beef; the seed is
// the ~226 foods somebody might actually log, each pinned to the FDC record its numbers come
// from so a wrong match is reviewable in a diff.
//
//   node tool/gen_foods.mjs [--src <FoodData_Central_sr_legacy_food_json_*.json>]
//
// With no --src the dataset is fetched into tool/.cache (git-ignored, ~200 MB unzipped) and
// reused on later runs.
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

// Pinned so a regeneration is reproducible. SR Legacy is a frozen historical release and does
// not change; bumping this is a deliberate act with a diff to review.
const RELEASE = 'FoodData_Central_sr_legacy_food_json_2021-10-28'
const URL_BASE = 'https://fdc.nal.usda.gov/fdc-datasets'

const here = p => fileURLToPath(new URL(p, import.meta.url))
const cache = here('.cache')

// The four the app tracks. FDC numbers them; the names are what the records call them.
const NUTRIENT = { kcal: 1008, p: 1003, c: 1005, f: 1004 }

function datasetPath() {
  const i = process.argv.indexOf('--src')
  if (i > -1 && process.argv[i + 1]) return process.argv[i + 1]

  const json = `${cache}/${RELEASE}.json`
  if (existsSync(json)) return json

  mkdirSync(cache, { recursive: true })
  const zip = `${cache}/${RELEASE}.zip`
  if (!existsSync(zip)) {
    console.log(`fetching ${RELEASE}.zip (~12 MB)...`)
    execFileSync('curl', ['-fsSL', '-o', zip, `${URL_BASE}/${RELEASE}.zip`], { stdio: 'inherit' })
  }
  console.log('unzipping (~200 MB)...')
  execFileSync('unzip', ['-o', '-q', zip, '-d', cache], { stdio: 'inherit' })
  if (!existsSync(json)) throw new Error(`${RELEASE}.json not found after unzip`)
  return json
}

/**
 * The photo manifest, keyed by food id: who took each picture and under what licence.
 *
 * Copied into foods.json so the app can show the credit under the photograph. Most of the
 * images are CC-BY or CC-BY-SA, which requires attribution wherever the work is shown — a
 * line in NOTICE.md discharges that for the repository, not for a phone screen.
 */
function readMedia() {
  const rows = new Map()
  const path = here('food_media.tsv')
  if (!existsSync(path)) return rows
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (!line.trim() || line.startsWith('#')) continue
    const [id, , licence, creator] = line.split('\t')
    rows.set(id, { licence, creator })
  }
  return rows
}

/** The seed, minus its comment block. */
function readSeed() {
  const rows = []
  for (const line of readFileSync(here('foods_seed.tsv'), 'utf8').split('\n')) {
    if (!line.trim() || line.startsWith('#')) continue
    const [id, fdcId, name, cat] = line.split('\t')
    rows.push({ id, fdcId: Number(fdcId), name, cat })
  }
  return rows
}

/** `Chicken breast` -> `f0012-chicken-breast.jpg`, the filename sync_food_media.sh writes. */
const imageName = (id, name) =>
  `${id}-${name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')}.jpg`

// Rounded the way a food label is: whole calories, one decimal on grams. The dataset carries
// more precision than the measurement justifies, and it all ends up multiplied by a portion
// size the user eyeballed anyway.
const g = v => Math.round((v ?? 0) * 10) / 10

const seed = readSeed()
const media = readMedia()
const db = JSON.parse(readFileSync(datasetPath(), 'utf8')).SRLegacyFoods
const byId = new Map(db.map(x => [x.fdcId, x]))

const out = []
const missing = []
for (const row of seed) {
  const rec = byId.get(row.fdcId)
  if (!rec) { missing.push(`${row.id} ${row.name} (fdcId ${row.fdcId})`); continue }

  const m = {}
  for (const fn of rec.foodNutrients) {
    for (const [k, id] of Object.entries(NUTRIENT)) if (fn.nutrient?.id === id) m[k] = fn.amount
  }
  if (m.kcal == null) { missing.push(`${row.id} ${row.name} (no energy)`); continue }

  const credit = media.get(row.id)
  out.push({
    id: row.id,
    n: row.name,
    cat: row.cat,
    kcal: Math.round(m.kcal),
    p: g(m.p),
    c: g(m.c),
    f: g(m.f),
    // A food with no manifest row has no photograph and falls back to its category glyph, so
    // it carries no filename either — that absence is what the app keys off.
    ...(credit ? { img: imageName(row.id, row.name) } : {}),
    ...(credit?.creator ? { by: credit.creator } : {}),
    ...(credit?.licence ? { lic: credit.licence } : {}),
    src: `usda:${row.fdcId}`,
  })
}

if (missing.length) {
  console.error(`refusing to write a partial catalogue — ${missing.length} unresolved:`)
  for (const m of missing) console.error('  ' + m)
  process.exit(1)
}

// Duplicate ids would repoint logged meals at the wrong food, so it is worth being loud.
const ids = new Set()
for (const f of out) {
  if (ids.has(f.id)) throw new Error(`duplicate id ${f.id} in foods_seed.tsv`)
  ids.add(f.id)
}

writeFileSync(here('../assets/data/foods.json'), JSON.stringify(out))
const byCat = {}
for (const f of out) byCat[f.cat] = (byCat[f.cat] ?? 0) + 1
console.log(`foods.json — ${out.length} foods`)
console.log(Object.entries(byCat).map(([k, v]) => `${k}:${v}`).join(' '))
