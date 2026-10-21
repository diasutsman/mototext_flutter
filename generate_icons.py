import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

MINT = (117, 240, 160, 255)       # #75F0A0
BG = (13, 18, 23, 255)            # #0D1217
PANEL = (23, 31, 39, 255)         # #171F27
EDGE = (52, 65, 78, 255)          # #34414E
WHITE = (245, 247, 250, 255)
GLOW_MINT = (117, 240, 160, 55)

SCALE = 4
SIZE = 1024 * SCALE  # 4096

# Icons.bluetooth_audio_rounded in Flutter MaterialIcons
# Defined in packages/flutter/lib/src/material/icons.dart as:
# IconData(0xf5c0, fontFamily: 'MaterialIcons')
ICON_CODEPOINT = chr(0xf5c0)

def find_material_icons_font():
    known_paths = [
        Path(r"E:\fvm\default\bin\cache\artifacts\material_fonts\materialicons-regular.otf"),
        Path(r"E:\fvm\default\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf"),
        Path(r"E:\fvm\default\engine\src\flutter\tools\font_subset\fixtures\MaterialIcons-Regular.ttf"),
    ]
    for p in known_paths:
        if p.exists():
            return str(p)
            
    # Try locating via flutter command
    try:
        res = subprocess.run(["where", "flutter"], capture_output=True, text=True, check=True)
        flutter_bin = Path(res.stdout.splitlines()[0]).parent
        sdk_font = flutter_bin / "cache" / "artifacts" / "material_fonts" / "materialicons-regular.otf"
        if sdk_font.exists():
            return str(sdk_font)
    except Exception:
        pass
        
    return str(known_paths[0])

FONT_PATH = find_material_icons_font()
print(f"Menggunakan font resmi Flutter MaterialIcons dari: {FONT_PATH}")

def draw_flutter_icon(draw, cx, cy, font_size, color):
    font = ImageFont.truetype(FONT_PATH, font_size)
    bbox = draw.textbbox((0, 0), ICON_CODEPOINT, font=font)
    # Center exact glyph
    gw = bbox[2] - bbox[0]
    gh = bbox[3] - bbox[1]
    gx = cx - (bbox[0] + bbox[2]) / 2.0
    gy = cy - (bbox[1] + bbox[3]) / 2.0
    draw.text((gx, gy), ICON_CODEPOINT, font=font, fill=color)

def generate_app_icon():
    img = Image.new('RGBA', (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(img)
    
    # 1. Panel container
    panel_margin = int(130 * SCALE)
    panel_radius = int(240 * SCALE)
    panel_bbox = [panel_margin, panel_margin, SIZE - panel_margin, SIZE - panel_margin]
    
    # Subtle ambient glow
    glow_img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_draw.rounded_rectangle(panel_bbox, radius=panel_radius, fill=GLOW_MINT)
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(radius=35 * SCALE))
    img.alpha_composite(glow_img)
    
    # Panel box
    draw.rounded_rectangle(panel_bbox, radius=panel_radius, fill=PANEL, outline=EDGE, width=int(8 * SCALE))
    
    # Inner border line
    inner_m = panel_margin + int(24 * SCALE)
    draw.rounded_rectangle(
        [inner_m, inner_m, SIZE - inner_m, SIZE - inner_m],
        radius=panel_radius - int(20 * SCALE),
        outline=(117, 240, 160, 32),
        width=int(3 * SCALE)
    )
    
    # 2. Draw official Icons.bluetooth_audio_rounded directly from Flutter SDK font
    draw_flutter_icon(draw, SIZE / 2, SIZE / 2, int(540 * SCALE), MINT)
    
    # Downsample
    final_img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
    final_img.save("assets/icon/app_icon.png", "PNG", optimize=True)
    print("✓ assets/icon/app_icon.png berhasil diexport dari Flutter MaterialIcons.")

def generate_foreground_icon():
    # Android Adaptive Icon: Safe area is center 66% circle/squircle
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Draw official Icons.bluetooth_audio_rounded centered in safe area
    draw_flutter_icon(draw, SIZE / 2, SIZE / 2, int(460 * SCALE), MINT)
    
    final_img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
    final_img.save("assets/icon/app_icon_foreground.png", "PNG", optimize=True)
    print("✓ assets/icon/app_icon_foreground.png berhasil diexport.")

def generate_splash_logo():
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    emblem_cy = SIZE * 0.43
    
    # Radial glow behind emblem
    glow_img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_draw.ellipse(
        [SIZE/2 - 260*SCALE, emblem_cy - 260*SCALE, SIZE/2 + 260*SCALE, emblem_cy + 260*SCALE],
        fill=(117, 240, 160, 40)
    )
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(radius=60 * SCALE))
    img.alpha_composite(glow_img)
    
    # Draw official Icons.bluetooth_audio_rounded
    draw_flutter_icon(draw, SIZE / 2, emblem_cy, int(380 * SCALE), MINT)
    
    # Typography: MotoText LCD
    try:
        font_large = ImageFont.truetype("arialbd.ttf", int(68 * SCALE))
        font_sub = ImageFont.truetype("arial.ttf", int(28 * SCALE))
    except Exception:
        font_large = ImageFont.load_default()
        font_sub = ImageFont.load_default()
        
    title = "MotoText"
    subtitle = "LCD BLUETOOTH CONTROLLER"
    
    text_y = int(SIZE * 0.67)
    bbox_large = draw.textbbox((0, 0), title, font=font_large)
    w_large = bbox_large[2] - bbox_large[0]
    draw.text(((SIZE - w_large) / 2, text_y), title, font=font_large, fill=WHITE)
    
    sub_y = text_y + int(85 * SCALE)
    bbox_sub = draw.textbbox((0, 0), subtitle, font=font_sub)
    w_sub = bbox_sub[2] - bbox_sub[0]
    draw.text(((SIZE - w_sub) / 2, sub_y), subtitle, font=font_sub, fill=MINT)
    
    final_img = img.resize((1024, 1024), Image.Resampling.LANCZOS)
    final_img.save("assets/icon/splash_logo.png", "PNG", optimize=True)
    print("✓ assets/icon/splash_logo.png berhasil diexport.")

if __name__ == '__main__':
    Path("assets/icon").mkdir(parents=True, exist_ok=True)
    generate_app_icon()
    generate_foreground_icon()
    generate_splash_logo()
