#!/usr/bin/env python3
"""从保留的原素材提取战斗/收集单次音效，记录可复现裁切及验收数据。"""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

import numpy as np

SOUNDS_DIR = Path(__file__).resolve().parents[2] / "Assets" / "Sounds"
TARGETS = {"Zap_T1": .16, "Zap_T2": .19, "Zap_T3": .22, "Zap_T4": .26,
           "Zap_T5": .30, "AnimalHit": .15, "AnimalCooked": .30,
           "FoodDrop": .15, "Pickup": .18, "Warning": .30}
SAMPLE_RATE = 44100
RECORD_PATH = SOUNDS_DIR / "combat_processing.json"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(path):
    return np.frombuffer(subprocess.check_output([
        "ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", "1",
        "-ar", str(SAMPLE_RATE), "pipe:1"]), dtype="<f4").copy()


def probe_duration(path):
    return float(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", str(path)]))


def process(name):
    output = SOUNDS_DIR / f"{name}.mp3"
    original = SOUNDS_DIR / "Originals" / output.name
    original.parent.mkdir(exist_ok=True)
    if not original.exists():
        shutil.copy2(output, original)
    samples = decode(original)
    # 5 ms RMS 门限定位首个有效起音，保留 2 ms 提前量，不选尾部最大峰。
    window = int(SAMPLE_RATE * .005)
    blocks = samples[:len(samples) // window * window].reshape(-1, window)
    rms = np.sqrt(np.mean(blocks * blocks, axis=1))
    active = np.flatnonzero(rms >= max(float(rms.max()) * .08, .0001))
    if not len(active):
        raise ValueError(f"{name}: no audible onset")
    start = max(0, int(active[0]) * window - int(SAMPLE_RATE * .002))
    count = round(TARGETS[name] * SAMPLE_RATE)
    clip = samples[start:start + count].copy()
    if len(clip) != count:
        raise ValueError(f"{name}: source too short")
    fade_in, fade_out = round(SAMPLE_RATE * .003), round(SAMPLE_RATE * .02)
    clip[:fade_in] *= np.linspace(0, 1, fade_in)
    clip[-fade_out:] *= np.linspace(1, 0, fade_out)
    # 只在接近满幅时衰减预留 MP3 编码余量，不提升响度或变速。
    safety_gain = min(1., .80 / max(float(np.max(np.abs(clip))), .0001))
    clip *= safety_gain
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SAMPLE_RATE),
        "-ac", "1", "-i", "pipe:0", "-map_metadata", "-1", "-c:a", "libmp3lame",
        "-b:a", "128k", str(output)], input=clip.astype("<f4").tobytes(), check=True)
    duration = probe_duration(output)
    decoded = decode(output)
    if not TARGETS[name] <= duration <= TARGETS[name] + .06:
        raise ValueError(f"{name}: encoded duration {duration} out of bounds")
    return {
        "source": original.relative_to(SOUNDS_DIR).as_posix(), "sourceSha256": sha256(original),
        "sourceDurationSeconds": len(samples) / SAMPLE_RATE,
        "trimStartSeconds": start / SAMPLE_RATE, "trimEndSeconds": (start + count) / SAMPLE_RATE,
        "effectiveDurationSeconds": count / SAMPLE_RATE, "encodedDurationSeconds": duration,
        "fadeInSeconds": .003, "fadeOutSeconds": .02,
        "safetyGain": safety_gain,
        "sha256": sha256(output), "peak": float(np.max(np.abs(decoded))),
        "rms": float(np.sqrt(np.mean(decoded * decoded))),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--names", nargs="+", choices=list(TARGETS), default=list(TARGETS))
    args = parser.parse_args()
    record = json.loads(RECORD_PATH.read_text(encoding="utf-8")) if RECORD_PATH.exists() else {"sounds": {}}
    for name in args.names:
        record["sounds"][name] = process(name)
        RECORD_PATH.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"{name}: {record['sounds'][name]['encodedDurationSeconds']:.3f}s")


if __name__ == "__main__":
    main()
