#version 410 core
// All mode-X (320x240) demo parts. Output is reduced to the Mega Drive's 9-bit colour ladder with
// ordered dither; the CRT's composite smear blends it back, like the real hardware on a TV.
in vec2 vUV;
out vec4 o;
uniform vec2 uRes;
uniform int uScene, uBlackout;
uniform float uT, uLT, uBeat, uFlash, uKickCum;
uniform vec4 uEnv;  // low, mid, high, kick
uniform sampler2D uFont8, uStr, uTop, uLeft, uRight, uLogo, uWord;
// cube + cameras
uniform mat3 uCubeRot, uCamRot;
uniform vec3 uCubeC, uCamPos;
uniform float uCubeS, uFov, uSnap;
uniform vec2 uAffS0;
uniform vec3 uAffP0, uAffP1, uAffD;
uniform vec3 uLogoPos;   // x, y, px per logo unit
uniform float uLogoA;
uniform vec2 uWordAS;    // alpha, scale
// text items
uniform int uTxtN;
uniform vec4 uTxt[24];   // x, y, scale, style
uniform vec2 uTxtX[24];  // len, alpha

const float PI = 3.14159265;
const vec3 GOLD = vec3(1.0, 0.741, 0.090), PURP = vec3(0.533, 0.102, 0.910), DEEP = vec3(0.141, 0.106, 0.220);
const vec3 PLUM = vec3(0.227, 0.149, 0.341), ROYAL = vec3(0.451, 0.306, 0.620), CREAM = vec3(1.0, 0.965, 0.867);
const vec3 UIGOLD = vec3(0.992, 0.733, 0.110), LAV = vec3(0.78, 0.68, 1.0);

float hash1(float n) { return fract(sin(n * 127.1) * 43758.5453); }
vec3 hash3(float n) { return fract(sin(vec3(n, n + 1.7, n + 3.1) * vec3(127.1, 311.7, 74.7)) * 43758.5453); }
float bayer4(vec2 p) {
    ivec2 q = ivec2(p) & 3;
    int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
    return (float(m[q.y * 4 + q.x]) + 0.5) / 16.0;
}
vec3 esaGrad(float x) { return mix(GOLD, PURP, clamp(x, 0.0, 1.0)); }
// 16-entry cycling palette for plasma/tunnel: gold -> purple -> deep -> royal -> gold
vec3 cyclePal(float x) {
    x = fract(x);
    if (x < 0.30) return mix(GOLD, PURP, x / 0.30);
    if (x < 0.55) return mix(PURP, DEEP, (x - 0.30) / 0.25);
    if (x < 0.78) return mix(DEEP, ROYAL, (x - 0.55) / 0.23);
    return mix(ROYAL, GOLD, (x - 0.78) / 0.22);
}

// ------------------------------------------------------------------ 8x8 text
float glyphAt(int item, vec2 q, float len) {  // q in glyph pixels
    if (q.x < 0.0 || q.y < 0.0 || q.y >= 8.0 || q.x >= len * 8.0) return 0.0;
    int col = int(q.x / 8.0);
    int ch = int(texelFetch(uStr, ivec2(col, item), 0).r * 255.0 + 0.5);
    ivec2 g = ivec2(mod(q, 8.0));
    return texelFetch(uFont8, ivec2((ch % 16) * 8 + g.x, (ch / 16) * 8 + g.y), 0).r;
}
vec3 styleCol(int style, float gy) {
    if (style == 1 || style == 5) {  // ESA chrome: lavender sky, white horizon, gold ground
        const vec3 C[8] = vec3[](vec3(0.62, 0.40, 1.0), vec3(0.78, 0.62, 1.0), vec3(0.92, 0.86, 1.0), vec3(1.0),
                                 vec3(1.0, 0.86, 0.35), GOLD, vec3(0.95, 0.55, 0.08), vec3(0.72, 0.36, 0.05));
        return C[int(clamp(gy, 0.0, 7.0))];
    }
    if (style == 2) return UIGOLD;
    if (style == 3) return LAV;
    if (style == 4) return vec3(0.25, 0.86, 0.40);
    if (style == 6) return vec3(0.95, 0.30, 0.30);
    if (style == 7) return vec3(0.62, 0.60, 0.70);
    return vec3(1.0);
}
vec3 drawTexts(vec2 p, vec3 col) {
    for (int i = 0; i < 24; i++) {
        if (i >= uTxtN) break;
        vec4 P = uTxt[i];
        float len = uTxtX[i].x, a = uTxtX[i].y;
        int style = int(P.w + 0.5);
        vec2 q = (p - P.xy) / P.z;
        if (style == 5) q.y -= sin(p.x * 0.035 + uT * 4.2) * 14.0 / P.z;  // sine scroller
        float on = glyphAt(i, floor(q), len);
        float sh = glyphAt(i, floor(q - vec2(1.0)), len);
        if (sh > 0.5 && on < 0.5) col = mix(col, col * 0.15, a);
        if (on > 0.5) col = mix(col, styleCol(style, fract(q.y / 8.0) * 8.0), a);
    }
    return col;
}

