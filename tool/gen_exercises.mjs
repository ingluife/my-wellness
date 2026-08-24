// Converts openGym's exercises-data.js (ES module, 888 KB) into a plain JSON asset.
// Field names are kept exactly as the source has them — the whole app indexes on them.
import { writeFileSync } from 'node:fs'
import { EXDB } from '../../openGym/frontend/src/lib/exercises-data.js'

const out = new URL('../assets/data/exercises.json', import.meta.url)
writeFileSync(out, JSON.stringify(EXDB))

const bp = [...new Set(EXDB.map(e => e.bp))].sort()
const eq = [...new Set(EXDB.map(e => e.eq))].sort()
console.log(`exercises.json — ${EXDB.length} exercises · ${bp.length} body parts · ${eq.length} equipment`)
