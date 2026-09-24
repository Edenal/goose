// @id boss
// @name BOSS FIGHT
// @split BOSS
// @bars 8
// @order 260
// @default off
// @inspired 16-bit shmup / Mega Drive boss battles
// @desc A two-round 16-bit boss rush with WARNING banners and boss HP bars: Goosebert honks THE WORLD into a K.O., then Plum beams THE VOID shut for a new PB.
// @str 0 WARNING!
// @str 1 GOOSEBERT
// @str 2 VS
// @str 3 THE WORLD
// @str 4 HONK!
// @str 5 K.O.!
// @str 6 HAS BEEN HONKED
// @str 7 ROUND 2
// @str 8 PLUM
// @str 9 THE VOID
// @str 10 VOID CLEARED
// @str 11 STAGE CLEAR
// @str 12 NEW PB!
// @str 13 FIGHT!
// @str 14 ROUND 1
// @str 15 A BOSS APPROACHES

// ---------------------------------------------------------------- timeline, in local beats (b = uLT * 1.5, 0..32)
//  0- 2 WARNING banner        2- 5.5 VS card (GOOSEBERT VS THE WORLD)      5.3 FIGHT!
//  HONK hits land on 6 8 10 12 14 (14 = K.O.), world volleys on 5 7 9 11 13, chain explosions 14-15, big boom 15
// 16-19 ROUND 2 card (PLUM VS THE VOID), beams charge over 19/23/27 and fire on the bar lines 20 24 28
// 28.8-29.5 the void implodes, 29.5 white flash, then VOID CLEARED / STAGE CLEAR / NEW PB!

const vec3 INK = vec3(0.04, 0.02, 0.07);
const float BS_CLEAR = 29.5;                   // beat the void is gone (the PB time)

// ---------------------------------------------------------------- sprites: one hex digit = one pixel (palette index)
// GOOSEBERT, 16x19, facing right, with an ESA-purple scarf.
// 0 clear  1 outline  2 white  3 grey  4 orange  5 dark orange  6 red (open beak)  7 scarf purple
const uint GOOSE[38] = uint[](
    0x00000000u,0x00111000u,
    0x00000000u,0x01222100u,
    0x00000000u,0x01212110u,
    0x00000000u,0x01222441u,
    0x00000000u,0x01222151u,
    0x00000000u,0x00122110u,
    0x00000000u,0x00122100u,
    0x00000000u,0x00177100u,
    0x00000000u,0x01777710u,
    0x01100000u,0x01272210u,
    0x12210000u,0x12272210u,
    0x12221111u,0x22222210u,
    0x13222222u,0x22222210u,
    0x13322333u,0x33222310u,
    0x01332223u,0x33223100u,
    0x00113333u,0x33331000u,
    0x00001111u,0x11110000u,
    0x00000040u,0x00400000u,
    0x00000444u,0x04440000u);
// rows 1-5 of the HONK frame (beak wide open)
const uint GHONK[10] = uint[](
    0x00000000u,0x01222111u,
    0x00000000u,0x01212144u,
    0x00000000u,0x01222166u,
    0x00000000u,0x01222144u,
    0x00000000u,0x00122111u);
// PLUM, 16x18, facing right: stem + leaf, gold headband, determined eyes.
// 0 clear  1 outline  2 purple  3 dark plum  4 highlight  5 leaf  6 dark leaf  7 white  8 stem  9 gold
const uint PLUMS[36] = uint[](
    0x00000000u,0x00111000u,
    0x00000011u,0x01555100u,
    0x00000018u,0x15556100u,
    0x00000001u,0x81661000u,
    0x00000111u,0x81110000u,
    0x00011222u,0x22221100u,
    0x00124422u,0x22222210u,
    0x01244222u,0x22222231u,
    0x19999999u,0x99999991u,
    0x12999999u,0x99999991u,
    0x01211122u,0x22111231u,
    0x01277112u,0x21177231u,
    0x01271722u,0x22717231u,
    0x01222222u,0x22222331u,
    0x01222211u,0x11122331u,
    0x00122222u,0x22233310u,
    0x00011333u,0x33331100u,
    0x00000111u,0x11110000u);

int bsNib(uint w, int x) { return int((w >> uint(4 * (7 - x))) & 15u); }

vec3 gooseCol(int i) {
    if (i == 1) return INK;
    if (i == 2) return vec3(1.0, 0.98, 0.94);
    if (i == 3) return vec3(0.64, 0.62, 0.74);
    if (i == 4) return vec3(1.0, 0.56, 0.08);
    if (i == 5) return vec3(0.72, 0.28, 0.04);
    if (i == 6) return vec3(0.86, 0.10, 0.22);
    return PURP;
}
vec3 plumCol(int i) {
    if (i == 1) return INK;
    if (i == 2) return PURP;
    if (i == 3) return vec3(0.30, 0.07, 0.52);
    if (i == 4) return LAV;
    if (i == 5) return vec3(0.35, 0.86, 0.30);
    if (i == 6) return vec3(0.10, 0.50, 0.20);
    if (i == 7) return vec3(1.0);
    if (i == 8) return vec3(0.50, 0.28, 0.10);
    return GOLD;
}
// goose centred at c, scale sc; honk = open beak, step = which foot is forward; tint = hit flash
vec3 drawGoose(vec3 col, vec2 p, vec2 c, float sc, bool honk, int stp, vec3 tint, float ta) {
    ivec2 g = ivec2(floor((p - floor(c - vec2(8.0, 9.5) * sc)) / sc));
    if (g.x < 0 || g.y < 0 || g.x >= 16 || g.y >= 19) return col;
    if (stp == 1 && g.y >= 17) g.x += g.x < 8 ? -1 : 1;           // waddle: feet swap places
    if (g.x < 0 || g.x >= 16) return col;
    uint w = (honk && g.y >= 1 && g.y <= 5) ? GHONK[(g.y - 1) * 2 + g.x / 8] : GOOSE[g.y * 2 + g.x / 8];
    int i = bsNib(w, g.x % 8);
    if (i == 0) return col;
    return mix(gooseCol(i), tint, i == 1 ? 0.0 : ta);
}
vec3 drawPlum(vec3 col, vec2 p, vec2 c, float sc, vec3 tint, float ta) {
    ivec2 g = ivec2(floor((p - floor(c - vec2(8.0, 9.0) * sc)) / sc));
    if (g.x < 0 || g.y < 0 || g.x >= 16 || g.y >= 18) return col;
    int i = bsNib(PLUMS[g.y * 2 + g.x / 8], g.x % 8);
    if (i == 0) return col;
    return mix(plumCol(i), tint, i == 1 ? 0.0 : ta);
}

