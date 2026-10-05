// @id halloween
// @name HALLOWEEN INVITATION
// @split SPOOKY
// @bars 8
// @order 195
// @default off
// @inspired Future Crew - Assembly '92 Invitation (Fishtro, 1992), Halloween edition
// @desc ESA Halloween invite: harvest moon, bats, a haunted hill and an ESA jack-o'-lantern; the weekend schedule types onto a board.
// @str 0 YOU ARE INVITED TO
// @str 1 ESA HALLOWEEN
// @str 2 OCT 30 - NOV 1
// @str 3 FRI 30 OCT  15:00-01:00
// @str 4 SAT 31 OCT  10:00-01:00
// @str 5 SUN  1 NOV  10:00-01:00
// @str 6 ALL TIMES CET
// @str 7 SPEEDRUNS FOR CHARITY
// @str 8 TWITCH.TV/ESAMARATHON
// @str 9 RIP
// @str 10 PB

const vec3 HW_ORANGE = vec3(1.0, 0.46, 0.06), HW_YELLOW = vec3(1.0, 0.88, 0.35), HW_RED = vec3(0.66, 0.08, 0.05);
const vec3 HW_NIGHT = vec3(0.07, 0.04, 0.12);

// glyph coverage with a non-uniform scale: 1 = glyph, 0.5 = outline, 0 = nothing
float hwGlyph(int row, vec2 p, vec2 pos, vec2 scl, int n) {
    vec2 q = floor((p - pos) / scl);
    if (strAt(row, q, 0, n) > 0.5) return 1.0;
    float o = 0.0;
    for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++) o = max(o, strAt(row, q + vec2(x, y), 0, n));
    return o * 0.5;
}
// spooky gradient per glyph row: candle yellow at the top, blood red at the bottom
vec3 hwFire(float gy) {
    return gy < 2.0 ? HW_YELLOW : gy < 4.0 ? mix(HW_YELLOW, HW_ORANGE, 0.7) : gy < 6.0 ? HW_ORANGE : HW_RED;
}
// typed text line with outline; dayCols chars at the start get the accent colour
vec3 hwLine(vec3 col, vec2 p, int row, vec2 pos, vec2 scl, int n, vec3 base, vec3 accent, int dayCols) {
    float g = hwGlyph(row, p, pos, scl, n);
    if (g > 0.75) {
        int c = int((p.x - pos.x) / (8.0 * scl.x));
        col = c < dayCols ? accent : base;
    } else if (g > 0.25) col = HW_NIGHT * 0.5;
    return col;
}
int hwTyped(float t0, float lt, int n, float rate) { return clamp(int((lt - t0) / rate), 0, n); }

// a bat silhouette in local units (wingspan -1..1); flap -1 (down) .. 1 (up)
float hwBat(vec2 q, float flap) {
    float ax = abs(q.x);
    if (length(q / vec2(0.16, 0.3)) < 1.0) return 1.0;                        // body
    if (length((q - vec2(0.0, -0.3)) / vec2(0.13, 0.12)) < 1.0) return 1.0;   // head
    if (ax < 0.12 && q.y < -0.36 && q.y > -0.48 && ax > 0.03) return 1.0;     // ears
    if (ax > 0.1 && ax < 1.0) {
        float top = -0.2 - flap * ax * 0.7;
        float bot = top + 0.42 * (1.0 - ax * 0.85) - 0.13 * abs(sin(ax * 3.0 * PI));  // scalloped trailing edge
        if (q.y > top && q.y < bot) return 1.0;
    }
    return 0.0;
}

