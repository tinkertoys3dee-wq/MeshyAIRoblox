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
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ASSETS_DIR = path.join(HERE, "assets");
const MANIFEST_PATH = path.join(HERE, "manifest.json");
const IDS_PATH = path.join(HERE, "ids.json");
const API_BASE = "https://apis.roblox.com/assets/v1";

function parseArgs(argv) {
  const args = { force: false, only: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--force") args.force = true;
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
  return JSON.parse(await readFile(MANIFEST_PATH, "utf8"));
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
  const filePath = path.join(ASSETS_DIR, item.file);
  const bytes = await readFile(filePath);

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

  const manifest = await loadManifest();
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

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}

export { uploadOne, loadManifest, loadIds, saveIds };
