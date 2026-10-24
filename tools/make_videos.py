#!/usr/bin/env python3
"""Cut the recorded simulator tour into Billow's promo videos.

Outputs (in --out):
  billow-app-preview-886x1920.mp4   App Store app preview (15-30 s, H.264 High@4.0, 30 fps, AAC stereo)
  billow-social-1080x1920.mp4       Reels/TikTok/Shorts cut with intro/outro cards
  billow-cover-1080x1920.png        Cover image for social posts
  contact-*.png                     Frame grids for reviewing the cut without a video player

The UI test stalls whenever XCTest waits for the app to go idle, so instead of
speeding the whole tour up, frozen stretches (no pixels changing) are cut down
to a short hold. Animations keep their natural speed. Captions are timed from
"TOURMARK <name> <unix time>" lines printed by BillowUITests, mapped through
the same cut. Both cuts show the footage inset on the brand gradient with the
caption above it, so captions never cover the app's own controls.

Requires ffmpeg/ffprobe on PATH and Pillow.
"""
import argparse
import glob
import os
import re
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont

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
FPS = 30
HOLD = 1.15            # longest still moment kept, seconds
HOLD_START = 3.0       # ...except the opening shot
HOLD_END = 2.6         # ...and the closing shot
MAX_PREVIEW = 29.0     # App Store limit is 30 s; keep a margin
MIN_PREVIEW = 15.5     # ...and 15 s minimum
MAX_SOCIAL = 34.0      # social cut can run closer to natural speed

# Layouts: canvas, footage height and top, caption size / centre / wrap width.
STORE = dict(W=886, H=1920, app_h=1560, app_y=288, cap_px=44, cap_cy=148, cap_wrap=780, radius=50)
SOCIAL = dict(W=1080, H=1920, app_h=1440, app_y=372, cap_px=64, cap_cy=215, cap_wrap=940, radius=58)


# ---------- helpers ----------

FFMPEG = os.environ.get("FFMPEG", "ffmpeg")


def run(cmd, capture=False):
    if cmd[0] == "ffmpeg":
        cmd = [FFMPEG, *cmd[1:]]
    print("+", " ".join(cmd), flush=True)
    result = subprocess.run(cmd, check=True, capture_output=capture, text=capture,
                            encoding="utf-8" if capture else None, errors="replace" if capture else None)
    return result.stderr if capture else None


def probe_size(path):
    info = subprocess.run([FFMPEG, "-hide_banner", "-i", path], capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stderr
    w, h = re.search(r"Video:.*?, (\d{2,5})x(\d{2,5})", info).groups()
    return int(w), int(h)


def find_font(font_dir, names):
    for name in names:
        hits = glob.glob(os.path.join(font_dir, "**", name), recursive=True) if font_dir else []
        if hits:
            return hits[0]
    for path in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                 "/System/Library/Fonts/Supplemental/Arial.ttf",
                 "C:/Windows/Fonts/segoeuib.ttf", "C:/Windows/Fonts/arialbd.ttf"]:
        if os.path.exists(path):
            return path
    raise SystemExit("no usable font found")


def even(x):
    return int(round(x / 2) * 2)


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
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= max_w or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    if len(lines) == 2:   # balance the two lines instead of leaving an orphan word
        words = text.split()
        splits = [(" ".join(words[:i]), " ".join(words[i:])) for i in range(1, len(words))]
        lines = list(min(splits, key=lambda s: max(draw.textlength(s[0], font=font),
                                                   draw.textlength(s[1], font=font))))
    return lines


def text_block(draw, lines, font, cx, top, fill, spacing=1.18):
    for i, line in enumerate(lines):
        w = draw.textlength(line, font=font)
        draw.text((cx - w / 2, top + i * font.size * spacing), line, font=font, fill=fill)


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

def caption_png(text, fonts, L, path):
    canvas = Image.new("RGBA", (L["W"], L["H"]), (0, 0, 0, 0))
    font = ImageFont.truetype(fonts["bold"], L["cap_px"])
    lines = wrap(ImageDraw.Draw(canvas), text, font, L["cap_wrap"])
    top = L["cap_cy"] - L["cap_px"] * 1.18 * len(lines) / 2
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    text_block(ImageDraw.Draw(glow), lines, font, L["W"] / 2, top + 4, (6, 28, 64, 150))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(8)))
    text_block(ImageDraw.Draw(canvas), lines, font, L["W"] / 2, top, (255, 255, 255, 255))
    canvas.save(path)


