// Builds assets/data/dishes.json from the curated seed.
//
// The day planner proposes the user's own saved recipes before anything else, and those are
// always the better suggestion — they are in the user's words, made of food the user buys. This
// catalogue exists for the fortnight before there are any: a profile on its first day has an
// empty recipe book and still deserves a plan that looks like food rather than a nutritionally
// correct list of ingredients.
//
// That is also why it is capped. Sixty dishes is enough that reshuffling stays interesting
// through the period it has to cover; the value of dish sixty-one is close to nothing next to
// one recipe the user writes down, and every one of them costs eleven translations.
//
//   node tool/gen_dishes.mjs
//
// Curation lives in tool/dishes_seed.tsv. The generator's job is to refuse to write a catalogue
// that points at a food which does not exist — a typo in an id would otherwise surface as a
// blank row in someone's breakfast.
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const here = p => fileURLToPath(new URL(p, import.meta.url))

// Must match `PartRole` in lib/domain/day_plan_source.dart. The bands each of these implies
// live in Dart, not here: one place to change them, and no need to regenerate the asset to do
// it. A part carries only what the *recipe* says — which food, what job it does, how much.
const ROLES = new Set(['fixed', 'unit', 'flex', 'accent', 'side', 'trace'])

// Lowercased slot names from `_splits` in lib/domain/nutrition.dart, so the catalogue and the
// meal-split table cannot drift apart.
const SLOTS = new Set(['breakfast', 'lunch', 'snack', 'dinner'])

// Must match `_cuisines` in lib/domain/dishes.dart.
const CUISINES = new Set([
  'generic', 'mediterranean', 'latin', 'european', 'asian', 'indian', 'middleeastern',
])

const foods = new Map(
  JSON.parse(readFileSync(here('../assets/data/foods.json'), 'utf8')).map(f => [f.id, f]))

const errors = []
const dishes = []
const seen = new Set()

const rows = readFileSync(here('dishes_seed.tsv'), 'utf8')
  .split('\n')
  .map((line, i) => [i + 1, line])
  .filter(([, line]) => line.trim() && !line.startsWith('#'))

for (const [lineNo, line] of rows) {
  const at = msg => errors.push(`dishes_seed.tsv:${lineNo}: ${msg}`)
  const [id, name, slots, cuisines, parts] = line.split('\t')

  if (!/^d\d{4}$/.test(id ?? '')) { at(`bad id ${JSON.stringify(id)}`); continue }
  if (seen.has(id)) { at(`duplicate id ${id}`); continue }
  seen.add(id)
  if (!name?.trim()) { at(`${id} has no name`); continue }

  const slotList = (slots ?? '').split(',').map(s => s.trim()).filter(Boolean)
  for (const s of slotList) if (!SLOTS.has(s)) at(`${id} unknown slot ${JSON.stringify(s)}`)
  if (!slotList.length) at(`${id} is filed under no meal`)

  const cuisineList = (cuisines ?? '').split(',').map(s => s.trim()).filter(Boolean)
  for (const c of cuisineList) if (!CUISINES.has(c)) at(`${id} unknown cuisine ${JSON.stringify(c)}`)
  if (!cuisineList.length) at(`${id} is tagged with no cuisine`)

  const partList = []
  for (const raw of (parts ?? '').split(',').map(s => s.trim()).filter(Boolean)) {
    const [fid, role, grams, step] = raw.split(':')
    const food = foods.get(fid)
    // The whole reason this is a generator rather than a hand-edited JSON file.
    if (!food) { at(`${id} refers to ${JSON.stringify(fid)}, which is not a food`); continue }
    if (!ROLES.has(role)) { at(`${id}/${fid} unknown role ${JSON.stringify(role)}`); continue }
    const g = Number(grams)
    if (!Number.isFinite(g) || g <= 0) { at(`${id}/${fid} bad grams ${JSON.stringify(grams)}`); continue }
    const part = { fid, role, g }
    if (step !== undefined) {
      const s = Number(step)
      if (!Number.isFinite(s) || s <= 0) at(`${id}/${fid} bad step ${JSON.stringify(step)}`)
      else part.step = s
    }
    if (role === 'unit' && part.step === undefined) at(`${id}/${fid} is a unit with no step`)
    partList.push(part)
  }
  if (partList.length < 2) at(`${id} has fewer than two parts`)

  // A reference serving nobody would recognise as a plate is a seed-file mistake, and it is
  // invisible until it turns up in somebody's plan.
  const kcal = partList.reduce((a, p) => a + foods.get(p.fid).kcal * p.g / 100, 0)
  if (kcal < 120 || kcal > 1200) at(`${id} prices out at ${Math.round(kcal)} kcal`)

  dishes.push({ id, n: name.trim(), slots: slotList, cuisines: cuisineList, parts: partList })
}

if (errors.length) {
  console.error(`refusing to write a broken catalogue — ${errors.length} problem(s):`)
  for (const e of errors) console.error('  ' + e)
  process.exit(1)
}

writeFileSync(here('../assets/data/dishes.json'), JSON.stringify(dishes))

const bySlot = {}
for (const d of dishes) for (const s of d.slots) bySlot[s] = (bySlot[s] ?? 0) + 1
const byCuisine = {}
for (const d of dishes) for (const c of d.cuisines) byCuisine[c] = (byCuisine[c] ?? 0) + 1
console.log(`dishes.json — ${dishes.length} dishes`)
console.log('  ' + Object.entries(bySlot).map(([k, v]) => `${k}:${v}`).join(' '))
console.log('  ' + Object.entries(byCuisine).map(([k, v]) => `${k}:${v}`).join(' '))
