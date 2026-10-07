// Shared SVG-origin checks for authored UI exports. No network or credentials.
import fs from 'node:fs/promises';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../backend/package.json'));
const sharp = require('sharp');
export const sha256 = data => createHash('sha256').update(data).digest('hex');

export function assertVectorSvg(bytes, name = 'SVG', { allowText = false } = {}) {
  const source = bytes.toString('utf8');
  if (!/<(?:[\w.-]+:)?svg\b/i.test(source)) throw new Error(`${name}: SVG root is missing.`);
  if (/<!DOCTYPE|<!ENTITY/i.test(source)) throw new Error(`${name}: external/entity document declarations are forbidden.`);
  const forbidden = allowText ? 'image|feImage|script|foreignObject' : 'image|feImage|script|foreignObject|text|tspan|textPath';
  if (new RegExp(`<\\s*(?:[\\w.-]+:)?(?:${forbidden})\\b`, 'i').test(source)) {
    throw new Error(`${name}: UI artwork must contain vector geometry, with no embedded bitmap or executable content.`);
  }
  if (/\son[\w-]+\s*=/i.test(source) || /@import|data:(?:image|application)/i.test(source)) {
    throw new Error(`${name}: external/embedded resources or event handlers are forbidden.`);
  }
  for (const match of source.matchAll(/(?:[\w.-]+:)?href\s*=\s*["']([^"']*)["']/gi)) {
    if (!match[1].startsWith('#')) throw new Error(`${name}: references must resolve to SVG-local geometry.`);
  }
  for (const match of source.matchAll(/url\(\s*["']?([^\s"')]+)["']?\s*\)/gi)) {
    if (!match[1].startsWith('#')) throw new Error(`${name}: external paint/filter resource is forbidden.`);
  }
  return source;
}

function localPath(dir, relative, extension) {
  if (typeof relative !== 'string' || !relative.toLowerCase().endsWith(extension)) throw new Error(`Expected a ${extension} asset source.`);
  const resolved = path.resolve(dir, relative);
  const inside = path.relative(path.resolve(dir), resolved);
  if (inside.startsWith('..') || path.isAbsolute(inside)) throw new Error('Asset paths must stay within their export folder.');
  return resolved;
}

export async function verifySvgPng(dir, item, { cache = new Map(), allowText = false } = {}) {
  const svgFile = item.svg || `svg/${item.name}.svg`;
  const svgBytes = await fs.readFile(localPath(dir, svgFile, '.svg'));
  assertVectorSvg(svgBytes, item.name, { allowText });
  const sourceHash = sha256(svgBytes);
  if (item.svgSha256 && item.svgSha256 !== sourceHash) throw new Error(`${item.name}: SVG export manifest is stale. Render it again before uploading.`);
  let rendered = cache.get(sourceHash);
  if (!rendered) {
    rendered = await sharp(svgBytes).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    cache.set(sourceHash, rendered);
  }
  const pngBytes = await fs.readFile(localPath(dir, item.file, '.png'));
  const actual = await sharp(pngBytes).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  if (rendered.info.width !== actual.info.width || rendered.info.height !== actual.info.height
    || !rendered.data.equals(actual.data)) {
    throw new Error(`${item.name}: PNG pixels do not match the SVG. Render the SVG before uploading.`);
  }
  if ((item.width && item.width !== actual.info.width) || (item.height && item.height !== actual.info.height)) {
    throw new Error(`${item.name}: export dimensions do not match the SVG.`);
  }
  const pixelHash = sha256(Buffer.concat([Buffer.from(`${actual.info.width}x${actual.info.height}:`), actual.data]));
  if (item.pixelHash && item.pixelHash !== pixelHash) throw new Error(`${item.name}: rendered-pixel manifest is stale.`);
  return { svg: svgFile, png: item.file, svgSha256: sourceHash, pngSha256: sha256(pngBytes),
    width: actual.info.width, height: actual.info.height, pixelHash, exactSvgRenderedPixels: true };
}
