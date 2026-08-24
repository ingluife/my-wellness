// Resolves a public-domain photograph for every food in assets/data/foods.json and records it
// in tool/food_media.tsv.
//
// Splitting "decide which image" from "download it" is deliberate. Openverse results shift as
// the index grows, so resolving at download time would mean a different photo every time
// anybody ran the sync. The manifest is checked in, so the choice is reviewed once, in a diff,
// and everyone gets the same pictures.
//
// cc0, pdm, by and by-sa are all accepted; nc (non-commercial) never is.
//
// Public domain alone was tried first and does not work. The CC0 pool for food is thin and
// noisy — "Bacon" returns busts of Francis Bacon, "Beef chuck" returns a Chuck E. Cheese sign —
// and about a third of what it produced was the wrong subject entirely. A catalogue of wrong
// photographs is worse than no photographs, because the glyph fallback is at least honest.
//
// Attribution is the price and it is paid properly: every row here records the creator, the
// licence and the source page, gen_foods.mjs copies the credit into foods.json, and the app
// shows it under the photograph in the food detail sheet. This is the same posture the repo
// already takes with its 1,324 exercise images.
//
//   node tool/fetch_food_media.mjs [--force] [--limit N]
//
// Anonymous Openverse allows 20 requests a minute and 200 a day, and the catalogue is larger
// than that. Foods already in the manifest are skipped, so the honest way to run this is to
// run it again tomorrow. Set OPENVERSE_TOKEN for higher limits.
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const here = p => fileURLToPath(new URL(p, import.meta.url))
const MANIFEST = here('food_media.tsv')
const API = 'https://api.openverse.org/v1/images/'

const force = process.argv.includes('--force')
const limitArg = process.argv.indexOf('--limit')
const limit = limitArg > -1 ? Number(process.argv[limitArg + 1]) : Infinity

const HEADER = `# Which photograph stands for which food, and where it came from.
#
# Written by tool/fetch_food_media.mjs, consumed by tool/sync_food_media.sh. Checked in so the
# catalogue looks the same for everyone and so provenance is reviewable without running
# anything — every row is a cc0 or public-domain-mark image from Openverse.
#
# Editing a row by hand is fine and is how a bad automatic pick gets fixed; the fetcher leaves
# existing rows alone unless run with --force.
#
# id\tfood\tlicence\tcreator\timage url\tsource page`

function readManifest() {
  const rows = new Map()
  if (!existsSync(MANIFEST)) return rows
  for (const line of readFileSync(MANIFEST, 'utf8').split('\n')) {
    if (!line.trim() || line.startsWith('#')) continue
    const p = line.split('\t')
    rows.set(p[0], p)
  }
  return rows
}

// Titles that are about a person, a place or a brand rather than a food. Most of the damage
// the first pass did came from here: surnames (Bacon, Broccoli, Berry), statues, and the chains
// whose signage is all over the free-licence pools.
const NOT_FOOD =
  /statue|portrait|bust of|memorial|church|cathedral|museum|castle|street|avenue|hotel|\bmap\b|logo|signage|billboard|storefront|premiere|festival|award|actor|actress|singer|band\b|album|\bSDCC\b|comic.?con|red carpet|stadium|university|college|library|graffiti|mural|postage|stamp|coat of arms|flag of|cemetery|grave|plaque|diagram|chart|drawing|illustration|painting|engraving|clipart|vector|icon set/i

// A plated dish is not the ingredient. Penalised, not rejected: for some foods (a stew, a
// bread) the composed shot is the only honest picture there is.
const COMPOSED =
  /recipe|salad|soup|sandwich|burger|pizza|casserole|stir.?fry|noodle|curry|stew|dinner|lunch|breakfast|buffet|restaurant|menu|platter/i

/**
 * How well one Openverse result stands for [name], or null if it is not a candidate at all.
 *
 * The hard requirement is what makes this usable: every meaningful word of the food's name has
 * to appear in the title. "Beef chuck" then rejects a Chuck E. Cheese sign for having no beef
 * in it, which no amount of weighting reliably did.
 */
