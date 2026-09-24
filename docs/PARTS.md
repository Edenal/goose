# Writing a GOOSE part

A part is one demo sequence: a single GLSL file in `shaders/parts/`. GOOSE picks it up automatically. It shows in
the GOOSE SETUP menu, can be switched on, reordered and previewed, and ends up in the export. No C++ changes are needed.

## The file

```glsl
// @id glenz                    unique, lowercase, = file name
// @name GLENZ VECTORS          menu name, max 22 chars
// @split GLENZ                 LiveSplit label in THE STAGE's HUD, max 10 chars
// @bars 4                      length in bars (90 BPM: 1 bar = 2.667 s). 4 is the norm.
// @order 110                   default position in the menu
// @default off                 on = part of the default arrangement (keep new parts off)
// @inspired Future Crew - Second Reality (1993)
// @desc One or two sentences for the menu's details box.
// @str 0 SOME TEXT             strings the part draws (rows 0-15, up to 256 chars each).
// @str 1 {EVENT}               {EVENT} {LINE2} {LINE3} = the event text set in the menu

vec3 part(vec2 p) {             // p = mode X pixel (0..320, 0..240), y DOWN, pixel centres at .5
    ...
    return col;                 // linear-ish RGB 0..1, before the Mega Drive quantiser
}
```

`shaders/common.glsl` is prepended and `shaders/part_main.glsl` appended, so a part may define its own helper
functions above `part()`. Don't redefine anything that already exists in `common.glsl`. GLSL 4.10 core. Avoid
built-in names such as `noise1`–`noise4`.

## What you get (see `shaders/common.glsl`)

| | |
|---|---|
| `uT` | trailer time (s) |
| `uLT` | time since this part started (0 .. `uLen`) |
| `uLen` | this part's length (s) |
| `uBeat` | beats since the music started. Integer = on the beat; `fract(uBeat)` is the beat phase |
| `uEnv` | music envelopes `.x` low, `.y` mid, `.z` high, `.w` kick (0..1) |
| `uKickCum` | running integral of the kick. Add it to a phase to push motion on the drums |
| `uFx` | the effects slider (1 = default). Optional |
| palette | `GOLD PURP DEEP PLUM ROYAL CREAM UIGOLD LAV`, `esaGrad(x)`, `cyclePal(x)` |
| maths | `hash1 hash2 hash3 vnoise fbm rot2 easeOut bayer4 screenUV(p)` |
| text | `drawStr / drawStrC / drawStrN / drawWave / drawChar / drawTime`, `strLen(row) strW(row, scale)`, styles `TS_WHITE TS_CHROME TS_GOLD TS_LAV TS_GREEN TS_RED TS_GREY` |
| the ESA cube | `cubePersp(ro, rd, lit)` traces the host's spinning cube; `cameraRay(p)` is the host's camera; `traceCube(ro, rd, lit, toWorld)` traces a cube in its own [0,1]³ space with your own ray; `faceColor`; the face textures `uTop` (E) `uLeft` (S) `uRight` (A) |
| logo | `logoAt(p, centre, heightPx)` = the flat ESA cube logo (rgba) |
| effects | `stars(p, speed, t, amount)`, `copper(p, col, t, spread, y)` |
| font | `uFont8` (IBM BIOS 8×8, CP437), `glyphBit(ch, ivec2)` |

## Rules

1. **Pure function of time.** No feedback textures and no state. Build motion blur, trails and feedback-zoom looks by
   evaluating your function several times at offset times or offset transforms.
2. **Readable at 320×240 after the 9-bit quantise and strong scanlines.** One-pixel details vanish, so aim for shapes of
   3 px or more, text at scale 1 or larger, and bold contrast. The quantiser dithers gradients for you.
3. **The whole length must look good.** Check stills from `uLT` 0 to `uLen`, not just the middle. The host handles
   the cut in and out (static, tear, flash), so don't fade to black at the ends.
4. **Stay on the music.** 90 BPM: accent the beat with `uBeat`, the drums with `uEnv.w` or `uKickCum`, and change
   things on bar lines. Every 4 beats is a bar.
5. **ESA-only on screen.** The picture shows the ESA brand, speedrun themes and the event text, never the name of the
   demo that inspired it. Credit goes in `@inspired`. Make a procedural homage to the effect: don't copy anyone's art.
6. **Performance.** Keep ray-march loops around 64 steps or fewer. The `--frames` log prints ms/frame, which includes
   the CRT pass. Stay under about 8 ms on the M4 so the live preview holds 60 fps.
7. **Brand palette.** Gold `#ffbd17` to purple `#881ae8` is the signature gradient, on deep plum backgrounds. Other
   colours are fine as accents, but the part should feel ESA.

## Test loop

```
make                                                              # after pulling
./build/goose --list                                              # your part must show without (SHADER ERROR)
./build/goose --part glenz --frames 0.2,1.5,3,4.5,6,7.5,9,10.4 out/stills/glenz   # times local to the part
```

`--part` renders the part on its own (no power-on, no glitches) with the music that would play under it. Look at the
PNGs. A 1920×1080 frame shows the CRT exactly as it will air.