vec3 part(vec2 p) {
    const float BAR = 4.0 * (60.0 / 90.0);
    float lt = uLT;
    int bar = int(lt / BAR);
    float lb = lt - float(bar) * BAR;
    // lightning on the title slam and on bar 6
    float bolt = max(exp(-(lt - BAR) * 14.0) * step(BAR, lt), exp(-(lt - 6.0 * BAR) * 14.0) * step(6.0 * BAR, lt));

    // ---- sky: stepped night gradient with an orange horizon glow
    float sb = floor(p.y / 6.0) * 6.0 / 175.0;
    vec3 col = mix(HW_NIGHT, PURP * 0.35, smoothstep(0.15, 0.85, sb));
    col = mix(col, vec3(0.75, 0.25, 0.15), smoothstep(0.7, 1.0, sb) * 0.7);
    col = mix(col, vec3(0.85, 0.8, 1.0), bolt * 0.55);
    // sparse stars
    vec2 sc = floor(p / 9.0);
    float sh = hash2(sc + 17.0);
    if (sh > 0.9 && p.y < 120.0) {
        vec2 sp = sc * 9.0 + 2.0 + floor(hash2(sc + 5.0) * 5.0);
        if (abs(p.x - sp.x) < 1.0 && abs(p.y - sp.y) < 1.0) col = mix(LAV, CREAM, 0.5 + 0.5 * sin(uBeat * PI + sh * 30.0));
    }
    // ---- the giant harvest moon, low behind the board
    vec2 mc = vec2(160.0, 118.0);
    float mr = length(p - mc);
    col += HW_ORANGE * 0.25 * (1.0 - smoothstep(60.0, 120.0, mr));          // halo
    if (mr < 66.0) {
        float crater = fbm(p * 0.045 + 3.0);
        float li = 0.75 + 0.25 * (crater - 0.5) * 2.0 - (p.y - mc.y) / 66.0 * 0.15;
        col = mix(vec3(1.0, 0.62, 0.22), vec3(1.0, 0.86, 0.55), floor(clamp(li, 0.0, 1.0) * 4.0) / 3.0);
    }
    // ---- bats crossing the sky (over the moon), wings beating on the eighth notes
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float speed = 34.0 + hash1(fi * 2.1) * 30.0;
        float x = mod(hash1(fi * 7.3) * 400.0 + uT * speed, 420.0) - 50.0;   // ambient: continuous clock
        float y = 50.0 + hash1(fi * 3.7) * 90.0 + sin(uT * 2.4 + fi * 1.9) * 9.0;
        float size = 9.0 + hash1(fi * 5.1) * 9.0;
        float flap = sin((uBeat * 2.0 + hash1(fi)) * PI);
        if (hwBat((p - vec2(x, y)) / size, flap) > 0.5) col = HW_NIGHT * 0.35;
    }
    // ---- hills, the haunted house (left) and a dead tree (right)
    float hill = 176.0 + 8.0 * sin(p.x * 0.018 + 0.6) + 5.0 * sin(p.x * 0.051 + 2.0);
    bool house = (p.x > 14.0 && p.x < 62.0 && p.y > 136.0) || (p.x > 44.0 && p.x < 58.0 && p.y > 112.0);
    float roof = 136.0 - (24.0 - abs(p.x - 38.0)) * 0.9;                    // main gable
    float spire = 112.0 - (7.0 - abs(p.x - 51.0)) * 2.4;                    // tower spire
    if ((p.x > 14.0 && p.x < 62.0 && p.y > roof && p.y <= 136.0) || (abs(p.x - 51.0) < 7.0 && p.y > spire && p.y <= 112.0)) house = true;
    if (house && p.y < hill + 6.0) {
        col = HW_NIGHT * 0.6;
        // glowing windows flicker like candles
        vec2 w = vec2(mod(p.x - 18.0, 12.0), mod(p.y - 142.0, 13.0));
        bool win = p.y > 142.0 && p.y < 168.0 && p.x > 18.0 && p.x < 58.0 && w.x < 6.0 && w.y < 7.0;
        bool tw = abs(p.x - 51.0) < 2.5 && p.y > 117.0 && p.y < 124.0;
        float fl = 0.75 + 0.25 * sin(uT * 13.0 + floor(p.x / 12.0) * 2.0) * sin(uT * 5.3);
        if (win || tw) col = mix(HW_ORANGE, HW_YELLOW, fl * 0.6) * fl;
    }
    // dead tree: a trunk and a few crooked branches
    vec2 tq = p - vec2(282.0, 178.0);
    bool tree = abs(tq.x + sin(tq.y * 0.08) * 3.0) < 3.0 - tq.y * 0.015 && tq.y > -54.0 && tq.y < 0.0;
    for (int b = 0; b < 4; b++) {
        float fb = float(b), by = -18.0 - fb * 9.0, dir = mod(fb, 2.0) < 0.5 ? -1.0 : 1.0;
        float bx = tq.x * dir;
        if (bx > 0.0 && bx < 26.0 - fb * 4.0 && abs(tq.y - by + bx * (0.55 + 0.1 * fb)) < 1.6 - bx * 0.04) tree = true;
    }
    if (tree) col = HW_NIGHT * 0.5;
    if (p.y > hill) {
        float slope = cos(p.x * 0.018 + 0.6) * 0.14 + cos(p.x * 0.051 + 2.0) * 0.25;
        col = mix(HW_NIGHT * 0.7, PLUM * 0.8, floor(clamp(0.5 - slope, 0.0, 1.0) * 3.0) / 2.0);
        if (p.y - hill < 1.5) col = mix(col, HW_ORANGE * 0.6, 0.6);           // moonlit rim
    }
    // ---- drifting fog
    float fog = fbm(vec2(p.x * 0.012 + uT * 0.18, p.y * 0.05 - uT * 0.05));
    float fa = smoothstep(0.45, 0.75, fog) * smoothstep(160.0, 205.0, p.y);
    col = mix(col, mix(LAV, CREAM, 0.3), floor(fa * 3.0) / 3.0 * 0.45);

    // ---- the schedule board (from bar 2)
    float boardIn = clamp((lt - 2.0 * BAR) / 0.35, 0.0, 1.0);
    vec2 bmin = vec2(36.0, 50.0), bmax = vec2(284.0, 180.0);
    bmin.y = mix(bmax.y, bmin.y, easeOut(boardIn));
    if (boardIn > 0.0 && p.x > bmin.x && p.x < bmax.x && p.y > bmin.y && p.y < bmax.y) {
        col = mix(col, HW_NIGHT * 0.6, 0.78);
        bool edge = p.x < bmin.x + 2.0 || p.x > bmax.x - 2.0 || p.y < bmin.y + 2.0 || p.y > bmax.y - 2.0;
        bool notch = (p.x < bmin.x + 7.0 || p.x > bmax.x - 7.0) && (p.y < bmin.y + 7.0 || p.y > bmax.y - 7.0);
        if (edge && !notch) col = HW_ORANGE;
        if (abs(p.y - 77.0) < 0.6 && p.x > 52.0 && p.x < 268.0 && boardIn >= 1.0) col = HW_ORANGE * 0.7;
        if (abs(p.y - 150.0) < 0.6 && p.x > 52.0 && p.x < 268.0 && lt > 6.0 * BAR) col = HW_ORANGE * 0.7;
    }
    if (boardIn >= 1.0) {
        col = hwLine(col, p, 2, vec2(48.0, 56.0), vec2(2.0), hwTyped(2.0 * BAR + 0.35, lt, strLen(2), 0.07), HW_YELLOW, HW_YELLOW, 0);
        for (int r = 0; r < 3; r++) {
            float t0 = float(3 + r) * BAR + 0.1;
            if (lt > t0) col = hwLine(col, p, 3 + r, vec2(68.0, 83.0 + float(r) * 18.0), vec2(1.0, 2.0),
                                      hwTyped(t0, lt, strLen(3 + r), 0.06), CREAM, HW_ORANGE, 10);
        }
        if (lt > 5.0 * BAR + 1.6) col = hwLine(col, p, 6, vec2(108.0, 139.0), vec2(1.0), 99, LAV, LAV, 0);
    }
    // ---- charity + where to watch (bars 6, 7)
    if (lt > 6.0 * BAR) col = hwLine(col, p, 7, vec2(76.0, 155.0), vec2(1.0), hwTyped(6.0 * BAR + 0.1, lt, strLen(7), 0.06), CREAM, CREAM, 0);
    if (lt > 7.0 * BAR) col = hwLine(col, p, 8, vec2(76.0, 167.0), vec2(1.0), hwTyped(7.0 * BAR + 0.1, lt, strLen(8), 0.06), HW_ORANGE, HW_ORANGE, 0);

    // ---- gravestones: RIP ... PB
    for (int g = 0; g < 2; g++) {
        vec2 gc = vec2(g == 0 ? 56.0 : 264.0, 210.0);
        vec2 gq = p - gc;
        bool stone = (abs(gq.x) < 17.0 && gq.y > -8.0 && gq.y < 30.0) || length(gq - vec2(0.0, -8.0)) < 17.0;
        if (stone) {
            float li = 0.55 - gq.x / 40.0 + (vnoise(p * 0.3) - 0.5) * 0.25;
            col = mix(HW_NIGHT * 1.6, mix(ROYAL, LAV, 0.3), floor(clamp(li, 0.0, 1.0) * 3.0) / 2.0);
            int row = g == 0 ? 9 : 10;
            float gx = strW(row, 1.0);
            if (hwGlyph(row, p, vec2(floor(gc.x - gx * 0.5), gc.y - 10.0), vec2(1.0), 9) > 0.75) col = HW_NIGHT;
        }
    }

    // ---- the ESA jack-o'-lantern: the cube logo carved out, lit by a candle that flickers with the kick
    vec2 pc = vec2(160.0, 214.0);
    vec2 pq = (p - pc) / vec2(44.0, 32.0);
    float pr = length(pq);
    float flick = 0.82 + 0.12 * sin(uT * 23.0) * sin(uT * 7.1) + 0.3 * uEnv.w;
    col += HW_ORANGE * 0.35 * flick * (1.0 - smoothstep(0.9, 2.2, pr));    // glow on the ground
    if (abs(p.x - 160.0 + 1.0) < 3.0 && p.y > 176.0 && p.y < 186.0) col = vec3(0.25, 0.32, 0.1);   // stem
    if (pr < 1.0) {
        float rib = abs(sin(pq.x * PI * 2.2));
        float li = 0.35 + 0.45 * (1.0 - pr) + 0.25 * rib - pq.y * 0.2;
        col = mix(HW_RED * 0.8, HW_ORANGE, floor(clamp(li, 0.0, 1.0) * 4.0) / 3.0);
        vec4 lg = logoAt(p, pc + vec2(0.0, 1.0), 40.0);
        if (lg.a > 0.5) {   // carved: the logo's light faces glow, its keyline stays as the carving edge
            float lum = dot(lg.rgb, vec3(0.3, 0.6, 0.1));
            col = lum < 0.3 ? HW_RED * 0.5 : mix(HW_ORANGE, HW_YELLOW, lum) * flick;
        }
    }

    // ---- title: "YOU ARE INVITED TO" types in big, then shrinks as ESA HALLOWEEN slams in with drips
    if (bar == 0) {
        int n0 = strLen(0);
        col = hwLine(col, p, 0, vec2(floor((uRes.x - float(n0) * 16.0) * 0.5), 26.0), vec2(2.0),
                     hwTyped(0.15, lt, n0, 0.08), CREAM, CREAM, 0);
    } else {
        col = hwLine(col, p, 0, vec2(floor((uRes.x - strW(0, 1.0)) * 0.5), 5.0), vec2(1.0), 99, LAV, LAV, 0);
        float drop = (1.0 - easeOut((lt - BAR) / 0.3)) * -60.0;
        vec2 tp = vec2(floor((uRes.x - strW(1, 2.0)) * 0.5), 16.0 + drop);
        vec2 scl = vec2(2.0, 3.0);
        float g = hwGlyph(1, p, tp, scl, 99);
        vec2 q = (p - tp) / scl;
        if (g > 0.75) col = hwFire(mod(q.y, 8.0));
        else if (g > 0.25) col = HW_NIGHT * 0.4;
        // drips run down from the bottom row of the letters as the part goes on
        float bottom = tp.y + 24.0;
        if (p.y >= bottom - 1.0 && p.y < bottom + 22.0) {
            float colx = floor((p.x - tp.x) / 2.0);
            float h = hash1(colx * 1.31 + 4.0);
            float len = h > 0.72 ? (h - 0.72) / 0.28 * 20.0 * clamp((lt - BAR) / (3.0 * BAR), 0.0, 1.0) : 0.0;
            if (strAt(1, vec2(floor(colx * 2.0 / 2.0), 7.0), 0, 99) > 0.5 && p.y - bottom < len)
                col = mix(HW_RED, HW_ORANGE, 0.3);
        }
    }
    return col;
}
