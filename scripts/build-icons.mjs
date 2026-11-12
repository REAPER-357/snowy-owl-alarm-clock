// Builds the icon sprite and writes it INSIDE www/index.html (between <!--ICONS--> and <!--/ICONS-->).
// - every .svg in www/assets/icons (and assets/icons) becomes <symbol id="ic-NAME"> (lucide / heroicons-outline
//   style, 24x24 stroke). If a name exists in both folders, www/assets/icons wins.
// - icons already in the page that have no file are kept, so a missing file never makes an icon vanish
// Drop your own lucide files (same names) into www/assets/icons and run "npm run build".
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';

const page = 'www/index.html', dirs = ['assets/icons', 'www/assets/icons'];
const START = '<!--ICONS-->', END = '<!--/ICONS-->';
let html = readFileSync(page, 'utf8');
const a = html.indexOf(START), b = html.indexOf(END);
if (a < 0 || b < 0 || b < a) { console.error(`Markers ${START} ... ${END} not found in ${page}`); process.exit(1); }

const symbols = new Map();
for (const m of html.slice(a, b).matchAll(/<symbol id="ic-([^"]+)"[\s\S]*?<\/symbol>/g)) symbols.set(m[1], m[0]);
const kept = symbols.size;

let fromFiles = 0;
const found = dirs.filter(d => existsSync(d));
for (const dir of found) {
  for (const f of readdirSync(dir).sort()) {
    if (!f.endsWith('.svg')) continue;
    const name = f.slice(0, -4);
    const src = readFileSync(`${dir}/${f}`, 'utf8').replace(/<!--[\s\S]*?-->/g, '');
    const open = src.match(/<svg\b[^>]*>/i), end = src.lastIndexOf('</svg>');
    if (!open || end < 0) { console.warn('Skipping ' + dir + '/' + f + ' (not an svg)'); continue; }
    const vb = (open[0].match(/viewBox="([^"]+)"/) || [, '0 0 24 24'])[1];
    symbols.set(name, `<symbol id="ic-${name}" viewBox="${vb}">${src.slice(open.index + open[0].length, end).trim()}</symbol>`);
    fromFiles++;
  }
}
if (!found.length) console.warn('No icon folder (' + dirs.join(' or ') + ') - using the icons already in the page.');

const sprite = '<svg xmlns="http://www.w3.org/2000/svg" width="0" height="0" style="position:absolute" aria-hidden="true"><defs>' +
  [...symbols.keys()].sort().map(k => symbols.get(k)).join('') + '</defs></svg>';
html = html.slice(0, a + START.length) + '\n' + sprite + '\n' + html.slice(b);
writeFileSync(page, html);
console.log(`Icons: ${symbols.size} in page (${fromFiles} from ${found.join(' + ') || 'no folder'}, ${kept} were already inline)`);
