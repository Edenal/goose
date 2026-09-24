# GOOSE 🪿

**G**litchy **O**ld-**S**chool **O**utput **S**cene **E**ngine — a DemoScene Maker. *Honk.*

GOOSE renders a 90s PC demo in real time with C++17 and OpenGL 4.1 (SDL3 handles the window and audio), then exports it
frame-perfect to video. The first production is the **ESA Marathon trailer**: 75 seconds that boot like a 486 and end on the
ESA logo.

- **Boot:**
  - The CRT powers on: beam dot, then a line, then an overexposed bloom and a degauss wobble.
  - BIOS POST, then an Award-style blue CMOS setup.
  - A DOS prompt with real commands, then a game-style `SETUP.EXE` that configures a Sound Blaster 16 (220h / IRQ 5 / DMA 1).
  - Pressing **Test** starts the SID music.
- **Easter eggs:** speedrun memes are hidden in the boot: Goosebert, Plum, *over estimate*, and *never happened before*.
- **Demo:** `ESA.EXE` switches VGA to mode X (320×240). The mode switch spews garbage, snow and a vertical roll, then
  the parts cut on the beat: starfield and copper bars, a ray-cast ESA cube on a checkerboard, plasma, a Mega Drive
  parallax stage with LiveSplit splits, and an E/S/A tunnel.
- **Finale:** the cube snaps onto the logo on the song's final hit, and the CRT powers off in reverse.
- **Look:** mode X output is quantised to the Mega Drive's 9-bit colour ladder with ordered dither.
  - **CRT pass:** curvature, beam scanlines, aperture grille, composite smear, ringing, RF ghost, RGB misconvergence,
    halation and phosphor persistence.
  - **Glitches:** deterministic in `t`. Every cut, every strong kick and some random off-beats get tearing and
    chroma splits, and bright frames make the raster bulge.
- **Sound:** every keystroke, POST beep, HDD seek, degauss *BWONG* and HV crackle is synthesised in sync with the picture.

## Quick start (macOS)

```
brew install sdl3 ffmpeg librsvg          # + Python 3 with numpy and Pillow
make assets                               # downloads the song from remix.kwed.org, builds font atlases, trims the cut
make run                                  # live: Space pause, ←/→ seek 5 s, Home restart, F fullscreen, Esc quit
make export                               # out/goose.mp4 — 1920×1080, 60 fps, exactly 4500 frames (~4 min on an M4)
./build/goose --frames 23.7,66.4 out/x    # single frames as PNG (with phosphor warm-up)
```

Every frame is a pure function of `t`, so live playback, stills and the export always match.

## Where things are

| File | What |
|---|---|
| `src/timeline.h` | **Production copy** (`EVENT_NAME`, URLs) and every cue time |
| `src/textmode.cpp` | BIOS / CMOS / DOS / SETUP.EXE screens; keystroke times drive both the visuals and the key-click sounds |
| `src/audio.cpp` | Synthesised PC sounds (keys, POST beep, HDD seeks, degauss, relay) + mix + per-frame audio envelopes |
| `src/main.cpp` | Render passes, cube camera and logo-snap solve, per-scene text layout, live/stills/export |
| `shaders/scenes.frag` | Demo parts: starfield + copper bars, checkerboard + ray-cast cube, plasma, parallax stage + LiveSplit HUD, E/S/A tunnel, logo finale |
| `shaders/crt.frag` | The tube |
| `tools/build_assets.py` | Un-projects the cube's three logo faces into textures, CP437 font atlases, trims the song |

## Timeline (seconds)

| t | Part |
|---|---|
| 0.0 | CRT power-on: beam dot → line → overexposed raster that blooms and settles, degauss wobble + rainbow purity (relay clunk, degauss BWONG, HV crackle, flyback whine) |
| 0.9 | BIOS POST: memory count, POST beep, IDE detect — the secondary slave is **GOOSEBERT (HONK)** |
| 3.75 | DEL → CMOS setup; the cursor passes **PLUM CONFIGURATION** ("Plum-approved settings. Do not touch.") → SAVE & EXIT (Y) |
| 6.35 | reboot (sync loss) → `Starting ESA-DOS...` → `cd esa` → `setup` |
| 9.0 | SETUP.EXE: select Sound Blaster 16 → port / IRQ / DMA → **Test** |
| 13.0 | music starts (song 4:32.00, bar 102). The sound test has a 1.5 s estimate, so it goes red and **OVER ESTIMATE** blinks |
| 16.0 | DOS: `eas` → "Bad command or file name" → `rem never happened before` → `esa` |
| 18.7 | loader checks (the estimate check fails with **OVER ESTIMATE**) → "Switching to VGA mode X" |
| 20.15 | mode switch: VGA memory spews garbage characters, horizontal hold loss, then black + snow + static |
| 21.0 | monitor re-sync → title: EUROPEAN SPEEDRUNNER ASSEMBLY PRESENTS |
| 23.667 | drop: spinning ESA cube on a checkerboard + sine scroller |
| 34.333 | plasma: SPEEDRUNS / LIVE ON TWITCH / FOR CHARITY / ESA WINTER 2027 |
| 45.0 | Mega Drive parallax stage, cube runner, LiveSplit splits (real cue times) |
| 55.667 | E/S/A tunnel, greetings to runners, hosts, commentators, tech crew, volunteers, viewers |
| 63.667 | cube flies in and snaps onto the logo on the song's ending hit (66.317) |
| 66.317 | ESA MARATHON lockup, event name, esamarathon.com, twitch.tv/esamarathon |
| 73.3 | CRT power-off, the power-on in reverse: bloom surge → line → dot → fade (reverse degauss swell, clunk, zap, discharge crackle) |

Sync is measured from the audio: 90 BPM, and the bass onsets sit exactly on the beat grid anchored at 13.000.
The ending hit measures at 66.318 in the exported file.

## Credits / licences

- **Code:** MIT (see `LICENSE`).
- **Music:** *Machinae Supremacy — "SIDology Episode 1: SID Evolution"*. It is **not included**: `make assets` downloads it
  from [Remix.Kwed.Org](https://remix.kwed.org/). The copyright is the band's, so get their permission before you
  publish a video that uses it.
- **VGA / BIOS fonts:** *The Ultimate Oldschool PC Font Pack* by VileR ([int10h.org](https://int10h.org/oldschool-pc-fonts/)),
  CC BY-SA 4.0. See `assets/OLDSCHOOL-PC-FONTS-LICENSE.TXT`.
- **ESA Marathon logo, cube and wordmark art** (`assets/gen/cube_*.png`, `logo_cube.png`, `word_marathon.png`) belong
  to the European Speedrunner Assembly. They're included so the trailer builds; the code's MIT licence doesn't cover them.
  The wordmark PNG was pre-rendered from Bebas Neue Pro, which is not included. `build_assets.py` regenerates brand art
  only where the ESA brand kit and the font are installed.
