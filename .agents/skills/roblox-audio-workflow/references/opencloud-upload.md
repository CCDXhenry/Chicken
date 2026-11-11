# Open Cloud 批量上云实战指南 (Roblox Open Cloud Upload)

本参考文档规定使用 Roblox 官方 Open Cloud Assets API 批量自动化上传音频资产、处理权限鉴权、异步轮询进度及输出持久化资产清单的标准流程。

---

## 1. 核心接口与鉴权机制

- **API 端点**：`https://apis.roblox.com/assets/v1/assets`
- **认证方式**：HTTP 请求头 `x-api-key: <API_KEY>`
- **密钥来源**：读取环境变量 `SIXCUBE_ROBLOX_OPENCLOUD_KEY`（或项目指定的凭据名）。该 Key 必须具备 `asset:read` 与 `asset:write` 权限。

---

## 2. 关键避坑：资产归属者 (Creator) 配置

> [!CAUTION]
> 这是 Open Cloud Assets API 最容易踩坑的权限错误！
> Roblox 资产不能脱离归属者独立存在。**必须先核对目标 Place 的所有者是个人用户 (User) 还是开发群组 (Group)**。

### 2.1 归属者判断方式
在 Studio 或通过 Open Cloud 检查 Universe/Place 元数据：
- 如果游戏由个人创建（Personal Place）：
  `"creator": {"userId": "<USER_ID>"}`
- 如果游戏挂载在群组名下（Group Place，如 Group `33977495`）：
  `"creator": {"groupId": "33977495"}`

### 2.2 常见错误表现
- **错误代码**：`HTTP 403 Forbidden`
- **错误信息**：`{"message": "User not authenticated to upload asset for creator"}`
- **根因**：使用了 `userId` 去上传属于 `groupId` 的项目，或者 API Key 仅对群组授权而未对个人授权。
- **解决方案**：请求 payload 的 `request` 字段中将 `creator` 改为 `{"groupId": "<groupId>"}`。

---

## 3. 标准上传与轮询流水线实现

Open Cloud 上传音频为**异步操作 (Asynchronous Operation)**：
1. `POST /assets/v1/assets` 返回状态码 `200`，并带有 `path: "operations/<GUID>"`；
2. 轮询 `GET /assets/v1/operations/<GUID>`，直到 `done == True`；
3. 从 `response.assetId` 提取永久资产 ID，组合为 `rbxassetid://<assetId>`。

### 3.1 Python 批量上传代码模板

```python
import os
import json
import time
import requests
from pathlib import Path

API_URL = "https://apis.roblox.com/assets/v1/assets"
OPERATION_BASE_URL = "https://apis.roblox.com/assets/v1/" # 注意：必须包含 assets/v1/

def upload_audio(file_path: Path, asset_name: str, group_id: str, api_key: str) -> str:
    headers = {"x-api-key": api_key}
    
    metadata = {
        "assetType": "Audio",
        "displayName": asset_name[:32], # Roblox 最多支持 32 字符展示名
        "description": f"Auto generated {asset_name} audio asset.",
        "creationContext": {
            "creator": {
                "groupId": str(group_id) # 若为用户则用 "userId": str(user_id)
            }
        }
    }
    
    with open(file_path, "rb") as f:
        files = {
            "request": (None, json.dumps(metadata), "application/json"),
            "fileContent": (file_path.name, f, "audio/mpeg")
        }
        res = requests.post(API_URL, headers=headers, files=files, timeout=30)
        
    if res.status_code != 200:
        raise RuntimeError(f"Upload failed [{res.status_code}]: {res.text}")
        
    op_path = res.json().get("path")
    if not op_path:
        raise RuntimeError(f"Missing operation path: {res.text}")
        
    # 异步轮询结果
    poll_url = f"https://apis.roblox.com/assets/v1/{op_path}"
    for _ in range(30):
        time.sleep(1.5)
        poll_res = requests.get(poll_url, headers=headers, timeout=15)
        if poll_res.status_code == 200:
            data = poll_res.json()
            if data.get("done") is True:
                if "error" in data:
                    raise RuntimeError(f"Operation failed: {data['error']}")
                asset_id = data.get("response", {}).get("assetId")
                return f"rbxassetid://{asset_id}"
                
    raise TimeoutError(f"Upload operation timeout for {asset_name}")
```

> [!WARNING]
> **轮询 URL 陷阱**：
> Roblox API 返回的 operation path 形如 `operations/018c-xxx-yyy`。
> 官方完整的轮询地址是 `https://apis.roblox.com/assets/v1/operations/<GUID>`。
> **如果漏掉 `assets/v1/`（拼成了 `https://apis.roblox.com/operations/...`），会直接返回 `HTTP 404 Not Found`**。

---

## 4. 资产清单维护规范 (`audio_manifest.json`)

为了避免重复上传造成资产冗余、API 配额浪费，上传工具必须在 `Assets/Sounds/audio_manifest.json` 中维护状态清单。

### 4.1 清单格式定义
```json
{
  "updatedAt": "2026-11-11T15:20:00Z",
  "total": 23,
  "creator": {
    "type": "Group",
    "id": "33977495"
  },
  "sounds": {
    "UIClick": {
      "assetId": "106682020053205",
      "soundId": "rbxassetid://106682020053205",
      "file": "UIClick.mp3",
      "category": "UI",
      "isLooped": false,
      "defaultVolume": 0.5
    },
    "BGM": {
      "assetId": "78050720932794",
      "soundId": "rbxassetid://78050720932794",
      "file": "BGM.mp3",
      "category": "BGM",
      "isLooped": true,
      "defaultVolume": 0.4
    }
  }
}
```

### 4.2 增量跳过原则
在上传循环中，优先检查 `audio_manifest.json` 中是否已存在对应键值且包含有效 `soundId`。若存在则打印 `[SKIP]` 并直接复用，实现幂等增量上传。
