// Render a new native SVG beside its generated mockup and an amplified pixel
// difference. No tracing, old layout loading, credential reads or uploads.
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(path.join(here, '../../backend/package.json'));
const sharp = require('sharp');
const [referenceArg, svgArg, outArg] = process.argv.slice(2);
if (!referenceArg || !svgArg) throw new Error('Usage: node render_conversion_review.mjs reference.png converted.svg [output-directory]');
const reference = path.resolve(referenceArg), svg = path.resolve(svgArg);
const out = path.resolve(outArg || path.join(path.dirname(svg), 'qa', path.basename(svg, '.svg')));
const source = await readFile(svg);
if (/<(?:[A-Za-z0-9_-]+:)?(?:image|feImage|script|foreignObject)(?:\s|>)/i.test(source.toString('utf8'))) {
  throw new Error('Converted SVG must contain native vectors, without a raster image wrapper.');
}
const meta = await sharp(reference).metadata();
const width = meta.width, height = meta.height;
if (!width || !height) throw new Error('Reference dimensions unavailable.');
const svgMeta = await sharp(source).metadata();
await mkdir(out, { recursive: true });
const backdrop = '#071121';
const image = await sharp(reference).flatten({ background: backdrop }).ensureAlpha().raw().toBuffer();
const rendered = await sharp(source).resize(width, height, { fit: 'contain', background: backdrop })
  .flatten({ background: backdrop }).ensureAlpha().raw().toBuffer();
const difference = Buffer.alloc(rendered.length);
let errorSum = 0, closePixels = 0;
for (let i = 0; i < rendered.length; i += 4) {
  let max = 0;
  for (let channel = 0; channel < 3; channel++) {
    const delta = Math.abs(rendered[i + channel] - image[i + channel]);
    errorSum += delta;
    max = Math.max(max, delta);
    difference[i + channel] = Math.min(255, delta * 3);
  }
  difference[i + 3] = 255;
  if (max <= 16) closePixels++;
}
const raw = { width, height, channels: 4 };
const preview = await sharp(rendered, { raw }).png().toBuffer();
const diffPng = await sharp(difference, { raw }).png().toBuffer();
await writeFile(path.join(out, 'render.png'), preview);
await writeFile(path.join(out, 'difference.png'), diffPng);
const columnWidth = Math.min(640, width);
const columnHeight = Math.round(columnWidth * height / width);
const cells = [];
for (const [i, input] of [[0, image], [1, rendered], [2, difference]]) {
  cells.push({ input: await sharp(input, { raw }).resize(columnWidth, columnHeight).png().toBuffer(),
    left: i * columnWidth, top: 36 });
}
const labels = ['Generated mockup', 'Editable SVG render', 'Difference (3x)'];
for (let i = 0; i < labels.length; i++) {
  cells.push({ input: Buffer.from(`<svg width="${columnWidth}" height="36"><text x="${columnWidth / 2}" y="24" fill="#e6f3ff" text-anchor="middle" font-size="17" font-family="Arial">${labels[i]}</text></svg>`), left: i * columnWidth, top: 0 });
}
await sharp({ create: { width: columnWidth * 3, height: columnHeight + 36,
  channels: 4, background: backdrop } }).composite(cells).png().toFile(path.join(out, 'review.png'));
const report = { reference, svg, width, height,
  sourceSvgWidth: svgMeta.width, sourceSvgHeight: svgMeta.height,
  svgToReferenceAspectRatio: (svgMeta.width / svgMeta.height) / (width / height),
  meanRgbDifference: errorSum / (width * height * 3),
  pixelsWithin16Rgb: closePixels / (width * height),
  note: 'Pixel differences guide visual review; fonts and anti-aliasing can differ. These metrics do not replace checking component geometry and editable text.' };
await writeFile(path.join(out, 'report.json'), JSON.stringify(report, null, 2) + '\n');
console.log(`Rendered conversion review: ${path.join(out, 'review.png')}`);
console.log(JSON.stringify(report, null, 2));