// ------------------------------------------------------------------ cube (cube space [0,1]^3)
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
// returns rgb + hit; lit = how much to light by the world normal (0 at the logo snap)
vec4 traceCube(vec3 ro, vec3 rd, float lit, mat3 toWorld) {
    vec3 inv = 1.0 / rd;
    vec3 t0 = (vec3(0.0) - ro) * inv, t1 = (vec3(1.0) - ro) * inv;
    vec3 tmn = min(t0, t1), tmx = max(t0, t1);
    float tn = max(max(tmn.x, tmn.y), tmn.z), tf = min(min(tmx.x, tmx.y), tmx.z);
    if (tn > tf || tf < 0.0) return vec4(0.0);
    vec3 p = ro + rd * tn, n;
    if (tn == tmn.x) n = vec3(-sign(rd.x), 0, 0); else if (tn == tmn.y) n = vec3(0, -sign(rd.y), 0); else n = vec3(0, 0, -sign(rd.z));
    vec4 c = faceColor(p, n);
    if (c.a < 0.5) {  // through a cut-out: the dark inside of the cube
        vec3 pf = ro + rd * tf;
        c = vec4(DEEP * 1.25, 1.0);
    }
    vec3 nw = toWorld * n;
    float l = 0.72 + 0.45 * max(dot(nw, normalize(vec3(-0.4, 0.8, 0.6))), 0.0);
    c.rgb *= mix(1.0, l, lit);
    return vec4(c.rgb, 1.0);
}
vec4 cubePersp(vec3 row, vec3 rdw, float lit) {
    vec3 ro = uCubeRot * (row - uCubeC) / uCubeS + 0.5;
    vec3 rd = uCubeRot * rdw;
    return traceCube(ro, rd, lit, transpose(uCubeRot));
}

// ------------------------------------------------------------------ shared bits
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

// ------------------------------------------------------------------ parts
vec3 partTitle(vec2 p) {
    float boost = smoothstep(2.2, 2.66, uLT);
    vec3 col = stars(p, 0.35 + 2.5 * boost * boost, uT, 1.0);
    col = copper(p, col, uT * 1.3, 90.0, 120.0) * 0.55 + col * 0.45;
    return col;
}

vec3 partDrop(vec2 p) {
    vec2 uv = (p - uRes * 0.5) / (uRes.y * 0.5) * vec2(1.0, -1.0);
    vec3 rd = normalize(uCamRot * vec3(uv * uFov, -1.0));
    const float FY = -0.72;
    vec3 col;
    float hz = rd.y;
    // sky: stepped gradient + copper bars pulsing with the bass
    float sk = floor(clamp(hz * 3.0 + 0.1, 0.0, 1.0) * 10.0) / 10.0;
    col = mix(PURP * 0.55, DEEP * 0.6, sk);
    col = mix(col, copper(p, col, uT, 40.0, 50.0), 0.55 + 0.3 * uEnv.x);
    if (rd.y < 0.0) {
        float t = (FY - uCamPos.y) / rd.y;
        vec3 P = uCamPos + rd * t;
        float scroll = uLT * 2.2 + uKickCum * 1.4;
        vec2 cc = floor(vec2(P.x * 1.25, P.z * 1.25 - scroll));
        float chk = mod(cc.x + cc.y, 2.0);
        vec3 f = chk > 0.5 ? ROYAL : PLUM;
        float lines = step(fract(P.z * 1.25 - scroll), 0.06) * 0.0;
        f += GOLD * 0.35 * uEnv.w * chk;
        // reflection of the cube
        vec3 rr = reflect(rd, vec3(0, 1, 0));
        vec4 rc = cubePersp(P, rr, 1.0);
        f = mix(f, rc.rgb * 0.9, rc.a * 0.45);
        // contact shadow
        float sh = length(P.xz - uCubeC.xz);
        f *= mix(0.45, 1.0, smoothstep(0.35, 0.95, sh));
        float fog = exp(-t * 0.11);
        col = mix(PURP * 0.5, f, fog) + lines;
    }
    vec4 c = cubePersp(uCamPos, rd, 1.0);
    if (c.a > 0.5) col = c.rgb;
    return col;
}

