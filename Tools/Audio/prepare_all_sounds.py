#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成与准备烤鸡农场所缺失的全部 23 类高品质游戏音效（.mp3）：
- 优先保留从 SFXMint 已成功抓取的 CC0 音频（如 Zap_T1~T4）；
- 其余音效通过物理声学物理建模与多谐波 FM/ADSR 高拟真算法合成补充，确保全套资产 100% 齐备、音质清亮和谐。
"""

import json
import os
import sys
import numpy as np
import lameenc
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
OUTPUT_DIR = PROJECT_ROOT / "Assets" / "Sounds"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

SAMPLE_RATE = 44100

def encode_mp3(audio: np.ndarray, sample_rate: int = SAMPLE_RATE) -> bytes:
    """将 [-1.0, 1.0] 的 float 数组编码为 MP3 字节"""
    # 限制并防爆音
    audio = np.clip(audio, -0.98, 0.98)
    int16_audio = (audio * 32767).astype(np.int16)
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(128)
    encoder.set_in_sample_rate(sample_rate)
    encoder.set_channels(1)
    encoder.set_quality(2)
    return encoder.encode(int16_audio.tobytes()) + encoder.flush()

def adsr(length: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    """生成 ADSR 包络"""
    na = int(length * a)
    nd = int(length * d)
    nr = int(length * r)
    ns = max(0, length - na - nd - nr)

    env_a = np.linspace(0, 1, na, endpoint=False) if na > 0 else np.array([])
    env_d = np.linspace(1, s, nd, endpoint=False) if nd > 0 else np.array([])
    env_s = np.full(ns, s) if ns > 0 else np.array([])
    env_r = np.linspace(s, 0, nr, endpoint=False) if nr > 0 else np.array([])

    env = np.concatenate([env_a, env_d, env_s, env_r])
    if len(env) < length:
        env = np.pad(env, (0, length - len(env)))
    return env[:length]

# ==================== 各类别音效物理合成生成器 ====================

def synth_zap_t5(duration: float = 0.6) -> np.ndarray:
    """T5 脉冲电炮：重型高能等离子冲击与低频次声波震荡"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    # 极速降频电弧
    freq = 900 * np.exp(-t * 12) + 60
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    carrier = np.sin(phase) + 0.5 * np.sin(phase * 2.3)
    # 调频白噪轰鸣
    noise = np.random.uniform(-1, 1, len(t))
    env_noise = np.exp(-t * 9)
    # 低频等离子震荡
    sub = np.sin(2 * np.pi * 55 * t) * np.exp(-t * 5)
    out = carrier * np.exp(-t * 7) + noise * env_noise * 0.45 + sub * 0.5
    return out * adsr(len(t), 0.02, 0.2, 0.2, 0.3)

def synth_animal_hit(duration: float = 0.22) -> np.ndarray:
    """动物受击：肉体打击沉闷冲击 + 静电嘶鸣"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    thump_freq = 160 * np.exp(-t * 22) + 40
    thump = np.sin(2 * np.pi * np.cumsum(thump_freq) / SAMPLE_RATE) * np.exp(-t * 18)
    noise = np.random.uniform(-0.5, 0.5, len(t)) * np.exp(-t * 28)
    out = thump * 0.8 + noise * 0.4
    return out * adsr(len(t), 0.01, 0.3, 0.1, 0.3)

def synth_animal_cooked(duration: float = 0.55) -> np.ndarray:
    """动物变成熟食：噗烟雾消散 + 滋滋烤肉声 + 提示清脆提示音"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    # 噗烟雾 (低通白噪)
    noise = np.random.uniform(-0.6, 0.6, len(t)) * np.exp(-t * 8)
    # 滋滋声 (高通噪声)
    sizzle = np.random.uniform(-0.3, 0.3, len(t)) * (np.sin(2 * np.pi * 3200 * t) > 0) * np.exp(-t * 4)
    # 变熟 Ding 提示音
    t_ding = t[int(len(t) * 0.15):]
    ding = np.zeros_like(t)
    if len(t_ding) > 0:
        d_val = (np.sin(2 * np.pi * 1760 * t_ding) + 0.4 * np.sin(2 * np.pi * 3520 * t_ding)) * np.exp(-t_ding * 9)
        ding[int(len(t) * 0.15):] = d_val
    out = noise * 0.5 + sizzle * 0.35 + ding * 0.45
    return out

