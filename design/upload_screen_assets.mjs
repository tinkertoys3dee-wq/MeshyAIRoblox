// Upload unique text-free components as raw Roblox Images. The ignored local
// upload key is read silently only during real uploads; dry-run reads no key.
// Approved moderation is required before an ID enters ScreenAssets.luau.
import fs from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash, randomUUID } from 'node:crypto';

const here = path.dirname(fileURLToPath(import.meta.url));
const api = 'https://apis.roblox.com/assets/v1';
const args = process.argv.slice(2);
const value = flag => args.includes(flag) ? args[args.indexOf(flag) + 1] : undefined;
const dir = path.resolve(value('--dir') || path.join(here, 'screens/assets'));
const output = path.resolve(value('--output') || path.join(here, '../src/Shared/ScreenAssets.luau'));
const tableName = value('--table') || 'ScreenAssets';
if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(tableName)) throw new Error('Invalid generated table name.');
const dryRun = args.includes('--dry-run');
const applyIds = args.includes('--apply-ids');
const verifyState = args.includes('--verify-state');
const selfTest = args.includes('--self-test');
const retryUncertain = args.includes('--retry-uncertain');
if (retryUncertain && args.includes('--force')) throw new Error('--retry-uncertain reuses known uploads; do not combine it with --force.');
const manifest = JSON.parse(await fs.readFile(path.join(dir, 'manifest.json'), 'utf8'));
const knownNames = new Set(manifest.map(item => item.name));
const only = value('--only')?.split(',');
if (only?.some(name => !knownNames.has(name))) throw new Error('Unknown asset in --only.');
const readJson = async file => existsSync(file) ? JSON.parse(await fs.readFile(file, 'utf8')) : {};
const readSnapshot = async file => {
  try { return await readJson(file); }
  catch (error) {
    if (error instanceof SyntaxError) { console.error(`Recovering incomplete ${path.basename(file)} from the upload journal.`); return {}; }
    throw error;
  }
};
const idsPath = path.join(dir, 'asset_ids.json');
const statePath = path.join(dir, 'upload_state.json');
const journalPath = path.join(dir, 'upload_journal.jsonl');
const recoveryPath = path.join(dir, 'recovery_required.json');
const retryAuditPath = path.join(dir, 'recovery_retry_audit.jsonl');
const retryBatchId = randomUUID();
const ids = await readSnapshot(idsPath);
const state = await readSnapshot(statePath);
// Temporary snapshots and the append-only journal survive Windows rename
// locks. Never discard an accepted operation just because a snapshot failed.
function mergeRecovery(previous, entry) {
  if (!previous) return { ...entry };
  const previousAt = Date.parse(previous.updatedAt || '') || 0;
  const entryAt = Date.parse(entry.updatedAt || '') || 0;
  if (entryAt < previousAt) return previous;
  const sameContent = previous.hash === entry.hash && previous.owner === entry.owner;
  const sameAttempt = sameContent && (entry.attemptId || previous.attemptId
    ? entry.attemptId === previous.attemptId
    : Boolean(entry.operation && entry.operation === previous.operation));
  const keepApproved = sameAttempt && previous.moderation?.includes('APPROVED')
    && !entry.moderation?.includes('REJECTED');
  // A fresh intent/operation must never inherit an older attempt's Image ID
  // or approval merely because --force uploaded identical PNG bytes again.
  return { ...(sameAttempt ? previous : {}), ...entry,
    ...(keepApproved ? { moderation: previous.moderation, assetId: previous.assetId } : {}) };
}
function mergeEntry(name, entry) {
  if (!knownNames.has(name)) return;
  state[name] = mergeRecovery(state[name], entry);
  if (state[name].moderation?.includes('APPROVED') && Number.isSafeInteger(state[name].assetId)) {
    ids[name] = state[name].assetId;
  }
}
for (const file of (await fs.readdir(dir)).filter(name => name.startsWith('upload_state.json.tmp')).sort()) {
  try {
    for (const [name, entry] of Object.entries(await readSnapshot(path.join(dir, file)))) mergeEntry(name, entry);
  } catch (error) { console.error(`Incomplete recovery snapshot ${file}; accepted operations remain journaled.`); }
}
if (existsSync(journalPath)) {
  for (const line of (await fs.readFile(journalPath, 'utf8')).split(/\r?\n/).filter(Boolean)) {
    try { const record = JSON.parse(line); mergeEntry(record.name, record.entry); }
    catch { console.error('Ignored an incomplete final upload journal line.'); }
  }
}
const recovery = await readSnapshot(recoveryPath);
const uncertainNames = new Set((recovery.uncertain || []).map(item => typeof item === 'string' ? item : item.name));
const canRetryUnknown = (enabled, quarantined, entry) => enabled && quarantined
  && !entry?.retryUncertain && !entry?.operation && !entry?.assetId;
