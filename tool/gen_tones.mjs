// The WebAudio beeps from lib/sound.js, rendered offline as WAVs.
//
// sound.js builds each beep the same way: a sine oscillator through a gain node whose value
// ramps exponentially 0.001 → 0.35 over 20 ms, then back down to 0.001 over the tone's
// duration, with the oscillator stopped 50 ms later. Reproducing that envelope here — rather
// than emitting a bare sine — is what keeps the click-free attack and soft tail the app has.
import { writeFileSync, mkdirSync } from 'node:fs'

const RATE = 44100
const PEAK = 0.35
const FLOOR = 0.001
const ATTACK = 0.02
const TAIL = 0.05

// Every (frequency, duration) pair beep() is actually called with:
//   rest over / workout finished   880 @ .15 · 1320 @ .4 · 1100 @ .15 · 1320 @ .3
//   rest countdown (last 3 s)      660 @ .1
//   set checked off                1040 @ .12
const TONES = [[880, 0.15], [1320, 0.4], [1320, 0.3], [1100, 0.15], [660, 0.1], [1040, 0.12]]

const envelope = (t, dur) => {
  if (t < ATTACK) return FLOOR * Math.pow(PEAK / FLOOR, t / ATTACK)
  if (t < dur) return PEAK * Math.pow(FLOOR / PEAK, (t - ATTACK) / (dur - ATTACK))
  return FLOOR
}

function wav(freq, dur) {
  const n = Math.round((dur + TAIL) * RATE)
  const data = Buffer.alloc(n * 2)
  for (let i = 0; i < n; i++) {
    const t = i / RATE
    const s = Math.sin(2 * Math.PI * freq * t) * envelope(t, dur)
    data.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(s * 32767))), i * 2)
  }
  const head = Buffer.alloc(44)
  head.write('RIFF', 0); head.writeUInt32LE(36 + data.length, 4); head.write('WAVE', 8)
  head.write('fmt ', 12); head.writeUInt32LE(16, 16); head.writeUInt16LE(1, 20)
  head.writeUInt16LE(1, 22); head.writeUInt32LE(RATE, 24); head.writeUInt32LE(RATE * 2, 28)
  head.writeUInt16LE(2, 32); head.writeUInt16LE(16, 34)
  head.write('data', 36); head.writeUInt32LE(data.length, 40)
  return Buffer.concat([head, data])
}

const dir = new URL('../assets/audio/', import.meta.url)
mkdirSync(dir, { recursive: true })
for (const [freq, dur] of TONES) {
  const name = `${freq}_${Math.round(dur * 1000)}.wav`
  const buf = wav(freq, dur)
  writeFileSync(new URL(name, dir), buf)
  console.log(`  ${name} — ${(buf.length / 1024).toFixed(1)} KB`)
}