// ---------------------------------------------------------------- text with a 1-2 px ink outline
vec3 bsStyle(int s, float gy) {
    if (s == 100) {   // hazard red
        if (gy < 2.0) return vec3(1.0, 0.72, 0.62);
        if (gy < 6.0) return vec3(1.0, 0.16, 0.20);
        return vec3(0.62, 0.02, 0.10);
    }
    if (s == 101) {   // fire: cream -> gold -> orange -> red
        if (gy < 2.0) return CREAM;
        if (gy < 4.0) return GOLD;
        if (gy < 6.0) return vec3(1.0, 0.46, 0.08);
        return vec3(0.88, 0.12, 0.16);
    }
    if (s == 102) return vec3(0.86, 0.08, 0.20);   // flat red, for the speech bubble
    return styleCol(s, gy);
}
vec3 bsTxt(vec3 col, vec2 p, int row, vec2 pos, float sc, int style, int maxC) {
    vec2 q = (p - pos) / sc;
    float w = float(min(strLen(row), maxC)) * 8.0, m = 3.0 / sc;
    if (q.x < -m || q.y < -m || q.x >= w + m || q.y >= 8.0 + m) return col;
    if (strAt(row, floor(q), 0, maxC) > 0.5) return bsStyle(style, q.y);
    float k = sc >= 2.0 ? 2.0 : 1.0, o = 0.0;
    for (int i = 0; i < 8; i++) {
        vec2 d = floor(vec2(cos(float(i) * 0.7854), sin(float(i) * 0.7854)) * k + 0.5);
        o = max(o, strAt(row, floor((p + d - pos) / sc), 0, maxC));
    }
    return o > 0.5 ? INK : col;
}
float bsCX(int row, float sc) { return floor((uRes.x - strW(row, sc)) * 0.5); }
vec3 bsTxtC(vec3 col, vec2 p, int row, float y, float sc, int style) { return bsTxt(col, p, row, vec2(bsCX(row, sc), y), sc, style, 256); }

// ---------------------------------------------------------------- shared bits
float segD(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}
// glowing orb bullet on a 2 px grid
void orb(inout vec3 col, vec2 q, vec2 c, float r, vec3 body, vec3 rim) {
    float d = length(floor(q / 2.0) * 2.0 + 1.0 - c);
    if (d < r * 0.45) col = CREAM;
    else if (d < r) col = body;
    else if (d < r + 2.0) col = mix(col, rim, 0.75);
}
// 16-bit fireball: t 0..1 over its life
vec3 boom(vec3 col, vec2 q, vec2 c, float t, float size, float seed) {
    if (t < 0.0 || t > 1.0) return col;
    vec2 d = floor(q / 2.0) * 2.0 + 1.0 - c;
    float L = length(d), a = atan(d.y, d.x);
    float r = size * easeOut(t * 1.7) * (1.0 + 0.16 * sin(a * 7.0 + seed * 9.0) + 0.1 * sin(a * 13.0 - seed * 5.0));
    float inner = size * max(0.0, t - 0.4) * 1.6;
    if (L > r || L < inner) return col;
    float x = (L - inner) / max(r - inner, 1.0) + t * 0.6;
    vec3 f = x < 0.35 ? CREAM : x < 0.6 ? GOLD : x < 0.85 ? vec3(1.0, 0.45, 0.08) : x < 1.15 ? vec3(0.85, 0.12, 0.18) : vec3(0.30, 0.10, 0.34);
    return f;
}
// stepped HP drain for hits at h0, h0+dh, ... ; lag = the white chunk that catches up later
float hpSteps(float b, float h0, float dh, int n, float per, float lag) {
    float s = 0.0;
    for (int i = 0; i < 6; i++) {
        if (i >= n) break;
        float h = h0 + dh * float(i) + lag;
        s += smoothstep(h, h + 0.2, b);
    }
    return clamp(1.0 - s * per, 0.0, 1.0);
}