function score(r, name) {
  const title = (r.title ?? '').toLowerCase()
  if (!title) return null
  // Qualifiers after a comma ("Chicken breast, roasted") are not part of the subject.
  const subject = name.toLowerCase().split(',')[0]
  const words = subject.split(/[^a-z]+/).filter(w => w.length > 2)
  for (const w of words) {
    // Singular/plural both count: the catalogue says "Almonds", Commons says "Almond".
    const stem = w.replace(/(ies|es|s)$/, '')
    if (!new RegExp(`\\b${stem}`, 'i').test(title)) return null
  }
  if (NOT_FOOD.test(title)) return null

  let v = 0
  // Commons photographs are far more often a plain shot of the ingredient; Flickr skews to
  // holiday snaps and kitchen scenes, which is the wrong picture for a catalogue row.
  if (r.source === 'wikimedia') v += 45
  if (COMPOSED.test(title)) v -= 30
  // A title that is little more than the food's own name is usually a photograph of exactly
  // that and nothing else.
  v += Math.max(0, 40 - (title.length - subject.length))
  if (title.startsWith(words[0])) v += 15
  const w = r.width ?? 0
  if (w >= 1200) v += 12
  else if (w < 500) v -= 45
  return v
}

/// Below this, the food is left without a photograph and shows its category glyph instead.
const MIN_SCORE = 20

const sleep = ms => new Promise(r => setTimeout(r, ms))

const foods = JSON.parse(readFileSync(here('../assets/data/foods.json'), 'utf8'))
const manifest = readManifest()

// Written after every row, not once at the end. This run takes twelve minutes against the
// anonymous rate limit and is expected to be interrupted and resumed; losing an hour of
// resolved rows to a Ctrl-C would make the resumability pointless.
const flush = () => {
  const ordered = foods.map(f => manifest.get(f.id)).filter(Boolean)
  writeFileSync(MANIFEST, HEADER + '\n' + ordered.map(r => r.join('\t')).join('\n') + '\n')
  return ordered.length
}
const headers = { accept: 'application/json' }
if (process.env.OPENVERSE_TOKEN) headers.authorization = `Bearer ${process.env.OPENVERSE_TOKEN}`

let done = 0
let added = 0
for (const food of foods) {
  if (!force && manifest.has(food.id)) continue
  if (done >= limit) break

  const q = encodeURIComponent(food.n.replace(/,.*$/, ''))
  // Commons first: its food photography is overwhelmingly plain shots of the subject.
  const url = `${API}?q=${q}&license=cc0,pdm,by,by-sa&page_size=20&mature=false`
  let res
  try {
    // A hung request would otherwise stall the whole run indefinitely — fetch has no default
    // timeout, and this loop is long enough that one bad connection is likely.
    res = await fetch(url, { headers, signal: AbortSignal.timeout(20_000) })
  } catch (e) {
    console.error(`  ${food.id} ${food.n}: ${e.message}`)
    continue
  }
  done++

  if (res.status === 429) {
    console.error(`rate limited after ${added} new rows — rerun later to continue`)
    break
  }
  if (!res.ok) { console.error(`  ${food.id} ${food.n}: HTTP ${res.status}`); continue }

  const { results = [] } = await res.json()
  const scored = []
  for (const r of results) {
    if (!r.url || String(r.license).includes('nc')) continue
    const v = score(r, food.n)
    if (v !== null && v >= MIN_SCORE) scored.push([v, r])
  }
  if (!scored.length) {
    // Deliberately leaves the row out. The glyph fallback is better than a wrong photograph.
    console.error(`  ${food.id} ${food.n}: no confident match`)
    continue
  }

  scored.sort((a, b) => b[0] - a[0])
  const best = scored[0][1]
  manifest.set(food.id, [
    food.id,
    food.n,
    `${best.license}${best.license_version ? '-' + best.license_version : ''}`,
    (best.creator ?? 'unknown').replace(/\s+/g, ' ').trim(),
    best.url,
    best.foreign_landing_url ?? '',
  ])
  added++
  flush()

  // Stay inside the 20/min burst allowance.
  if (!process.env.OPENVERSE_TOKEN) await sleep(3200)
}

console.log(`food_media.tsv — ${flush()}/${foods.length} foods resolved (+${added} this run)`)
