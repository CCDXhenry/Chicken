"""Project measured screen rectangles and generate an exact static rectangle union.

Run from the repository root: python Tools/UI/build_screen_layout_guide.py
Only developer artifacts are written; this module is never shipped to the client.
"""
import json
import math
import argparse
from pathlib import Path

CANVAS = (1920, 1080)
DIRECTORY = Path(__file__).resolve().parent


def clip(rect, width=1920, height=1080):
    x1, y1, x2, y2 = rect
    value = [max(0, x1), max(0, y1), min(width, x2), min(height, y2)]
    return value if value[0] < value[2] and value[1] < value[3] else None


def project(rect, origin, scale):
    if scale <= 0:
        raise ValueError("Scale must be positive")
    return [(value - origin[index % 2]) / scale for index, value in enumerate(rect)]


def rectangle_union(rectangles):
    """Sweep horizontal slabs; merge only equal adjacent covered intervals.

    The output is non-overlapping and preserves disconnected areas and holes.
    """
    ys = sorted({rect[index] for rect in rectangles for index in (1, 3)})
    result, previous = [], {}
    for y1, y2 in zip(ys, ys[1:]):
        intervals = sorted((r[0], r[2]) for r in rectangles if r[1] < y2 and r[3] > y1)
        merged = []
        for x1, x2 in intervals:
            if merged and x1 <= merged[-1][1]:
                merged[-1][1] = max(merged[-1][1], x2)
            else:
                merged.append([x1, x2])
        current = {}
        for x1, x2 in merged:
            key = (x1, x2)
            index = previous.get(key)
            if index is not None and result[index][3] == y1:
                result[index][3] = y2
            else:
                index = len(result)
                result.append([x1, y1, x2, y2])
            current[key] = index
        previous = current
    return result


def area(rect):
    return (rect[2] - rect[0]) * (rect[3] - rect[1])


def coverage(rect, union):
    return sum(max(0, min(rect[2], other[2]) - max(rect[0], other[0])) *
               max(0, min(rect[3], other[3]) - max(rect[1], other[1])) for other in union)


def build(data):
    padded_rectangles = []
    included_names = data.get("includedRegionNames", ["TopLeftCore", "JumpButton"])
    for sample in data["samples"]:
        assert sample["logicalSize"] == list(CANVAS)
        assert sample["movementExcluded"]
        width, height = sample["screenSize"]
        assert abs(sample["scale"] - min(width / 1920, height / 1080)) < 1e-5
        assert abs(sample["origin"][0] - (width - 1920 * sample["scale"]) / 2) < .01
        assert abs(sample["origin"][1] - (height - 1080 * sample["scale"]) / 2) < .01
        assert sample["modal"]["size"] == sample["screenSize"]
        for region in sample["reserved"]:
            assert "Movement" not in region["name"]
            rect = project(region["screenRect"], sample["origin"], sample["scale"])
            region["designRect"] = rect
            clipped = clip(rect)
            region["clippedDesignRect"] = clipped
            region["includedInGuide"] = region["name"] in included_names
            padded = None
            if clipped and region["includedInGuide"]:
                padding = data["padding"]
                # Outward rounding creates conservative whole-design-pixel Frames.
                padded = clip([math.floor(clipped[0] - padding), math.floor(clipped[1] - padding),
                               math.ceil(clipped[2] + padding), math.ceil(clipped[3] + padding)])
                padded_rectangles.append(padded)
            region["paddedDesignRect"] = padded
    union = rectangle_union(padded_rectangles)
    for rect in padded_rectangles:
        assert coverage(rect, union) == area(rect), ("Uncovered measured region", rect)
    result = {"version": 1, "canvas": list(CANVAS), "padding": data["padding"],
              "includedRegionNames": included_names,
              "sampleCount": len(data["samples"]), "rectangles": union,
              "coverageChecks": len(padded_rectangles), "coveredArea": sum(map(area, union))}
    return result


def preview(result):
    # Design artifact; these SVG rectangles are the exact measured union.
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">',
             '<rect width="1920" height="1080" fill="#152633"/>',
             '<path d="M960 0V1080 M0 540H1920" stroke="#466171" stroke-dasharray="8 8"/>']
    for index, (x1, y1, x2, y2) in enumerate(result["rectangles"], 1):
        parts.append(f'<rect x="{x1}" y="{y1}" width="{x2-x1}" height="{y2-y1}" fill="#f04444" fill-opacity=".6" stroke="#ff9b9b"/>')
        parts.append(f'<text x="{x1+8}" y="{y1+22}" fill="white" font-family="sans-serif" font-size="16">{index}</text>')
    parts.append('<text x="960" y="480" fill="#e6f4fc" text-anchor="middle" font-family="sans-serif" font-size="34">1920 x 1080 | SHARED SCREEN LAYOUT GUIDE</text>')
    parts.append('<text x="960" y="530" fill="#a7c3d3" text-anchor="middle" font-family="sans-serif" font-size="24">Top-left system + jump only | 24 design px padding | No bottom strip</text>')
    parts.append('</svg>')
    return '\n'.join(parts)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=DIRECTORY / "Samples/screen-layout-samples.json")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    source = args.source
    output = args.output_dir or source.parent
    output.mkdir(parents=True, exist_ok=True)
    data = json.loads(source.read_text(encoding="utf-8"))
    result = build(data)
    (output / "screen-layout-samples.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "screen-layout-union.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    (output / "screen-layout-guide.svg").write_text(preview(result), encoding="utf-8")
    print(json.dumps(result))
