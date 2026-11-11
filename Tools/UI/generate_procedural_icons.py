#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
High quality procedural cartoon minimalist 2D icon generator.
Generates supersampled (1024x1024 -> 512x512) transparent PNG icons for:
- ui_icon_shop.png (Shopping cart with thick outline and cartoon shading)
- ui_icon_index.png (Open encyclopedia book with golden ribbon and page layers)
- ui_icon_egg.png (Glossy speckled egg with highlight and shadow)
- ui_icon_equipment.png (Cartoon chicken paw / claw pad with glossy highlight)
"""

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUTPUT_DIR = Path(r"C:\Users\herong\Desktop\work\Chicken\Assets\Studio\UI_Icons")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

def create_egg_icon(path: Path):
    """Render glossy cartoon egg with thick outline and highlights."""
    W, H = 1024, 1024
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    # Egg shape using bezier / oval layers
    # Outer dark outline (thick stroke)
    outline_box = [230, 160, 794, 880]
    # Draw shadow first
    shadow_box = [260, 780, 764, 910]
    draw.ellipse(shadow_box, fill=(0, 0, 0, 60))

    # Base egg outline
    draw.ellipse(outline_box, fill=(40, 25, 20, 255))

    # Egg body (warm cream/golden gradient)
    body_box = [255, 185, 769, 855]
    draw.ellipse(body_box, fill=(255, 248, 225, 255))

    # Inner warm tone
    inner_box = [270, 210, 754, 840]
    draw.ellipse(inner_box, fill=(255, 235, 180, 255))

    # Cartoon spots (golden orange)
    spots = [
        ([380, 360, 470, 460], (245, 185, 90, 230)),
        ([560, 480, 680, 610], (245, 185, 90, 220)),
        ([340, 600, 430, 700], (245, 185, 90, 200)),
        ([520, 280, 590, 350], (245, 185, 90, 210)),
        ([460, 680, 560, 770], (245, 185, 90, 190)),
    ]
    for s_box, col in spots:
        draw.ellipse(s_box, fill=col)

    # Specular glossy highlights (curved white gloss)
    draw.ellipse([340, 240, 460, 400], fill=(255, 255, 255, 240))
    draw.ellipse([370, 260, 440, 350], fill=(255, 255, 255, 255))
    draw.ellipse([320, 420, 360, 480], fill=(255, 255, 255, 200))

    # Downsample to 512x512
    res = im.resize((512, 512), Image.Resampling.LANCZOS)
    res.save(path)
    print("Generated:", path)

def create_shop_icon(path: Path):
    """Render crisp cartoon shopping cart icon with thick outline."""
    W, H = 1024, 1024
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    # Thick outline color
    outline_col = (30, 40, 30, 255)
    cart_col = (255, 255, 255, 255)
    accent_col = (76, 217, 100, 255) # Green
    accent_light = (130, 235, 150, 255)

    # Wheels (shadow and outer)
    wheels = [(380, 780), (680, 780)]
    for wx, wy in wheels:
        draw.ellipse([wx - 80, wy - 80, wx + 80, wy + 80], fill=outline_col)
        draw.ellipse([wx - 60, wy - 60, wx + 60, wy + 60], fill=(120, 130, 140, 255))
        draw.ellipse([wx - 35, wy - 35, wx + 35, wy + 35], fill=(240, 245, 250, 255))
        draw.ellipse([wx - 15, wy - 15, wx + 15, wy + 15], fill=outline_col)

    # Cart chassis bar
    draw.rounded_rectangle([320, 710, 740, 760], radius=25, fill=outline_col)
    draw.rounded_rectangle([335, 720, 725, 750], radius=15, fill=(180, 190, 200, 255))

    # Basket polygon
    # Points: handle top (180, 260) -> basket back top (300, 360) -> front top (820, 360) -> front bottom (740, 680) -> back bottom (380, 680)
    # Basket outline
    pts_outline = [(280, 340), (840, 340), (750, 700), (360, 700)]
    draw.polygon(pts_outline, fill=outline_col)

    # Basket inner body (accent green)
    pts_body = [(305, 365), (815, 365), (730, 675), (385, 675)]
    draw.polygon(pts_body, fill=accent_col)

    # Basket grid lines (thick cartoon white bars)
    for y in [440, 520, 600]:
        y_left = 305 + (385 - 305) * ((y - 365) / (675 - 365))
        y_right = 815 - (815 - 730) * ((y - 365) / (675 - 365))
        draw.line([(y_left + 15, y), (y_right - 15, y)], fill=(255, 255, 255, 240), width=24)

    for x_top, x_bot in [(440, 480), (560, 580), (680, 670)]:
        draw.line([(x_top, 375), (x_bot, 665)], fill=(255, 255, 255, 240), width=24)

    # Cart handle
    draw.line([(180, 260), (320, 380)], fill=outline_col, width=54)
    draw.line([(180, 260), (320, 380)], fill=(255, 255, 255, 255), width=30)
    draw.ellipse([150, 230, 210, 290], fill=outline_col)
    draw.ellipse([160, 240, 200, 280], fill=accent_light)

    # Gloss highlight on top edge
    draw.line([(310, 365), (810, 365)], fill=(255, 255, 255, 255), width=20)

    res = im.resize((512, 512), Image.Resampling.LANCZOS)
    res.save(path)
    print("Generated:", path)

def create_index_icon(path: Path):
    """Render cartoon open encyclopedia book with ribbon bookmark."""
    W, H = 1024, 1024
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    outline_col = (25, 35, 55, 255)
    cover_col = (0, 160, 235, 255) # Sky blue
    cover_dark = (0, 110, 185, 255)
    page_col = (255, 255, 250, 255)
    page_shade = (235, 240, 245, 255)
    ribbon_col = (255, 75, 75, 255) # Red bookmark

    # Book cover base (open wings)
    # Left cover
    draw.polygon([(140, 340), (490, 380), (490, 780), (140, 730)], fill=outline_col)
    draw.polygon([(160, 360), (480, 395), (480, 760), (160, 715)], fill=cover_dark)

    # Right cover
    draw.polygon([(534, 380), (884, 340), (884, 730), (534, 780)], fill=outline_col)
    draw.polygon([(544, 395), (864, 360), (864, 715), (544, 760)], fill=cover_col)

    # Spine base
    draw.polygon([(480, 370), (544, 370), (544, 790), (480, 790)], fill=outline_col)

    # Left pages (thick stack)
    draw.polygon([(180, 320), (500, 350), (500, 720), (180, 680)], fill=outline_col)
    draw.polygon([(200, 335), (490, 360), (490, 700), (200, 665)], fill=page_col)

    # Left page lines
    for ly in [420, 480, 540, 600]:
        draw.line([(240, ly), (450, ly + 20)], fill=(180, 200, 220, 255), width=16)

    # Right pages (thick stack)
    draw.polygon([(524, 350), (844, 320), (844, 680), (524, 720)], fill=outline_col)
    draw.polygon([(534, 360), (824, 335), (824, 665), (534, 700)], fill=page_col)

    # Right page chicken icon emblem (cute little golden silhouette)
    draw.ellipse([630, 420, 730, 520], fill=(255, 215, 0, 255))
    draw.polygon([(720, 460), (760, 475), (720, 490)], fill=(255, 140, 0, 255)) # Beak
    draw.line([(580, 570), (780, 550)], fill=(180, 200, 220, 255), width=16)
    draw.line([(580, 620), (740, 600)], fill=(180, 200, 220, 255), width=16)

    # Bookmark ribbon hanging down
    draw.polygon([(490, 320), (534, 320), (534, 820), (512, 780), (490, 820)], fill=outline_col)
    draw.polygon([(498, 330), (526, 330), (526, 805), (512, 775), (498, 805)], fill=ribbon_col)

    res = im.resize((512, 512), Image.Resampling.LANCZOS)
    res.save(path)
    print("Generated:", path)

def create_equipment_icon(path: Path):
    """Render cartoon chicken claw / paw print with glossy golden glow."""
    W, H = 1024, 1024
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)

    outline_col = (45, 30, 10, 255)
    main_col = (255, 185, 20, 255) # Golden orange
    light_col = (255, 230, 100, 255) # Specular warm yellow

    # Central pad
    pad_box = [340, 460, 684, 820]
    draw.ellipse([pad_box[0]-25, pad_box[1]-25, pad_box[2]+25, pad_box[3]+25], fill=outline_col)
    draw.ellipse(pad_box, fill=main_col)
    draw.ellipse([pad_box[0]+30, pad_box[1]+25, pad_box[2]-30, pad_box[3]-60], fill=light_col)

    # 3 Toes
    toes = [
        ([220, 240, 390, 450], -25), # Left toe
        ([437, 180, 587, 410], 0),   # Center toe
        ([634, 240, 804, 450], 25)   # Right toe
    ]
    for (t_box, ang) in toes:
        draw.ellipse([t_box[0]-22, t_box[1]-22, t_box[2]+22, t_box[3]+22], fill=outline_col)
        draw.ellipse(t_box, fill=main_col)
        draw.ellipse([t_box[0]+25, t_box[1]+20, t_box[2]-25, t_box[3]-50], fill=light_col)

    # Specular white gloss highlights
    draw.ellipse([470, 220, 520, 300], fill=(255, 255, 255, 230))
    draw.ellipse([270, 280, 320, 350], fill=(255, 255, 255, 220))
    draw.ellipse([700, 280, 750, 350], fill=(255, 255, 255, 220))
    draw.ellipse([420, 520, 480, 620], fill=(255, 255, 255, 230))

    res = im.resize((512, 512), Image.Resampling.LANCZOS)
    res.save(path)
    print("Generated:", path)

if __name__ == "__main__":
    create_egg_icon(OUTPUT_DIR / "ui_icon_egg.png")
    create_shop_icon(OUTPUT_DIR / "ui_icon_shop.png")
    create_index_icon(OUTPUT_DIR / "ui_icon_index.png")
    create_equipment_icon(OUTPUT_DIR / "ui_icon_equipment.png")
