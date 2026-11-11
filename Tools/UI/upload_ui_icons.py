#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通过 Roblox Open Cloud Assets API v1 (POST https://apis.roblox.com/assets/v1/assets)
将 Assets/Studio/UI_Icons/ 下的 UI 图标自动批量上传至 Roblox 官方云端，
归属群组指定为 Group 33977495，生成永久 rbxassetid:// 映射表 Assets/Studio/UI_Icons/icon_manifest.json。
"""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
import requests

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
ICONS_DIR = PROJECT_ROOT / "Assets" / "Studio" / "UI_Icons"
MANIFEST_PATH = ICONS_DIR / "icon_manifest.json"

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
        except Exception:
            pass
    return {
        "kind": "chicken_farm_ui_icon_manifest",
        "groupId": GROUP_ID,
        "updatedAt": "",
        "icons": {}
    }

def save_manifest(manifest: dict):
    manifest["updatedAt"] = datetime.now(timezone.utc).isoformat()
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

def upload_single_decal(session: requests.Session, api_key: str, icon_name: str, file_path: Path) -> str:
    """上传单份图片文件并轮询 operation，返回 assetId"""
    display_name = f"ChickenFarm_Icon_{icon_name}"[:50]
    description = f"Chicken Farm UI Icon: {icon_name}"

    payload = {
        "assetType": "Decal",
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
        "fileContent": (file_path.name, file_bytes, "image/png")
    }

    headers = {
        "x-api-key": api_key,
        "user-agent": "RobloxOpenCloud-DecalUploader/1.0"
    }

    resp = session.post(CREATE_URL, headers=headers, files=files, timeout=60)
    if resp.status_code != 200:
        raise RuntimeError(f"HTTP {resp.status_code}: {resp.text}")

    data = resp.json()
    path = data.get("path")
    if not path:
        raise RuntimeError(f"响应缺少 path 字段: {data}")

    op_url = f"{API_BASE}/assets/v1/{path.lstrip('/')}"
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

def upload_all_icons():
    ICONS_DIR.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    api_key = get_api_key()
    session = requests.Session()

    png_files = list(ICONS_DIR.glob("*.png"))
    if not png_files:
        print("[WARN] UI_Icons 目录下暂无 png 文件")
        return

    print(f"找到 {len(png_files)} 个图标待处理...")
    for idx, f in enumerate(png_files, 1):
        icon_name = f.stem
        if icon_name in manifest["icons"] and manifest["icons"][icon_name].get("rbxassetid"):
            print(f"[{idx}/{len(png_files)}] [SKIP] {icon_name} 已存在: {manifest['icons'][icon_name]['rbxassetid']}")
            continue

        print(f"[{idx}/{len(png_files)}] 上传中: {icon_name} ({f.name})...")
        try:
            asset_id = upload_single_decal(session, api_key, icon_name, f)
            rbx_id = f"rbxassetid://{asset_id}"
            manifest["icons"][icon_name] = {
                "assetId": asset_id,
                "rbxassetid": rbx_id,
                "file": f.name
            }
            save_manifest(manifest)
            print(f"[{idx}/{len(png_files)}] [OK] 上传成功: {icon_name} -> {rbx_id}")
        except Exception as e:
            print(f"[{idx}/{len(png_files)}] [FAIL] 上传失败 {icon_name}: {e}")

if __name__ == "__main__":
    upload_all_icons()
