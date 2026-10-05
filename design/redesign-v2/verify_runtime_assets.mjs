// Verify the actual imported pixels, world-coordinate metrics and approved IDs.
// This reads only public assets and local upload metadata, never credentials.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dir = path.join(here, 'assets');
const require = createRequire(path.join(here, '../../backend/package.json'));
const sharp = require('sharp');
const requireApproved = process.argv.includes('--require-approved');
const manifest = JSON.parse(await fs.readFile(path.join(dir, 'manifest.json'), 'utf8'));
const metrics = JSON.parse(await fs.readFile(path.join(dir, 'metrics.json'), 'utf8'));
const ids = JSON.parse(await fs.readFile(path.join(dir, 'asset_ids.json'), 'utf8'));
const homeIds = JSON.parse(await fs.readFile(path.join(here, '../home/asset_ids.json'), 'utf8'));
const state = await fs.readFile(path.join(dir, 'upload_state.json'), 'utf8').then(JSON.parse).catch(error => {
  if (error.code === 'ENOENT') return {};
  throw error;
});
const registry = requireApproved ? await fs.readFile(path.join(here, '../../src/Shared/RedesignAssets.luau'), 'utf8') : null;
const checked = new Map();
let approvedNames = 0;
const errors = [];
for (const item of manifest) {
  const metric = metrics[item.screen]?.[item.sourceName];
  if (registry !== null && !registry.includes(`[${JSON.stringify(item.name)}] = ${ids[item.name] || 0},`)) {
    errors.push(`${item.name}: approved ID missing from quoted Luau registry key`);
  }
  if (!metric?.imported || metric.assetKey !== item.name || JSON.stringify(metric.rect) !== JSON.stringify(item.rect)) {
    errors.push(`${item.name}: incorrect runtime metrics`);
  }
  const source = await fs.readFile(path.join(dir, item.svg), 'utf8');
  if (/<(?:[A-Za-z0-9_-]+:)?(?:text|tspan|textPath|image|feImage|script|foreignObject)(?:\s|>)/i.test(source)) {
    errors.push(`${item.name}: non-vector or text content in runtime artwork`);
  }
  if (item.homeAsset) {
    if (!Number.isSafeInteger(homeIds[item.homeAsset]) || ids[item.name] !== homeIds[item.homeAsset]) {
      errors.push(`${item.name}: existing Home ID was not reused`);
    } else approvedNames++;
    continue;
  }
  const canonical = item.uploadName || item.name;
  let actual = checked.get(item.file);
  if (!actual) {
    const bytes = await fs.readFile(path.join(dir, item.file));
    const { data, info } = await sharp(bytes).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const pixelHash = createHash('sha256').update(`${info.width}x${info.height}:`).update(data).digest('hex');
    let alpha = 0;
    for (let index = 3; index < data.length; index += 4) alpha += data[index];
    actual = { width: info.width, height: info.height, pixelHash, hash: createHash('sha256').update(bytes).digest('hex'), visible: alpha > 0 };
    checked.set(item.file, actual);
  }
  if (!actual.visible || actual.width !== item.width || actual.height !== item.height || actual.pixelHash !== item.pixelHash) {
    errors.push(`${item.name}: PNG pixels/dimensions do not match the current manifest`);
  }
  const entry = state[canonical];
  const approved = entry?.moderation?.includes('APPROVED') && entry.pixelHash === item.pixelHash
    && entry.hash === actual.hash && Number.isSafeInteger(entry.assetId) && entry.assetId > 0
    && ids[item.name] === entry.assetId && ids[canonical] === entry.assetId;
  if (approved) approvedNames++;
  else if (requireApproved) errors.push(`${item.name}: no matching moderation-approved raw Image`);
}
const excluded = Object.values(metrics).flatMap(screen => Object.values(screen)).filter(item => !item.imported);
for (const item of excluded) if (manifest.some(asset => asset.name === item.assetKey)) errors.push(`${item.assetKey}: live art was imported`);
const report = { assetNames: manifest.length, uniquePngs: checked.size,
  reusedHomeNames: manifest.filter(item => item.homeAsset).length, excludedLiveArt: excluded.length,
  approvedNames, allApproved: approvedNames === manifest.length, errors };
await fs.writeFile(path.join(dir, 'verification.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));
if (errors.length) process.exitCode = 1;
