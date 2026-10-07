// Independently render the runtime SVGs and compare their raw pixels to PNGs.
// Writes only audit metadata; does not modify manifests, assets, or registries.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const auditDir = path.dirname(fileURLToPath(import.meta.url));
const here = path.dirname(auditDir);
const assets = path.join(here, 'assets');
const sharp = createRequire(path.join(here, '../../backend/package.json'))('sharp');
const manifest = JSON.parse(await fs.readFile(path.join(assets, 'manifest.json'), 'utf8'));
const pngs = new Map();
const errors = [];
let matches = 0;
for (const item of manifest) {
  if (item.homeAsset) continue;
  try {
    const svg = await fs.readFile(path.join(assets, item.svg));
    const rendered = await sharp(svg).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    let png = pngs.get(item.file);
    if (!png) {
      const bytes = await fs.readFile(path.join(assets, item.file));
      png = await sharp(bytes).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      pngs.set(item.file, png);
    }
    const hash = createHash('sha256').update(`${rendered.info.width}x${rendered.info.height}:`).update(rendered.data).digest('hex');
    if (rendered.info.width !== item.width || rendered.info.height !== item.height ||
        png.info.width !== rendered.info.width || png.info.height !== rendered.info.height ||
        !rendered.data.equals(png.data) || hash !== item.pixelHash) {
      errors.push({ name: item.name, error: 'Stored runtime PNG or manifest hash differs from independently rendered vector SVG.' });
    } else matches++;
  } catch (error) { errors.push({ name: item.name, error: String(error) }); }
}
const report = {
  generatedAtUtc: new Date().toISOString(), runtimeNames: manifest.length,
  checkedSVGNames: manifest.filter(item => !item.homeAsset).length,
  uniqueStoredPNGFiles: pngs.size, exactPixelMatches: matches,
  reusedHomeAliases: manifest.filter(item => item.homeAsset).map(item => item.name),
  errors,
};
await fs.writeFile(path.join(auditDir, 'svg-png-pixel-verification.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
if (errors.length) process.exitCode = 1;
