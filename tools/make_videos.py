#!/usr/bin/env python3
"""Cut the recorded simulator tour into Billow's promo videos.

Outputs (in --out):
  billow-app-preview-886x1920.mp4   App Store app preview (15-30 s, H.264 High@4.0, 30 fps, AAC stereo)
  billow-social-1080x1920.mp4       Reels/TikTok/Shorts cut with intro/outro cards and big captions
  billow-cover-1080x1920.png        Cover image for social posts
  contact-*.png                     Frame grids for reviewing the cut without a video player

Captions are timed from "TOURMARK <name> <unix time>" lines printed by BillowUITests.
Requires ffmpeg/ffprobe on PATH and Pillow.
"""
import argparse
import glob
import os
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# Kept short so the App Store pill stays on one line and clear of the app's buttons.
STEPS = [
    ("overview", "Your month at a glance"),
    ("scrub", "Slide across any day"),
    ("scroll", "Spending by category and card"),
    ("activity", "Search every charge"),
    ("recategorize", "Fix a category once, Billow learns"),
    ("connect", "Bring your own free Plaid account"),
    ("finale", "Every card. Every charge."),
]
BLUE_TOP, BLUE_BOTTOM = (57, 135, 229), (16, 66, 129)
INK = (11, 11, 11)
FPS = 30
STORE_W, STORE_H = 886, 1920
SOCIAL_W, SOCIAL_H = 1080, 1920
MAX_PREVIEW = 29.0          # App Store limit is 30 s; keep a margin
MIN_PREVIEW = 15.5          # ...and 15 s minimum


# ---------- helpers ----------

def run(cmd):
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def probe_size(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height", "-of", "csv=p=0", path],
                         check=True, capture_output=True, text=True).stdout.strip()
    w, h = out.split(",")[:2]
    return int(w), int(h)


