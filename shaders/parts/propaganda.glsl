// @id propaganda
// @name PROPAGANDA
// @split SLOGANS
// @bars 4
// @order 230
// @default off
// @inspired Bomb - State of Mind (1998)
// @desc Stark black-and-cream poster cards slam in every two beats: halftone, scan lines, frame rules and one accent colour each, shouting speedrun slogans.
// @str 0 RESET?
// @str 1 PB PACE
// @str 2 ONE MORE RUN
// @str 3 FRAME PERFECT
// @str 4 NO SLEEP
// @str 5 WR OR RESET
// @str 6 OVER ESTIMATE
// @str 7 NEVER HAPPENED BEFORE
// @str 8 {EVENT}
// @str 9 SPLIT
// @str 10 ESA

const vec3 INK = vec3(0.045, 0.035, 0.075);
const vec3 ACID = vec3(0.62, 1.0, 0.12);
const float CARD = 2.0 * 60.0 / 90.0;   // a new card every two beats
const float IMP = 0.10;                 // time from card start to the stamp hitting the paper

// the current slogan, broken into one word per line
int gWs[4], gWl[4], gNw, gRow, gMax;
float gSc;
vec2 gOrg;
bool gCentre;

int chAt(int row, int k) { return int(texelFetch(uStr, ivec2(k, row), 0).r * 255.0 + 0.5); }

void parseWords(int row) {
    for (int k = 0; k < 4; k++) { gWs[k] = 0; gWl[k] = 0; }
    gNw = 0; gMax = 1; gRow = row;
    int n = min(strLen(row), 40), cur = -1;
    for (int k = 0; k < 40; k++) {
        if (k >= n) break;
        int c = chAt(row, k);
        if (c == 32) {
            if (cur >= 0 && gNw < 4) { gWl[gNw] = k - cur; gNw++; }
            cur = -1;
        } else if (cur < 0) { cur = k; if (gNw < 4) gWs[gNw] = k; }
    }
    if (cur >= 0 && gNw < 4) { gWl[gNw] = n - cur; gNw++; }
    for (int k = 0; k < 4; k++) if (k < gNw) gMax = max(gMax, gWl[k]);
}

// 1 where the slogan's ink is, q in stamp space (pixels)
float slogan(vec2 q) {
    vec2 r = q - gOrg;
    if (r.x < 0.0 || r.y < 0.0) return 0.0;
    float lh = 10.0 * gSc;
    int j = int(r.y / lh);
    if (j >= gNw) return 0.0;
    float ly = r.y - float(j) * lh;
    if (ly >= 8.0 * gSc) return 0.0;
    float lw = float(gWl[j]) * 8.0 * gSc;
    float x0 = gCentre ? floor((float(gMax) * 8.0 * gSc - lw) * 0.5 / gSc) * gSc : 0.0;
    float lx = r.x - x0;
    if (lx < 0.0 || lx >= lw) return 0.0;
    ivec2 g = ivec2(floor(vec2(lx, ly) / gSc));
    return glyphBit(chAt(gRow, gWs[j] + g.x / 8), ivec2(g.x % 8, g.y));
}

// rotated halftone screen: v = tone 0..1 at the cell, cell = pitch in px
float halftone(vec2 p, float cell, float v) {
    vec2 pr = rot2(0.785) * p;
    vec2 cc = (floor(pr / cell) + 0.5) * cell;
    return step(length(pr - cc), sqrt(clamp(v, 0.0, 1.0)) * cell * 0.72);
}

float boxD(vec2 p, vec2 c, vec2 h) { vec2 d = abs(p - c) - h; return max(d.x, d.y); }

// flat-colour text (the poster has no drop shadows)
vec3 inkChar(vec3 col, vec2 p, int ch, vec2 pos, float sc, vec3 c) {
    vec2 q = floor((p - pos) / sc);
    if (q.x < 0.0 || q.y < 0.0 || q.x >= 8.0 || q.y >= 8.0) return col;
    return glyphBit(ch, ivec2(q)) > 0.5 ? c : col;
}
vec3 inkStr(vec3 col, vec2 p, int row, vec2 pos, float sc, vec3 c, int maxChars) {
    vec2 q = (p - pos) / sc;
    return strAt(row, floor(q), 0, maxChars) > 0.5 ? c : col;
}