def title_card(fonts, icon_path, path, outro=False):
    canvas = gradient(SOCIAL["W"], SOCIAL["H"]).convert("RGBA")
    W = SOCIAL["W"]
    d = ImageDraw.Draw(canvas)
    icon_size = 250 if outro else 300
    top = 520 if outro else 600
    paste_with_shadow(canvas, rounded_icon(icon_path, icon_size), (W - icon_size) // 2, top,
                      blur=30, alpha=110, dy=18)
    title = ImageFont.truetype(fonts["bold"], 128)
    tag = ImageFont.truetype(fonts["medium"], 54)
    y = top + icon_size + 70
    text_block(d, ["Billow"], title, W / 2, y, (255, 255, 255, 255))
    y += 175
    taglines = ["Every card. Every charge.", "Automatically."] if outro else ["Every card. Every charge."]
    text_block(d, taglines, tag, W / 2, y, (255, 255, 255, 235))
    if outro:
        pill_font = ImageFont.truetype(fonts["semibold"], 46)
        label = "Free on the App Store"
        w = d.textlength(label, font=pill_font) + 96
        x0, y0 = (W - w) / 2, y + 2 * 54 * 1.18 + 90
        d.rounded_rectangle((x0, y0, x0 + w, y0 + 108), radius=54, fill=(255, 255, 255, 255))
        d.text((x0 + 48, y0 + 26), label, font=pill_font, fill=(28, 92, 171, 255))
    canvas.convert("RGB").save(path)


# ---------- timeline ----------

def detect_freezes(video, duration):
    # Sensitive enough that small changes (a chart day highlight) count as motion.
    log = run(["ffmpeg", "-hide_banner", "-i", video, "-vf",
               "scale=660:-2,freezedetect=n=0.0002:d=0.5", "-f", "null", "-"], capture=True)
    starts = [float(x) for x in re.findall(r"freeze_start: ([\d.]+)", log)]
    ends = [float(x) for x in re.findall(r"freeze_end: ([\d.]+)", log)]
    ends += [duration] * (len(starts) - len(ends))
    return list(zip(starts, ends))


def scene_changes(video, threshold=0.06):
    """Timestamps of large visual changes: tab switches, sheets, scrolling."""
    log = run(["ffmpeg", "-hide_banner", "-i", video, "-vf",
               f"scale=330:-2,select='gt(scene,{threshold})',showinfo", "-f", "null", "-"], capture=True)
    return sorted(float(x) for x in re.findall(r"pts_time:([\d.]+)", log))


def keep_intervals(freezes, duration):
    keeps, cursor = [], 0.0
    for start, end in freezes:
        # Let the opening and closing shots breathe; trim the rest harder.
        limit = HOLD_START if start <= 0.05 else HOLD_END if end >= duration - 0.05 else HOLD
        if end - start > limit:
            keeps.append((cursor, start + limit))
            cursor = end
    keeps.append((cursor, duration))
    return [(a, b) for a, b in keeps if b - a > 0.05]


def mapper(keeps, speed):
    def to_cut(t):
        return sum(max(0.0, min(b, t) - a) for a, b in keeps) / speed
    return to_cut


# ---------- composition ----------