// ---------------------------------------------------------------- backgrounds
vec3 starLayer(vec2 q, float speed, float cell, float dens, vec3 tint) {
    vec2 s = q + vec2(speed, 0.0);
    vec2 cl = floor(s / cell);
    float h = hash2(cl + cell);
    if (h < 1.0 - dens) return vec3(0.0);
    vec2 sp = cl * cell + floor(hash2(cl + 3.7) * (cell - 4.0)) + 2.0;
    vec2 d = abs(s - sp);
    float big = h > 1.0 - dens * 0.3 ? 1.5 : 0.75;
    if (d.x < big && d.y < big) return tint;
    if (big > 1.0 && ((d.x < 3.5 && d.y < 0.6) || (d.y < 3.5 && d.x < 0.6))) return tint * 0.6;   // twinkle cross
    return vec3(0.0);
}
vec3 bgSpace(vec2 q, float b, float warm) {
    float sb = floor(q.y / 8.0) * 8.0 / 240.0;
    vec3 col = mix(DEEP * 0.45, PLUM * 1.1, sb);
    // slow nebula bands
    float nb = sin(q.x * 0.018 + q.y * 0.03 + uLT * 0.3) + sin(q.x * 0.011 - q.y * 0.02 - uLT * 0.2);
    col = mix(col, PURP * 0.45, step(1.2, nb) * 0.5);
    col = mix(col, mix(PURP, GOLD, warm) * 0.35, step(1.65, nb) * 0.6);
    float sp = uLT * 40.0 + uKickCum * 6.0;
    col += starLayer(q, sp * 0.25, 18.0, 0.18, LAV * 0.5);
    col += starLayer(q, sp * 0.7, 26.0, 0.16, LAV);
    col += starLayer(q, sp * 1.8, 40.0, 0.14, CREAM);
    return col;
}
vec3 bgVoid(vec2 q, float b, vec2 vc, float s) {
    vec2 d = q - vc;
    float L = length(d);
    float sw = s * 900.0 / (L + 30.0) * (0.4 + 0.1 * sin(uLT));
    vec2 w = vc + rot2(sw + uLT * 0.2 * s) * d;               // stars swirl around the void
    float sb = floor(q.y / 8.0) * 8.0 / 240.0;
    vec3 col = mix(INK, PLUM * 0.7, sb);
    float a = atan(d.y, d.x);
    float neb = sin(a * 3.0 - log(L + 1.0) * 5.0 + uLT * 2.0);
    col = mix(col, PURP * 0.35, step(0.55, neb) * smoothstep(220.0, 60.0, L) * s);
    float sp = uLT * 20.0;
    col += starLayer(w, sp * 0.3, 20.0, 0.2, LAV * 0.55);
    col += starLayer(w, sp, 30.0, 0.16, CREAM);
    return col;
}

// ---------------------------------------------------------------- THE WORLD
vec3 drawWorld(vec3 col, vec2 q, vec2 c, float R, float b, float flash, vec2 look, float mouth, float red) {
    vec2 qq = floor(q / 2.0) * 2.0 + 1.0;
    vec2 d = (qq - c) / R;
    float L = length(d);
    if (L > 1.0 + 7.0 / R) return col;
    if (L > 1.0 + 3.0 / R) return mix(col, GOLD, 0.35);                 // atmosphere glow
    if (L > 1.0) return INK;
    vec3 n = vec3(d.x, -d.y, sqrt(1.0 - L * L));
    float a = b * 0.45 + uKickCum * 0.05;
    vec3 m = vec3(n.x * cos(a) + n.z * sin(a), n.y, -n.x * sin(a) + n.z * cos(a));
    float h = vnoise(m.xy * 2.4 + 3.1) * 0.5 + vnoise(m.yz * 3.2 + 7.7) * 0.32 + vnoise(m.zx * 6.5 + 1.3) * 0.18;
    vec3 base;
    if (h > 0.52) base = h > 0.60 ? GOLD : vec3(0.28, 0.74, 0.30);
    else base = h > 0.47 ? vec3(0.34, 0.44, 0.98) : vec3(0.26, 0.14, 0.66);
    if (abs(m.y) > 0.84) base = CREAM;
    float lit = dot(n, normalize(vec3(-0.55, 0.6, 0.6)));
    float sh = floor(clamp(lit * 0.55 + 0.5, 0.0, 0.999) * 4.0) / 3.0;
    col = base * (0.32 + 0.78 * sh);
    col = mix(col, vec3(1.0, 0.15, 0.2), red);
    col = mix(col, vec3(1.0), flash * 0.85);
    // ---- the face (drawn on the same 2 px grid)
    float k = R / 46.0;
    for (int e = 0; e < 2; e++) {
        float sg = e == 0 ? 1.0 : -1.0;                                // +1 left eye, -1 right eye
        vec2 ec = c + vec2(e == 0 ? -17.0 : 12.0, -6.0) * k;
        vec2 ed = (qq - ec) / (vec2(8.5, 10.0) * k);
        float el = length(ed);
        float lid = ec.y - 4.0 * k + sg * 0.55 * (qq.x - ec.x);        // angry lid: inner corner lower
        if (el < 1.0 + 2.5 / (8.5 * k)) col = INK;
        if (el < 1.0 && qq.y > lid) {
            col = vec3(1.0);
            if (length(qq - (ec + look * 3.5 * k + vec2(0.0, 1.5 * k))) < 3.6 * k) col = INK;
        }
        vec2 b0 = ec + vec2(-11.0, -16.0 + sg * 5.0) * k, b1 = ec + vec2(10.0, -16.0 - sg * 5.0) * k;
        if (segD(qq, b0, b1) < 3.2 * k) col = INK;
    }
    // mouth: a gritted frown, wide open while firing
    vec2 md = qq - (c + vec2(-3.0, 19.0) * k);
    float hh = (3.5 + 6.0 * mouth) * k, cy = 0.02 * md.x * md.x / k;
    if (abs(md.x) < 15.0 * k && abs(md.y - cy) < hh + 2.0) {
        col = INK;
        if (abs(md.y - cy) < hh) {
            col = vec3(0.45, 0.02, 0.10);
            bool tooth = mod(md.x + 30.0, 6.0) < 4.0 && abs(md.y - cy) > hh - 3.5;
            if (tooth) col = vec3(1.0);
        }
    }
    return col;
}

