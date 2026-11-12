# 音效设计与声学合成规范 (Audio Generation & Synthesis)

本参考文档规定在 Roblox 项目中进行音频资产规划、AI 工具拉取（SFXMint）以及通过 Python 进行物理声学算法合成（FM 调频、谐波衰减、噪声滤波与 ADSR 包络）的具体实施细节。

---

## 1. 声音规格与分类标准

下表为初步选材建议，不是固定时长或响度门禁。以实际动作冷却、动画与混音为准，修正现有素材时先校准而非直接换音色；裁切、触发与验收细节从 SKILL.md 的“校准与触发验收”入口读取。空间声或全局声应按听众与玩法决定，不因名称含 Zap 就强制改为 3D。

| 分类 | 典型音效 | 播放机制 | 声道与格式建议 | 混音响度建议 |
| :--- | :--- | :--- | :--- | :--- |
| **2D UI 音效** | `UIClick`, `UIOpen`, `UIClose` | 全局 2D | 单声道/立体声 44.1kHz MP3, <0.3s | -12 dB ~ -15 dB |
| **2D 反馈音效** | `Coin`, `Upgrade`, `Warning` | 全局 2D | 单声道/立体声 44.1kHz MP3, 0.4s~1.2s | -10 dB ~ -12 dB |
| **3D 战斗/电击** | `Zap_T1` ~ `Zap_T5` | 空间 3D (Attachment) | 单声道 44.1kHz MP3, 0.2s~0.5s | -8 dB ~ -10 dB |
| **3D 环境/生物** | `AnimalHit`, `AnimalScared`, `EggHatch` | 空间 3D (Attachment) | 单声道 44.1kHz MP3, 0.4s~0.8s | -10 dB ~ -12 dB |
| **3D 物理交互** | `EggSpawn`, `EggLand`, `FoodDrop` | 空间 3D (Attachment) | 单声道 44.1kHz MP3, 0.2s~0.4s | -12 dB ~ -14 dB |
| **BGM 背景音乐** | `BGM` (FarmTheme) | 全局循环 (Looped) | 立体声 44.1kHz MP3, 30s~120s 循环点 | -18 dB ~ -22 dB |

> [!IMPORTANT]
> 空间 3D 音效**强烈推荐使用单声道 (Mono)**。Roblox 声音引擎在计算双耳声差、方位感（Panning）和基于距离衰减（RollOff）时，单声道音频效果最清晰且计算开销最低。

---

## 2. SFXMint 工具接入与拉取流水线

对于常见游戏音效（如硬币叮当、按钮点击、UI 开关、水滴、爆炸），首选采用 SFXMint（`https://github.com/sfxmint/sfxmint-mcp`）开源 CC0 音效库：

### 2.1 语义关键词检索规范
- **硬币结算**：`coin`, `pickup_gold`, `cash_register`
- **UI 交互**：`click_clean`, `interface_tap`, `pop_menu`, `whoosh_open`
- **升级成就**：`level_up_fanfare`, `magic_chime`, `tada_jingle`
- **受击受挫**：`cartoon_squish`, `hit_thud`, `punch_impact`
- **警告提示**：`buzzer_deny`, `alert_soft`, `warning_beep`

### 2.2 API 限流与降级策略
- **问题**：外部服务可能返回 HTTP 429 或鉴权错误；以当前响应为准，不依赖固定匿名配额。
- **策略**：
  1. 下载成功的音频直接存入 `Assets/Sounds/<Name>.mp3`；
  2. 遇到限流或网络阻断时停止无效重试；可按任务要求使用已有授权素材或本地合成。用户要求保留原音色时不得擅自换成合成音，也不能把合成成功等同于音质验收。

---

## 3. Python 物理声学高保真合成引擎

当缺少外部音效或需要精确的阶梯式过渡（如武器阶位 T1~T5 的能量频率由低到高）时，使用 `numpy` + `lameenc` 进行物理声学建模。

