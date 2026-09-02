#!/usr/bin/env python3
"""Upload every PNG in assets/manifest.json to Roblox via the Open Cloud
Assets API, in one command, and bake the resulting asset ids straight into
src/Shared/UIAssets.luau.

Setup (one time):
  1. https://create.roblox.com/dashboard/credentials -> API Keys -> Create.
     Grant it the "Assets" API with "Create" access, scoped to either your
     user or the creator group that owns this game.
  2. export ROBLOX_API_KEY="..."
  3. export ROBLOX_CREATOR_TYPE="User"   (or "Group")
  4. export ROBLOX_CREATOR_ID="<your numeric user or group id>"

Then:
  python3 export_ui_assets.py   # if you haven't already
  python3 upload_ui_assets.py

Each upload goes through Roblox's normal moderation queue like any other
asset -- this script polls until each one is done (or reports if one gets
rejected) rather than assuming success. Safe to re-run: assets that already
have an id in assets/asset_ids.json are skipped unless --force is passed.
"""

import argparse
import json
import os
import sys
import time

import requests

from ui_assets_common import ASSETS, load_manifest, load_ids, save_ids, write_luau_module

API_BASE = "https://apis.roblox.com/assets/v1"


def upload_one(api_key: str, creator_type: str, creator_id: str, item: dict) -> int:
    path = ASSETS / item["file"]
    request_payload = {
        "assetType": "Decal",
        "displayName": item["name"][:50],
        "description": (item.get("usage") or "Forge UI chrome")[:1000],
        "creationContext": {
            "creator": (
                {"userId": str(creator_id)} if creator_type == "User" else {"groupId": str(creator_id)}
            )
        },
    }
    with open(path, "rb") as f:
        response = requests.post(
            f"{API_BASE}/assets",
            headers={"x-api-key": api_key},
            data={"request": json.dumps(request_payload)},
            files={"fileContent": (path.name, f, "image/png")},
            timeout=60,
        )
    if response.status_code >= 400:
        raise RuntimeError(f"upload failed ({response.status_code}): {response.text}")
    operation = response.json()

    if operation.get("done") and "response" in operation:
        return int(operation["response"]["assetId"])

    op_path = operation["path"]
    for _ in range(60):  # ~5 minutes at 5s intervals
        time.sleep(5)
        poll = requests.get(f"{API_BASE}/{op_path}", headers={"x-api-key": api_key}, timeout=30)
        poll.raise_for_status()
        result = poll.json()
        if result.get("done"):
            if "error" in result:
                raise RuntimeError(f"moderation/upload rejected: {result['error']}")
            return int(result["response"]["assetId"])
    raise TimeoutError(f"{item['name']} did not finish processing within 5 minutes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="re-upload assets that already have an id")
    parser.add_argument("--only", nargs="*", help="only upload these asset names")
    args = parser.parse_args()

    api_key = os.environ.get("ROBLOX_API_KEY")
    creator_type = os.environ.get("ROBLOX_CREATOR_TYPE", "User")
    creator_id = os.environ.get("ROBLOX_CREATOR_ID")
    if not api_key or not creator_id:
        sys.exit(
            "Set ROBLOX_API_KEY and ROBLOX_CREATOR_ID first (ROBLOX_CREATOR_TYPE defaults to "
            "'User'; set it to 'Group' if this game's assets should belong to a creator group). "
            "See the top of this file for how to get an API key."
        )
    if creator_type not in ("User", "Group"):
        sys.exit("ROBLOX_CREATOR_TYPE must be 'User' or 'Group'")

    manifest = load_manifest()
    ids = load_ids()

    for item in manifest:
        name = item["name"]
        if args.only and name not in args.only:
            continue
        if ids.get(name) and not args.force:
            print(f"skip  {name} (already {ids[name]}, pass --force to redo)")
            continue
        print(f"...   {name}", end="", flush=True)
        try:
            asset_id = upload_one(api_key, creator_type, creator_id, item)
        except Exception as exc:  # noqa: broad, this is a CLI tool -- report and move on
            print(f"\r FAIL {name}: {exc}")
            continue
        ids[name] = asset_id
        save_ids(ids)  # persist after every asset so a crash mid-run loses nothing
        print(f"\r  ok  {name} -> {asset_id}")

    write_luau_module(ids)
    missing = [m["name"] for m in manifest if not ids.get(m["name"])]
    if missing:
        print(f"\n{len(missing)} asset(s) still missing an id: {', '.join(missing)}")
        print("Re-run this script (already-uploaded ones are skipped) once those clear moderation or are fixed.")
    else:
        print("\nAll assets uploaded and baked into src/Shared/UIAssets.luau.")


if __name__ == "__main__":
    main()
