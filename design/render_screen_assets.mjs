// Render transparent screen components, deduplicate pixel-identical art, and
// create a labeled contact sheet. This script never reads upload credentials.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../backend/package.json'));
const sharp = require('sharp');
const args = process.argv.slice(2);
const value = flag => args.includes(flag) ? args[args.indexOf(flag) + 1] : undefined;
const dir = path.resolve(value('--dir') || path.join(here, 'screens/assets'));
const manifestPath = path.join(dir, 'manifest.json');
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
await mkdir(path.join(dir, 'png'), { recursive: true });
const unique = new Map();
const assets = manifest.filter(item => !item.homeAsset);
let duplicateCount = 0;
for (const item of assets) {
  const svg = await readFile(path.join(dir, item.svg));
  if (/<(?:[A-Za-z0-9_-]+:)?(?:text|tspan|textPath|image|feImage|script|foreignObject)(?:\s|>)/i.test(svg.toString('utf8'))) {
    throw new Error(`Unsafe or non-vector content remains in ${item.name}.svg.`);
  }
  const { data, info } = await sharp(svg).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  if (info.width !== item.width || info.height !== item.height) throw new Error(`Incorrect dimensions: ${item.name}`);
  const hash = createHash('sha256').update(`${info.width}x${info.height}:`).update(data).digest('hex');
  item.pixelHash = hash;
  const canonical = unique.get(hash);
  if (canonical) {
    item.uploadName = canonical.name;
    item.file = canonical.file;
    duplicateCount++;
  } else {
    item.uploadName = item.name;
    item.file = `png/${item.name}.png`;
    await sharp(data, { raw: info }).png().toFile(path.join(dir, item.file));
    unique.set(hash, item);
  }
}
await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
const cells = [];
const cellWidth = 240, cellHeight = 176, columns = 5;
const escapeXml = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const show = [...unique.values()];
for (let i = 0; i < show.length; i++) {
  const item = show[i];
  const thumb = await sharp(path.join(dir, item.file)).resize(220, 130, { fit: 'contain', background: '#15233b' }).png().toBuffer();
  const left = (i % columns) * cellWidth, top = Math.floor(i / columns) * cellHeight;
  cells.push({ input: thumb, left: left + 10, top: top + 5 });
  cells.push({ input: Buffer.from(`<svg width="240" height="30"><text x="120" y="20" text-anchor="middle" font-family="Arial" font-size="12" fill="white">${escapeXml(item.name)}</text></svg>`), left, top: top + 140 });
}
await sharp({ create: { width: columns * cellWidth, height: Math.ceil(show.length / columns) * cellHeight, channels: 4, background: '#15233b' } })
  .composite(cells).png().toFile(path.join(dir, 'contact-sheet.png'));
console.log(`Rendered ${assets.length} components as ${unique.size} unique transparent PNGs; ${duplicateCount} duplicate names reuse images.`);
console.log(`Contact sheet: ${path.relative(here, path.join(dir, 'contact-sheet.png'))}`);