// ---------------------------------------------------------------- THE VOID
vec3 drawVoid(vec3 col, vec2 q, vec2 c, float s, float b, float hurt, float rage) {
    if (s < 0.004) return col;
    vec2 qq = floor(q / 2.0) * 2.0 + 1.0;
    float gl = hash1(floor(q.y / 3.0) + floor(uLT * 14.0) * 13.0);
    if (gl > 0.92) qq.x += floor((hash1(gl * 91.0) - 0.5) * 8.0) * 2.0;   // glitchy row tears
    vec2 d = (qq - c) / s;
    float r = length(d);
    if (r > 100.0) return col;
    float a = atan(d.y, d.x);
    const float R = 26.0;
    // static fringe
    if (r > 64.0) {
        float st = hash2(floor(qq / 2.0) + floor(uLT * 20.0) * vec2(7.0, 3.0));
        float dens = smoothstep(100.0, 74.0, r) * 0.6;
        if (st < dens * 0.22) col = LAV;
        else if (st < dens * 0.5) col = vec3(0.36, 0.30, 0.46);
        else if (st < dens) col *= 0.3;
    }
    // particles being pulled in
    for (int i = 0; i < 28; i++) {
        vec3 h = hash3(float(i) * 3.1 + 5.0);
        float ph = fract(h.z + b * 0.28 + h.x * 0.5);
        float rr = R + 120.0 * pow(1.0 - ph, 1.4);
        float an = h.y * 6.2832 + 5.0 * ph * ph;
        vec2 pp = c + vec2(cos(an), sin(an)) * rr * s;
        vec2 dd = abs(q - pp);
        if (max(dd.x, dd.y) < 1.6) col = h.x > 0.5 ? GOLD : LAV;
    }
    // accretion disk: spiral arms swirling inward
    if (r < 78.0) {
        float t = clamp((r - R) / (78.0 - R), 0.0, 1.0);
        float ph = 2.0 * a - 9.0 * log(max(r, 1.0)) + b * (4.0 + 12.0 * (1.0 - s)) + uKickCum * 0.25;
        float arm = 0.5 + 0.5 * sin(ph);
        float tone = arm * (1.05 - t) + 0.3 * (1.0 - t);
        vec3 dc = tone > 0.78 ? CREAM : tone > 0.6 ? GOLD : tone > 0.42 ? PURP : tone > 0.22 ? ROYAL * 0.75 : PLUM * 0.7;
        float al = 1.0 - smoothstep(0.55, 1.0, t);
        col = mix(col, dc, step(bayer4(qq * 0.5), al));
        if (hurt > 0.0 && tone > 0.42) col = mix(col, CREAM, hurt * step(0.5, fract(uLT * 15.0)) * 0.6);
    }
    if (r < R + 3.0) col = mix(GOLD, CREAM, step(R + 1.5, r));        // photon ring
    if (r < R) {
        col = vec3(0.015, 0.0, 0.035);
        // menacing eyes in the dark
        for (int e = 0; e < 2; e++) {
            float sg = e == 0 ? 1.0 : -1.0;
            vec2 ec = c + vec2(-10.0 * sg, -5.0) * s;
            vec2 ed = rot2(0.42 * sg) * (qq - ec) / s;
            float ry = mix(2.8, 1.0, hurt) + rage * 0.8;
            float el = length(ed / vec2(6.5, ry));
            if (el < 2.2) col = mix(col, PURP * 0.6, 0.6);
            if (el < 1.0) col = abs(ed.x + 1.0) < 1.1 ? INK : (el < 0.5 ? CREAM : vec3(1.0, 0.25, 0.42));
        }
        // a thin toothy grin
        vec2 md = (qq - c) / s - vec2(0.0, 9.0);
        float gy = -0.035 * md.x * md.x;
        if (abs(md.x) < 12.0 && md.y > gy - 1.0 && md.y < gy + 2.5 - 1.3 * abs(mod(md.x + 12.0, 4.0) - 2.0))
            col = mix(vec3(0.7, 0.62, 0.9), CREAM, rage);
    }
    return col;
}

// ---------------------------------------------------------------- HUD
vec3 hpBar(vec3 col, vec2 p, float x0, float x1, float y, float hp, float lag, bool fromRight, float flash) {
    if (p.y < y - 1.0 || p.y > y + 8.0 || p.x < x0 - 1.0 || p.x > x1 + 1.0) return col;
    if (p.y < y || p.y > y + 7.0 || p.x < x0 || p.x > x1) return INK;
    float w = x1 - x0;
    float u = fromRight ? (x1 - p.x) / w : (p.x - x0) / w;
    col = vec3(0.22, 0.04, 0.10);
    vec3 fc = hp > 0.5 ? vec3(0.25, 0.88, 0.35) : hp > 0.25 ? GOLD : vec3(1.0, 0.22, 0.22);
    if (u < lag) col = vec3(1.0, 0.85, 0.85);
    if (u < hp) col = mix(fc, vec3(1.0), flash);
    if (p.y < y + 2.0 && u < max(hp, lag)) col = mix(col, vec3(1.0), 0.45);   // shine
    if (mod(p.x - x0, 6.0) < 1.0) col *= 0.35;                                   // segments
    return col;
}
vec3 hud(vec3 col, vec2 p, float b, bool r2, float hpL, float lagL, float hpR, float lagR, float flR) {
    if (p.y > 29.0) return col;
    if (p.y < 27.0) col = mix(col, INK, 0.78);
    else col = GOLD;
    int lRow = r2 ? 8 : 1, rRow = r2 ? 9 : 3;
    col = bsTxt(col, p, lRow, vec2(8.0, 3.0), 1.0, TS_WHITE, 256);
    col = bsTxt(col, p, rRow, vec2(312.0 - strW(rRow, 1.0), 3.0), 1.0, TS_GOLD, 256);
    col = hpBar(col, p, 8.0, 140.0, 14.0, hpL, lagL, false, 0.0);
    col = hpBar(col, p, 180.0, 312.0, 14.0, hpR, lagR, true, flR);
    vec4 lg = logoAt(p, vec2(160.0, 14.0), 22.0);
    return mix(col, lg.rgb, lg.a);
}

