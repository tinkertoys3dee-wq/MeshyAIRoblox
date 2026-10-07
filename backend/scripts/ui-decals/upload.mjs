#!/usr/bin/env node
// Upload every Forge UI decal PNG in ./assets to Roblox via the Open Cloud
// Assets API, one command, right from Railway's terminal for this service --
// no pip install, no npm install, just Node (this repo already requires >=22,
// which has fetch/FormData/Blob built in).
//
// This is the Node twin of design/upload_ui_assets.py, for environments
// (like a Railway shell) where Python isn't installed but Node already is.
// Same source images, same manifest, same Roblox API -- just no dependency
// on a Python interpreter being present in the container.
//
// Setup (one time):
//   1. https://create.roblox.com/dashboard/credentials -> API Keys -> Create.
//      Grant it the "Assets" API with "Create" access, scoped to either your
//      user or the creator group that owns this game.
//   2. In the Railway service's Shell/Terminal tab:
//        export ROBLOX_API_KEY="..."
//        export ROBLOX_CREATOR_TYPE="User"   # or "Group"
//        export ROBLOX_CREATOR_ID="<your numeric user or group id>"
//      (Or set these as Railway service Variables first -- they'll already
//      be in the shell's environment when you open the terminal, so you
//      never have to type the key itself into the terminal history.)
//
// Then, from this directory (backend/scripts/ui-decals/):
//   node upload.mjs
//   node upload.mjs --dry-run  (verify only; no keys, network, or ID writes)
//
// The original design/assets SVGs, PNGs and manifest must remain available
// in the checkout. Bundled PNG copies must match those vector exports before
// this historical uploader can send them. Refresh stale copies explicitly.
//
// Each upload goes through Roblox's normal moderation queue like any other
// asset -- this polls until each one is done (or reports if one gets
// rejected) rather than assuming success. Safe to re-run: assets that
// already have an id in ids.json are skipped unless --force is passed.
//
// Output: prints "ok  <Name> -> <id>" per asset as it finishes, writes the
// running results to ./ids.json after every single upload (so a crash or a
// Railway redeploy mid-run loses nothing already uploaded), and -- because
// this container's filesystem won't survive a redeploy -- prints the full
// {name: id} map again at the end as one copy-pasteable block. Copy that
// block out of the terminal before you close it.
//
// IMPORTANT -- one required follow-up step: Open Cloud hands back a Decal
// *wrapper* id (Roblox AssetTypeId 13), which works fine as a 3D
// Decal.Texture but NOT as an ImageLabel/ImageButton.Image -- GUI images
// need the raw texture id nested inside that wrapper, and there's no public
// HTTP API to get it. After these ids clear Roblox's separate GUI-image
// moderation pass (which can lag behind 3D-decal approval), run
// design/tools/resolve_decal_ids.lua in Studio's Command Bar to resolve
// every id to its real, GUI-usable form.

import { readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ASSETS_DIR = path.join(HERE, "assets");
const MANIFEST_PATH = path.join(HERE, "manifest.json");
const IDS_PATH = path.join(HERE, "ids.json");
const SOURCE_DIR = path.resolve(HERE, "../../../design/assets");
const VECTOR_GUARD = path.resolve(HERE, "../../../design/svg_png_guard.mjs");
const API_BASE = "https://apis.roblox.com/assets/v1";

function parseArgs(argv) {
  const args = { force: false, only: null, dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--force") args.force = true;
    else if (argv[i] === "--dry-run") args.dryRun = true;
    else if (argv[i] === "--only") {
      args.only = [];
      while (argv[i + 1] && !argv[i + 1].startsWith("--")) args.only.push(argv[++i]);
    }
  }
  return args;
}

async function loadManifest() {
  if (!existsSync(MANIFEST_PATH)) {
    throw new Error(`${MANIFEST_PATH} not found -- copy it alongside this script (see design/assets/manifest.json).`);
  }
  const manifest = JSON.parse(await readFile(MANIFEST_PATH, "utf8"));
  if (!Array.isArray(manifest)) throw new Error("The bundled UI manifest must be an array.");
  const names = new Set();
  for (const item of manifest) {
    if (!item || !/^[A-Za-z][A-Za-z0-9_]*$/.test(item.name || "")) throw new Error("Invalid bundled UI asset name.");
    if (names.has(item.name)) throw new Error(`Duplicate bundled UI asset: ${item.name}`);
    names.add(item.name);
  }
  return manifest;
}

function localAssetPath(directory, relative, extension) {
  if (typeof relative !== "string" || !relative.toLowerCase().endsWith(extension)) {
    throw new Error(`Expected a ${extension} asset file.`);
  }
  const root = path.resolve(directory), resolved = path.resolve(root, relative);
  const inside = path.relative(root, resolved);
  if (inside.startsWith("..") || path.isAbsolute(inside)) throw new Error("Asset files must remain inside their source folder.");
  return resolved;
}

function pngDimensions(bytes, label) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(signature)
    || bytes.readUInt32BE(8) !== 13 || bytes.toString("ascii", 12, 16) !== "IHDR") {
    throw new Error(`${label}: expected a PNG with an IHDR header.`);
  }
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  if (!width || !height) throw new Error(`${label}: invalid PNG dimensions.`);
  return { width, height };
}

