// Focused checks for the SVG-origin guard; no uploads or credentials.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { assertVectorSvg, verifySvgPng } from './svg_png_guard.mjs';

const require = createRequire(new URL('../backend/package.json', import.meta.url));
const sharp = require('sharp');
const svg = color => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><rect width="24" height="24" fill="${color}"/></svg>`);
const wrap = body => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">${body}</svg>`);
let checks = 0;
assertVectorSvg(svg('#1188ff')); checks++;
for (const unsafe of [
  wrap('<image href="data:image/png;base64,AA=="/>'),
  wrap('<feImage href="picture.png"/>'),
  wrap('<g><use href="https://example.com/icon.svg#icon"/></g>'),
  wrap('<rect fill="url(https://example.com/paint.svg#paint)"/>'),
  wrap('<g onclick="doSomething()"/>'),
  wrap('<style>@import "https://example.com/a.css";</style>'),
  wrap('<text>Rasterized UI lettering</text>'),
  Buffer.from('<!DOCTYPE svg [<!ENTITY a "data:image/png;base64,AA==">]><svg/>'),
]) { assert.throws(() => assertVectorSvg(unsafe)); checks++; }
const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'forge-svg-origin-'));
const svgFile = path.join(directory, 'shape.svg');
const pngFile = path.join(directory, 'shape.png');
try {
  await fs.writeFile(svgFile, svg('#1188ff'));
  await sharp(svg('#1188ff')).png().toFile(pngFile);
  const item = { name: 'Shape', svg: 'shape.svg', file: 'shape.png', width: 24, height: 24 };
  const proof = await verifySvgPng(directory, item);
  assert.equal(proof.exactSvgRenderedPixels, true); checks++;
  await sharp(svg('#ff2211')).png().toFile(pngFile);
  await assert.rejects(verifySvgPng(directory, item), /PNG pixels do not match/); checks++;
  await sharp(svg('#1188ff')).png().toFile(pngFile);
  await assert.rejects(verifySvgPng(directory, { ...item, pixelHash: 'stale' }), /manifest is stale/); checks++;
  await assert.rejects(verifySvgPng(directory, { ...item, svg: '../outside.svg' }), /within their export folder/); checks++;
  await fs.unlink(svgFile);
  await assert.rejects(verifySvgPng(directory, item), /ENOENT/); checks++;
} finally {
  await fs.unlink(svgFile).catch(error => { if (error.code !== 'ENOENT') throw error; });
  await fs.unlink(pngFile).catch(error => { if (error.code !== 'ENOENT') throw error; });
  await fs.rmdir(directory);
}
console.log(`Passed ${checks} SVG-origin checks.`);