// ---------------------------------------------------------------- title cards
vec3 hazardBand(vec3 col, vec2 p, float y0, float y1, float open, float blink) {
    float yc = (y0 + y1) * 0.5, hh = (y1 - y0) * 0.5 * open;
    if (abs(p.y - yc) > hh) return col;
    col = mix(col, mix(vec3(0.20, 0.0, 0.04), vec3(0.42, 0.02, 0.08), blink), 0.88);
    float e = hh - abs(p.y - yc);
    if (e < 10.0) col = mod(p.x + p.y - uLT * 60.0, 16.0) < 8.0 ? GOLD : INK;
    if (e < 1.0) col = INK;
    return col;
}
vec3 vsCard(vec3 col, vec2 p, float t, int rowL, int rowR, int rowTop, float tx) {
    // t: 0 = start, panels in by 1.2, VS pops at 1.3, exit from 3.0 to 3.5
    float inL = easeOut(t / 1.1) - easeOut((t - tx) / 0.45);
    float sx = (1.0 - inL) * 340.0;
    // top panel from the left
    vec2 a = vec2(p.x + sx, p.y);
    if (p.y > 62.0 && p.y < 108.0 && a.x < 300.0 - (p.y - 62.0) * 0.5) {
        col = mix(PURP * 0.9, PLUM, step(85.0, p.y));
        if (p.y < 65.0 || p.y > 105.0) col = GOLD;
        col = bsTxt(col, a, rowL, vec2(18.0, 73.0), 3.0, TS_CHROME, 256);
    }
    // bottom panel from the right
    vec2 bq = vec2(p.x - sx, p.y);
    if (p.y > 132.0 && p.y < 178.0 && bq.x > 20.0 + (178.0 - p.y) * 0.5) {
        col = mix(vec3(0.62, 0.08, 0.14), vec3(0.34, 0.03, 0.10), step(155.0, p.y));
        if (p.y < 135.0 || p.y > 175.0) col = GOLD;
        col = bsTxt(col, bq, rowR, vec2(302.0 - strW(rowR, 3.0), 143.0), 3.0, TS_CHROME, 256);
    }
    // VS burst
    float v = t - 1.3;
    if (v > 0.0 && t < tx + 0.1) {
        vec2 d = p - vec2(160.0, 120.0);
        float an = atan(d.y, d.x);
        float rr = (26.0 + 8.0 * step(0.5, fract(an * 16.0 / 6.2832 + uLT))) * easeOut(v / 0.25);
        if (length(d) < rr) col = mix(GOLD, CREAM, step(length(d), rr * 0.6));
        if (length(d) < rr && length(d) > rr - 2.0) col = INK;
        col = bsTxtC(col, p, 2, 108.0, 3.0, 101);
    }
    if (t > 0.3 && t < tx + 0.2) col = bsTxtC(col, p, rowTop, 44.0, rowTop == 7 ? 2.0 : 1.0, TS_GOLD);
    return col;
}

// ---------------------------------------------------------------- the two rounds
vec2 goosePos(float b) {
    float x = 66.0 - 140.0 * (1.0 - easeOut(b / 1.8));
    float seg = floor(b / 2.0);
    float y0 = (hash1(seg + 3.0) - 0.5) * 84.0, y1 = (hash1(seg + 4.0) - 0.5) * 84.0;
    float y = 138.0 + mix(y0, y1, smoothstep(0.9, 1.5, fract(b / 2.0) * 2.0)) * smoothstep(4.5, 6.0, b) * (1.0 - smoothstep(14.0, 15.0, b));
    y -= 6.0 * sin(PI * fract(b));                       // hop, landing on every beat
    return vec2(x, y);
}
vec2 plumPos(float b) {
    float x = 58.0 - 140.0 * (1.0 - easeOut((b - 16.0) / 1.8));
    float seg = floor(b / 2.0);
    float y0 = (hash1(seg + 11.0) - 0.5) * 90.0, y1 = (hash1(seg + 12.0) - 0.5) * 90.0;
    float y = 136.0 + mix(y0, y1, smoothstep(1.1, 1.7, fract(b / 2.0) * 2.0)) * smoothstep(18.5, 19.5, b);
    y -= 5.0 * sin(PI * fract(b));
    return vec2(x, y);
}