vec3 partPlasma(vec2 p) {
    float t = uT;
    vec2 q = floor(p / 2.0) * 2.0;  // chunky 2x2 plasma like a real-time 160x120 effect
    float v = sin(q.x * 0.045 + t * 1.3) + sin(q.y * 0.061 - t * 0.9) + sin((q.x + q.y) * 0.031 + t * 0.7)
            + sin(length(q - vec2(160.0 + 80.0 * sin(t * 0.6), 120.0 + 60.0 * cos(t * 0.5))) * 0.065);
    float idx = floor(fract(v * 0.18 + t * 0.12) * 16.0) / 16.0;
    vec3 col = cyclePal(idx) * (0.75 + 0.35 * uEnv.x);
    // text band with raster lines
    float band = smoothstep(84.0, 88.0, p.y) * (1.0 - smoothstep(140.0, 144.0, p.y));
    vec3 bc = mix(DEEP * 0.6, DEEP * 1.1, mod(floor(p.y / 2.0), 2.0));
    col = mix(col, bc, band * 0.85);
    if (abs(p.y - 86.0) < 1.0 || abs(p.y - 142.0) < 1.0) col = mix(GOLD, CREAM, 0.5 + 0.5 * sin(p.x * 0.1 - t * 8.0));
    return col;
}

