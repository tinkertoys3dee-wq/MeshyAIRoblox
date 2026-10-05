import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../backend/package.json'));
const sharp = require('sharp');
const dir = path.join(here, 'home');
const manifest = JSON.parse(await readFile(path.join(dir, 'manifest.json'), 'utf8'));
await mkdir(path.join(dir, 'png'), { recursive: true });
for (const item of manifest) {
  await sharp(path.join(dir, 'svg', `${item.name}.svg`)).png().toFile(path.join(dir, item.file));
}
const cells = [];
const cellWidth = 240, cellHeight = 190, columns = 5;
for (let i = 0; i < manifest.length; i++) {
  const item = manifest[i];
  const thumb = await sharp(path.join(dir, item.file)).resize(220, 144, { fit: 'contain', background: '#15233b' }).png().toBuffer();
  const left = (i % columns) * cellWidth + 10, top = Math.floor(i / columns) * cellHeight;
  cells.push({ input: thumb, left, top: top + 5 });
  cells.push({ input: Buffer.from(`<svg width="240" height="32"><text x="120" y="23" text-anchor="middle" font-family="Arial" font-size="15" fill="white">${item.name}</text></svg>`), left: left - 10, top: top + 148 });
}
await sharp({ create: { width: columns * cellWidth, height: Math.ceil(manifest.length / columns) * cellHeight, channels: 4, background: '#15233b' } })
  .composite(cells).png().toFile(path.join(dir, 'contact-sheet.png'));
console.log(`Rendered ${manifest.length} transparent PNG assets and contact-sheet.png.`);