vec3 round1(vec3 col, vec2 q, float b, inout float flR) {
    vec2 gp = goosePos(b);
    vec2 beak = gp + vec2(22.0, -19.0);
    float enter = easeOut((b - 1.0) / 3.0);
    vec2 wc = vec2(240.0 + 170.0 * (1.0 - enter), 140.0 + 8.0 * sin(b * PI * 0.5));
    const float WR = 46.0;
    // flashes on the hits
    float flash = 0.0;
    for (int i = 0; i < 5; i++) {
        float t = b - (6.0 + 2.0 * float(i));
        if (t >= 0.0 && t < 0.3) flash = step(0.5, fract(t * 8.0 + 0.5));
    }
    flR = flash;
    float red = b > 14.0 && b < 15.2 ? step(0.5, fract(b * 6.0)) * 0.7 : 0.0;
    float volley = 0.0;
    for (int i = 0; i < 5; i++) { float t = b - (5.0 + 2.0 * float(i)); if (t > -0.3 && t < 0.5) volley = 1.0; }
    vec2 look = normalize(gp - wc + vec2(0.0, 1e-3));
    if (b < 15.15) col = drawWorld(col, q, wc + (b > 14.0 ? vec2(hash1(floor(uLT * 30.0)) - 0.5, 0.0) * 6.0 : vec2(0.0)),
                                   WR, b, flash, look, volley, red);
    // bullets: rings on the off beats + a two-arm spiral stream
    if (b > 5.0 && b < 18.0) {
        for (int v = 0; v < 5; v++) {
            float te = 5.0 + 2.0 * float(v), t = b - te;
            if (t < 0.0 || t > 4.0) continue;
            float rr = WR + 4.0 + t * 72.0;
            float an = atan(q.y - wc.y, q.x - wc.x);
            float n = 14.0, j = floor((an - float(v) * 0.23) / 6.2832 * n + 0.5);
            float aj = j * 6.2832 / n + float(v) * 0.23;
            orb(col, q, wc + vec2(cos(aj), sin(aj)) * rr, 4.5, vec3(1.0, 0.45, 0.10), vec3(1.0, 0.2, 0.25));
        }
        for (int e = 0; e < 18; e++) {
            float te = floor(b * 6.0) / 6.0 - float(e) / 6.0;
            if (te < 5.5 || te > 13.8) continue;
            float t = b - te, rr = WR + 2.0 + t * 95.0;
            for (int arm = 0; arm < 2; arm++) {
                float aj = te * 6.0 * 0.42 + float(arm) * PI;
                orb(col, q, wc + vec2(cos(aj), sin(aj)) * rr, 3.0, GOLD, PURP);
            }
        }
    }
    // HONK shockwaves: emitted 0.7 beats before each hit, landing on the beat
    bool honk = false;
    for (int i = 0; i < 6; i++) {
        float h = i < 5 ? 6.0 + 2.0 * float(i) : 15.4;
        float t = b - (h - 0.7);
        if (t > -0.1 && t < 0.5) honk = true;
        if (i < 5 && t > 0.0 && t < 0.7) {
            vec2 dd = q - beak;
            vec2 dir = normalize(wc - beak);
            float D = length(wc - beak) - WR * 0.6;
            float ang = acos(clamp(dot(normalize(dd + 1e-3), dir), -1.0, 1.0));
            for (int k = 0; k < 3; k++) {
                float R = D * t / 0.7 - float(k) * 11.0;
                if (R < 4.0) continue;
                if (abs(length(dd) - R) < 3.0 - float(k) * 0.5 && ang < 0.62) col = k == 0 ? CREAM : k == 1 ? GOLD : LAV;
            }
        }
    }
    // goose (flashes red when a bullet grazes it)
    float gHit = 0.0;
    for (int i = 0; i < 2; i++) { float t = b - (i == 0 ? 9.5 : 12.5); if (t > 0.0 && t < 0.5) gHit = step(0.5, fract(t * 8.0)); }
    col = drawGoose(col, q, gp, 3.0, honk, int(mod(floor(b), 2.0)), vec3(1.0, 0.2, 0.25), gHit * 0.8);
    // HONK! speech bubble
    for (int i = 0; i < 5; i++) {
        float h = 6.0 + 2.0 * float(i);
        float t = b - (h - 0.7);
        if (t < -0.1 || t > 1.0) continue;
        float pop = easeOut((t + 0.1) / 0.2);
        vec2 bc = beak + vec2(52.0, -26.0);
        vec2 hs = vec2(48.0, 14.0) * pop;
        vec2 d = abs(q - bc) - hs;
        float box = max(d.x, d.y);
        // tail towards the beak
        float tail = segD(q, bc + vec2(-30.0, 8.0) * pop, beak + vec2(4.0, -2.0));
        if (box < 0.0 || tail < 4.0) col = INK;
        if (box < -2.0 || tail < 2.0) col = vec3(1.0);
        if (pop > 0.99) col = bsTxt(col, q, 4, bc - vec2(40.0, 8.0) + vec2(0.0, floor(sin(t * 30.0) * 1.5)), 2.0, 102, 256);
    }
    // K.O.: chain explosions across the world, then one big burst
    if (b > 14.0) {
        for (int j = 0; j < 8; j++) {
            float tj = 14.05 + float(j) * 0.13;
            vec2 bp = wc + (hash3(float(j) * 7.7).xy - 0.5) * 80.0;
            col = boom(col, q, bp, (b - tj) / 0.6, 16.0 + 6.0 * hash1(float(j)), float(j));
        }
        col = boom(col, q, wc, (b - 15.1) / 1.2, 92.0, 3.0);
        // debris
        for (int j = 0; j < 10; j++) {
            float t = b - 15.1;
            if (t < 0.0) break;
            vec3 h = hash3(float(j) * 4.3 + 1.0);
            float an = h.x * 6.2832;
            vec2 dp = wc + vec2(cos(an), sin(an)) * t * (60.0 + 90.0 * h.y) + vec2(0.0, 30.0 * t * t);
            vec2 dd = abs(q - dp);
            if (max(dd.x, dd.y) < 3.0 + 2.0 * h.z) col = h.z > 0.5 ? vec3(0.28, 0.74, 0.30) : GOLD;
        }
    }
    return col;
}

