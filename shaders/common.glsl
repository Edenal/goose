#version 410 core
// GOOSE part library. Every part in shaders/parts/ is compiled as: common.glsl + <part>.glsl + part_main.glsl.
// A part defines `vec3 part(vec2 p)` where p is the mode X pixel coordinate (0..320, 0..240, y down) and
// returns the colour before the Mega Drive quantiser. See docs/PARTS.md.
in vec2 vUV;
out vec4 o;

// ---- time + music
uniform vec2 uRes;          // 320x240
uniform float uT;           // trailer time, seconds
uniform float uLT;          // time since this part started
uniform float uLen;         // this part's length in seconds (whole bars)
uniform float uBeat;        // beats since the music started (90 BPM; integer = on the beat)
uniform float uFlash;       // white flash on cuts (already weighted by the effects slider)
uniform float uKickCum;     // integral of the kick envelope: use it to push motion on the drums
uniform vec4 uEnv;          // music envelopes: low, mid, high, kick (0..1)
uniform float uFx;          // effects weighting slider (1.0 = default)
uniform float uHit;         // finale: trailer time the cube lands on the logo (-1 = no finale)

// ---- art
uniform sampler2D uFont8;   // IBM BIOS 8x8 CP437 font, 16x16 glyphs
uniform sampler2D uStr;     // strings, one per row (256 chars): 0-15 this part's @str, 16 EVENT, 17 LINE2,
                            // 18 LINE3, 20-35 split labels of the arrangement
uniform int uStrLen[40];
uniform sampler2D uTop, uLeft, uRight;   // the ESA cube's three faces (E top, S left, A right), RGBA
uniform sampler2D uLogo;    // 2D ESA cube logo, 1200x1200 RGBA (the cube spans 600-unit logo space)
uniform sampler2D uWord;    // MARATHON wordmark mask

// ---- the spinning ESA cube (set up by the host for every part)
uniform mat3 uCubeRot, uCamRot;
uniform vec3 uCubeC, uCamPos;
uniform float uCubeS, uFov, uSnap;
uniform vec2 uAffS0;
uniform vec3 uAffP0, uAffP1, uAffD;
uniform vec3 uLogoPos;      // x, y, px per logo unit
uniform float uLogoA;
uniform vec2 uWordAS;       // alpha, scale

// ---- the arrangement's LiveSplit data
uniform float uSplitT[16];
uniform int uSplitN, uSplitCur;

const float PI = 3.14159265;
const vec3 GOLD = vec3(1.0, 0.741, 0.090), PURP = vec3(0.533, 0.102, 0.910), DEEP = vec3(0.141, 0.106, 0.220);
const vec3 PLUM = vec3(0.227, 0.149, 0.341), ROYAL = vec3(0.451, 0.306, 0.620), CREAM = vec3(1.0, 0.965, 0.867);
const vec3 UIGOLD = vec3(0.992, 0.733, 0.110), LAV = vec3(0.78, 0.68, 1.0);

// text styles
const int TS_WHITE = 0, TS_CHROME = 1, TS_GOLD = 2, TS_LAV = 3, TS_GREEN = 4, TS_RED = 6, TS_GREY = 7;

// ------------------------------------------------------------------ small maths
float hash1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 hash3(float n) { return fract(sin(vec3(n, n + 1.7, n + 3.1) * vec3(127.1, 311.7, 74.7)) * 43758.5453); }
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }
mat2 rot2(float a) { float c = cos(a), s = sin(a); return mat2(c, s, -s, c); }
float easeOut(float x) { x = clamp(x, 0.0, 1.0); return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x); }
float bayer4(vec2 p) {
    ivec2 q = ivec2(p) & 3;
    int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
    return (float(m[q.y * 4 + q.x]) + 0.5) / 16.0;
}
// camera ray for a pinhole camera: uv in -1..1 (y up), fov = tan(half angle)
vec2 screenUV(vec2 p) { return (p - uRes * 0.5) / (uRes.y * 0.5) * vec2(1.0, -1.0); }

// ------------------------------------------------------------------ palettes
vec3 esaGrad(float x) { return mix(GOLD, PURP, clamp(x, 0.0, 1.0)); }
// cycling palette for plasma/tunnel: gold -> purple -> deep -> royal -> gold
vec3 cyclePal(float x) {
    x = fract(x);
    if (x < 0.30) return mix(GOLD, PURP, x / 0.30);
    if (x < 0.55) return mix(PURP, DEEP, (x - 0.30) / 0.25);
    if (x < 0.78) return mix(DEEP, ROYAL, (x - 0.55) / 0.23);
    return mix(ROYAL, GOLD, (x - 0.78) / 0.22);
}

