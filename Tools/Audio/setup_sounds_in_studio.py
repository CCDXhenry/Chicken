#!/usr/bin/env python3
"""在指定 Studio Edit 会话部署清单中的指定音效，保留既有模板调音属性。"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

SOUNDS_DIR = Path(__file__).resolve().parents[2] / "Assets" / "Sounds"
MANIFEST_PATH = SOUNDS_DIR / "audio_manifest.json"


def build_setup_code(sounds, group_id):
    payload = json.dumps(sounds, ensure_ascii=False)
    return f'''
assert(not game:GetService("RunService"):IsRunning(), "Audio deployment requires Edit mode")
assert(game.CreatorType == Enum.CreatorType.Group and game.CreatorId == {int(group_id)}, "Creator mismatch")
local sounds = game:GetService("HttpService"):JSONDecode([==[{payload}]==])
local storage = game:GetService("ReplicatedStorage")
local service = game:GetService("SoundService")
local folder = storage:FindFirstChild("Sounds")
assert(not folder or folder:IsA("Folder"), "Sounds must be a Folder")
-- 先校验整批，避免同名错误实例导致部分更新。
for name, item in pairs(sounds) do
    assert(type(item.rbxassetid) == "string" and item.rbxassetid:match("^rbxassetid://%d+$"), "Invalid asset: " .. name)
    local parent = if name == "BGM" then service else folder
    local existing = if parent then parent:FindFirstChild(name) else nil
    assert(not existing or existing:IsA("Sound"), "Template is not a Sound: " .. name)
end
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "Sounds"
    folder.Parent = storage
end
local groups = service:FindFirstChild("SoundGroups")
local details = {{}}
for name, item in pairs(sounds) do
    local parent = if name == "BGM" then service else folder
    local sound = parent:FindFirstChild(name)
    if not sound then
        sound = Instance.new("Sound")
        sound.Name = name
        sound.Volume = if name == "BGM" then 0.5 else 0.7
        sound.RollOffMode = Enum.RollOffMode.InverseTapered
        sound.RollOffMinDistance = 10
        sound.RollOffMaxDistance = 80
        local group = if groups then groups:FindFirstChild(if name == "BGM" then "BGM" else "SoundEffects") else nil
        if group and group:IsA("SoundGroup") then sound.SoundGroup = group end
        sound.Parent = parent
    end
    sound.SoundId = item.rbxassetid
    sound.Looped = name == "BGM"
    -- 裁切成品按原速播放；不改变音量、衰减或 SoundGroup。
    sound.PlaybackSpeed = 1
    table.insert(details, {{name=name, id=sound.SoundId, speed=sound.PlaybackSpeed, volume=sound.Volume, looped=sound.Looped}})
end
return details
'''


def main():
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--names", nargs="+", choices=list(manifest["sounds"]), required=True)
    parser.add_argument("--studio-id")
    parser.add_argument("--emit-code", action="store_true", help="只输出部署代码，不连接或修改 Studio")
    args = parser.parse_args()
    sounds = {name: manifest["sounds"][name] for name in args.names}
    for name, item in sounds.items():
        if item.get("sha256"):
            local_hash = hashlib.sha256((SOUNDS_DIR / item["file"]).read_bytes()).hexdigest()
            if item["sha256"] != local_hash:
                raise RuntimeError(f"{name}: 本地素材尚未上传，拒绝部署旧映射")
    code = build_setup_code(sounds, manifest["groupId"])
    if args.emit_code:
        print(code)
        return
    if not args.studio_id:
        parser.error("部署必须显式指定 --studio-id")
    sys.path.append(r"C:\Users\herong\.gemini\config\skills\roblox-studio-mcp\scripts")
    from fast_connect import RobloxMCPClient
    client = RobloxMCPClient()
    try:
        studios = client.list_studios()
        if not any(studio["id"] == args.studio_id for studio in studios):
            raise RuntimeError("指定的 Studio 会话未连接")
        print(client.execute_luau(code, "Edit", args.studio_id))
    finally:
        client.close()


if __name__ == "__main__":
    main()
