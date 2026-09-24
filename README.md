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
  - **Scanlines:** a narrow gaussian beam leaves a visible dark gap between every source line.
  - **Glitches:** reserved for transitions, so inside a part the content has the focus. They're deterministic in `t`:
    power-on degauss, a reboot sync loss, the VGA mode switch (garbage, static, roll), a static burst with tear and
    chroma split on every scene cut, and a signal breakdown before the power-off. The static rides on the scanlines.
- **Sound:** every keystroke, POST beep, HDD seek, degauss *BWONG* and HV crackle is synthesised in sync with the picture.

## Run it

**The app:** download `GOOSE-macOS.zip` from the releases, unzip it, then right-click `GOOSE.app` and choose **Open** the first
time (it's ad-hoc signed, not notarised). It opens in **GOOSE SETUP**, a 90s-style setup program shown on the CRT:

- **Sequences:** switch demo parts on or off with Space, reorder them with Shift+↑↓, and press Enter to preview from
  that part. Boot and finale can be switched off too. The details panel shows what each part is and which classic
  demo inspired it.
- **Output:** sliders for **Scanlines**, **Effects** (curvature, grille, halation, ghosting, flashes) and **Glitches**
  (static, tears, rolls). 100 % is the reference look. The Event / Line 2 / Line 3 texts appear in the demo.
  Quality is WEB (24 Mbps, upload-sized) or MASTER (CRF 14).
- **Music:** the song isn't bundled. On first run select **Music** and press Enter to download it from Remix.Kwed.Org.
- **F5** plays everything with sound (Esc back, Space pause, ←/→ seek). **F9** exports a 1080p60 MP4 to `~/Movies/GOOSE`,
  which needs `ffmpeg` (`brew install ffmpeg`).
- Settings are saved in `~/Library/Application Support/GOOSE/settings.ini`.

Timing is automatic. Every part is a whole number of bars at 90 BPM, and the song is **back-timed**: however many
parts you pick, the cube lands on the logo on the song's final hit and every cut stays on the beat.

**From source:**

```
brew install sdl3 ffmpeg
make                                   # build/goose
make run                               # the app
make app                               # build/GOOSE.app (bundles SDL3); make zip -> build/GOOSE-macOS.zip
./build/goose --export out/goose.mp4 --web      # render the saved arrangement (--defaults: the factory trailer)
./build/goose --frames 23.7,66.4 out/x          # stills
./build/goose --list                            # the parts
./build/goose --part plasma --frames 1,5,9 out/p   # one part on its own (for writing parts)
```

Every frame is a pure function of `t`, so live playback, stills and the export always match.

## Parts

Each demo part is one GLSL file in `shaders/parts/`, picked up automatically. See [`docs/PARTS.md`](docs/PARTS.md) to
write your own.

<!-- parts:start -->
| Part | Bars | Inspired by | What it does | Default |
|---|---|---|---|---|
| **TITLE** (`title`) | 1 | GOOSE original: starfield + copper list opener | Stars accelerate through stepped copper bars while EUROPEAN SPEEDRUNNER ASSEMBLY types out, then PRESENTS in chrome. | on |
| **THE CUBE** (`cube`) | 4 | GOOSE original: ray-cast brand cube on a Mode 7 checkerboard | The drop: the ESA cube spins over a scrolling checkerboard with its reflection, copper sky and a sine scroller. | on |
| **PLASMA** (`plasma`) | 4 | GOOSE original: palette-cycled plasma with a raster text band | Chunky 160x120 plasma cycling through the brand palette; one big chrome word per bar drops into a raster band. | on |
| **THE STAGE** (`stage`) | 4 | GOOSE original: Mega Drive parallax platformer with a LiveSplit HUD | Dusk parallax hills with line-scroll heat haze; the cube hops along with speed-shoes afterimages while LiveSplit shows the trailer's real splits. | on |
| **GREETINGS TUNNEL** (`tunnel`) | 3 | GOOSE original: texture tunnel built from the cube's E/S/A faces | Flying down a tube tiled with the logo's faces; greetings zoom out of the vanishing point on every other beat. | on |
| **GLENZ VECTORS** (`glenz`) | 4 | Future Crew - Second Reality (1993) | Two nested see-through polyhedra, front and back faces blended in gold, purple and cream checkers, bouncing and squashing on every beat over a plum grid floor. | off |
| **CHROME CHESS** (`chess`) | 4 | Triton - Crystal Dream 2 (1993) | Ray-traced chrome pawns and a king on a floating cream and purple board, mirroring the board and a gold-to-purple sky. The camera orbits slowly; the pieces hop one square on every bar. | off |
| **PHONG BLOBS** (`blobs`) | 4 | Complex - Dope (1995) | Morphing metaballs with phong and environment-mapped shading in gold, purple and cream, pulsing on the kick in front of a rotating ring of brand-coloured fire. | off |
| **DOT MORPH** (`dots`) | 4 | Iguana - HeartQuake (1994) | 1,536 depth-shaded vector dots morph on every bar line: sphere, torus, cube, then a twisted helix. Near dots are big gold bobs, far dots small purple ones. | off |
| **CHECKER WARP** (`warp`) | 4 | Cascada - Hex Appeal (1993) | A full-screen checkerboard waving like a rubber flag, with a credits roll scrolling up through the same warp. The distortion swells on every kick. | off |
| **TILE SPIRAL** (`spiral`) | 4 | Orange - Project XYZ (1995) | A rotating galaxy of square tiles textured with the ESA cube's faces, streaming out of the core with motion blur. The arms wind tighter or looser on every bar. | off |
| **JULIA DREAM** (`julia`) | 4 | Electromotive Force - Verses (1994) | A morphing Julia set in a palette-cycled gold-to-purple ramp, slowly zooming and turning. Its constant orbits a path and hops to a new region on every bar. | off |
| **VOXEL FLIGHT** (`voxel`) | 4 | CNCD - Inside (1996) | A banking flight down a valley of chunky voxel mountains at dusk, water in the valley mirroring a gold-to-purple sky, with the ESA logo glowing in front of the sun. | off |
| **THE INVITATION** (`invite`) | 4 | Future Crew - Assembly '92 Invitation (Fishtro, 1992) | A hand-painted night landscape with the ESA cube on a floating island; a text writer types one invitation line per bar. | off |
| **LIQUID METAL** (`liquid`) | 4 | RealTech - Countdown (1995) | A ray-marched chrome form melts from torus to twisted knot to blob and back on the bar lines, mirroring the brand gradient; a frame counter ticks in the corner. | off |
| **COLOUR FEEDBACK** (`feedback`) | 4 | Orange - X14 (1995) | A video-feedback swirl without feedback: the spinning ESA cube and its orbiting sparks are redrawn sixteen times under stacked rotate, zoom and hue shifts, and the twist flips on every bar. | off |
| **HYPERSPACE** (`hyperspace`) | 4 | Acme - 303 (1997) | A radial-blurred speed-line starburst explodes from the centre, a glossy hexagon floor and ceiling rush past, light bursts on the kick and a speedrun word slams in on every bar. | off |
| **PROPAGANDA** (`propaganda`) | 4 | Bomb - State of Mind (1998) | Stark black-and-cream poster cards slam in every two beats: halftone, scan lines, frame rules and one accent colour each, shouting speedrun slogans. | off |
| **UNDERWATER** (`caustics`) | 4 | Pulse - Sunflower (1997) | The ESA cube sinks into teal water and hovers over a plum seabed laced with gold caustics, under light shafts, swaying kelp and rising bubbles. | off |
| **FLYING LETTERS** (`letters`) | 4 | Cascada - Holistic (1994) | Chunky voxel-extruded letters fly in from every direction, tumble and slam onto a glossy grid floor, spelling one word per bar. | off |
| **BOSS FIGHT** (`boss`) | 8 | 16-bit shmup / Mega Drive boss battles | A two-round 16-bit boss rush with WARNING banners and boss HP bars: Goosebert honks THE WORLD into a K.O., then Plum beams THE VOID shut for a new PB. | off |
| **FINALE** (`finale`) | 1 | GOOSE original: 3D cube snaps onto the flat brand logo | The cube flies in and lands exactly on the ESA MARATHON logo on the song's final hit; event name and links type in, then the tube powers off. | on |
<!-- parts:end -->

## Where things are

| File | What |
|---|---|
| `src/timeline.*` | Arrangement → cue times, back-timed song entry, hit, power-off |
| `src/renderer.*` | Text mode + parts → halation → CRT; cube camera + logo snap; glitch schedule |
| `src/menu.*` | GOOSE SETUP |
| `src/settings.*`, `src/parts.*` | Saved settings; part metadata |
| `src/textmode.cpp` | BIOS / CMOS / DOS / SETUP.EXE boot; keystroke times drive visuals and key-click sounds |
| `src/audio.cpp`, `src/music.cpp` | Synthesised PC/CRT sounds, mix, envelopes; song download + MP3 decode (minimp3) |
| `shaders/common.glsl` | The part library (uniforms, palette, 8×8 text, cube tracer) |
| `shaders/parts/*.glsl` | The demo parts |
| `shaders/crt.frag` | The tube |
| `tools/build_assets.py` | Regenerates font atlases and the cube face textures (needs the ESA brand kit) |

## The ESA trailer (default arrangement)


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
