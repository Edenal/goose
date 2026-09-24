#!/usr/bin/env python3
"""Build every derived asset the trailer needs into assets/gen/.

  - font_vga9x16.png   CP437 atlas, 16x16 cells of 9x16 (IBM VGA text mode)
  - font_bios8x8.png   CP437 atlas, 16x16 cells of 8x8  (IBM BIOS, classic demo font)
  - cube_top/left/right.png  the ESA cube's three faces un-projected to squares
  - logo_stacked.png / logo_cube.png  2D brand lockups for the finale overlay
  - wordmark_*.png     Bebas SemiExp XB strings for titles
  - song_cut.wav       the song excerpt the trailer uses (decoded once, trimmed exactly)

Run:  python3 tools/build_assets.py
"""
import os, re, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "assets")
G = os.path.join(A, "gen")
KIT = os.path.expanduser("~/Documents/ESA Assets/ESA Marathon Brand/Kit")
os.makedirs(G, exist_ok=True)

# ---- timing contract (mirrored in src/timeline.h) -------------------------
BEAT = 60.0 / 90.0
SONG_BAR0 = 261.337           # song time of bar 98 (refitted beat phase)
SONG_START = SONG_BAR0 + 4 * 4 * BEAT   # bar 102 = the "sound test" entry
MUSIC_AT = 13.0               # trailer time the song starts
LENGTH = 75.0
SONG_LEN = LENGTH - MUSIC_AT
FADE = 3.0


def cp437_atlas(ttf, size, cw, ch, out):
    font = ImageFont.truetype(ttf, size)
    img = Image.new("L", (16 * cw, 16 * ch), 0)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    # CP437 glyphs 1..31 are the smiley/arrow set, not control codes
    low = " ☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼"
    for i in range(256):
        c = low[i] if i < 32 else (bytes([i]).decode("cp437") if i != 127 else "⌂")
        x, y = (i % 16) * cw, (i // 16) * ch
        asc, _ = font.getmetrics()
        d.text((x, y), c, font=font, fill=255)
    img.save(out)


def svg_png(svg_text, width, out):
    tmp = out + ".svg"
    open(tmp, "w").write(svg_text)
    subprocess.run(["rsvg-convert", "-w", str(width), tmp, "-o", out], check=True)
    os.remove(tmp)


def cube_faces():
    src = open(os.path.join(KIT, "ESA-Marathon_Cube_Light.svg")).read()
    # drop the paper background and the dark keyline silhouette: faces only
    src = re.sub(r'<rect width="600" height="600" fill="#efeeec"/>', "", src)
    src = re.sub(r'<path d="M250,39\.96.*?fill="#241b38"/>', "", src, flags=re.S)
    S = 4  # render 2400px for clean resampling
    big = os.path.join(G, "_cube_big.png")
    svg_png(src, 600 * S, big)
    im = np.asarray(Image.open(big).convert("RGBA")).astype(np.float32)
    os.remove(big)
    off = 50.0  # the cube group is translated (50,50)
    P = lambda x, y: np.array([(x + off) * S, (y + off) * S])
    F, L, R, T, B = P(250, 201), P(57.46, 120.48), P(442.54, 120.48), P(250, 39.96), P(250, 459.1)
    N = 256

    def sample(o, du, dv, name):
        u = (np.arange(N) + 0.5) / N
        uu, vv = np.meshgrid(u, u)
        pts = o[None, None, :] + uu[..., None] * du + vv[..., None] * dv
        x = np.clip(pts[..., 0], 0, im.shape[1] - 1.001)
        y = np.clip(pts[..., 1], 0, im.shape[0] - 1.001)
        x0, y0 = x.astype(int), y.astype(int)
        fx, fy = (x - x0)[..., None], (y - y0)[..., None]
        c = (im[y0, x0] * (1 - fx) * (1 - fy) + im[y0, x0 + 1] * fx * (1 - fy)
             + im[y0 + 1, x0] * (1 - fx) * fy + im[y0 + 1, x0 + 1] * fx * fy)
        Image.fromarray(np.clip(c, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(G, name))

    # left face z=1: u = x (L->F), v = down (F->B)
    sample(L, F - L, B - F, "cube_left.png")
    # right face x=1: u = F->R, v = down
    sample(F, R - F, B - F, "cube_right.png")
    # top face y=1: u = x (T->R), v = z (T->L)
    sample(T, R - T, L - T, "cube_top.png")
    # 2D reference geometry for the snap (in 600-unit logo space)
    return dict(F=(250 + off, 201 + off), L=(57.46 + off, 120.48 + off), R=(442.54 + off, 120.48 + off),
                T=(250 + off, 39.96 + off), B=(250 + off, 459.1 + off))


def logos():
    src = open(os.path.join(KIT, "ESA-Marathon_Cube_Light.svg")).read()
    src = re.sub(r'<rect width="600" height="600" fill="#efeeec"/>', "", src)
    svg_png(src, 1200, os.path.join(G, "logo_cube.png"))


def wordmarks():
    bebas = os.path.join(A, "BebasSemiExpXB.otf")
    for name, text, size in [("marathon", "MARATHON", 200)]:
        f = ImageFont.truetype(bebas, size)
        l, t, r, b = f.getbbox(text)
        img = Image.new("L", (r - l + 8, b - t + 8), 0)
        ImageDraw.Draw(img).text((4 - l, 4 - t), text, font=f, fill=255)
        img.save(os.path.join(G, f"word_{name}.png"))


SONG_URL = ("https://remix.kwed.org/files/RKOfiles/"
            "machinae%20supremacy%20-%20sidology%20episode%201%20-%20sid%20evolution%20(128kbs).mp3")


def song():
    mp3 = os.path.join(A, "sidology-sid-evolution.mp3")
    if not os.path.exists(mp3):  # not redistributed with the repo: fetch it from Remix.Kwed.Org
        print("downloading the song from remix.kwed.org ...")
        subprocess.run(["curl", "-sSL", "--fail", "-o", mp3, SONG_URL], check=True)
    out = os.path.join(G, "song_cut.wav")
    # decode the whole mp3 once, then trim sample-accurately (same decode the analysis used)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", os.path.join(A, "sidology-sid-evolution.mp3"),
                    "-af", f"atrim=start={SONG_START:.4f}:duration={SONG_LEN:.4f},asetpts=PTS-STARTPTS,"
                           f"afade=t=out:st={SONG_LEN - FADE:.4f}:d={FADE}",
                    "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", out], check=True)


if __name__ == "__main__":
    cp437_atlas(os.path.join(A, "Px437_IBM_VGA_9x16.ttf"), 16, 9, 16, os.path.join(G, "font_vga9x16.png"))
    cp437_atlas(os.path.join(A, "Px437_IBM_BIOS.ttf"), 8, 8, 8, os.path.join(G, "font_bios8x8.png"))
    # brand art is regenerated only where the ESA brand kit / Bebas are installed; the repo ships the PNGs
    if os.path.isdir(KIT):
        print("cube geometry (1200px logo space = x2):", cube_faces())
        logos()
    else:
        print("brand kit not found - keeping the committed cube/logo PNGs")
    if os.path.exists(os.path.join(A, "BebasSemiExpXB.otf")):
        wordmarks()
    else:
        print("Bebas Neue Pro not found - keeping the committed wordmark PNG")
    song()
    print("ok ->", G)
