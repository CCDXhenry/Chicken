#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
读取 Assets/Sounds/audio_manifest.json，
通过 Roblox Studio MCP 在当前处于 Edit 模式的 Studio 中自动构建声音实例树：
- 除 BGM 实例放置于 SoundService.BGM（或 SoundService.SoundGroups.BGM）外；
- 其余 22 类音效模板实例全部创建并放置于 ReplicatedStorage.Sounds（Folder）。
"""

import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
MANIFEST_PATH = PROJECT_ROOT / "Assets" / "Sounds" / "audio_manifest.json"

sys.path.append(r"C:\Users\herong\.gemini\config\skills\roblox-studio-mcp\scripts")
from fast_connect import RobloxMCPClient

def main():
    if not MANIFEST_PATH.exists():
        print(f"[ERROR] 找不到清单文件: {MANIFEST_PATH}", file=sys.stderr)
        sys.exit(1)

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    sounds = manifest.get("sounds", {})
    if not sounds:
        print("[ERROR] 清单内暂无已上传音效", file=sys.stderr)
        sys.exit(1)

    print(f"正在连接 Roblox Studio 并部署 {len(sounds)} 个声音实例...")
    client = RobloxMCPClient()
    studios = client.list_studios()
    if not studios:
        print("[ERROR] 未发现打开的 Roblox Studio 会话", file=sys.stderr)
        client.close()
        sys.exit(1)

    sid = studios[0]["id"]
    print(f"目标 Studio: {studios[0]['name']} (ID: {sid})")

    # 构建 Luau 安装脚本
    # 按照规范：除 BGM 外全部放置在 ReplicatedStorage.Sounds
    sounds_payload = json.dumps(sounds, ensure_ascii=False)

    setup_code = f"""
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local rawJson = [==[{sounds_payload}]==]
local soundsMap = HttpService:JSONDecode(rawJson)

-- 1. 确保 ReplicatedStorage.Sounds 存在
local repSounds = ReplicatedStorage:FindFirstChild("Sounds")
if not repSounds then
    repSounds = Instance.new("Folder")
    repSounds.Name = "Sounds"
    repSounds.Parent = ReplicatedStorage
end

-- 2. 获取 SoundGroups
local soundGroups = SoundService:FindFirstChild("SoundGroups")
local sfxGroup = if soundGroups then soundGroups:FindFirstChild("SoundEffects") else nil
local bgmGroup = if soundGroups then soundGroups:FindFirstChild("BGM") else nil

local createdSFX = 0
local createdBGM = 0
local details = {{}}

for name, item in pairs(soundsMap) do
    local rbxId = item.rbxassetid or ("rbxassetid://" .. tostring(item.assetId))
    if name == "BGM" then
        -- BGM 放置于 SoundService
        local bgm = SoundService:FindFirstChild("BGM") :: Sound
        if not bgm then
            bgm = Instance.new("Sound")
            bgm.Name = "BGM"
            bgm.Parent = SoundService
        end
        bgm.SoundId = rbxId
        bgm.Volume = 0.5
        bgm.Looped = true
        if bgmGroup and bgmGroup:IsA("SoundGroup") then
            bgm.SoundGroup = bgmGroup
        end
        createdBGM += 1
        table.insert(details, {{ name = name, parent = "SoundService", soundId = rbxId }})
    else
        -- 其余所有音效全部放置在 ReplicatedStorage.Sounds
        local sound = repSounds:FindFirstChild(name) :: Sound
        if not sound then
            sound = Instance.new("Sound")
            sound.Name = name
            sound.Parent = repSounds
        end
        sound.SoundId = rbxId
        sound.Volume = 0.7
        sound.Looped = false
        sound.RollOffMode = Enum.RollOffMode.InverseTapered
        sound.RollOffMinDistance = 10
        sound.RollOffMaxDistance = 80
        if sfxGroup and sfxGroup:IsA("SoundGroup") then
            sound.SoundGroup = sfxGroup
        end
        createdSFX += 1
        table.insert(details, {{ name = name, parent = "ReplicatedStorage.Sounds", soundId = rbxId }})
    end
end

return {{
    repSoundsCount = #repSounds:GetChildren(),
    createdSFX = createdSFX,
    createdBGM = createdBGM,
    details = details
}}
"""

    res = client.execute_luau(setup_code, studio_id=sid)
    print("Studio 执行结果:", res)
    client.close()

if __name__ == "__main__":
    main()