float layerH(float x, float a, float b, float c) { return a + b * sin(x * c) + b * 0.45 * sin(x * c * 2.7 + 1.3); }
vec3 partStage(vec2 p) {
    float sp = uLT * 150.0 + uKickCum * 40.0;
    vec3 col;
    // sky: dusk bands (MD-style stepped gradient)
    float sb = floor(p.y / 12.0) * 12.0 / 150.0;
    col = mix(DEEP, PURP * 0.75, clamp(sb, 0.0, 1.0));
    col = mix(col, vec3(1.0, 0.45, 0.25), smoothstep(0.55, 1.05, sb));
    // sun with synthwave cuts
    vec2 sd = p - vec2(236.0, 104.0);
    float sr = length(sd);
    if (sr < 36.0) {
        bool cut = sd.y > 0.0 && mod(p.y, 7.0) < (sd.y / 36.0) * 4.0 + 0.5;
        if (!cut) col = mix(GOLD, vec3(1.0, 0.35, 0.3), clamp((sd.y + 36.0) / 72.0, 0.0, 1.0));
    }
    // far mountains
    float x1 = p.x + sp * 0.12;
    if (p.y > layerH(x1, 118.0, 16.0, 0.021)) col = mix(PLUM, ROYAL * 0.8, step(0.5, fract(x1 / 64.0)) * 0.0) * 0.95;
    // mid hills: checkered, with heat-wave line scroll
    float x2 = p.x + sp * 0.42 + sin(p.y * 0.35 + uT * 7.0) * 1.2;
    float h2 = layerH(x2, 150.0, 12.0, 0.017);
    if (p.y > h2) {
        vec2 c2 = floor(vec2(x2, p.y - h2) / 12.0);
        col = mod(c2.x + c2.y, 2.0) > 0.5 ? ROYAL : PLUM;
        if (p.y - h2 < 3.0) col = GOLD * 0.85;
    }
    // ground: Green-Hill-ish checks in ESA gold, grass lip in purple
    float gy = 198.0;
    if (p.y > gy) {
        float x3 = p.x + sp;
        vec2 c3 = floor(vec2(x3 / 16.0, (p.y - gy) / 8.0));
        col = mod(c3.x + c3.y, 2.0) > 0.5 ? vec3(0.70, 0.37, 0.05) : vec3(0.47, 0.22, 0.04);
        if (p.y - gy < 5.0) col = mix(PURP, LAV, step(p.y - gy, 1.0));
    }
    // runner: the ESA cube hopping every other beat, with a speed-shoes afterimage trail
    float jb = fract(uBeat / 2.0);
    for (int k = 3; k >= 0; k--) {
        float ph = fract((uBeat - float(k) * 0.12) / 2.0);
        float jump = 44.0 * 4.0 * ph * (1.0 - ph);
        vec2 o = vec2(182.0 - float(k) * 11.0, gy - 30.0 - jump);
        vec2 lp = (p - o) / 30.0;
        if (lp.x >= 0.0 && lp.y >= 0.0 && lp.x < 1.0 && lp.y < 1.0) {
            vec4 l = texture(uLogo, (lp - 0.5) * 0.92 + 0.5);
            float a = k == 0 ? 1.0 : 0.45 - float(k) * 0.1;
            if (l.a > 0.5) col = mix(col, k == 0 ? l.rgb : mix(PURP, LAV, 0.4), a);
        }
    }
    // LiveSplit panel
    if (p.x > 4.0 && p.x < 156.0 && p.y > 4.0 && p.y < 130.0) {
        col = mix(col, DEEP * 0.55, 0.82);
        if (p.y > 30.0 && p.y < 31.0) col = ROYAL;
        float cur = 34.0 + 5.0 * 10.0;  // highlighted current split row
        if (p.y > cur - 2.0 && p.y < cur + 9.0) col = mix(col, PURP * 0.6, 0.8);
    }
    return col;
}

vec3 partTunnel(vec2 p) {
    vec2 ctr = uRes * 0.5 + vec2(sin(uT * 0.7) * 34.0, cos(uT * 0.9) * 22.0);
    vec2 c = (p - ctr) / uRes.y;
    float r = length(c), a = atan(c.y, c.x);
    float z = 0.22 / max(r, 1e-3) + uLT * 2.6 + uKickCum * 0.9;
    float u = (a / (2.0 * PI) + 0.5) * 6.0 + uLT * 0.35;
    int face = int(mod(floor(u), 3.0));
    vec2 fuv = vec2(fract(u), fract(z));
    vec4 tx = face == 0 ? texture(uTop, fuv) : face == 1 ? texture(uLeft, fuv) : texture(uRight, fuv);
    vec3 col = mix(DEEP, tx.rgb, tx.a);
    // tint the white faces into the brand purples so the tube reads as colour, not paper
    float wht = smoothstep(0.75, 0.95, min(col.r, min(col.g, col.b)));
    col = mix(col, mix(ROYAL, LAV, fract(z) * 0.6), wht * 0.85);
    col *= 0.55 + 0.45 * step(0.5, fract(z * 0.5));   // alternating ring shading
    // bright ring on each kick travelling down the tube
    col += GOLD * 0.6 * uEnv.w * step(fract(z * 0.5), 0.08);
    col *= smoothstep(0.02, 0.45, r) * 0.9;   // depth fog
    return col;
}

