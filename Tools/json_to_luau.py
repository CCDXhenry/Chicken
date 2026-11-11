# -*- coding: utf-8 -*-
"""
Converts JsonData/*.json files into Luau module scripts in
Scripts/ReplicatedStorage/Scripts/Shared/GameConfig/*.luau
"""
import json
import os
import glob

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
JSON_DIR = os.path.join(REPO_ROOT, "JsonData")
LUAU_DIR = os.path.join(REPO_ROOT, "Scripts", "ReplicatedStorage", "Scripts", "Shared", "GameConfig")

def format_value(val, indent_level=0):
    ind = "\t" * indent_level
    if val is None:
        return "nil"
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, (int, float)):
        return str(val)
    if isinstance(val, str):
        escaped = val.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        return f'"{escaped}"'
    if isinstance(val, list):
        if not val:
            return "{}"
        if all(isinstance(x, (int, float)) for x in val):
            return "{ " + ", ".join(str(x) for x in val) + " }"
        lines = ["{"]
        for item in val:
            lines.append(f"{ind}\t{format_value(item, indent_level + 1)},")
        lines.append(f"{ind}}}")
        return "\n".join(lines)
    if isinstance(val, dict):
        if not val:
            return "{}"
        lines = ["{"]
        for k, v in val.items():
            lines.append(f'{ind}\t["{k}"] = {format_value(v, indent_level + 1)},')
        lines.append(f"{ind}}}")
        return "\n".join(lines)
    return str(val)

def json_to_luau(json_path, luau_path):
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    
    lines = ["--!strict", "return {"]
    if isinstance(data, list):
        for idx, row in enumerate(data, start=1):
            lines.append(f"\t[{idx}] = {format_value(row, 1)},")
    elif isinstance(data, dict):
        for k, v in data.items():
            lines.append(f'\t["{k}"] = {format_value(v, 1)},')
    lines.append("}\n")
    
    content = "\n".join(lines)
    with open(luau_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(content)
    print(f"Updated: {os.path.basename(luau_path)} ({len(data)} items)")

def main():
    os.makedirs(LUAU_DIR, exist_ok=True)
    json_files = glob.glob(os.path.join(JSON_DIR, "*.json"))
    for jf in json_files:
        base_name = os.path.basename(jf)
        name_no_ext = os.path.splitext(base_name)[0]
        luau_file = os.path.join(LUAU_DIR, f"{name_no_ext}.luau")
        json_to_luau(jf, luau_file)

if __name__ == "__main__":
    main()
