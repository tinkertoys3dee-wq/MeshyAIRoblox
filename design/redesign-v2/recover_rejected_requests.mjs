// One-time migration for explicit HTTP 400 responses from the first batch.
// Run only after that uploader process has completed. Never infer an HTTP
// rejection from a lost response, and never repeat an accepted operation.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'assets');
const evidence = JSON.parse(await fs.readFile(path.join(dir, 'explicit_http_rejections.json'), 'utf8'));
if (evidence.httpStatus !== 400 || evidence.message !== 'Asset name length is invalid.'
    || evidence.source !== 'Roblox POST assets/v1/assets response in uploader stdout') {
  throw new Error('Only recorded explicit invalid-name HTTP 400 responses can be recovered.');
}
const state = JSON.parse(await fs.readFile(path.join(dir, 'upload_state.json'), 'utf8'));
const manifest = JSON.parse(await fs.readFile(path.join(dir, 'manifest.json'), 'utf8'));
const canonical = new Set(manifest.filter(item => !item.homeAsset && item.uploadName === item.name).map(item => item.name));
let recovered = 0;
const handle = await fs.open(path.join(dir, 'upload_journal.jsonl'), 'a');
try {
  for (const name of evidence.names) {
    if (!canonical.has(name)) throw new Error('Evidence names an unknown canonical component.');
    const entry = state[name];
    if (entry?.operation || entry?.assetId || entry?.moderation?.includes('APPROVED')) continue;
    const proof = evidence.requests?.[name];
    if (!proof || proof.attemptId !== entry?.attemptId || proof.hash !== entry?.hash || proof.pixelHash !== entry?.pixelHash) {
      throw new Error('The explicit rejection evidence does not match this exact upload attempt.');
    }
    if (!entry?.intent || entry.moderation !== 'REQUEST_STARTED') continue;
    const updatedAt = new Date().toISOString();
    const rejected = { ...entry, intent: false, moderation: 'REQUEST_REJECTED',
      requestErrorStatus: 400, requestError: 'Explicit Roblox HTTP 400: Asset name length is invalid.',
      rejectionEvidence: 'explicit_http_rejections.json', updatedAt };
    await handle.writeFile('\n' + JSON.stringify({ name, entry: rejected, at: updatedAt }) + '\n');
    await handle.sync();
    recovered++;
  }
} finally { await handle.close(); }
console.log(`Recorded ${recovered} definite rejected requests; accepted operations were not changed. No credentials or network accessed.`);