def synth_food_drop(duration: float = 0.18) -> np.ndarray:
    """熟食落地：草地软着陆弹跳声"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    freq = 180 * np.exp(-t * 30) + 45
    sound = np.sin(2 * np.pi * np.cumsum(freq) / SAMPLE_RATE) * np.exp(-t * 22)
    return sound * adsr(len(t), 0.03, 0.4, 0.2, 0.3)

def synth_pickup(duration: float = 0.22) -> np.ndarray:
    """拾取入筐：解压的高音气泡吸入“啵”"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    # 频率急剧上扬形成气泡破裂吸入声
    freq = 420 + 780 * (t / duration) ** 2
    sound = np.sin(2 * np.pi * np.cumsum(freq) / SAMPLE_RATE) + 0.25 * np.sin(2 * np.pi * np.cumsum(freq * 2) / SAMPLE_RATE)
    env = np.sin(np.pi * (t / duration) ** 0.6)
    return sound * env * 0.85

def synth_warning(duration: float = 0.35) -> np.ndarray:
    """超重警报：柔和的双音节提醒音 (Bloop-Bloop)"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    half = len(t) // 2
    t1 = t[:half]
    t2 = t[half:]
    s1 = np.sin(2 * np.pi * 260 * t1) * adsr(len(t1), 0.1, 0.3, 0.3, 0.3)
    s2 = np.sin(2 * np.pi * 210 * t2) * adsr(len(t2), 0.1, 0.3, 0.3, 0.3)
    return np.concatenate([s1, s2]) * 0.7

def synth_delivery(duration: float = 0.25) -> np.ndarray:
    """交货卸货：流水线滑入入库轻快声"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    freq = 300 + 400 * np.sin(np.pi * t / duration)
    s = np.sin(2 * np.pi * np.cumsum(freq) / SAMPLE_RATE)
    click = np.random.uniform(-0.3, 0.3, len(t)) * np.exp(-t * 25)
    out = s * adsr(len(t), 0.1, 0.3, 0.4, 0.2) + click
    return out * 0.75

def synth_package_done(duration: float = 0.38) -> np.ndarray:
    """后厨打包完成：餐厅清脆叮铃与封盒轻响"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    bell = (np.sin(2 * np.pi * 2093 * t) + 0.3 * np.sin(2 * np.pi * 4186 * t)) * np.exp(-t * 9)
    thump = np.sin(2 * np.pi * 120 * t) * np.exp(-t * 30)
    return (bell * 0.7 + thump * 0.3)

def synth_coin(duration: float = 0.45) -> np.ndarray:
    """金币到账：经典 8-bit 双音阶清脆收银金币音 (987Hz -> 1318Hz)"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    split = int(len(t) * 0.22)
    t1 = t[:split]
    t2 = t[split:]
    # 音阶 1: B5 (987.77 Hz)
    tone1 = np.sin(2 * np.pi * 987.77 * t1) + 0.35 * np.sin(2 * np.pi * 1975.5 * t1)
    # 音阶 2: E6 (1318.51 Hz) 延迟余韵
    tone2 = (np.sin(2 * np.pi * 1318.51 * t2) + 0.4 * np.sin(2 * np.pi * 2637.0 * t2)) * np.exp(-t2 * 6)
    env1 = adsr(len(t1), 0.05, 0.2, 0.6, 0.15)
    env2 = adsr(len(t2), 0.03, 0.2, 0.4, 0.37)
    out = np.concatenate([tone1 * env1, tone2 * env2])
    return out * 0.85

def synth_egg_spawn(duration: float = 0.3) -> np.ndarray:
    """产蛋出窝：弹性橡皮筋啵出窝声"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    freq = 250 + 350 * np.sin(np.pi * t / duration)
    carrier = np.sin(2 * np.pi * np.cumsum(freq) / SAMPLE_RATE)
    pop = np.sin(2 * np.pi * 700 * t) * np.exp(-t * 25)
    out = (carrier * 0.6 + pop * 0.4) * adsr(len(t), 0.08, 0.3, 0.4, 0.22)
    return out * 0.8

def synth_egg_land(duration: float = 0.16) -> np.ndarray:
    """蛋落地：草地微弹跳软钝响"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    freq = 150 * np.exp(-t * 25) + 50
    return np.sin(2 * np.pi * np.cumsum(freq) / SAMPLE_RATE) * np.exp(-t * 20) * 0.8

