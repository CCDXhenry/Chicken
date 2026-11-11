#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate game-feature-aligned cartoon minimalist 2D UI icons for Chicken Farm:
1. ui_icon_tools.png: Tools / Workshop (Wrench & Hammer or Red/Orange Toolbox) -> corresponds to ToolShop
2. ui_icon_species.png: Cute Cartoon Chick Face (小黄鸡头像) -> corresponds to Species
3. ui_icon_weapon.png: Electric Zap Gun / Baton with Lightning Spark -> corresponds to Equipment
4. ui_icon_restaurant.png: Chef Hat / Roast Chicken Cloche -> optional for Restaurant
"""

import math
from pathlib import Path
from PIL import Image, ImageDraw

OUTPUT_DIR = Path(r"C:\Users\herong\Desktop\work\Chicken\Assets\Studio\UI_Icons")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

def create_species_chick_icon(path: Path):
    """Render super cute cartoon yellow chick face (SIM theme)."""
    W, H = 1024, 1024
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    outline_col = (45, 30, 15, 255)
    body_col = (255, 215, 30, 255) # Bright chick yellow
    body_shade = (245, 180, 20, 255)
    comb_col = (245, 60, 60, 255)   # Red comb
    beak_col = (255, 130, 20, 255)  # Orange beak
    blush_col = (255, 140, 140, 160)

    # 1. Chicken Comb (3 bumps on top of head)
    # Comb outline
    draw.ellipse([460, 130, 564, 280], fill=outline_col)
    draw.ellipse([380, 160, 480, 290], fill=outline_col)
    draw.ellipse([544, 160, 644, 290], fill=outline_col)
    # Comb body
    draw.ellipse([475, 145, 549, 265], fill=comb_col)
    draw.ellipse([395, 175, 465, 275], fill=comb_col)
    draw.ellipse([559, 175, 629, 275], fill=comb_col)

    # 2. Main Head / Body (big cute round shape)
    draw.ellipse([210, 230, 814, 850], fill=outline_col)
    draw.ellipse([235, 255, 789, 825], fill=body_col)
    # Bottom subtle warm shadow
    draw.ellipse([270, 540, 754, 810], fill=body_shade)
    draw.ellipse([250, 270, 774, 760], fill=body_col)

    # 3. Fluffy Cheek Tufts (wings/cheeks)
    # Left cheek tuft
    draw.ellipse([180, 510, 290, 650], fill=outline_col)
    draw.ellipse([195, 525, 275, 635], fill=body_col)
    # Right cheek tuft
    draw.ellipse([734, 510, 844, 650], fill=outline_col)
    draw.ellipse([749, 525, 829, 635], fill=body_col)

    # 4. Cute Big Anime/Cartoon Eyes
    eye_y = 480
    # Left eye
    draw.ellipse([340, eye_y, 440, eye_y + 130], fill=outline_col)
    draw.ellipse([360, eye_y + 15, 420, eye_y + 75], fill=(255, 255, 255, 255)) # Eye gloss
    draw.ellipse([390, eye_y + 70, 415, eye_y + 95], fill=(255, 255, 255, 200)) # Small gleam
    # Right eye
    draw.ellipse([584, eye_y, 684, eye_y + 130], fill=outline_col)
    draw.ellipse([604, eye_y + 15, 664, eye_y + 75], fill=(255, 255, 255, 255))
    draw.ellipse([634, eye_y + 70, 659, eye_y + 95], fill=(255, 255, 255, 200))

    # 5. Pink Blushes
    draw.ellipse([280, 570, 370, 630], fill=blush_col)
    draw.ellipse([654, 570, 744, 630], fill=blush_col)

    # 6. Cute Orange Triangle Beak
    beak_pts_out = [(430, 550), (594, 550), (512, 690)]
    draw.polygon(beak_pts_out, fill=outline_col)
    beak_pts_in = [(445, 560), (579, 560), (512, 670)]
    draw.polygon(beak_pts_in, fill=beak_col)
    # Beak upper highlight
    draw.polygon([(455, 565), (569, 565), (512, 615)], fill=(255, 175, 50, 255))

    # 7. Forehead Highlight
    draw.ellipse([350, 280, 490, 380], fill=(255, 255, 255, 180))
    draw.ellipse([370, 300, 460, 350], fill=(255, 255, 255, 240))

    res = im.resize((512, 512), Image.Resampling.LANCZOS)
    res.save(path)
    print("Generated Chick/Species icon:", path)

def create_tools_icon(path: Path):
    """Render crossed cartoon wrench & hammer (SIM theme)."""
    W, H = 1024, 1024
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    outline_col = (30, 35, 45, 255)
    metal_light = (235, 245, 255, 255)
    metal_mid = (160, 180, 205, 255)
    metal_dark = (100, 120, 145, 255)
    handle_wood = (215, 125, 45, 255)
    handle_dark = (150, 75, 25, 255)

    # 1. Hammer (tilted +45 deg)
    # Hammer handle
    h_outline = [(340, 280), (740, 780), (700, 820), (300, 320)]
    draw.polygon(h_outline, fill=outline_col)
    h_body = [(345, 290), (730, 770), (705, 795), (320, 315)]
    draw.polygon(h_body, fill=handle_wood)
    # Hammer head
    draw.rounded_rectangle([200, 200, 440, 360], radius=35, fill=outline_col)
    draw.rounded_rectangle([215, 215, 425, 345], radius=25, fill=metal_mid)
    draw.rounded_rectangle([225, 225, 415, 275], radius=15, fill=metal_light)

    # 2. Wrench (tilted -45 deg, in front)
    # Wrench shaft
    w_outline = [(684, 320), (284, 820), (244, 780), (644, 280)]
    draw.polygon(w_outline, fill=outline_col)
    w_body = [(675, 325), (290, 805), (265, 780), (650, 300)]
    draw.polygon(w_body, fill=metal_mid)
    draw.polygon([(665, 325), (450, 595), (440, 580), (655, 310)], fill=metal_light) # Highlight

    # Wrench head (top right)
    draw.ellipse([600, 190, 820, 410], fill=outline_col)
    draw.ellipse([620, 210, 800, 390], fill=metal_mid)
    # Wrench jaw cutout (rotated)
    draw.polygon([(680, 170), (830, 320), (780, 370), (630, 220)], fill=(0, 0, 0, 0)) # Punch out
    # Redraw jaw accurately
    jaw_back = [(690, 180), (840, 330), (790, 380), (640, 230)]
    draw.polygon(jaw_back, fill=(0, 0, 0, 0))

    # Wrench ring (bottom left)
    draw.ellipse([210, 710, 370, 870], fill=outline_col)
    draw.ellipse([225, 725, 355, 855], fill=metal_mid)
    draw.ellipse([260, 760, 320, 820], fill=outline_col)
    draw.ellipse([272, 772, 308, 808], fill=(0, 0, 0, 0))

    # 3. Golden Upgrade Star / Sparkle in center
    cx, cy = 512, 512
    draw.ellipse([cx - 90, cy - 90, cx + 90, cy + 90], fill=outline_col)
    draw.ellipse([cx - 75, cy - 75, cx + 75, cy + 75], fill=(255, 215, 0, 255))
    draw.ellipse([cx - 55, cy - 55, cx + 55, cy + 55], fill=(255, 245, 130, 255))
    # Gear teeth or star
    draw.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], fill=(255, 140, 0, 255))

    res = im.resize((512, 512), Image.Resampling.LANCZOS)
    res.save(path)
    print("Generated Tools/Workshop icon:", path)

def create_weapon_zap_icon(path: Path):
    """Render cartoon electric zap gun / baton with lightning sparks."""
    W, H = 1024, 1024
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    outline_col = (25, 30, 50, 255)
    metal_dark = (50, 60, 95, 255)
    metal_mid = (90, 120, 185, 255)
    metal_light = (160, 205, 255, 255)
    energy_cyan = (0, 235, 255, 255)
    spark_gold = (255, 230, 20, 255)

    # 1. Baton / Gun Body (tilted 45 deg)
    # Handle grip
    g_out = [(260, 710), (410, 860), (360, 910), (210, 760)]
    draw.polygon(g_out, fill=outline_col)
    g_in = [(270, 720), (400, 850), (365, 885), (235, 755)]
    draw.polygon(g_in, fill=(70, 45, 30, 255))
    # Grip wraps
    for offset in [40, 80, 120]:
        draw.line([(240 + offset, 740 + offset), (280 + offset, 700 + offset)], fill=(120, 80, 50, 255), width=18)

    # Main Barrel
    b_out = [(290, 680), (680, 290), (740, 350), (350, 740)]
    draw.polygon(b_out, fill=outline_col)
    b_in = [(305, 675), (670, 310), (725, 345), (360, 710)]
    draw.polygon(b_in, fill=metal_mid)
    draw.polygon([(320, 675), (665, 330), (690, 345), (345, 690)], fill=metal_light)

    # Energy Rings on barrel
    for rx, ry in [(440, 530), (540, 430)]:
        draw.ellipse([rx - 45, ry - 45, rx + 45, ry + 45], fill=outline_col)
        draw.ellipse([rx - 32, ry - 32, rx + 32, ry + 32], fill=energy_cyan)
        draw.ellipse([rx - 15, ry - 15, rx + 15, ry + 15], fill=(255, 255, 255, 255))

    # Emitter Tip
    draw.ellipse([640, 210, 790, 360], fill=outline_col)
    draw.ellipse([655, 225, 775, 345], fill=metal_dark)
    draw.ellipse([680, 250, 750, 320], fill=energy_cyan)
    draw.ellipse([695, 265, 735, 305], fill=(255, 255, 255, 255))

    # 2. Big Stylized Zigzag Lightning Bolt burst from tip!
    bolt_pts = [
        (720, 270),
        (850, 140),
        (770, 240),
        (920, 120),
        (820, 250),
        (950, 220),
        (840, 290),
        (910, 370),
        (800, 330),
        (820, 440),
        (750, 330)
    ]
    # Bolt outer outline
    draw.polygon(bolt_pts, fill=outline_col)
    # Inner bolt
    inner_bolt = [(x + 4, y + 4) for (x, y) in bolt_pts]
    draw.polygon(bolt_pts, fill=spark_gold)
    draw.polygon([(740, 260), (840, 160), (780, 230), (890, 150), (810, 250)], fill=(255, 255, 255, 255))

    # Extra electric spark particles
    sparks = [(780, 110), (950, 180), (880, 420), (690, 150)]
    for sx, sy in sparks:
        draw.ellipse([sx - 20, sy - 20, sx + 20, sy + 20], fill=outline_col)
        draw.ellipse([sx - 12, sy - 12, sx + 12, sy + 12], fill=energy_cyan)
        draw.ellipse([sx - 5, sy - 5, sx + 5, sy + 5], fill=(255, 255, 255, 255))

    res = im.resize((512, 512), Image.Resampling.LANCZOS)
    res.save(path)
    print("Generated Weapon Zap icon:", path)

if __name__ == "__main__":
    create_species_chick_icon(OUTPUT_DIR / "ui_icon_species.png")
    create_tools_icon(OUTPUT_DIR / "ui_icon_tools.png")
    create_weapon_zap_icon(OUTPUT_DIR / "ui_icon_weapon.png")