vec3 round2(vec3 col, vec2 q, float b, inout float flR, inout float plumHitA) {
    vec2 pp = plumPos(b);
    vec2 mouthP = pp + vec2(24.0, 5.0);
    float grow = easeOut((b - 16.4) / 1.6);
    float s = grow * (1.0 - smoothstep(28.8, 29.5, b));
    vec2 vc = vec2(236.0 + 8.0 * sin(b * 0.8), 134.0 + 10.0 * sin(b * PI * 0.25));
    // beams on the bar lines
    float hurt = 0.0, beamW = 0.0, charge = 0.0;
    for (int i = 0; i < 3; i++) {
        float h = 20.0 + 4.0 * float(i), t = b - h;
        if (t > -1.0 && t < 0.0) charge = t + 1.0;
        if (t >= 0.0 && t < 1.3) {
            beamW = 12.0 * smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(1.0, 1.3, t));
            hurt = 1.0 - smoothstep(1.0, 1.3, t);
        }
    }
    flR = hurt * step(0.5, fract(uLT * 12.0));
    float rage = 0.0;
    for (int i = 0; i < 2; i++) { float t = b - (21.2 + 4.0 * float(i)); if (t > 0.0 && t < 1.8) rage = 1.0; }
    // tendrils reach for Plum
    for (int i = 0; i < 2; i++) {
        float t = b - (21.2 + 4.0 * float(i));
        if (t < 0.0 || t > 1.8 || s < 0.5) continue;
        float ext = easeOut(t / 0.6) * (1.0 - smoothstep(1.2, 1.8, t));
        float x0 = vc.x - 20.0, L = (x0 - pp.x - 14.0) * ext;
        for (int k = 0; k < 3; k++) {
            float u = (x0 - q.x) / max(L, 1.0);
            if (u < 0.0 || u > 1.0) continue;
            float fk = float(k) - 1.0;
            float y = mix(vc.y + fk * 12.0, pp.y + fk * 26.0, u * u) + sin(q.x * 0.07 - b * 7.0 + fk * 2.0) * 10.0 * u;
            float th = mix(7.0, 2.0, u);
            float dy = abs(q.y - y);
            if (dy < th + 1.5) col = mix(PURP, LAV, 0.4);
            if (dy < th) col = vec3(0.03, 0.0, 0.06);
        }
    }
    col = drawVoid(col, q, vc, s, b, hurt, rage);
    // void bullets: a two-arm spiral plus rings on beats 22 and 26
    if (b > 19.3 && b < 29.0 && s > 0.5) {
        for (int e = 0; e < 18; e++) {
            float te = floor(b * 6.0) / 6.0 - float(e) / 6.0;
            if (te < 19.5 || te > 28.4) continue;
            float t = b - te, rr = 34.0 + t * 85.0;
            for (int arm = 0; arm < 2; arm++) {
                float aj = -te * 6.0 * 0.37 + float(arm) * PI;
                orb(col, q, vc + vec2(cos(aj), sin(aj)) * rr, 3.2, PURP, LAV);
            }
        }
        for (int v = 0; v < 2; v++) {
            float t = b - (22.0 + 4.0 * float(v));
            if (t < 0.0 || t > 3.5) continue;
            float rr = 36.0 + t * 70.0, n = 16.0;
            float an = atan(q.y - vc.y, q.x - vc.x);
            float aj = floor(an / 6.2832 * n + 0.5) * 6.2832 / n;
            orb(col, q, vc + vec2(cos(aj), sin(aj)) * rr, 4.5, vec3(0.9, 0.2, 0.6), LAV);
        }
    }
    // the gold beam
    if (beamW > 0.0) {
        vec2 ab = vc - mouthP;
        float len = length(ab);
        vec2 dir = ab / len;
        vec2 dq = q - mouthP;
        float u = dot(dq, dir), dp = abs(dot(dq, vec2(-dir.y, dir.x)));
        if (u > -4.0 && u < len) {
            float w = beamW * (0.85 + 0.15 * sin(u * 0.25 - uLT * 40.0)) * (0.9 + 0.2 * uEnv.w);
            float node = step(0.8, fract(u / 22.0 - uLT * 6.0));
            if (dp < w + 5.0) col = mix(col, GOLD, 0.35);
            if (dp < w) col = vec3(1.0, 0.5, 0.08);
            if (dp < w * 0.72) col = GOLD;
            if (dp < w * 0.38 + node * 2.0) col = CREAM;
        }
        // impact burst on the void
        float ir = 16.0 + 5.0 * step(0.5, fract(uLT * 14.0));
        float il = length(floor(q / 2.0) * 2.0 + 1.0 - vc);
        if (il < ir * s + 4.0) col = il < ir * s * 0.6 + 2.0 ? CREAM : GOLD;
    }
    // charge-up glow at Plum's mouth
    if (charge > 0.0) {
        float cr = 3.0 + 12.0 * charge * (0.85 + 0.15 * step(0.5, fract(uLT * 16.0)));
        float cl = length(q - mouthP - vec2(4.0, 0.0));
        if (cl < cr + 3.0) col = mix(col, GOLD, 0.5);
        if (cl < cr) col = cl < cr * 0.5 ? CREAM : GOLD;
        for (int k = 0; k < 8; k++) {
            float an = float(k) * 0.785 + b * 2.0;
            float rr = 34.0 * (1.0 - fract(charge * 2.0 + float(k) * 0.125));
            vec2 sp = mouthP + vec2(4.0, 0.0) + vec2(cos(an), sin(an)) * rr;
            vec2 dd = abs(q - sp);
            if (max(dd.x, dd.y) < 1.6) col = CREAM;
        }
    }
    // Plum: glows gold while charging, flashes red when a tendril grazes it
    float pHit = 0.0;
    for (int i = 0; i < 2; i++) { float t = b - (22.3 + 4.0 * float(i)); if (t > 0.0 && t < 0.5) pHit = step(0.5, fract(t * 8.0)); }
    plumHitA = pHit;
    vec3 tint = pHit > 0.0 ? vec3(1.0, 0.2, 0.25) : GOLD;
    float ta = pHit > 0.0 ? 0.8 : charge * 0.55 * step(0.5, fract(uLT * 10.0));
    if (b < 29.5) col = drawPlum(col, q, pp + vec2(beamW > 0.0 ? -2.0 : 0.0, 0.0), 3.0, tint, ta);
    // implosion: a white point swallowing everything
    if (b > 28.8 && b < 29.6) {
        float t = (b - 28.8) / 0.7;
        vec2 d = abs(q - vc);
        float arm = 2.0 + 60.0 * t * t;
        if ((d.x < arm && d.y < 1.5) || (d.y < arm * 0.6 && d.x < 1.5) || length(q - vc) < 3.0 + 4.0 * t) col = CREAM;
    }
    return col;
}

// the end screen: both heroes celebrate under the PB
vec3 victory(vec3 col, vec2 p, float b) {
    float t = b - BS_CLEAR;
    col = bsTxt(col, p, 10, vec2(bsCX(10, 2.0), 40.0), 2.0, TS_WHITE, int(t * 14.0));
    if (t > 0.5) col = bsTxtC(col, p, 11, 62.0 - 50.0 * (1.0 - easeOut((t - 0.5) / 0.3)), 3.0, TS_CHROME);
    // LiveSplit box
    if (t > 0.8) {
        if (p.x > 64.0 && p.x < 256.0 && p.y > 94.0 && p.y < 152.0) {
            col = mix(col, INK, 0.85);
            if (p.x < 66.0 || p.x > 254.0 || p.y < 96.0 || p.y > 150.0) col = GOLD;
        }
        if (fract(b * 2.0) < 0.75) col = bsTxtC(col, p, 12, 101.0, 2.0, 101);
        col = drawTime(col, p, BS_CLEAR / 1.5, 244.0, 122.0, 3.0, TS_GREEN);
    }
    // Goosebert and Plum hop on the beat
    float hop = 10.0 * sin(PI * fract(b));
    col = drawGoose(col, p, vec2(118.0, 190.0 - hop), 3.0, fract(b) < 0.4, int(mod(floor(b), 2.0)), vec3(0.0), 0.0);
    float hop2 = 10.0 * sin(PI * fract(b + 0.5));
    col = drawPlum(col, p, vec2(202.0, 190.0 - hop2), 3.0, vec3(0.0), 0.0);
    return col;
}