async function validateAsset(item, { bundledDir = ASSETS_DIR, sourceDir = SOURCE_DIR } = {}) {
  // This runs before credentials/IDs are read, and again immediately before
  // each upload. Missing original SVG sources always fail closed.
  const { assertVectorSvg, sha256 } = await import(pathToFileURL(VECTOR_GUARD).href);
  const sourceManifest = JSON.parse(await readFile(path.join(sourceDir, "manifest.json"), "utf8"));
  if (!Array.isArray(sourceManifest)) throw new Error("Original SVG export manifest must be an array.");
  const originals = sourceManifest.filter(source => source.name === item.name);
  if (originals.length !== 1) throw new Error(`${item.name}: expected exactly one original vector-export manifest entry.`);
  const original = originals[0];
  if (item.file !== original.file) throw new Error(`${item.name}: bundled file does not match its original vector export.`);
  const originalPng = localAssetPath(sourceDir, original.file, ".png");
  const originalSvg = originalPng.replace(/\.png$/i, ".svg");
  const [svgBytes, exportBytes, bundledBytes] = await Promise.all([
    readFile(originalSvg), readFile(originalPng),
    readFile(localAssetPath(bundledDir, item.file, ".png")),
  ]);
  const source = assertVectorSvg(svgBytes, item.name, { allowText: true });
  const root = source.match(/<(?:[\w.-]+:)?svg\b([^>]*)>/i)?.[1] || "";
  const width = Number(root.match(/\bwidth=["']([\d.]+)(?:px)?["']/i)?.[1]);
  const height = Number(root.match(/\bheight=["']([\d.]+)(?:px)?["']/i)?.[1]);
  const dimensions = pngDimensions(exportBytes, item.name);
  pngDimensions(bundledBytes, `${item.name} bundled copy`);
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0
    || width !== dimensions.width || height !== dimensions.height) {
    throw new Error(`${item.name}: original PNG dimensions do not match its genuine SVG.`);
  }
  if (original.origin !== undefined) {
    const origin = original.origin;
    if (!origin || origin.kind !== "pure-svg" || origin.renderer !== "chromium-svg"
      || origin.source !== path.basename(originalSvg) || origin.width !== width || origin.height !== height
      || origin.sourceSha256 !== sha256(svgBytes) || origin.pngSha256 !== sha256(exportBytes)) {
      throw new Error(`${item.name}: SVG/PNG origin stamp is stale; render again.`);
    }
  }
  if (!bundledBytes.equals(exportBytes)) {
    throw new Error(`${item.name}: bundled PNG differs from the original SVG export; refresh this stale copy before uploading.`);
  }
  return { bytes: bundledBytes, svg: originalSvg, width, height,
    svgSha256: sha256(svgBytes), pngSha256: sha256(bundledBytes) };
}

async function preflight(manifest) {
  const failures = [];
  let verified = 0;
  for (const item of manifest) {
    try { await validateAsset(item); verified++; }
    catch (error) { failures.push(error.message); }
  }
  if (failures.length) {
    throw new Error(`SVG origin preflight blocked ${failures.length}/${manifest.length} bundled images (${verified} verified):\n${failures.join("\n")}`);
  }
  return verified;
}

async function loadIds() {
  if (!existsSync(IDS_PATH)) return {};
  return JSON.parse(await readFile(IDS_PATH, "utf8"));
}

async function saveIds(ids) {
  await writeFile(IDS_PATH, JSON.stringify(ids, Object.keys(ids).sort(), 2) + "\n");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function uploadOne(apiKey, creatorType, creatorId, item) {
  const { bytes } = await validateAsset(item);

  const requestPayload = {
    assetType: "Decal",
    displayName: item.name.slice(0, 50),
    description: (item.usage || "Forge UI chrome").slice(0, 1000),
    creationContext: {
      creator: creatorType === "User" ? { userId: String(creatorId) } : { groupId: String(creatorId) },
    },
  };

  const form = new FormData();
  form.append("request", JSON.stringify(requestPayload));
  form.append("fileContent", new Blob([bytes], { type: "image/png" }), item.file);

  const postResp = await fetch(`${API_BASE}/assets`, {
    method: "POST",
    headers: { "x-api-key": apiKey },
    body: form,
  });
  if (!postResp.ok) {
    throw new Error(`upload failed (${postResp.status}): ${await postResp.text()}`);
  }
  const operation = await postResp.json();
  if (operation.done && operation.response) {
    return Number(operation.response.assetId);
  }

  for (let attempt = 0; attempt < 60; attempt++) {
    // ~5 minutes at 5s intervals
    await sleep(5000);
    const pollResp = await fetch(`${API_BASE}/${operation.path}`, {
      headers: { "x-api-key": apiKey },
    });
    if (!pollResp.ok) {
      throw new Error(`poll failed (${pollResp.status}): ${await pollResp.text()}`);
    }
    const result = await pollResp.json();
    if (result.done) {
      if (result.error) throw new Error(`moderation/upload rejected: ${JSON.stringify(result.error)}`);
      return Number(result.response.assetId);
    }
  }
  throw new Error(`${item.name} did not finish processing within 5 minutes`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const manifest = await loadManifest();
  if (args.only) {
    const unknown = args.only.filter(name => !manifest.some(item => item.name === name));
    if (!args.only.length || unknown.length) throw new Error(`--only requires known bundled asset names: ${unknown.join(", ")}`);
  }
  const selected = manifest.filter(item => !args.only || args.only.includes(item.name));
  const verified = await preflight(selected);
  if (args.dryRun) {
    console.log(`Verified ${verified} bundled PNGs against their genuine SVG exports. No credentials read, uploads sent, or IDs written.`);
    return;
  }

  const apiKey = process.env.ROBLOX_API_KEY;
  const creatorType = process.env.ROBLOX_CREATOR_TYPE || "User";
  const creatorId = process.env.ROBLOX_CREATOR_ID;

  if (!apiKey || !creatorId) {
    console.error(
      "Set ROBLOX_API_KEY and ROBLOX_CREATOR_ID first (ROBLOX_CREATOR_TYPE defaults to 'User';\n" +
        "set it to 'Group' if this game's assets should belong to a creator group).\n" +
        "See the comment at the top of this file for how to get an API key."
    );
    process.exit(1);
  }
  if (creatorType !== "User" && creatorType !== "Group") {
    console.error("ROBLOX_CREATOR_TYPE must be 'User' or 'Group'");
    process.exit(1);
  }

  const ids = await loadIds();

  for (const item of manifest) {
    const { name } = item;
    if (args.only && !args.only.includes(name)) continue;
    if (ids[name] && !args.force) {
      console.log(`skip  ${name} (already ${ids[name]}, pass --force to redo)`);
      continue;
    }
    process.stdout.write(`...   ${name}`);
    try {
      const assetId = await uploadOne(apiKey, creatorType, creatorId, item);
      ids[name] = assetId;
      await saveIds(ids); // persist after every asset so a crash mid-run loses nothing
      console.log(`\r  ok  ${name} -> ${assetId}`);
    } catch (err) {
      console.log(`\r FAIL ${name}: ${err.message}`);
    }
  }

  const missing = manifest.filter((m) => !ids[m.name]).map((m) => m.name);
  console.log("\n=== Final ids (copy this block) ===");
  console.log(JSON.stringify(ids, Object.keys(ids).sort(), 2));
  console.log("=== end ===\n");
  console.log(`Also written to ${IDS_PATH} (won't survive a redeploy -- copy the block above now).`);
  if (missing.length > 0) {
    console.log(`\n${missing.length} asset(s) still missing an id: ${missing.join(", ")}`);
    console.log("Re-run this script (already-uploaded ones are skipped) once those clear moderation or are fixed.");
  } else {
    console.log("\nAll assets uploaded.");
  }

  console.log(
    "\nOne more required step: the ids above are Decal wrapper ids, which don't\n" +
      "render in ImageLabel/ImageButton (only in a 3D Decal.Texture). Open Studio,\n" +
      "paste design/tools/resolve_decal_ids.lua into the Command Bar, and feed the\n" +
      "block it prints back through apply_asset_ids.py to get the real, GUI-usable ids."
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

export { uploadOne, loadManifest, loadIds, saveIds, validateAsset, preflight };
