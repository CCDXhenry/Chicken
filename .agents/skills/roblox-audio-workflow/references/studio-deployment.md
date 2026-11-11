# Studio 实例树部署与 MCP 挂载指南 (Studio Deployment)

本参考文档规定通过 Roblox Studio MCP 在处于 **Edit 模式** 的 Studio 会话中，将已上传的云端音频自动化部署为标准实例树的执行流程与规范。

---

## 1. 实例挂载结构红线

Roblox 游戏架构中，声音实例的摆放位置直接决定客户端与服务端的寻址统一性以及多端资源预载。

```text
game
├── ReplicatedStorage
│   └── Sounds (Folder)                <-- 唯一音效模板源 (Single Source of Truth)
│       ├── UIClick (Sound)            Looped=false, Volume=0.5
│       ├── Coin (Sound)               Looped=false, Volume=0.6
│       ├── Zap_T1 (Sound)             Looped=false, Volume=0.7
│       ├── AnimalHit (Sound)          Looped=false, Volume=0.8
│       └── ... (全量 SFX 模板)
└── SoundService
    └── BGM (Sound)                    <-- 唯独背景音乐放置于此处 (Looped=true, Volume=0.4)
```

> [!IMPORTANT]
> **摆放规则**：
> 1. **除 BGM 实例外，其余所有 SFX 音效必须且只能全部放置在 `ReplicatedStorage.Sounds`（Folder）中**。
> 2. `ReplicatedStorage` 中的 `Sound` 实例仅作为**模板 (Template)** 存在，运行期不直接在此处调用 `:Play()`，而是通过对象池克隆/复用播放。
> 3. **唯独 BGM 放置于 `SoundService.BGM`**（或挂在 `SoundGroups.BGM` 下），作为常驻背景循环音乐。

---

## 2. 自动化部署脚本实现 (通过 StudioMCP)

使用 Python 桥接 `fast_connect`，在 Studio 打开工程的 Edit 模式下，直接注入幂等性 Luau 初始化代码。

### 2.1 部署代码核心逻辑

```python
import json
import sys
from pathlib import Path

# 引入 StudioMCP fast_connect 客户端
sys.path.append(r"C:\Users\herong\.gemini\config\skills\roblox-studio-mcp\scripts")
from fast_connect import RobloxMCPClient

def deploy_sounds_to_studio(manifest_path: Path):
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    sounds = manifest.get("sounds", {})
    
    client = RobloxMCPClient()
    studios = client.list_studios()
    if not studios:
        raise RuntimeError("未检测到打开的 Roblox Studio 会话")
    sid = studios[0]["id"]
    
    sounds_payload = json.dumps(sounds, ensure_ascii=False)
    
    # 构造 Edit 模式下执行的 Luau 部署脚本
    luau_code = f"""
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local rawData = [===[{sounds_payload}]===]
local sounds = HttpService:JSONDecode(rawData)

-- 1. 确保 ReplicatedStorage.Sounds (Folder) 存在
local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
if not soundsFolder then
    soundsFolder = Instance.new("Folder")
    soundsFolder.Name = "Sounds"
    soundsFolder.Parent = ReplicatedStorage
end

local createdSFX = 0
local createdBGM = 0

-- 2. 遍历清单并部署
for soundName, data in pairs(sounds) do
    if soundName == "BGM" or data.category == "BGM" then
        -- 部署 BGM 到 SoundService
        local bgm = SoundService:FindFirstChild("BGM")
        if not bgm or not bgm:IsA("Sound") then
            if bgm then bgm:Destroy() end
            bgm = Instance.new("Sound")
            bgm.Name = "BGM"
            bgm.Parent = SoundService
        end
        bgm.SoundId = data.soundId
        bgm.Volume = data.defaultVolume or 0.4
        bgm.Looped = true
        createdBGM = createdBGM + 1
    else
        -- 部署 SFX 到 ReplicatedStorage.Sounds
        local sound = soundsFolder:FindFirstChild(soundName)
        if not sound or not sound:IsA("Sound") then
            if sound then sound:Destroy() end
            sound = Instance.new("Sound")
            sound.Name = soundName
            sound.Parent = soundsFolder
        end
        sound.SoundId = data.soundId
        sound.Volume = data.defaultVolume or 0.6
        sound.Looped = false
        sound.RollOffMode = Enum.RollOffMode.InverseTapered
        sound.RollOffMinDistance = 10
        sound.RollOffMaxDistance = 100
        createdSFX = createdSFX + 1
    end
end

return HttpService:JSONEncode({{
    success = true,
    createdSFX = createdSFX,
    createdBGM = createdBGM,
    soundsFolder = soundsFolder:GetFullName()
}})
"""
    # 注意：execute_luau 参数依次为 (code, datamodel_type, studio_id)
    res = client.execute_luau(luau_code, "Edit", sid)
    print("Studio 部署响应:", res)
    client.close()
```

---

## 3. 部署后只读校验与验收

部署执行完毕后，执行只读探针确认实例存在且数量完全吻合：

```python
code = """
local rep = game:GetService("ReplicatedStorage")
local ss = game:GetService("SoundService")

local folder = rep:FindFirstChild("Sounds")
local count = 0
if folder then
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Sound") then count = count + 1 end
    end
end

local bgm = ss:FindFirstChild("BGM")
return {
    soundsFolderExists = folder ~= nil,
    sfxCount = count,
    bgmExists = (bgm ~= nil and bgm.SoundId ~= "")
}
"""
```

验收标准：
- `soundsFolderExists == True`；
- `sfxCount` 严格等于清单中的 SFX 总数（如 22）；
- `bgmExists == True`。