def compose(cfr, keeps, speed, hold, total, windows, fonts, L, work, tag, out, audio):
    raw_w, raw_h = probe_size(cfr)
    app_h = L["app_h"]
    app_w = even(app_h * raw_w / raw_h)
    app_x = (L["W"] - app_w) // 2
    bg, mask, shade = (os.path.join(work, f"{tag}-{n}.png") for n in ("bg", "mask", "shadow"))
    gradient(L["W"], L["H"]).save(bg)
    rounded_mask(app_w, app_h, L["radius"]).save(mask)
    shadow = Image.new("RGBA", (L["W"], L["H"]), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((app_x, L["app_y"] + 18, app_x + app_w, L["app_y"] + app_h + 18),
                                             radius=L["radius"], fill=(4, 20, 48, 120))
    shadow.filter(ImageFilter.GaussianBlur(30)).save(shade)
    caps = []
    for i, (_, _, text) in enumerate(windows):
        p = os.path.join(work, f"{tag}-cap-{i}.png")
        caption_png(text, fonts, L, p)
        caps.append(p)

    inputs = ["-i", cfr]
    for p in [bg, mask, shade, *caps]:
        inputs += ["-loop", "1", "-t", f"{total:.3f}", "-i", p]
    if audio:
        inputs += ["-f", "lavfi", "-t", f"{total:.3f}", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]
    select = "+".join(f"between(t,{a:.3f},{b:.3f})" for a, b in keeps)   # quoted below
    pad = f",tpad=stop_mode=clone:stop_duration={hold:.3f}" if hold > 0 else ""
    graph = (f"[0:v]select='{select}',setpts=N/({FPS}*TB),setpts=PTS/{speed:.5f},fps={FPS},"
             f"scale={app_w}:{app_h}:flags=lanczos{pad},format=rgba[app0]"
             f";[2:v]fps={FPS},format=gray[m];[app0][m]alphamerge[app]"
             f";[1:v]fps={FPS},format=rgba[bg];[3:v]fps={FPS},format=rgba[sh]"
             f";[bg][sh]overlay=0:0[b1];[b1][app]overlay={app_x}:{L['app_y']}:shortest=1[v]")
    label = "v"
    for i, (s, e, _) in enumerate(windows):
        k = 4 + i
        fade_out = max(s + 0.3, e - 0.3)
        graph += (f";[{k}:v]format=rgba,fps={FPS},fade=t=in:st={s:.3f}:d=0.3:alpha=1,"
                  f"fade=t=out:st={fade_out:.3f}:d=0.3:alpha=1[c{i}];[{label}][c{i}]overlay=0:0:format=auto[o{i}]")
        label = f"o{i}"
    graph += f";[{label}]format=yuv420p,settb=AVTB,setsar=1[vout]"

    cmd = ["ffmpeg", "-y", *inputs, "-filter_complex", graph, "-map", "[vout]"]
    if audio:   # App Store preview spec
        cmd += ["-map", f"{4 + len(caps)}:a", "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0",
                "-preset", "slow", "-b:v", "11M", "-maxrate", "12M", "-bufsize", "22M",
                "-c:a", "aac", "-b:a", "256k", "-ar", "44100", "-ac", "2", "-movflags", "+faststart"]
    else:
        cmd += ["-c:v", "libx264", "-preset", "slow", "-crf", "16"]
    run(cmd + ["-r", str(FPS), "-t", f"{total:.3f}", out])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--start", required=True, help="file holding the unix time recording began")
    ap.add_argument("--marks", required=True, help="file with TOURMARK lines")
    ap.add_argument("--icon", required=True)
    ap.add_argument("--font-dir")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    work = os.path.join(a.out, "work")
    os.makedirs(work, exist_ok=True)

    fonts = {
        "bold": find_font(a.font_dir, ["Inter-Bold.ttf"]),
        "semibold": find_font(a.font_dir, ["Inter-SemiBold.ttf", "Inter-Bold.ttf"]),
        "medium": find_font(a.font_dir, ["Inter-Medium.ttf", "Inter-Regular.ttf"]),
    }
    rec_start = float(open(a.start).read().strip())
    marks = {}
    for line in open(a.marks):
        parts = line.split()
        if "TOURMARK" in parts:
            i = parts.index("TOURMARK")
            if i + 2 < len(parts):
                marks.setdefault(parts[i + 1], float(parts[i + 2]))
    steps = [(n, c) for n, c in STEPS if n in marks]
    if not steps:
        raise SystemExit("no TOURMARK lines found")
    end = marks.get("end", max(marks.values()) + 2.5)

    # 1. Constant-frame-rate copy of the tour. simctl records variable frame rate
    #    (almost no frames while the screen is still), so seeking first would start
    #    at the next *change* and shift everything early. Convert the whole file
    #    to CFR, then trim frame-exactly.
    t0 = max(0.0, marks[steps[0][0]] - rec_start - 0.15)
    raw_d = end - rec_start - t0
    cfr = os.path.join(work, "tour-cfr.mp4")
    run(["ffmpeg", "-y", "-i", a.raw, "-vf",
         f"fps={FPS},trim=start={t0:.3f}:end={t0 + raw_d:.3f},setpts=PTS-STARTPTS",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "12", cfr])

    # 2. Cut still stretches down to a short hold.
    freezes = detect_freezes(cfr, raw_d)
    keeps = keep_intervals(freezes, raw_d)
    kept = sum(b - a for a, b in keeps)

    # Each step logs its mark, then XCTest pauses before acting. Start each
    # caption when its action visibly begins: the first big scene change after
    # the mark, else the first moment motion resumes (small changes like the
    # chart scrub).
    onsets = sorted(e for _, e in freezes if e < raw_d - 0.05)
    cuts = scene_changes(cfr)

    def timeline(max_len):
        speed = max(1.0, kept / max_len)
        body = kept / speed
        hold = max(0.0, MIN_PREVIEW - body)
        total = body + hold
        to_cut = mapper(keeps, speed)

        def at(name):
            return marks[name] - rec_start - t0

        def caption_start(i):
            m = at(steps[i][0])
            nxt = at(steps[i + 1][0]) if i + 1 < len(steps) else at("end") if "end" in marks else raw_d
            hi = min(m + 8.0, nxt)          # never borrow the next step's action
            hit = next((c for c in cuts if m - 0.05 <= c < hi), None)
            if hit is not None:
                # Scene scores rise late on cross-fades; back up to where motion began.
                early = [o for o in onsets if max(m - 0.05, hit - 1.5) <= o <= hit]
                if early:
                    hit = early[0]
            else:
                hit = next((o for o in onsets if m - 0.05 <= o < hi), None)
            return to_cut(hit) - 0.12 if hit is not None else to_cut(m)

        starts = [0.0] + [caption_start(i) for i in range(1, len(steps))]
        for i in range(1, len(starts)):
            starts[i] = max(starts[i], starts[i - 1] + 1.0)
        windows = [(starts[i], starts[i + 1] if i + 1 < len(starts) else total, c)
                   for i, (_, c) in enumerate(steps)]
        print(f"tour {raw_d:.1f}s -> kept {kept:.1f}s in {len(keeps)} pieces -> {total:.1f}s "
              f"(speed x{speed:.2f}, end hold {hold:.1f}s)")
        for s, e, c in windows:
            print(f"  {s:5.1f}-{e:5.1f}s  {c}")
        return speed, hold, total, windows

    # 3. App Store preview (must stay within 15-30 s).
    speed, hold, total, windows = timeline(MAX_PREVIEW)
    store_out = os.path.join(a.out, "billow-app-preview-886x1920.mp4")
    compose(cfr, keeps, speed, hold, total, windows, fonts, STORE, work, "store", store_out, audio=True)
    store_total = total

    # 4. Social cut: intro card -> tour -> outro card, cross-faded, gentler pace.
    speed, hold, total, windows = timeline(MAX_SOCIAL)
    main_mp4 = os.path.join(work, "social-main.mp4")
    compose(cfr, keeps, speed, hold, total, windows, fonts, SOCIAL, work, "social", main_mp4, audio=False)
    intro_png = os.path.join(work, "intro.png")
    outro_png = os.path.join(a.out, "billow-cover-1080x1920.png")
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
    off2 = intro_d + total - 2 * xf
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

    # 5. Frame grids for review.
    for src, name, width, grid in [(store_out, "contact-app-preview.png", 221, "6x2"),
                                   (social_out, "contact-social.png", 216, "6x3")]:
        run(["ffmpeg", "-y", "-i", src, "-vf",
             f"fps=1/2.4,scale={width}:-2,tile={grid}:padding=8:margin=8:color=white",
             "-frames:v", "1", os.path.join(a.out, name)])
    print(f"done: preview {store_total:.1f}s, social {social_total:.1f}s")


if __name__ == "__main__":
    main()
