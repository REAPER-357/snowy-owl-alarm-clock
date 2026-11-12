// Renders the five alarm tones to 20-second WAV files (res/raw on Android).
// Android notification sounds play the file once, so each file loops the tone pattern.
// Names must be lowercase a-z, 0-9 and underscores: owl_<sound>.wav
import { writeFileSync, mkdirSync } from 'node:fs';

const SR = 22050, DUR = 20;
const SOUNDS = {
  'Classic Beep': { type: 'square',   period: 1.4, gain: .28, notes: [[880, 0, .12], [880, .2, .12], [880, .4, .12], [880, .6, .12]] },
  'Soft Chime':   { type: 'sine',     period: 2.4, gain: .55, notes: [[523.25, 0, .6], [659.25, .3, .6], [783.99, .6, .9]] },
  'Digital':      { type: 'triangle', period: 1.2, gain: .5,  notes: [[988, 0, .15], [740, .2, .15], [988, .4, .15], [740, .6, .15]] },
  'Gentle Bell':  { type: 'sine',     period: 3,   gain: .65, notes: [[659.25, 0, 1.4], [987.77, 0, 1.0]] },
  'Owl Hoot':     { type: 'sine',     period: 3.4, gain: .8,  notes: [[340, 0, .35], [300, .5, .35], [300, 1, .9]] }
};
const slug = n => n.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
const wave = (type, f, t) => { const ph = (f * t) % 1; return type === 'sine' ? Math.sin(2 * Math.PI * ph) : type === 'square' ? (ph < .5 ? 1 : -1) : 4 * Math.abs(ph - .5) - 1; };

mkdirSync('assets/sounds', { recursive: true });
for (const [name, def] of Object.entries(SOUNDS)) {
  const buf = new Float32Array(SR * DUR);
  for (let start = 0; start < DUR; start += def.period) {
    for (const [f, off, d] of def.notes) {
      const s0 = Math.floor((start + off) * SR), n = Math.floor(d * SR);
      for (let i = 0; i < n && s0 + i < buf.length; i++) {
        const t = i / SR;
        const env = t < .02 ? def.gain * t / .02 : def.gain * Math.pow(.001 / def.gain, (t - .02) / (d - .02));
        buf[s0 + i] += wave(def.type, f, t) * env;
      }
    }
  }
  let peak = 0; for (const v of buf) peak = Math.max(peak, Math.abs(v));
  const k = peak > 0 ? .85 / peak : 1;
  const pcm = Buffer.alloc(buf.length * 2);
  for (let i = 0; i < buf.length; i++) pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, buf[i] * k)) * 32767), i * 2);
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8); h.write('fmt ', 12);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(SR, 24);
  h.writeUInt32LE(SR * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  writeFileSync(`assets/sounds/owl_${slug(name)}.wav`, Buffer.concat([h, pcm]));
  console.log('wrote owl_' + slug(name) + '.wav');
}