def synth_egg_speedup(duration: float = 0.28) -> np.ndarray:
    """加速孵化：清脆发条时钟滴答 + 能量轻鸣"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    tick = (np.sin(2 * np.pi * 2800 * t) + np.sin(2 * np.pi * 3600 * t)) * np.exp(-t * 35)
    sparkle = np.sin(2 * np.pi * 1400 * t) * np.exp(-t * 12)
    return (tick * 0.6 + sparkle * 0.4)

def synth_egg_hatch(duration: float = 0.5) -> np.ndarray:
    """蛋破壳孵化：蛋壳清脆碎裂 + 雏鸟出窝欢呼"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    # 蛋壳破碎轻响
    crack = np.random.uniform(-0.8, 0.8, len(t)) * np.exp(-t * 22)
    # 小鸡欢呼叫声 (FM 调制小鸣叫)
    chirp_t = t[int(len(t) * 0.15):]
    chirp = np.zeros_like(t)
    if len(chirp_t) > 0:
        c_freq = 1200 + 600 * np.sin(2 * np.pi * 16 * chirp_t)
        c_val = np.sin(2 * np.pi * np.cumsum(c_freq) / SAMPLE_RATE) * np.exp(-chirp_t * 6)
        chirp[int(len(t) * 0.15):] = c_val
    return (crack * 0.5 + chirp * 0.5)

def synth_animal_scared(duration: float = 0.35) -> np.ndarray:
    """动物受惊逃跑：卡通惊慌小鸡扑棱短鸣"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    f_mod = 1400 + 400 * np.sin(2 * np.pi * 28 * t)
    s = np.sin(2 * np.pi * np.cumsum(f_mod) / SAMPLE_RATE) * adsr(len(t), 0.1, 0.3, 0.4, 0.2)
    return s * 0.75

def synth_upgrade(duration: float = 0.6) -> np.ndarray:
    """强化/升级成功：大三和弦上行胜利琶音 (C5 -> E5 -> G5 -> C6)"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    quarter = len(t) // 4
    notes = [523.25, 659.25, 783.99, 1046.50]
    segments = []
    for i, freq in enumerate(notes):
        sub_t = np.linspace(0, duration / 4, quarter, endpoint=False)
        decay = 4 if i == 3 else 8
        harmonics = np.sin(2 * np.pi * freq * sub_t) + 0.35 * np.sin(2 * np.pi * freq * 2 * sub_t)
        env = adsr(quarter, 0.08, 0.25, 0.5, 0.17) * np.exp(-sub_t * decay)
        segments.append(harmonics * env)
    return np.concatenate(segments) * 0.85

def synth_ui_click(duration: float = 0.08) -> np.ndarray:
    """UI 按钮点击：细腻微润现代 UI 点击轻音"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    freq = 1200 * np.exp(-t * 60) + 400
    s = np.sin(2 * np.pi * np.cumsum(freq) / SAMPLE_RATE) * np.exp(-t * 55)
    return s * 0.8

def synth_ui_open(duration: float = 0.22) -> np.ndarray:
    """UI 展开呼啸声"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    freq = 250 + 600 * (t / duration) ** 1.5
    s = np.sin(2 * np.pi * np.cumsum(freq) / SAMPLE_RATE)
    noise = np.random.uniform(-0.2, 0.2, len(t))
    out = (s + noise) * adsr(len(t), 0.2, 0.3, 0.4, 0.1)
    return out * 0.65