### 3.1 核心算法实现：ADSR 包络控制
消除一切音频头尾的硬切断爆音（Pop/Click）：
```python
import numpy as np

def apply_adsr(signal, sample_rate, attack=0.005, decay=0.05, sustain=0.7, release=0.05):
    """
    应用 ADSR (Attack-Decay-Sustain-Release) 包络，确保音效平滑、饱满、无爆音。
    """
    n_samples = len(signal)
    t = np.linspace(0, n_samples / sample_rate, n_samples, endpoint=False)
    envelope = np.zeros(n_samples)

    n_attack = int(attack * sample_rate)
    n_decay = int(decay * sample_rate)
    n_release = int(release * sample_rate)
    n_sustain = max(0, n_samples - n_attack - n_decay - n_release)

    # 1. Attack: 线性或指数上升
    idx = 0
    if n_attack > 0:
        envelope[idx:idx + n_attack] = np.linspace(0, 1, n_attack)
        idx += n_attack
    # 2. Decay: 下降到 sustain 电平
    if n_decay > 0:
        envelope[idx:idx + n_decay] = np.linspace(1, sustain, n_decay)
        idx += n_decay
    # 3. Sustain: 稳定电平
    if n_sustain > 0:
        envelope[idx:idx + n_sustain] = sustain
        idx += n_sustain
    # 4. Release: 衰减到 0
    if n_release > 0:
        rem = n_samples - idx
        envelope[idx:] = np.linspace(sustain, 0, rem)

    return signal * envelope
```

### 3.2 典型物理声学建模公式

#### 1. 激光/电击系列（FM 调频 + 阶跃调制）
```python
def synthesize_zap(tier=1, sample_rate=44100):
    duration = 0.22 + tier * 0.04
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    # 阶位越高，基频越宽、调频深度越剧烈
    base_freq = 400 + tier * 250
    end_freq = 120 + tier * 60
    carrier_freq = np.linspace(base_freq, end_freq, len(t))
    modulator = np.sin(2 * np.pi * (base_freq * 1.5) * t) * (tier * 0.4)
    wave = np.sin(2 * np.pi * carrier_freq * t + modulator)
    # 注入轻度饱和削波增强激光打击感
    wave = np.tanh(wave * (1.2 + tier * 0.3))
    return apply_adsr(wave, sample_rate, attack=0.002, decay=0.04, sustain=0.3, release=0.08)
```

#### 2. 金币/铃铛系列（多重谐波叠加 + 指数衰减）
```python
def synthesize_coin(sample_rate=44100):
    duration = 0.45
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    # 经典马里奥/街机硬币：双频阶跃 (987Hz -> 1318Hz, B5 到 E6)
    split = int(0.08 * sample_rate)
    wave = np.zeros_like(t)
    wave[:split] = np.sin(2 * np.pi * 987.77 * t[:split]) + 0.3 * np.sin(2 * np.pi * 1975.5 * t[:split])
    wave[split:] = np.sin(2 * np.pi * 1318.51 * t[split:]) + 0.4 * np.sin(2 * np.pi * 2637.0 * t[split:])
    decay = np.exp(-7.0 * t)
    return wave * decay
```

#### 3. 破壳/雏鸟鸣叫（扫频正弦波与颤音）
```python
def synthesize_egg_hatch(sample_rate=44100):
    duration = 0.55
    t = np.linspace(0, duration, int(sample_rate * duration), endpoint=False)
    # 蛋壳爆开喀嚓短脉冲
    crack = (np.random.rand(int(0.04 * sample_rate)) * 2 - 1) * np.exp(-50 * t[:int(0.04 * sample_rate)])
    # 雏鸟颤音叫声 (2.8kHz 上扫到 3.6kHz 带 20Hz 颤音)
    t_chirp = t[len(crack):]
    freq = np.linspace(2800, 3600, len(t_chirp))
    vibrato = 120 * np.sin(2 * np.pi * 22 * t_chirp)
    chirp = 0.6 * np.sin(2 * np.pi * (freq + vibrato) * t_chirp)
    signal = np.concatenate([crack, chirp])
    return apply_adsr(signal, sample_rate, attack=0.003, decay=0.06, sustain=0.5, release=0.1)
```

### 3.3 MP3 编码与元数据导出
合成完成后，通过 `lameenc` 编码为紧凑标准的 MP3 格式：
```python
import lameenc

def export_mp3(pcm_float_data, sample_rate, out_path):
    # 归一化并转 16-bit PCM
    pcm_int16 = (np.clip(pcm_float_data, -1.0, 1.0) * 32767).astype(np.int16)
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(128)
    encoder.set_in_sample_rate(sample_rate)
    encoder.set_channels(1)
    encoder.set_quality(2) # 高品质编码
    mp3_data = encoder.encode(pcm_int16.tobytes()) + encoder.flush()
    out_path.write_bytes(mp3_data)
```
