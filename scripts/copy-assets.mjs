// Copies Inter out of node_modules into www/ so the app has no CDN dependencies. (Icons come from assets/icons.)
import { cpSync, mkdirSync, existsSync } from 'node:fs';

const need = p => { if (!existsSync(p)) { console.error('Missing ' + p + ' - run "npm install" first.'); process.exit(1); } return p; };

mkdirSync('www/css', { recursive: true });
mkdirSync('www/fonts', { recursive: true });
mkdirSync('www/js', { recursive: true });

// Inter (latin subset, the weights the app uses)
for (const w of [200, 300, 400, 500, 600, 700]) {
  const f = `inter-latin-${w}-normal.woff2`;
  cpSync(need(`node_modules/@fontsource/inter/files/${f}`), `www/fonts/${f}`);
}
console.log('Assets copied to www/');
