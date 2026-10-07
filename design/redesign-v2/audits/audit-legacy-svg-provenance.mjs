// Read-only provenance verification for the three legacy static UI families.
// Never reads credential files, upload logs, or remote assets.
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../..');
const require = createRequire(path.join(repo, 'backend/package.json'));
const sharp = require('sharp');
const hash = data => createHash('sha256').update(data).digest('hex');
const families = [
  { name: 'UIAssets', dir: 'design/assets', svg: item => item.file.replace(/\.png$/, '.svg'), renderer: 'Chromium source rendering with transparent crop; renderer differences expected', exactPixels: false },
  { name: 'HomeAssets', dir: 'design/home', svg: item => `svg/${item.name}.svg`, renderer: 'design/render_home_assets.mjs Sharp SVG rendering', exactPixels: true },
  { name: 'ScreenAssets', dir: 'design/screens/assets', svg: item => item.svg, renderer: 'design/render_screen_assets.mjs Sharp SVG rendering', exactPixels: true },
];
const report = { scope: 'Authored static UI decorations; live avatar/catalog/player generated media excluded', families: [], failures: [] };
for (const family of families) {
  const dir = path.join(repo, family.dir);
  const manifest = JSON.parse(await readFile(path.join(dir, 'manifest.json'), 'utf8'));
  const entries = [];
  for (const item of manifest) {
    if (item.homeAsset) { entries.push({ name: item.name, homeAlias: item.homeAsset }); continue; }
    const svgPath = family.svg(item);
    try {
      const svgBytes = await readFile(path.join(dir, svgPath));
      const svg = svgBytes.toString('utf8');
      const forbidden = [...svg.matchAll(/<(?:[\w-]+:)?(image|feImage|script|foreignObject)(?:\s|>)/gi)].map(match => match[1]);
      const external = [...svg.matchAll(/(?:href|xlink:href)\s*=\s*["']([^"']*)["']/gi)].map(match => match[1]).filter(value => !value.startsWith('#'));
      const pngBytes = await readFile(path.join(dir, item.file));
      const png = await sharp(pngBytes).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      let pixelsMatch = null;
      if (family.exactPixels) {
        const rendered = await sharp(svgBytes).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
        pixelsMatch = rendered.info.width === png.info.width && rendered.info.height === png.info.height && rendered.data.equals(png.data);
      }
      const entry = { name: item.name, svg: `${family.dir}/${svgPath}`, png: `${family.dir}/${item.file}`, svgSha256: hash(svgBytes), pngSha256: hash(pngBytes), width: png.info.width, height: png.info.height, embeddedRasterTags: forbidden, externalResources: external, exactSvgRenderedPixels: pixelsMatch };
      entries.push(entry);
      if (forbidden.length || external.length || pixelsMatch === false) report.failures.push({ family: family.name, ...entry });
    } catch (error) { report.failures.push({ family: family.name, name: item.name, error: error.message }); }
  }
  report.families.push({ name: family.name, count: manifest.length, renderer: family.renderer, entries });
}
await writeFile(path.join(here, 'legacy-svg-provenance.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ families: report.families.map(family => ({ name: family.name, total: family.count, homeAliases: family.entries.filter(entry => entry.homeAlias).length, verifiedVectorSvg: family.entries.filter(entry => entry.svg && !entry.embeddedRasterTags.length && !entry.externalResources.length).length, exactPixelMatches: family.entries.filter(entry => entry.exactSvgRenderedPixels === true).length })), failures: report.failures.map(failure => ({ family: failure.family, name: failure.name, error: failure.error, exactSvgRenderedPixels: failure.exactSvgRenderedPixels })) }, null, 2));