vec3 part(vec2 p) {
    float tt = uLT + IMP;                 // the stamp hits the paper exactly on the beat
    int i = clamp(int(tt / CARD), 0, 7);
    float lb = tt - float(i) * CARD;
    const int STY[8] = int[](0, 1, 2, 3, 1, 0, 3, 2);
    const int ACC[8] = int[](0, 1, 0, 2, 2, 1, 0, 1);
    int sty = STY[i];
    int ai = ACC[i];
    vec3 acc = ai == 0 ? GOLD : ai == 1 ? PURP : ACID;
    float seed = float(i) * 7.31;
    float fr = floor(uLT * 30.0);   // 30 Hz jitter clock

    // ---- the slam: zoom down onto the page, then a decaying shake (and a smaller thump on the card's 2nd beat)
    float zoom = lb < IMP ? mix(3.2, 1.0, pow(lb / IMP, 2.0)) : 1.0;
    float shk = lb < IMP ? 0.0 : 8.0 * exp(-(lb - IMP) * 16.0);
    if (lb > CARD * 0.5 + IMP) shk += 3.0 * exp(-(lb - CARD * 0.5 - IMP) * 14.0);
    shk += 1.5 * uEnv.w;
    vec2 jit = (vec2(hash1(fr + seed), hash1(fr * 1.7 + 3.0 + seed)) - 0.5) * 2.0 * shk;
    // horizontal slice tear right at impact
    float tear = exp(-max(lb - IMP, 0.0) * 16.0) * step(IMP * 0.5, lb);
    float sl = hash2(vec2(floor(p.y / 7.0), fr + seed));
    vec2 gp = p + vec2((sl - 0.5) * 40.0 * tear * step(0.55, sl), 0.0);

    vec2 ctr = vec2(160.0, 114.0);
    vec2 sp = ctr + (gp + jit - ctr) / zoom;   // stamp space

    // ---- the slogan layout
    parseWords(i);
    gSc = clamp(floor(292.0 / (float(gMax) * 8.0)), 3.0, 5.0);
    gCentre = (sty == 0 || sty == 2);
    float bw = float(gMax) * 8.0 * gSc, bh = float(gNw) * 10.0 * gSc - 2.0 * gSc;
    gOrg = floor(ctr - vec2(bw, bh) * 0.5);
    vec2 bc = gOrg + vec2(bw, bh) * 0.5;
    vec2 bhs = vec2(bw, bh) * 0.5 + vec2(14.0, 12.0);

    // ---- page
    vec3 paper, ink;
    vec3 col;
    float t = uLT;
    if (sty == 0) {          // black page, accent halftone cloud
        paper = INK; ink = CREAM;
        float v = (fbm(gp * 0.018 + vec2(t * 0.25, seed)) - 0.42) * 2.2;
        v *= 0.6 + 0.6 * smoothstep(40.0, 220.0, length(gp - vec2(60.0, 200.0)));
        col = mix(paper, acc * 0.75, halftone(gp + vec2(0.0, t * 6.0), 8.0, v));
    } else if (sty == 1) {   // cream page, ink halftone from the corner, accent slab
        paper = CREAM; ink = INK;
        float v = 1.0 - length(gp - vec2(330.0, 250.0)) / 260.0 + 0.15 * vnoise(gp * 0.05 + seed);
        col = mix(paper, INK, halftone(gp, 7.0, v));
    } else if (sty == 2) {   // accent page, heavy scan lines
        paper = acc; ink = CREAM;
        col = acc * (mod(floor(gp.y), 3.0) < 1.0 ? 0.55 : 1.0);
        float v = fbm(gp * 0.03 + vec2(-t * 0.4, seed));
        col = mix(col, col * 0.6, halftone(gp, 6.0, v * 0.6));
    } else {                 // black page, a scan-line "video still" and a digit ticker
        paper = INK; ink = INK;
        float img = fbm(vec2(gp.x * 0.012 + t * 0.15, gp.y * 0.02) + seed);
        img = smoothstep(0.35, 0.75, img);
        float ln = mod(floor(gp.y), 4.0) < 2.0 ? 1.0 : 0.25;
        col = mix(paper, mix(ROYAL * 0.5, CREAM * 0.8, img), ln * (0.25 + 0.6 * img));
        // vertical rolling digits on the left and right edges
        for (int s = 0; s < 2; s++) {
            float x0 = s == 0 ? 10.0 : 294.0;
            float roll = t * (s == 0 ? 60.0 : -45.0) + uKickCum * 8.0;
            vec2 dq = gp - vec2(x0, roll);
            float cy = floor(dq.y / 18.0);
            int dg = 48 + int(mod(cy + float(s) * 3.0, 10.0));
            if (gp.y > 32.0 && gp.y < 206.0) col = drawChar(col, vec2(gp.x, mod(dq.y, 18.0)), dg, vec2(x0, 0.0), 2.0, TS_WHITE);
        }
    }

    // ---- the stamp: frame rules, filled plate, slogan, misregistered accent under-print
    float d = boxD(sp, bc, bhs);
    bool filled = (sty == 2 || sty == 3);
    vec3 plate = sty == 2 ? INK : CREAM;
    vec3 rule = sty == 1 ? INK : sty == 2 ? INK : CREAM;
    if (filled && d < 0.0) col = plate;
    if (sty == 1 && d < -4.0) col = CREAM;
    if (sty == 1) {   // off-register accent slab behind the last line, printed after the paper is cleared
        float ly = gOrg.y + float(gNw - 1) * 10.0 * gSc;
        vec2 sc = sp - vec2(-6.0, 4.0);
        if (sc.y > ly + 3.0 * gSc && sc.y < ly + 8.0 * gSc + 5.0 && sc.x > gOrg.x - 12.0 && sc.x < gOrg.x + bw + 12.0) col = acc;
    }
    if (d < 0.0 && d > -4.0) col = rule;                                          // outer rule
    if (!filled && d < -7.0 && d > -9.0) col = rule;                              // inner hairline
    if (filled && d < -6.0 && d > -8.0) col = sty == 2 ? acc : INK;
    if (d > 3.0 && d < 7.0 && sty == 3) {                                         // accent under-rule
        if (sp.y > bc.y + bhs.y) col = acc;
    }
    // registration crosses at the corners
    for (int k = 0; k < 4; k++) {
        vec2 cp = bc + bhs * vec2(k % 2 == 0 ? -1.0 : 1.0, k < 2 ? -1.0 : 1.0) + vec2(k % 2 == 0 ? -10.0 : 10.0, k < 2 ? -10.0 : 10.0);
        vec2 a = abs(sp - cp);
        if ((a.x < 1.0 && a.y < 6.0) || (a.y < 1.0 && a.x < 6.0) || abs(length(sp - cp) - 3.5) < 0.8)
            col = sty == 1 ? INK : sty == 2 ? INK : CREAM;
    }
    // worn rubber-stamp ink
    float wear = step(0.1, vnoise(floor(sp / 3.0) * 0.9 + seed * 3.0)) * step(0.06, hash2(floor(sp / 3.0) + seed));
    vec3 tcol = sty == 0 ? CREAM : sty == 1 ? INK : sty == 2 ? CREAM : INK;
    vec3 mcol = sty == 1 ? acc : sty == 3 ? acc : sty == 2 ? acc * 0.5 : acc;   // under-print colour
    vec2 mis = vec2(3.0, 3.0) + vec2(sin(t * 3.0 + seed), cos(t * 2.3)) * 1.0;
    if ((sty == 0 || sty == 3) && slogan(sp - mis) > 0.5) col = mcol;
    if (slogan(sp) > 0.5) col = mix(col, tcol, max(wear, 0.6));

    // ---- header and footer strips
    vec3 hud = sty == 1 || (sty == 2 && ai != 1) ? INK : CREAM;
    vec3 hacc = sty == 2 ? hud : acc;
    if (abs(p.y - 27.0) < 1.0 && p.x > 10.0 && p.x < 310.0) col = hud;
    if (abs(p.y - 212.0) < 1.0 && p.x > 10.0 && p.x < 310.0) col = hud;
    col = inkStr(col, p, 9, vec2(12.0, 8.0), 2.0, hud, 5);
    int hc[5] = int[](48, 49 + i, 47, 48, 56);
    for (int k = 0; k < 5; k++) col = inkChar(col, p, hc[k], vec2(100.0 + 16.0 * float(k), 8.0), 2.0, k == 1 ? hacc : hud);
    // running split timer
    int cs = int(floor((7.0 * 60.0 + 12.0 + uLT) * 100.0));
    int m = cs / 6000, s = (cs / 100) % 60, c = cs % 100;
    int tc[7] = int[](48 + m % 10, 58, 48 + s / 10, 48 + s % 10, 46, 48 + c / 10, 48 + c % 10);
    for (int k = 0; k < 7; k++) col = inkChar(col, p, tc[k], vec2(196.0 + 16.0 * float(k), 8.0), 2.0, hud);
    col = inkStr(col, p, 8, vec2(12.0, 220.0), 1.0, hud, 30);
    col = inkStr(col, p, 10, vec2(262.0, 216.0), 2.0, hacc, 3);

    // ---- impact: two frames of photographic negative, and a paper flash on the stamp
    if (lb > IMP && lb < IMP + 0.045) col = vec3(1.0) - col;
    return col;
}
