#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通过 Roblox Open Cloud Assets API v1 (POST https://apis.roblox.com/assets/v1/assets)
将 Assets/Sounds/ 下的全部 23 类音效自动批量上传至 Roblox 官方云端，
归属群组指定为 Group 33977495，生成永久 rbxassetid:// 映射表 Assets/Sounds/audio_manifest.json。
"""

import json
import argparse
import hashlib
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
import requests

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
SOUNDS_DIR = PROJECT_ROOT / "Assets" / "Sounds"
MANIFEST_PATH = SOUNDS_DIR / "audio_manifest.json"

GROUP_ID = "33977495"
API_BASE = "https://apis.roblox.com"
CREATE_URL = f"{API_BASE}/assets/v1/assets"

def get_api_key() -> str:
    key = os.environ.get("SIXCUBE_ROBLOX_OPENCLOUD_KEY") or os.environ.get("ROBLOX_API_KEY")
    if not key:
        print("[ERROR] 缺少环境变量 SIXCUBE_ROBLOX_OPENCLOUD_KEY 或 ROBLOX_API_KEY", file=sys.stderr)
        sys.exit(1)
    return key.strip()

def load_manifest() -> dict:
    if MANIFEST_PATH.exists():
        try:
            return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        except (ValueError, OSError) as error:
            raise RuntimeError("音效清单读取失败，停止上传以保留现有映射") from error
    return {
        "kind": "chicken_farm_audio_manifest",
        "groupId": GROUP_ID,
        "updatedAt": "",
        "sounds": {}
    }

def save_manifest(manifest: dict):
    manifest["updatedAt"] = datetime.now(timezone.utc).isoformat()
    temporary = MANIFEST_PATH.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(MANIFEST_PATH)

def upload_single_audio(session: requests.Session, api_key: str, sound_name: str, file_path: Path) -> str:
    """上传单份音频文件并轮询 operation，返回 assetId"""
    display_name = f"ChickenFarm_{sound_name}"[:50]
    description = f"Chicken Farm audio: {sound_name}"

    payload = {
        "assetType": "Audio",
        "displayName": display_name,
        "description": description,
        "creationContext": {
            "creator": {
                "groupId": GROUP_ID
            },
            "expectedPrice": 0
        }
    }

    file_bytes = file_path.read_bytes()
    files = {
        "request": (None, json.dumps(payload, ensure_ascii=False), "application/json"),
        "fileContent": (file_path.name, file_bytes, "audio/mpeg")
    }

    headers = {
        "x-api-key": api_key,
        "user-agent": "RobloxOpenCloud-AudioUploader/1.0"
    }

    resp = session.post(CREATE_URL, headers=headers, files=files, timeout=60)
    if resp.status_code != 200:
        raise RuntimeError(f"HTTP {resp.status_code}: {resp.text}")

    data = resp.json()
    path = data.get("path")
    if not path:
        raise RuntimeError(f"响应缺少 path 字段: {data}")

    op_path = path.lstrip("/")
    if not op_path.startswith("assets/v1/"):
        op_path = "assets/v1/" + op_path
    op_url = f"{API_BASE}/{op_path}"
    # 轮询等待完成
    deadline = time.monotonic() + 60
    interval = 1.0

    while time.monotonic() < deadline:
        r = session.get(op_url, headers=headers, timeout=30)
        if r.status_code != 200:
            raise RuntimeError(f"查询 operation 失败 HTTP {r.status_code}: {r.text}")

        op_data = r.json()
        if op_data.get("done"):
            if "error" in op_data:
                raise RuntimeError(f"上传失败: {op_data['error']}")
            inner = op_data.get("response")
            if not isinstance(inner, dict) or "assetId" not in inner:
                raise RuntimeError(f"operation 完成但缺少 assetId: {op_data}")
            return str(inner["assetId"])

        time.sleep(interval)
        interval = min(interval * 1.2, 3.0)

    raise TimeoutError(f"等待 operation {path} 完成超时")

ALL_SOUNDS = [
    "Zap_T1", "Zap_T2", "Zap_T3", "Zap_T4", "Zap_T5",
    "AnimalHit", "AnimalCooked", "FoodDrop", "Pickup", "Warning",
    "Delivery", "PackageDone", "Coin",
    "EggSpawn", "EggLand", "EggSpeedup", "EggHatch", "AnimalScared",
    "Upgrade", "UIClick", "UIOpen", "UIClose",
    "BGM"
]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--names", nargs="+", choices=ALL_SOUNDS, default=ALL_SOUNDS)
    args = parser.parse_args()
    print("=" * 60)
    print("正在通过 Roblox Open Cloud 上传指定音效...")
    print(f"目标群组: Group {GROUP_ID}")
    print("=" * 60)

    api_key = get_api_key()
    manifest = load_manifest()
    session = requests.Session()

    success_count = 0
    fail_count = 0

    processing_path = SOUNDS_DIR / "combat_processing.json"
    processing = json.loads(processing_path.read_text(encoding="utf-8"))["sounds"] if processing_path.exists() else {}
    for idx, name in enumerate(args.names, start=1):
        file_path = SOUNDS_DIR / f"{name}.mp3"
        if not file_path.exists():
            print(f"[{idx}/{len(args.names)}] [SKIP] 文件不存在: {file_path.name}")
            fail_count += 1
            continue

        existing = manifest["sounds"].get(name)
        content_hash = hashlib.sha256(file_path.read_bytes()).hexdigest()
        # 旧清单无哈希时，以原素材哈希迁移；其他未知来源的资产保守复用。
        baseline_hash = (existing or {}).get("sha256") or processing.get(name, {}).get("sourceSha256")
        if existing and existing.get("assetId") and (baseline_hash is None or baseline_hash == content_hash):
            existing["sha256"] = content_hash
            print(f"[{idx}/{len(args.names)}] [EXISTS] {name} -> rbxassetid://{existing['assetId']}")
            success_count += 1
            continue

        print(f"[{idx}/{len(args.names)}] [UPLOADING] {name} ({file_path.stat().st_size} 字节)...", end=" ", flush=True)
        try:
            asset_id = upload_single_audio(session, api_key, name, file_path)
            rbx_id = f"rbxassetid://{asset_id}"
            print(f"OK -> {rbx_id}")
            history = list((existing or {}).get("history", []))
            if existing:
                previous = {key: value for key, value in existing.items() if key != "history"}
                if baseline_hash:
                    previous["sha256"] = baseline_hash
                history.append(previous)
            manifest["sounds"][name] = {
                "name": name,
                "assetId": asset_id,
                "rbxassetid": rbx_id,
                "file": file_path.name,
                "fileSize": file_path.stat().st_size,
                "uploadedAt": datetime.now(timezone.utc).isoformat(),
                "sha256": content_hash,
                "history": history,
            }
            save_manifest(manifest)
            success_count += 1
        except Exception as e:
            print(f"FAILED: {e}")
            fail_count += 1

        time.sleep(0.5)

    save_manifest(manifest)
    print("=" * 60)
    print(f"上传流程结束：成功 {success_count}/{len(args.names)}，失败 {fail_count}")
    print(f"资产清单已保存: {MANIFEST_PATH}")
    print("=" * 60)
    return 1 if fail_count else 0

if __name__ == "__main__":
    sys.exit(main())
