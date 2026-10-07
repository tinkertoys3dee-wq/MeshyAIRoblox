// Verify every authored static UI registry against its actual vector source.
// Live Roblox thumbnails and player-created pictures are intentionally outside
// the static UI pipeline. This command never reads keys or calls a network API.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { assertVectorSvg, sha256, verifySvgPng } from './svg_png_guard.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..');
const output = path.join(here, 'redesign-v2/audits/static-ui-provenance.json');
const families = [
  { name: 'UIAssets', dir: 'assets', exact: false, renderer: 'Chromium SVG export with transparent crop', svg: item => item.file.replace(/\.png$/i, '.svg') },
  { name: 'HomeAssets', dir: 'home', exact: true, renderer: 'Sharp SVG export' },
  { name: 'ScreenAssets', dir: 'screens/assets', exact: true, renderer: 'Sharp SVG export' },
  { name: 'RedesignAssets', dir: 'redesign-v2/assets', exact: true, renderer: 'Sharp SVG export' },
];
const cache = new Map();
const report = { scope: 'All authored static UI registry entries, including fallback artwork',
  excludes: ['live avatar thumbnails', 'catalog/item thumbnails', 'player-created graphics'],
  families: [], failures: [] };
const registry = async name => {
  const source = await fs.readFile(path.join(repo, 'src/Shared', `${name}.luau`), 'utf8');
  return new Map([...source.matchAll(/^\s*(?:\["([^"]+)"\]|([\w]+))\s*=\s*(\d+)\s*,/gm)]
    .map(match => [match[1] || match[2], Number(match[3])]));
};
const homeIds = await registry('HomeAssets');
const homeManifest = JSON.parse(await fs.readFile(path.join(here, 'home/manifest.json'), 'utf8'));
for (const family of families) {
  const dir = path.join(here, family.dir);
  const manifest = JSON.parse(await fs.readFile(path.join(dir, 'manifest.json'), 'utf8'));
  const ids = await registry(family.name);
  const entries = [];
  for (const item of manifest) {
    try {
      if (!ids.get(item.name)) throw new Error('Missing positive runtime registry ID.');
      let evidence;
      if (item.homeAsset) {
        const home = homeManifest.find(asset => asset.name === item.homeAsset);
        if (!home || ids.get(item.name) !== homeIds.get(home.name)) throw new Error('Home alias does not match its runtime source.');
        evidence = { ...await verifySvgPng(path.join(here, 'home'), home, { cache }), homeAlias: home.name };
      } else if (family.exact) {
        evidence = await verifySvgPng(dir, item, { cache });
      } else {
        const svg = family.svg(item);
        const svgBytes = await fs.readFile(path.join(dir, svg));
        assertVectorSvg(svgBytes, item.name, { allowText: true });
        const pngBytes = await fs.readFile(path.join(dir, item.file));
        if (!pngBytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error('PNG signature is missing.');
        const source = svgBytes.toString('utf8');
        const width = Number(source.match(/<svg\b[^>]*\bwidth="([\d.]+)"/i)?.[1]);
        const height = Number(source.match(/<svg\b[^>]*\bheight="([\d.]+)"/i)?.[1]);
        if (width !== pngBytes.readUInt32BE(16) || height !== pngBytes.readUInt32BE(20)) throw new Error('PNG dimensions differ from the SVG source.');
        if (item.origin && (item.origin.kind !== 'pure-svg' || item.origin.renderer !== 'chromium-svg'
          || item.origin.source !== path.basename(svg) || item.origin.sourceSha256 !== sha256(svgBytes)
          || item.origin.pngSha256 !== sha256(pngBytes) || item.origin.width !== width || item.origin.height !== height)) {
          throw new Error('SVG/PNG origin stamp is stale; export the vector again.');
        }
        evidence = { svg, png: item.file, svgSha256: sha256(svgBytes), pngSha256: sha256(pngBytes), width, height,
          exactSvgRenderedPixels: null, proof: 'Existing Chromium exporter produces this PNG from its paired genuine SVG; independent Sharp pixel equality is not asserted.' };
      }
      entries.push({ name: item.name, assetId: ids.get(item.name), ...evidence });
    } catch (error) { report.failures.push({ family: family.name, name: item.name, error: error.message }); }
  }
  for (const name of ids.keys()) if (!manifest.some(item => item.name === name)) report.failures.push({ family: family.name, name, error: 'Registry entry has no SVG export manifest source.' });
  report.families.push({ name: family.name, renderer: family.renderer, registryNames: ids.size, entries });
}
report.totalRegistryNames = report.families.reduce((total, family) => total + family.registryNames, 0);
report.exactPixelVerifiedNames = report.families.flatMap(family => family.entries).filter(entry => entry.exactSvgRenderedPixels === true).length;
report.allVectorSources = report.failures.length === 0;
await fs.mkdir(path.dirname(output), { recursive: true });
await fs.writeFile(output, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ totalRegistryNames: report.totalRegistryNames, exactPixelVerifiedNames: report.exactPixelVerifiedNames,
  families: report.families.map(family => ({ name: family.name, registryNames: family.registryNames, verified: family.entries.length })),
  failures: report.failures }, null, 2));
if (report.failures.length) process.exitCode = 1;