const homeIds = await readJson(path.join(here, 'home/asset_ids.json'));
let key, creatorId, creatorType;
if (!dryRun && !applyIds && !verifyState && !selfTest) {
  const envFile = path.resolve(value('--env') || path.join(here, '../backend/.env.roblox-upload'));
  if (existsSync(envFile)) process.loadEnvFile(envFile);
  key = process.env.ROBLOX_API_KEY;
  creatorId = process.env.ROBLOX_CREATOR_ID;
  creatorType = process.env.ROBLOX_CREATOR_TYPE || 'User';
  if (!key?.trim() || !/^\d+$/.test(creatorId || '') || !['User', 'Group'].includes(creatorType)) {
    console.error('Set ROBLOX_API_KEY, ROBLOX_CREATOR_TYPE and ROBLOX_CREATOR_ID in backend/.env.roblox-upload.');
    process.exit(1);
  }
}
const validId = id => Number.isSafeInteger(Number(id)) && Number(id) > 0;
function approvedId(item) {
  if (item.homeAsset) return validId(homeIds[item.homeAsset]) ? Number(homeIds[item.homeAsset]) : 0;
  const canonical = item.uploadName || item.name;
  const entry = state[canonical];
  return entry?.pixelHash === item.pixelHash && entry?.moderation?.includes('APPROVED')
    && (!creatorId || entry.owner === `${creatorType}:${creatorId}`)
    && validId(ids[canonical]) ? Number(ids[canonical]) : 0;
}
let writes = Promise.resolve();
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const transient = error => ['EPERM', 'EACCES', 'EBUSY'].includes(error.code);
let injectRenameFailures = 0;
let journalFailed = false;
async function retryFile(operation) {
  for (let attempt = 0; ; attempt++) {
    try { return await operation(); }
    catch (error) {
      if (!transient(error) || attempt >= 8) throw error;
      await delay(Math.min(1000, 25 * 2 ** attempt));
    }
  }
}
async function durableWrite(file, data, flags = 'w') {
  await retryFile(async () => {
    const handle = await fs.open(file, flags);
    try { await handle.writeFile(data); await handle.sync(); }
    finally { await handle.close(); }
  });
}
const atomic = async (file, data) => {
  const temp = `${file}.tmp-${process.pid}-${randomUUID()}`;
  await durableWrite(temp, data, 'wx');
  try {
    await retryFile(async () => {
      if (injectRenameFailures > 0) {
        injectRenameFailures--;
        throw Object.assign(new Error('Simulated Windows rename lock'), { code: 'EPERM' });
      }
      await fs.rename(temp, file);
    });
  } catch (error) {
    if (!transient(error)) throw error;
    // On Windows an app can permit writes while denying replacement/rename.
    // The journal is the durable source of truth if replacement stays locked.
    await durableWrite(file, data);
    await fs.unlink(temp).catch(() => {});
  }
};
async function checkpoint(name, entry) {
  entry.updatedAt = new Date().toISOString();
  // Separate from the snapshot queue; prefix newline isolates any truncated
  // final record from a prior process. Sync before another network operation.
  try { await durableWrite(journalPath, '\n' + JSON.stringify({ name, entry, at: entry.updatedAt }) + '\n', 'a'); }
  catch (error) { journalFailed = true; throw error; }
}
function enqueue(job) {
  writes = writes.catch(() => {}).then(job).catch(error => {
    if (!selfTest) {
      console.error(`Snapshot deferred: ${String(error.message).replaceAll(key || '\0', '[redacted]')}; upload operations are preserved in the journal.`);
      process.exitCode = 1;
    }
  });
  return writes;
}
function save() {
  return enqueue(async () => {
    for (const item of manifest) {
      const id = approvedId(item);
      if (id) ids[item.name] = id;
      else delete ids[item.name];
    }
    await atomic(statePath, JSON.stringify(state, null, 2) + '\n');
    await atomic(idsPath, JSON.stringify(ids, null, 2) + '\n');
    const lines = ['--!strict', '', '-- GENERATED by design/upload_screen_assets.mjs.',
      '-- Moderation-approved raw Image asset IDs. Text and live thumbnails remain native.',
      `local ${tableName} = {`, ...manifest.map(item => `\t[${JSON.stringify(item.name)}] = ${approvedId(item)},`),
      '}', '', `return table.freeze(${tableName})`, ''];
    await atomic(output, lines.join('\n'));
  });
}
const redact = error => String(error).replaceAll(key || '\0', '[redacted]');
async function request(method, endpoint, body) {
  // Endpoints can never redirect to another host or leak the upload key.
  if (!/^(?:assets(?:\/\d+(?:\?readMask=moderationResult)?)?|operations\/[A-Za-z0-9_-]+)$/.test(endpoint)) {
    throw new Error('Invalid Roblox Assets endpoint.');
  }
  for (let attempt = 0; attempt < 5; attempt++) {
    let response;
    try {
      response = await fetch(`${api}/${endpoint}`, { method, body,
        headers: { 'x-api-key': key }, redirect: 'error', signal: AbortSignal.timeout(60000) });
    } catch (error) {
      // Reads are safe to repeat after transient network failures. A failed
      // POST remains journaled as uncertain; repeating it could create a copy.
      if (method !== 'GET' || attempt === 4) throw error;
      await delay(Math.min(10000, 1000 * 2 ** attempt));
      continue;
    }
    if (response.status === 429 || (method === 'GET' && response.status >= 500)) {
      await delay(Math.min(10000, 1000 * 2 ** attempt));
      continue;
    }
    if (!response.ok) {
      const detail = redact(await response.text()).slice(0, 350);
      throw Object.assign(new Error(`Roblox ${method} failed (${response.status}): ${detail}`),
        { status: response.status, method, endpoint, explicitHttpResponse: true });
    }
    return response.json();
  }
  throw new Error('Roblox rate limit or temporary failure; run again to resume.');
}
function assetId(response) {
  const id = Number(response?.assetId || response?.path?.split('/').pop());
  if (!validId(id)) throw new Error('Roblox returned an invalid Image asset ID.');
  if (response.assetType && !['Image', 'IMAGE', 'ASSET_TYPE_IMAGE'].includes(response.assetType)) {
    throw new Error('Roblox returned another asset type; no GUI image ID was applied.');
  }
  return id;
}
async function upload(item) {
  const pngPath = path.resolve(dir, item.file);
  if (path.dirname(pngPath) !== path.join(dir, 'png')) throw new Error('PNG path is outside screen assets.');
  const bytes = await fs.readFile(pngPath);
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error('Not a PNG.');
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  if (bytes.length > 20 * 1024 * 1024 || width >= 8000 || height >= 8000) throw new Error('Image exceeds Roblox upload limits.');
  if (width !== item.width || height !== item.height) throw new Error('Rendered PNG dimensions do not match the manifest.');
  if (dryRun) {
    console.log(`ready ${item.name}: ${width}x${height}`);
    return;
  }
  const hash = createHash('sha256').update(bytes).digest('hex');
  const owner = `${creatorType}:${creatorId}`;
  const priorRecord = state[item.name];
  let entry = state[item.name];
  // A new screen can change the first name of an identical component.
  // Reuse its saved operation/Image by content rather than uploading again.
  if (!args.includes('--force') && (entry?.hash !== hash || entry?.owner !== owner)) {
    const prior = Object.values(state).find(saved => saved.hash === hash && saved.owner === owner);
    if (prior) {
      entry = state[item.name] = { ...prior, pixelHash: item.pixelHash };
      if (entry.moderation?.includes('APPROVED') && validId(entry.assetId)) ids[item.name] = entry.assetId;
      await checkpoint(item.name, entry);
      await save();
    }
  }
  const same = entry?.hash === hash && entry?.owner === owner;
  if (same) entry.pixelHash = item.pixelHash;
  if (same && approvedId(item) && !args.includes('--force')) { console.log(`skip ${item.name}`); return; }
  if (!same || args.includes('--force')) {
    delete ids[item.name];
    entry = undefined;
  }
  if (!entry?.operation && !entry?.assetId) {
    const controlledRetry = canRetryUnknown(retryUncertain, uncertainNames.has(item.name), priorRecord);
    if ((uncertainNames.has(item.name) || entry?.intent) && !controlledRetry) {
      throw new Error('An earlier upload may already exist. Recover its Image ID/operation before retrying; no duplicate was uploaded.');
    }
    if (controlledRetry) {
      // One deliberate recovery retry is allowed for legacy missing records.
      // Persist its audit before the normal intent checkpoint and POST. If
      // this retry becomes ambiguous, the flag cannot bypass its new intent.
      const previousQuarantine = (recovery.uncertain || []).find(saved => (typeof saved === 'string' ? saved : saved.name) === item.name);
      await durableWrite(retryAuditPath, '\n' + JSON.stringify({ name: item.name,
        batchId: retryBatchId, at: new Date().toISOString(), priorEntry: entry || null,
        quarantine: previousQuarantine, reason: recovery.reason,
        notice: 'Earlier accepted Image copies may remain unused; this is one controlled recovery retry.' }) + '\n', 'a');
    }
    entry = state[item.name] = { hash, pixelHash: item.pixelHash, owner,
      intent: true, moderation: 'REQUEST_STARTED', attemptId: randomUUID(),
      ...(controlledRetry ? { retryUncertain: true, retryBatchId } : {}) };
    // An intent makes an interrupted/ambiguous POST visible on the next run.
    await checkpoint(item.name, entry);
    const form = new FormData();
    const fullDisplayName = `Forge UI ${item.name}`;
    const displayName = fullDisplayName.length <= 50 ? fullDisplayName
      : `${fullDisplayName.slice(0, 41)}_${createHash('sha256').update(item.name).digest('hex').slice(0, 8)}`;
    form.append('request', JSON.stringify({ assetType: 'Image', displayName,
      description: `Text-free ${item.name} interface artwork for Forge UGC.${controlledRetry ? ` Recovery batch ${retryBatchId}.` : ''}`,
      creationContext: { creator: { [creatorType === 'Group' ? 'groupId' : 'userId']: creatorId } } }));
    form.append('fileContent', new Blob([bytes], { type: 'image/png' }), `${item.name}.png`);
    let result;
    try { result = await request('POST', 'assets', form); }
    catch (error) {
      if (error.explicitHttpResponse && error.status === 400) {
        // Invalid input was explicitly rejected; no Image was created. This
        // differs from a lost POST response, which remains quarantined.
        entry.intent = false;
        entry.moderation = 'REQUEST_REJECTED';
        entry.requestErrorStatus = 400;
        entry.requestError = redact(error.message);
        await checkpoint(item.name, entry);
        await save();
      }
      throw error;
    }
    if (!result.path && !result.response) throw new Error('Roblox returned no saved upload operation.');
    entry = state[item.name] = { hash, pixelHash: item.pixelHash, owner, attemptId: entry.attemptId,
      operation: result.path, intent: false, moderation: 'PENDING',
      ...(controlledRetry ? { retryUncertain: true, retryBatchId } : {}) };
    // Print the public operation as an additional recovery trail, then flush
    // it to the journal immediately before any queued snapshot writes.
    console.log(`accepted ${item.name}: ${result.path || 'completed Image'}`);
    if (result.done && result.error) {
      entry.moderation = 'REJECTED';
      await checkpoint(item.name, entry); await save();
      throw new Error('Roblox rejected the upload operation.');
    }
    if (result.done && result.response) entry.assetId = assetId(result.response);
    await checkpoint(item.name, entry);
    await save();
  }
  if (entry.operation && !/^operations\/[A-Za-z0-9_-]+$/.test(entry.operation)) throw new Error('Invalid operation path.');
  for (let attempt = 0; attempt < 60; attempt++) {
    let response;
    if (entry.assetId) {
      response = await request('GET', `assets/${entry.assetId}?readMask=moderationResult`);
    } else {
      const operation = await request('GET', entry.operation);
      if (operation.error) {
        entry.error = redact(operation.error.message || operation.error.code || 'upload rejected');
        entry.moderation = 'REJECTED';
        await checkpoint(item.name, entry);
        await save();
        throw new Error(`Upload rejected: ${redact(entry.error)}`);
      }
      if (!operation.done || !operation.response) { await delay(5000); continue; }
      response = operation.response;
      entry.assetId = assetId(response);
      await checkpoint(item.name, entry);
      await save();
    }
    const moderation = String(response.moderationResult?.moderationState || '').toUpperCase();
    entry.moderation = moderation;
    if (moderation.includes('REJECTED')) {
      await checkpoint(item.name, entry); await save();
      throw new Error('Image rejected by Roblox moderation.');
    }
    if (moderation.includes('APPROVED')) {
      ids[item.name] = entry.assetId;
      await checkpoint(item.name, entry);
      await save();
      console.log(`ok ${item.name} -> ${entry.assetId}`);
      return;
    }
    await delay(5000);
  }
  await checkpoint(item.name, entry);
  await save();
  console.log(`pending ${item.name}: processing state saved; re-run to resume without another upload.`);
  if (process.exitCode !== 1) process.exitCode = 2;
}
if (selfTest) {
  const previousApproval = { hash: 'same-bytes', owner: 'Group:1', attemptId: 'old',
    operation: 'operations/old', assetId: 123, moderation: 'APPROVED', updatedAt: '2026-10-04T12:00:00.000Z' };
  const freshIntent = mergeRecovery(previousApproval, { hash: 'same-bytes', owner: 'Group:1',
    attemptId: 'new', intent: true, moderation: 'REQUEST_STARTED', updatedAt: '2026-10-04T12:00:01.000Z' });
  if (freshIntent.assetId || freshIntent.operation || freshIntent.moderation !== 'REQUEST_STARTED') {
    throw new Error('Forced intent inherited an older approval.');
  }
  const freshOperation = mergeRecovery(freshIntent, { ...freshIntent, intent: false,
    operation: 'operations/new', moderation: 'PENDING', updatedAt: '2026-10-04T12:00:02.000Z' });
  if (freshOperation.assetId || freshOperation.moderation !== 'PENDING') throw new Error('Forced operation inherited an older Image ID.');
  const freshApproval = { ...freshOperation, assetId: 456, moderation: 'APPROVED', updatedAt: '2026-10-04T12:00:03.000Z' };
  if (mergeRecovery(freshApproval, previousApproval).assetId !== 456) throw new Error('Older journal record replaced a newer Image ID.');
  const laterReview = mergeRecovery(freshApproval, { ...freshOperation, updatedAt: '2026-10-04T12:00:04.000Z' });
  if (laterReview.assetId !== 456 || laterReview.moderation !== 'APPROVED') throw new Error('Same-attempt approval regressed.');
  if (!canRetryUnknown(true, true, undefined)
    || canRetryUnknown(false, true, undefined)
    || canRetryUnknown(true, true, { retryUncertain: true, intent: true })
    || canRetryUnknown(true, true, { operation: 'operations/known' })
    || canRetryUnknown(true, true, { assetId: 123 })) {
    throw new Error('Controlled retry guard test failed.');
  }
  const testFile = path.join(dir, '.upload-write-self-test.json');
  injectRenameFailures = 2;
  await atomic(testFile, '{"stage":"retry"}\n');
  if (JSON.parse(await fs.readFile(testFile, 'utf8')).stage !== 'retry') throw new Error('Rename retry test failed.');
  injectRenameFailures = 9;
  await atomic(testFile, '{"stage":"fallback"}\n');
  if (JSON.parse(await fs.readFile(testFile, 'utf8')).stage !== 'fallback') throw new Error('Rename fallback test failed.');
  await enqueue(async () => { throw new Error('Simulated snapshot failure'); });
  await enqueue(async () => atomic(testFile, '{"stage":"queue-recovered"}\n'));
  if (JSON.parse(await fs.readFile(testFile, 'utf8')).stage !== 'queue-recovered') throw new Error('Snapshot queue recovery test failed.');
  await fs.unlink(testFile);
  console.log('Windows writes/queue recovery, one-time retry guards and forced-upload journal ordering verified. No credentials, network or game files accessed.');
} else if (verifyState) {
  const canonical = manifest.filter(item => !item.homeAsset && (item.uploadName || item.name) === item.name);
  const uncertain = canonical.filter(item => !state[item.name]?.operation && !state[item.name]?.assetId
    && (uncertainNames.has(item.name) || state[item.name]?.intent));
  console.log(`${Object.keys(state).length} saved records; ${Object.values(state).filter(entry => entry.operation).length} operations; ${Object.values(state).filter(entry => entry.assetId).length} Image IDs; ${uncertain.length} names quarantined from duplicate uploads.`);
} else if (applyIds) {
  await save();
  console.log('Applied approved screen Image IDs and reused Home Image IDs.');
} else {
  const wanted = manifest.filter(item => !item.homeAsset && (!only || only.includes(item.name)));
  const canonicalNames = new Set(wanted.map(item => item.uploadName || item.name));
  const selected = manifest.filter(item => !item.homeAsset && canonicalNames.has(item.name));
  if (selected.some(item => !item.pixelHash)) throw new Error('Render screen assets before uploading.');
  let cursor = 0;
  await Promise.all(Array.from({ length: Math.min(3, selected.length) }, async () => {
    while (cursor < selected.length && !journalFailed) {
      const item = selected[cursor++];
      try { await upload(item); }
      catch (error) { console.error(`FAIL ${item.name}: ${redact(error.message)}`); process.exitCode = 1; }
    }
  }));
  await writes;
  if (!dryRun) {
    await save();
    console.log(`${manifest.filter(item => approvedId(item)).length}/${manifest.length} approved Image names available in ${path.basename(output)}.`);
  } else {
    console.log(`Dry-run passed for ${selected.length} unique Images. Credentials were not read and nothing was uploaded.`);
  }
}