// ------------------------------------------------------------------ 8x8 text
int strLen(int row) { return uStrLen[row]; }
float strW(int row, float scale) { return float(uStrLen[row]) * 8.0 * scale; }
float glyphBit(int ch, ivec2 g) { return texelFetch(uFont8, ivec2((ch % 16) * 8 + g.x, (ch / 16) * 8 + g.y), 0).r; }
// q in glyph pixels relative to the string origin; maxChars limits typing effects
float strAt(int row, vec2 q, int first, int maxChars) {
    int n = min(uStrLen[row] - first, maxChars);
    if (q.x < 0.0 || q.y < 0.0 || q.y >= 8.0 || q.x >= float(n) * 8.0) return 0.0;
    int ch = int(texelFetch(uStr, ivec2(first + int(q.x / 8.0), row), 0).r * 255.0 + 0.5);
    return glyphBit(ch, ivec2(mod(q, 8.0)));
}
vec3 styleCol(int style, float gy) {
    if (style == TS_CHROME) {  // ESA chrome: lavender sky, white horizon, gold ground
        const vec3 C[8] = vec3[](vec3(0.62, 0.40, 1.0), vec3(0.78, 0.62, 1.0), vec3(0.92, 0.86, 1.0), vec3(1.0),
                                 vec3(1.0, 0.86, 0.35), GOLD, vec3(0.95, 0.55, 0.08), vec3(0.72, 0.36, 0.05));
        return C[int(clamp(gy, 0.0, 7.0))];
    }
    if (style == TS_GOLD) return UIGOLD;
    if (style == TS_LAV) return LAV;
    if (style == TS_GREEN) return vec3(0.25, 0.86, 0.40);
    if (style == TS_RED) return vec3(0.95, 0.30, 0.30);
    if (style == TS_GREY) return vec3(0.62, 0.60, 0.70);
    return vec3(1.0);
}
// draw string `row` at pos (top-left, pixels) with a 1-glyph-pixel drop shadow
vec3 drawStrN(vec3 col, vec2 p, int row, vec2 pos, float scale, int style, float alpha, int maxChars) {
    vec2 q = (p - pos) / scale;
    float on = strAt(row, floor(q), 0, maxChars), sh = strAt(row, floor(q - vec2(1.0)), 0, maxChars);
    if (sh > 0.5 && on < 0.5) col = mix(col, col * 0.15, alpha);
    if (on > 0.5) col = mix(col, styleCol(style, fract(q.y / 8.0) * 8.0), alpha);
    return col;
}
vec3 drawStr(vec3 col, vec2 p, int row, vec2 pos, float scale, int style, float alpha) {
    return drawStrN(col, p, row, pos, scale, style, alpha, 256);
}
vec3 drawStrC(vec3 col, vec2 p, int row, float y, float scale, int style, float alpha) {  // centred
    return drawStr(col, p, row, vec2(floor((uRes.x - strW(row, scale)) * 0.5), y), scale, style, alpha);
}
// sine scroller: x0 = where the string starts (scrolls left as it decreases)
vec3 drawWave(vec3 col, vec2 p, int row, float x0, float y, float scale, float amp) {
    vec2 q = (p - vec2(x0, y)) / scale;
    q.y -= sin(p.x * 0.035 + uT * 4.2) * amp / scale;
    float on = strAt(row, floor(q), 0, 256), sh = strAt(row, floor(q - vec2(1.0)), 0, 256);
    if (sh > 0.5 && on < 0.5) col *= 0.15;
    if (on > 0.5) col = styleCol(TS_CHROME, fract(q.y / 8.0) * 8.0);
    return col;
}
// one character by code (for digits etc.)
vec3 drawChar(vec3 col, vec2 p, int ch, vec2 pos, float scale, int style) {
    vec2 q = floor((p - pos) / scale);
    if (q.x < 0.0 || q.y < 0.0 || q.x >= 8.0 || q.y >= 8.0) return col;
    return glyphBit(ch, ivec2(q)) > 0.5 ? styleCol(style, q.y) : col;
}
// "m:ss.cc" right-aligned so its last character ends at xRight
vec3 drawTime(vec3 col, vec2 p, float secs, float xRight, float y, float scale, int style) {
    secs = max(secs, 0.0);
    int cs = int(floor(secs * 100.0 + 0.5));
    int m = cs / 6000, s = (cs / 100) % 60, c = cs % 100;
    int ch[7] = int[](48 + m % 10, 58, 48 + s / 10, 48 + s % 10, 46, 48 + c / 10, 48 + c % 10);
    float w = 8.0 * scale;
    for (int i = 0; i < 7; i++) col = drawChar(col, p, ch[i], vec2(xRight - w * float(7 - i), y), scale, style);
    return col;
}

