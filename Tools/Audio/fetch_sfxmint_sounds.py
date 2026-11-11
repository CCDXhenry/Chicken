#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 SFXMint (https://sfxmint.com / https://github.com/sfxmint/sfxmint-mcp)
批量抓取并下载烤鸡农场所缺失的 23 类高品质 CC0 游戏音效。
"""

import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent
OUTPUT_DIR = PROJECT_ROOT / "Assets" / "Sounds"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# 23 类音效规划与 SFXMint 检索偏好
SOUND_SPECS = [
    {
        "name": "Zap_T1",
        "query": "light electric zap short",
        "description": "T1 基础电棒轻型电火花",
    },
    {
        "name": "Zap_T2",
        "query": "chain lightning arc spark",
        "description": "T2 连锁电枪高频电弧",
    },
    {
        "name": "Zap_T3",
        "query": "sci-fi plasma pulse blast",
        "description": "T3 范围电炮电磁震爆",
    },
    {
        "name": "Zap_T4",
        "query": "heavy shockwave laser cannon",
        "description": "T4 广角电炮宽幅轰鸣",
    },
    {
        "name": "Zap_T5",
        "query": "overcharged plasma explosion",
        "description": "T5 脉冲电炮重型离子波",
    },
    {
        "name": "AnimalHit",
        "query": "flesh punch impact shock",
        "description": "动物被电击受击钝响",
    },
    {
        "name": "AnimalCooked",
        "query": "smoke puff sizzle fry magic",
        "description": "动物生命归零变烤肉",
    },
    {
        "name": "FoodDrop",
        "query": "soft item drop grass thud",
        "description": "熟食掉落到草地沉闷声",
    },
    {
        "name": "Pickup",
        "query": "bubble cartoon pop item pickup",
        "description": "按 E 拾取熟食入筐气泡音",
    },
    {
        "name": "Warning",
        "query": "error double beep warning low",
        "description": "背包超重/装不下双音节警告",
    },
    {
        "name": "Delivery",
        "query": "conveyor swoosh deposit whoosh",
        "description": "黄色交货区自动卸货入库",
    },
    {
        "name": "PackageDone",
        "query": "kitchen bell order ding box",
        "description": "餐厅服务员打包封装完成",
    },
    {
        "name": "Coin",
        "query": "retro game coin pickup 8-bit",
        "description": "顾客买走熟食金币入账结算",
    },
    {
        "name": "EggSpawn",
        "query": "cartoon squish pop egg plop",
        "description": "产蛋窝弹出新蛋",
    },
    {
        "name": "EggLand",
        "query": "soft egg shell ground hit",
        "description": "蛋落地开始倒计时",
    },
    {
        "name": "EggSpeedup",
        "query": "fast clock tick energy charge",
        "description": "靠近蛋按 F 加速孵化时钟音",
    },
    {
        "name": "EggHatch",
        "query": "egg crack cute chick chirp",
        "description": "蛋破壳小鸡出窝",
    },
    {
        "name": "AnimalScared",
        "query": "chicken squawk cartoon panic",
        "description": "走近动物受惊吓跑叫声",
    },
    {
        "name": "Upgrade",
        "query": "ascending arpeggio level up fanfare",
        "description": "强化/升级/解锁大三和弦上行琶音",
    },
    {
        "name": "UIClick",
        "query": "button click modern subtle tap",
        "description": "现代 UI 按钮点击轻音",
    },
    {
        "name": "UIOpen",
        "query": "whoosh menu open slide",
        "description": "打开功能弹窗平滑呼啸",
    },
    {
        "name": "UIClose",
        "query": "whoosh menu close slide",
        "description": "关闭功能弹窗平滑呼啸",
    },
    {
        "name": "BGM",
        "query": "cheerful casual farm game loop",
        "description": "农场经营轻松欢快背景音乐循环",
    },
]

def search_sfxmint(query: str, limit: int = 5):
    """通过 SFXMint REST API 搜索符合条件的 CC0 音效"""
    encoded = urllib.parse.quote(query)
    url = f"https://sfxmint.com/api/v1/search?q={encoded}&limit={limit}"
    req = urllib.request.Request(url, headers={"User-Agent": "ChickenFarm-SFXFetcher/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read().decode("utf-8")
            return json.loads(data)
    except Exception as e:
        print(f"  [ERROR] 搜索 '{query}' 失败: {e}", file=sys.stderr)
        return []

def download_audio(url: str, save_path: Path):
    """从指定 URL 下载音频数据"""
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = resp.read()
        save_path.write_bytes(data)
    return len(data)

def main():
    print("=" * 60)
    print("正在通过 SFXMint 检索并下载烤鸡农场所需音效...")
    print(f"目标目录: {OUTPUT_DIR}")
    print("=" * 60)

    results = []

    for idx, spec in enumerate(SOUND_SPECS, start=1):
        name = spec["name"]
        query = spec["query"]
        desc = spec["description"]
        dest_file = OUTPUT_DIR / f"{name}.mp3"

        print(f"[{idx}/{len(SOUND_SPECS)}] 检索: {name} (查询: '{query}')")
        items = search_sfxmint(query, limit=5)
        if not items:
            # 回退泛化关键词
            fallback_q = query.split()[-1]
            print(f"  未命中，尝试回退关键词: '{fallback_q}'")
            items = search_sfxmint(fallback_q, limit=5)

        if not items:
            print(f"  [FAIL] 未找到匹配音效: {name}")
            continue

        # 选取首个有效项
        best = items[0]
        # 优先使用 mp3_url，次选 wav_url
        download_url = best.get("mp3_url") or best.get("wav_url")
        if not download_url:
            print(f"  [FAIL] 项缺少下载 URL: {best.get('slug')}")
            continue

        try:
            bytes_count = download_audio(download_url, dest_file)
            print(f"  -> 已成功下载: {dest_file.name} ({bytes_count} 字节) - 标题: {best.get('title')}")
            results.append({
                "name": name,
                "file": str(dest_file.resolve()),
                "sourceTitle": best.get("title"),
                "slug": best.get("slug"),
                "license": best.get("license", "CC0"),
                "durationMs": best.get("duration_ms"),
                "downloadUrl": download_url,
                "description": desc
            })
        except Exception as e:
            print(f"  [ERROR] 下载 {download_url} 失败: {e}", file=sys.stderr)

        time.sleep(0.3)

    summary_file = OUTPUT_DIR / "sfxmint_download_summary.json"
    summary_file.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print("=" * 60)
    print(f"下载完成！共成功下载 {len(results)}/{len(SOUND_SPECS)} 款音效。")
    print(f"汇总记录已写入: {summary_file}")
    print("=" * 60)

if __name__ == "__main__":
    main()
