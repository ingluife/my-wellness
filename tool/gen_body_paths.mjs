// Body geometry for the muscle map: male/female × front/back, each { vb, p: { slug: [d…] } }.
import { writeFileSync } from 'node:fs'
import BODY from '../../openGym/frontend/src/lib/body-paths.js'

writeFileSync(new URL('../assets/data/body_paths.json', import.meta.url), JSON.stringify(BODY))

for (const body of Object.keys(BODY)) {
  for (const view of Object.keys(BODY[body])) {
    const v = BODY[body][view]
    const n = Object.values(v.p).reduce((a, l) => a + l.length, 0)
    console.log(`  ${body}/${view}  vb="${v.vb}"  ${Object.keys(v.p).length} parts · ${n} paths`)
  }
}