// ------------------------------------------------------------------ the ESA cube (cube space [0,1]^3)
vec4 faceColor(vec3 p, vec3 n) {
    vec2 uv; vec4 c;
    if (n.y > 0.5)       { uv = vec2(p.x, p.z);             c = texture(uTop, uv); }
    else if (n.y < -0.5) { uv = vec2(p.x, 1.0 - p.z);       c = texture(uTop, uv); }
    else if (n.z > 0.5)  { uv = vec2(p.x, 1.0 - p.y);       c = texture(uLeft, uv); }
    else if (n.z < -0.5) { uv = vec2(1.0 - p.x, 1.0 - p.y); c = texture(uLeft, uv); }
    else if (n.x > 0.5)  { uv = vec2(1.0 - p.z, 1.0 - p.y); c = texture(uRight, uv); }
    else                 { uv = vec2(p.z, 1.0 - p.y);       c = texture(uRight, uv); }
    float e = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    if (e < 0.022 && c.a > 0.5) c.rgb = DEEP;  // keyline on the cube edges
    return c;
}
// rgb + hit; lit = how much to light by the world normal (0 at the logo snap)
vec4 traceCube(vec3 ro, vec3 rd, float lit, mat3 toWorld) {
    vec3 inv = 1.0 / rd;
    vec3 t0 = (vec3(0.0) - ro) * inv, t1 = (vec3(1.0) - ro) * inv;
    vec3 tmn = min(t0, t1), tmx = max(t0, t1);
    float tn = max(max(tmn.x, tmn.y), tmn.z), tf = min(min(tmx.x, tmx.y), tmx.z);
    if (tn > tf || tf < 0.0) return vec4(0.0);
    vec3 p = ro + rd * tn, n;
    if (tn == tmn.x) n = vec3(-sign(rd.x), 0, 0); else if (tn == tmn.y) n = vec3(0, -sign(rd.y), 0); else n = vec3(0, 0, -sign(rd.z));
    vec4 c = faceColor(p, n);
    if (c.a < 0.5) c = vec4(DEEP * 1.25, 1.0);   // through a cut-out: the dark inside of the cube
    vec3 nw = toWorld * n;
    float l = 0.72 + 0.45 * max(dot(nw, normalize(vec3(-0.4, 0.8, 0.6))), 0.0);
    c.rgb *= mix(1.0, l, lit);
    return vec4(c.rgb, 1.0);
}
// trace the host's spinning cube from a world-space ray (camera: uCamPos / uCamRot / uFov)
vec4 cubePersp(vec3 row, vec3 rdw, float lit) {
    vec3 ro = uCubeRot * (row - uCubeC) / uCubeS + 0.5;
    vec3 rd = uCubeRot * rdw;
    return traceCube(ro, rd, lit, transpose(uCubeRot));
}
vec3 cameraRay(vec2 p) { return normalize(uCamRot * vec3(screenUV(p) * uFov, -1.0)); }
// the flat 2D logo, `size` px tall, centred at c
vec4 logoAt(vec2 p, vec2 c, float size) {
    vec2 lu = (p - c) / size * (419.0 / 600.0) + vec2(300.0, 299.5) / 600.0;
    if (lu.x < 0.0 || lu.y < 0.0 || lu.x > 1.0 || lu.y > 1.0) return vec4(0.0);
    return texture(uLogo, lu);
}

// ------------------------------------------------------------------ shared effects
vec3 stars(vec2 p, float speed, float t, float amt) {
    vec3 c = vec3(0.0);
    vec2 ctr = uRes * 0.5;
    for (int i = 0; i < 110; i++) {
        vec3 h = hash3(float(i) * 1.37);
        float z = fract(h.z - t * speed);
        vec2 sp = ctr + (h.xy * 2.0 - 1.0) * vec2(170.0, 130.0) / (z * 3.0 + 0.08) * 0.35;
        float sz = z < 0.25 ? 1.5 : 0.75;
        if (abs(p.x - sp.x) < sz && abs(p.y - sp.y) < sz) c = max(c, vec3(1.0 - z) * mix(vec3(1.0), LAV, h.x) * amt);
    }
    return c;
}
vec3 copper(vec2 p, vec3 col, float t, float spread, float yc0) {
    const vec3 CB[4] = vec3[](GOLD, PURP, vec3(0.2, 0.8, 1.0), vec3(1.0, 0.35, 0.55));
    for (int i = 0; i < 4; i++) {
        float yc = yc0 + sin(t * 2.1 + float(i) * 0.9) * spread;
        float d = abs(p.y - yc) / 9.0;
        if (d < 1.0) {
            float b = floor((1.0 - d) * 6.0) / 6.0;   // stepped like a copper list
            col = mix(col, CB[i] * (0.35 + 0.9 * b) + vec3(0.35) * pow(b, 4.0), 0.95);
        }
    }
    return col;
}