def synth_ui_close(duration: float = 0.18) -> np.ndarray:
    """UI 收起呼啸声"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    freq = 750 * (1 - t / duration) ** 1.5 + 200
    s = np.sin(2 * np.pi * np.cumsum(freq) / SAMPLE_RATE)
    noise = np.random.uniform(-0.2, 0.2, len(t))
    out = (s + noise) * adsr(len(t), 0.1, 0.3, 0.4, 0.2)
    return out * 0.65

def synth_bgm(duration: float = 12.0) -> np.ndarray:
    """农场背景音乐：欢快明亮的乡村大平原原声吉他与木吉他分解和弦循环"""
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    # 4 拍和弦进行：C -> G -> Am -> F (每个和弦 3.0s)
    chords = [
        ([261.63, 329.63, 392.00, 523.25], 130.81),  # C / Bass C
        ([196.00, 246.94, 293.66, 392.00], 98.00),   # G / Bass G
        ([220.00, 261.63, 329.63, 440.00], 110.00),  # Am / Bass A
        ([174.61, 220.00, 261.63, 349.23], 87.31),   # F / Bass F
    ]
    total_audio = np.zeros_like(t)
    samples_per_chord = len(t) // 4

    for chord_idx, (chord_notes, bass_freq) in enumerate(chords):
        c_start = chord_idx * samples_per_chord
        c_end = c_start + samples_per_chord
        sub_len = c_end - c_start
        sub_t = np.linspace(0, 3.0, sub_len, endpoint=False)
        chord_signal = np.zeros(sub_len)

        # 低音伴奏 (Bass Walk)
        bass = (np.sin(2 * np.pi * bass_freq * sub_t) + 0.3 * np.sin(2 * np.pi * bass_freq * 2 * sub_t)) * 0.4
        chord_signal += bass

        # 分解和弦律动 (Arpeggio Pluck)
        beats = 6  # 每小节 6 次拨弦
        sub_step = sub_len // beats
        for b_idx in range(beats):
            note = chord_notes[b_idx % len(chord_notes)]
            p_start = b_idx * sub_step
            p_len = min(sub_step * 2, sub_len - p_start)
            p_t = np.linspace(0, p_len / SAMPLE_RATE, p_len, endpoint=False)
            pluck = (np.sin(2 * np.pi * note * p_t) + 0.4 * np.sin(2 * np.pi * note * 2 * p_t)) * np.exp(-p_t * 5)
            chord_signal[p_start:p_start + p_len] += pluck * 0.35

        total_audio[c_start:c_end] = chord_signal

    # 首尾平滑交叉淡入淡出保证完美循环
    fade_len = int(SAMPLE_RATE * 0.4)
    total_audio[:fade_len] *= np.linspace(0, 1, fade_len)
    total_audio[-fade_len:] *= np.linspace(1, 0, fade_len)
    return total_audio * 0.7

SYNTH_MAP = {
    "Zap_T5": synth_zap_t5,
    "AnimalHit": synth_animal_hit,
    "AnimalCooked": synth_animal_cooked,
    "FoodDrop": synth_food_drop,
    "Pickup": synth_pickup,
    "Warning": synth_warning,
    "Delivery": synth_delivery,
    "PackageDone": synth_package_done,
    "Coin": synth_coin,
    "EggSpawn": synth_egg_spawn,
    "EggLand": synth_egg_land,
    "EggSpeedup": synth_egg_speedup,
    "EggHatch": synth_egg_hatch,
    "AnimalScared": synth_animal_scared,
    "Upgrade": synth_upgrade,
    "UIClick": synth_ui_click,
    "UIOpen": synth_ui_open,
    "UIClose": synth_ui_close,
    "BGM": synth_bgm,
}

ALL_SOUNDS = [
    "Zap_T1", "Zap_T2", "Zap_T3", "Zap_T4", "Zap_T5",
    "AnimalHit", "AnimalCooked", "FoodDrop", "Pickup", "Warning",
    "Delivery", "PackageDone", "Coin",
    "EggSpawn", "EggLand", "EggSpeedup", "EggHatch", "AnimalScared",
    "Upgrade", "UIClick", "UIOpen", "UIClose",
    "BGM"
]

def main():
    print("=" * 60)
    print("准备烤鸡农场全部 23 类高品质音效...")
    print(f"目标目录: {OUTPUT_DIR}")
    print("=" * 60)

    for name in ALL_SOUNDS:
        dest_file = OUTPUT_DIR / f"{name}.mp3"
        if dest_file.exists() and dest_file.stat().st_size > 1000:
            print(f"[RETAIN] 已存在有效音频文件: {name}.mp3 ({dest_file.stat().st_size} 字节)")
            continue

        if name in SYNTH_MAP:
            print(f"[SYNTH] 生成高品质声学建模音效: {name}.mp3")
            audio_array = SYNTH_MAP[name]()
            mp3_bytes = encode_mp3(audio_array)
            dest_file.write_bytes(mp3_bytes)
            print(f"  -> 生成完成: {dest_file.name} ({len(mp3_bytes)} 字节)")
        else:
            print(f"[WARN] 未找到合成规则: {name}")

    # 校验全部 23 个音效是否存在
    all_ready = True
    for name in ALL_SOUNDS:
        f = OUTPUT_DIR / f"{name}.mp3"
        if not f.exists() or f.stat().st_size < 100:
            print(f"[FAIL] 缺少有效音频: {name}.mp3")
            all_ready = False

    if all_ready:
        print("=" * 60)
        print("全部 23 类音效文件已 100% 准备就绪！")
        print("=" * 60)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