def find_font(font_dir, names):
    for name in names:
        hits = glob.glob(os.path.join(font_dir or "", "**", name), recursive=True) if font_dir else []
        if hits:
            return hits[0]
    for path in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                 "/System/Library/Fonts/Supplemental/Arial.ttf",
                 "C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"]:
        if os.path.exists(path):
            return path
    raise SystemExit("no usable font found")


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(round(BLUE_TOP[i] + (BLUE_BOTTOM[i] - BLUE_TOP[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=255)
    return m


def wrap(draw, text, font, max_w):
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= max_w or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def text_block(draw, lines, font, cx, top, fill, spacing=1.18):
    size = font.size
    for i, line in enumerate(lines):
        w = draw.textlength(line, font=font)
        draw.text((cx - w / 2, top + i * size * spacing), line, font=font, fill=fill)


def rounded_icon(icon_path, size):
    icon = Image.open(icon_path).convert("RGBA").resize((size, size), Image.LANCZOS)
    icon.putalpha(rounded_mask(size, size, round(size * 0.225)))
    return icon


def paste_with_shadow(canvas, img, x, y, blur=24, alpha=90, dy=14):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    silhouette = Image.new("RGBA", img.size, (0, 0, 0, alpha))
    shadow.paste(silhouette, (x, y + dy), img.split()[-1])
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(img, (x, y))


# ---------- artwork ----------

def store_caption(text, fonts, path):
    canvas = Image.new("RGBA", (STORE_W, STORE_H), (0, 0, 0, 0))
    font = ImageFont.truetype(fonts["semibold"], 34)
    d = ImageDraw.Draw(canvas)
    lines = wrap(d, text, font, 600)   # pill <= ~680 px: clears the top-right toolbar button
    tw = max(d.textlength(l, font=font) for l in lines)
    pad_x, pad_y, line_h = 40, 22, round(34 * 1.25)
    pill_w, pill_h = round(tw + 2 * pad_x), pad_y * 2 + line_h * len(lines) - 6
    x, y = (STORE_W - pill_w) // 2, 112
    pill = Image.new("RGBA", (pill_w, pill_h), (0, 0, 0, 0))
    ImageDraw.Draw(pill).rounded_rectangle((0, 0, pill_w - 1, pill_h - 1), radius=min(pill_h // 2, 44),
                                           fill=(255, 255, 255, 246))
    paste_with_shadow(canvas, pill, x, y, blur=14, alpha=70, dy=6)
    text_block(ImageDraw.Draw(canvas), lines, font, STORE_W / 2, y + pad_y - 4, INK, spacing=1.25)
    canvas.save(path)


def social_caption(text, fonts, path):
    canvas = Image.new("RGBA", (SOCIAL_W, SOCIAL_H), (0, 0, 0, 0))
    font = ImageFont.truetype(fonts["bold"], 64)
    d = ImageDraw.Draw(canvas)
    lines = wrap(d, text, font, 940)
    block_h = 64 * 1.18 * len(lines)
    top = 215 - block_h / 2
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    text_block(ImageDraw.Draw(glow), lines, font, SOCIAL_W / 2, top + 4, (6, 28, 64, 150))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(8)))
    text_block(ImageDraw.Draw(canvas), lines, font, SOCIAL_W / 2, top, (255, 255, 255, 255))
    canvas.save(path)


def title_card(fonts, icon_path, path, outro=False):
    canvas = gradient(SOCIAL_W, SOCIAL_H).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    icon_size = 250 if outro else 300
    icon = rounded_icon(icon_path, icon_size)
    top = 520 if outro else 600
    paste_with_shadow(canvas, icon, (SOCIAL_W - icon_size) // 2, top, blur=30, alpha=110, dy=18)
    title = ImageFont.truetype(fonts["bold"], 128)
    tag = ImageFont.truetype(fonts["medium"], 54)
    y = top + icon_size + 70
    text_block(d, ["Billow"], title, SOCIAL_W / 2, y, (255, 255, 255, 255))
    y += 175
    taglines = ["Every card. Every charge.", "Automatically."] if outro else ["Every card. Every charge."]
    text_block(d, taglines, tag, SOCIAL_W / 2, y, (255, 255, 255, 235))
    if outro:
        pill_font = ImageFont.truetype(fonts["semibold"], 46)
        label = "Free on the App Store"
        w = d.textlength(label, font=pill_font) + 96
        x0, y0 = (SOCIAL_W - w) / 2, y + 2 * 54 * 1.18 + 90
        d.rounded_rectangle((x0, y0, x0 + w, y0 + 108), radius=54, fill=(255, 255, 255, 255))
        d.text((x0 + 48, y0 + 26), label, font=pill_font, fill=(28, 92, 171, 255))
    canvas.convert("RGB").save(path)


# ---------- main ----------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--start", required=True, help="file holding the unix time recording began")
    ap.add_argument("--marks", required=True, help="file with TOURMARK lines")
    ap.add_argument("--icon", required=True)
    ap.add_argument("--font-dir")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    work = os.path.join(a.out, "work")
    os.makedirs(work, exist_ok=True)

    fonts = {
        "bold": find_font(a.font_dir, ["Inter-Bold.ttf"]),
        "semibold": find_font(a.font_dir, ["Inter-SemiBold.ttf", "Inter-Bold.ttf"]),
        "medium": find_font(a.font_dir, ["Inter-Medium.ttf", "Inter-Regular.ttf"]),
    }
    print("fonts:", fonts)

    rec_start = float(open(a.start).read().strip())
    marks = {}
    for line in open(a.marks):
        parts = line.split()
        if "TOURMARK" in parts:
            i = parts.index("TOURMARK")
            if i + 2 < len(parts):
                marks.setdefault(parts[i + 1], float(parts[i + 2]))
    print("marks:", {k: round(v - rec_start, 2) for k, v in marks.items()})
    steps = [(n, c) for n, c in STEPS if n in marks]
    if not steps:
        raise SystemExit("no TOURMARK lines found")
    end = marks.get("end", max(marks.values()) + 2.5)

    t0 = max(0.0, marks[steps[0][0]] - rec_start - 0.15)
    raw_d = end - rec_start - t0
    speed = max(1.0, raw_d / MAX_PREVIEW)
    body = raw_d / speed
    hold = max(0.0, MIN_PREVIEW - body)
    total = body + hold
    windows = []
    for i, (name, caption) in enumerate(steps):
        start = (marks[name] - rec_start - t0) / speed
        stop = (marks[steps[i + 1][0]] - rec_start - t0) / speed if i + 1 < len(steps) else total
        windows.append((max(0.0, start), min(total, stop), caption))
    print(f"raw {raw_d:.1f}s -> {total:.1f}s (speed x{speed:.2f}, hold {hold:.1f}s)")

    raw_w, raw_h = probe_size(a.raw)
    trim = ["-ss", f"{t0:.3f}", "-t", f"{raw_d:.3f}", "-i", a.raw]
    tail = f",tpad=stop_mode=clone:stop_duration={hold:.3f}" if hold > 0 else ""
    silent = ["-f", "lavfi", "-t", f"{total:.3f}", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]

    def caption_chain(first_input, base_label, overlay_xy="0:0"):
        graph, label = "", base_label
        for i, (s, e, _) in enumerate(windows):
            k = first_input + i
            fade_out = max(s + 0.3, e - 0.3)
            graph += (f";[{k}:v]format=rgba,fps={FPS},fade=t=in:st={s:.3f}:d=0.3:alpha=1,"
                      f"fade=t=out:st={fade_out:.3f}:d=0.3:alpha=1[c{i}]"
                      f";[{label}][c{i}]overlay={overlay_xy}:format=auto[o{i}]")
            label = f"o{i}"
        return graph, label

    # --- App Store preview: full-bleed footage + caption pills ---
    store_caps = []
    for i, (_, _, text) in enumerate(windows):
        p = os.path.join(work, f"store-cap-{i}.png")
        store_caption(text, fonts, p)
        store_caps.append(p)
    inputs = trim + silent
    for p in store_caps:
        inputs += ["-loop", "1", "-t", f"{total:.3f}", "-i", p]
    scale_h = round(STORE_W * raw_h / raw_w / 2) * 2
    graph = (f"[0:v]setpts=(PTS-STARTPTS)/{speed:.5f},fps={FPS},"
             f"scale={STORE_W}:{scale_h}:flags=lanczos,crop={STORE_W}:{STORE_H}{tail},format=rgba[base]")
    caps, last = caption_chain(2, "base")
    graph += caps + f";[{last}]format=yuv420p,setsar=1[vout]"
    store_out = os.path.join(a.out, "billow-app-preview-886x1920.mp4")
    run(["ffmpeg", "-y", *inputs, "-filter_complex", graph, "-map", "[vout]", "-map", "1:a",
         "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-preset", "slow",
         "-b:v", "11M", "-maxrate", "12M", "-bufsize", "22M", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "256k", "-ar", "44100", "-ac", "2",
         "-t", f"{total:.3f}", "-movflags", "+faststart", store_out])

    # --- Social cut: branded background, rounded footage, big captions, intro/outro ---
    bg = os.path.join(work, "bg.png")
    gradient(SOCIAL_W, SOCIAL_H).save(bg)
    app_h = 1440
    app_w = round(app_h * raw_w / raw_h / 2) * 2
    app_x, app_y = (SOCIAL_W - app_w) // 2, 372
    mask = os.path.join(work, "mask.png")
    rounded_mask(app_w, app_h, 58).save(mask)
    shadow = Image.new("RGBA", (SOCIAL_W, SOCIAL_H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((app_x, app_y + 18, app_x + app_w, app_y + app_h + 18),
                                             radius=58, fill=(4, 20, 48, 120))
    shadow_path = os.path.join(work, "shadow.png")
    shadow.filter(ImageFilter.GaussianBlur(30)).save(shadow_path)
    social_caps = []
    for i, (_, _, text) in enumerate(windows):
        p = os.path.join(work, f"social-cap-{i}.png")
        social_caption(text, fonts, p)
        social_caps.append(p)

    inputs = trim[:]
    for p in [bg, mask, shadow_path, *social_caps]:
        inputs += ["-loop", "1", "-t", f"{total:.3f}", "-i", p]
    graph = (f"[0:v]setpts=(PTS-STARTPTS)/{speed:.5f},fps={FPS},scale={app_w}:{app_h}:flags=lanczos{tail},format=rgba[app0]"
             f";[2:v]fps={FPS},format=gray[m];[app0][m]alphamerge[app]"
             f";[1:v]fps={FPS},format=rgba[bg];[3:v]fps={FPS},format=rgba[sh]"
             f";[bg][sh]overlay=0:0[b1];[b1][app]overlay={app_x}:{app_y}:shortest=1[base]")
    caps, last = caption_chain(4, "base")
    graph += caps + f";[{last}]format=yuv420p,settb=AVTB,setsar=1[vout]"
    main_mp4 = os.path.join(work, "social-main.mp4")
    run(["ffmpeg", "-y", *inputs, "-filter_complex", graph, "-map", "[vout]", "-c:v", "libx264",
         "-preset", "slow", "-crf", "16", "-r", str(FPS), "-t", f"{total:.3f}", main_mp4])

    intro_png, outro_png = os.path.join(work, "intro.png"), os.path.join(a.out, "billow-cover-1080x1920.png")
    title_card(fonts, a.icon, intro_png)
    title_card(fonts, a.icon, outro_png, outro=True)
    intro_d, outro_d, xf = 1.8, 2.8, 0.5
    clips = []
    for png, dur, name in [(intro_png, intro_d, "intro"), (outro_png, outro_d, "outro")]:
        clip = os.path.join(work, f"{name}.mp4")
        run(["ffmpeg", "-y", "-loop", "1", "-t", f"{dur}", "-i", png, "-vf",
             f"fps={FPS},format=yuv420p,settb=AVTB,setsar=1", "-c:v", "libx264", "-preset", "slow",
             "-crf", "16", clip])
        clips.append(clip)
    social_total = intro_d + total + outro_d - 2 * xf
    off1 = intro_d - xf
    off2 = (intro_d + total - xf) - xf
    social_out = os.path.join(a.out, "billow-social-1080x1920.mp4")
    run(["ffmpeg", "-y", "-i", clips[0], "-i", main_mp4, "-i", clips[1],
         "-f", "lavfi", "-t", f"{social_total:.3f}", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
         "-filter_complex",
         f"[0:v]settb=AVTB[i0];[1:v]settb=AVTB[i1];[2:v]settb=AVTB[i2];"
         f"[i0][i1]xfade=transition=fade:duration={xf}:offset={off1:.3f}[x1];"
         f"[x1][i2]xfade=transition=fade:duration={xf}:offset={off2:.3f},format=yuv420p[vout]",
         "-map", "[vout]", "-map", "3:a", "-c:v", "libx264", "-preset", "slow", "-crf", "18",
         "-r", str(FPS), "-c:a", "aac", "-b:a", "192k", "-t", f"{social_total:.3f}",
         "-movflags", "+faststart", social_out])

    # --- Frame grids for review ---
    for src, name, width, grid in [(store_out, "contact-app-preview.png", 221, "6x2"),
                                   (social_out, "contact-social.png", 216, "6x3")]:
        run(["ffmpeg", "-y", "-i", src, "-vf",
             f"fps=1/2.4,scale={width}:-2,tile={grid}:padding=8:margin=8:color=white",
             "-frames:v", "1", os.path.join(a.out, name)])
    print(f"done: preview {total:.1f}s, social {social_total:.1f}s")


if __name__ == "__main__":
    main()