vec3 partFinale(vec2 p) {
    // background: brand halo + slow stars
    vec2 hc = p - vec2(uLogoPos.x, uLogoPos.y + 20.0);
    float h = exp(-dot(hc, hc) / (2.0 * 95.0 * 95.0));
    vec3 col = mix(DEEP * 0.55, PURP * 0.55, h * (0.7 + 0.3 * sin(uT * 1.7)));
    col += stars(p, 0.06, uT, 0.6) * (1.0 - h * 0.6);
    col = floor(col * 16.0 + bayer4(p) * 0.0) / 16.0;

    // cube: perspective flight blended into the logo's own parallel projection
    vec2 uv = (p - uRes * 0.5) / (uRes.y * 0.5) * vec2(1.0, -1.0);
    vec3 rdw = normalize(uCamRot * vec3(uv * uFov, -1.0));
    vec3 roP = uCubeRot * (uCamPos - uCubeC) / uCubeS + 0.5, rdP = uCubeRot * rdw;
    vec3 roA = uAffP0 * (p.x - uAffS0.x) + uAffP1 * (p.y - uAffS0.y) - uAffD * 4.0, rdA = uAffD;
    float s = uSnap;
    vec4 c = traceCube(mix(roP, roA, s), normalize(mix(rdP, rdA, s)), 1.0 - s, transpose(uCubeRot));
    if (uLogoA < 0.5 && c.a > 0.5) col = c.rgb;

    // after the hit: the real 2D logo (with its keyline) and the wordmark
    if (uLogoA > 0.5) {
        vec2 lu = ((p - uLogoPos.xy) / uLogoPos.z + vec2(250.0, 249.53) + 50.0) / 600.0;
        if (lu.x >= 0.0 && lu.y >= 0.0 && lu.x <= 1.0 && lu.y <= 1.0) {
            vec4 l = texture(uLogo, lu);
            col = mix(col, l.rgb, smoothstep(0.35, 0.65, l.a));
        }
        vec2 wsz = vec2(textureSize(uWord, 0));
        float ww = 200.0 * uWordAS.y, wh = ww * wsz.y / wsz.x;
        vec2 wo = vec2(160.0 - ww * 0.5, 162.0 - wh * 0.5);
        vec2 wu = (p - wo) / vec2(ww, wh);
        float px = 1.0 / ww;
        float m = 0.0, ol = 0.0;
        if (wu.x > -0.05 && wu.x < 1.05 && wu.y > -0.2 && wu.y < 1.2) {
            m = texture(uWord, wu).r;
            for (int k = 0; k < 8; k++) {
                vec2 d = vec2(cos(float(k) * PI / 4.0), sin(float(k) * PI / 4.0)) * vec2(2.2 * px, 2.2 / wh);
                ol = max(ol, texture(uWord, wu + d).r);
            }
        }
        if (ol > 0.5) col = mix(col, vec3(0.227, 0.149, 0.341), uWordAS.x);
        if (m > 0.5) {
            float gy = clamp(wu.y, 0.0, 1.0);
            vec3 g = gy < 0.55 ? mix(UIGOLD, vec3(1.0, 0.85, 0.41), gy / 0.55) : mix(vec3(1.0, 0.85, 0.41), CREAM, (gy - 0.55) / 0.45);
            float glint = step(abs(wu.x * ww - wu.y * wh * 0.6 - (fract(uT * 0.35) * 420.0 - 60.0)), 5.0);
            col = mix(col, mix(g, vec3(1.0), glint * 0.7), uWordAS.x);
        }
    }
    return col;
}

void main() {
    vec2 p = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y);  // pixel coords, y down
    vec3 col = vec3(0.0);
    if (uBlackout == 1) { o = vec4(0, 0, 0, 1); return; }
    if (uScene == 1) col = partTitle(p);
    else if (uScene == 2) col = partDrop(p);
    else if (uScene == 3) col = partPlasma(p);
    else if (uScene == 4) col = partStage(p);
    else if (uScene == 5) col = partTunnel(p);
    else if (uScene == 6) col = partFinale(p);
    col = drawTexts(p, col);
    col = mix(col, vec3(1.0), uFlash);

    // Mega Drive 9-bit output: 8 non-linear DAC levels per channel, ordered dither
    const float LV[8] = float[](0.0, 0.204, 0.341, 0.455, 0.565, 0.675, 0.808, 1.0);
    float th = bayer4(p);
    vec3 outc;
    for (int ch = 0; ch < 3; ch++) {
        float v = clamp(col[ch], 0.0, 1.0);
        int i = 0;
        for (int k = 0; k < 7; k++) if (v >= LV[k + 1]) i = k + 1;
        float q = LV[i];
        if (i < 7) { float f = (v - LV[i]) / (LV[i + 1] - LV[i]); q = f > th ? LV[i + 1] : LV[i]; }
        outc[ch] = q;
    }
    o = vec4(outc, 1.0);
}