vec3 part(vec2 p) {
    float b = uLT * 1.5;
    bool r2 = b >= 16.0;
    // screen shake: sharp on the honk hits, rumbling under the beams and the K.O.
    float shake = 0.0;
    for (int i = 0; i < 5; i++) { float t = b - (6.0 + 2.0 * float(i)); if (t >= 0.0) shake = max(shake, exp(-t * 7.0) * (i == 4 ? 9.0 : 5.0)); }
    if (b > 14.0 && b < 15.9) shake = max(shake, 3.0 + 6.0 * exp(-max(b - 15.1, 0.0) * 4.0) * step(15.1, b));
    for (int i = 0; i < 3; i++) { float t = b - (20.0 + 4.0 * float(i)); if (t >= 0.0 && t < 1.3) shake = max(shake, 2.0 + 5.0 * exp(-t * 8.0)); }
    if (b > 28.8 && b < 30.2) shake = max(shake, 5.0 * (1.0 - abs(b - 29.5) / 0.7));
    vec2 sh = floor((vec2(hash1(floor(uLT * 30.0)), hash1(floor(uLT * 30.0) + 7.0)) - 0.5) * 2.0 * shake + 0.5);
    vec2 q = p + sh;

    float flR = 0.0, pHit = 0.0;
    vec3 col;
    float hpL, lagL, hpR, lagR;
    if (!r2) {
        col = bgSpace(q, b, 0.3);
        col = round1(col, q, b, flR);
        hpL = 1.0 - 0.12 * (smoothstep(9.5, 9.7, b) + smoothstep(12.5, 12.7, b));
        lagL = 1.0 - 0.12 * (smoothstep(10.2, 10.4, b) + smoothstep(13.2, 13.4, b));
        hpR = hpSteps(b, 6.0, 2.0, 5, 0.2, 0.0);
        lagR = hpSteps(b, 6.0, 2.0, 5, 0.2, 0.6);
        hpR *= step(0.0, hpR);
    } else {
        vec2 vc = vec2(236.0 + 8.0 * sin(b * 0.8), 134.0 + 10.0 * sin(b * PI * 0.25));
        float vs = easeOut((b - 16.4) / 1.6) * (1.0 - smoothstep(28.8, 29.5, b));
        col = bgVoid(q, b, vc, vs);
        if (b < BS_CLEAR + 0.3) col = round2(col, q, b, flR, pHit);
        else col = victory(col, p, b);
        hpL = 1.0 - 0.1 * (smoothstep(22.3, 22.5, b) + smoothstep(26.3, 26.5, b));
        lagL = 1.0 - 0.1 * (smoothstep(23.0, 23.2, b) + smoothstep(27.0, 27.2, b));
        float drain = 0.0, dlag = 0.0;
        for (int i = 0; i < 3; i++) {
            float h = 20.0 + 4.0 * float(i);
            drain += clamp((b - h) / 1.2, 0.0, 1.0);
            dlag += clamp((b - h - 0.6) / 1.0, 0.0, 1.0);
        }
        hpR = 1.0 - drain / 3.0;
        lagR = 1.0 - dlag / 3.0;
    }
    // ---- overlays in screen space (no shake)
    if (b < 2.3) {
        float open = easeOut(b / 0.25) * (1.0 - smoothstep(2.0, 2.3, b));
        col = hazardBand(col, p, 80.0, 164.0, open, step(0.5, fract(b * 2.0)));
        if (open > 0.95) {
            if (b < 0.6 || fract(b * 2.0) < 0.75) col = bsTxtC(col, p, 0, 98.0, 4.0, 100);
            col = bsTxtC(col, p, 15, 138.0, 1.0, TS_GOLD);
        }
    }
    if (b > 2.0 && b < 5.0) col = vsCard(col, p, b - 2.0, 1, 3, 14, 2.5);
    if (b > 4.85 && b < 5.6 && fract(b * 4.0) < 0.8) col = bsTxtC(col, p, 13, 104.0, 4.0, TS_CHROME);
    if (b > 14.2 && b < 16.0) {
        float t = b - 14.2;
        float drop = (1.0 - easeOut(t / 0.2)) * -80.0;
        col = bsTxtC(col, p, 5, 44.0 + drop, 5.0, 101);
        if (t > 0.8) {
            col = bsTxtC(col, p, 3, 184.0, 2.0, TS_WHITE);
            col = bsTxt(col, p, 6, vec2(bsCX(6, 2.0), 204.0), 2.0, TS_GOLD, int((t - 0.8) * 18.0));
        }
    }
    if (b > 16.0 && b < 19.4) col = vsCard(col, p, b - 16.0, 8, 9, 7, 2.8);
    if (b > 19.2 && b < 20.0 && fract(b * 4.0) < 0.8) col = bsTxtC(col, p, 13, 104.0, 4.0, TS_CHROME);
    // flashes: the K.O. burst, the void's collapse
    if (b > 15.1 && b < 15.5) col = mix(col, vec3(1.0), (1.0 - (b - 15.1) / 0.4) * 0.8);
    if (b > 29.35) col = mix(col, vec3(1.0), clamp(1.0 - (b - 29.5) / 0.45, 0.0, 1.0) * step(29.35, b));
    // HUD + the run timer
    if (b < BS_CLEAR) {
        col = hud(col, p, b, r2, hpL, lagL, hpR, lagR, flR);
        if (p.y > 226.0) col = drawTime(col, p, uLT, 314.0, 229.0, 1.0, TS_GREEN);
    }
    return col;
}
