// @id invite
// @name THE INVITATION
// @split INVITE
// @bars 4
// @order 190
// @default off
// @inspired Future Crew - Assembly '92 Invitation (Fishtro, 1992)
// @desc A hand-painted night landscape with the ESA cube on a floating island; a text writer types one invitation line per bar.
// @str 0 YOU ARE INVITED TO
// @str 1 {EVENT}
// @str 2 SPEEDRUNS FOR CHARITY
// @str 3 {LINE2}

// stepped "painted" shading: quantise a 0..1 light value into a few flat tones
float ivPaint(float v, float steps) { return floor(clamp(v, 0.0, 0.999) * steps) / (steps - 1.0); }

// a row of painted peaks. Returns (top y, lit side 0/1, distance below the top); top = 999 when no peak here
vec3 ivPeaks(float x, float base, float hMin, float hMax, float spacing, float seed) {
    float cell = floor(x / spacing);
    vec3 best = vec3(999.0, 0.0, 0.0);
    for (int k = -1; k <= 1; k++) {
        float c = cell + float(k);
        float cx = (c + 0.2 + 0.6 * hash1(c + seed)) * spacing;
        float h = mix(hMin, hMax, hash1(c * 1.7 + seed + 3.0));
        float w = h * (1.1 + 0.5 * hash1(c + seed + 7.0));
        float dx = x - cx;
        // jagged flanks: a few notches on each side
        float j = (vnoise(vec2(x * 0.18, c + seed)) - 0.5) * 7.0;
        float top = base - h * (1.0 - abs(dx) / w) + j * (abs(dx) / w);
        if (abs(dx) < w && top < best.x) best = vec3(top, step(dx, 0.0), h);
    }
    return best;
}

// outlined text: 1 = glyph, 0.5 = outline, 0 = nothing
float ivGlyph(int row, vec2 q, int n) {
    if (strAt(row, floor(q), 0, n) > 0.5) return 1.0;
    float o = 0.0;
    for (int y = -1; y <= 1; y++)
        for (int x = -1; x <= 1; x++) o = max(o, strAt(row, floor(q) + vec2(x, y), 0, n));
    return o * 0.5;
}

vec3 part(vec2 p) {
    const float BAR = 4.0 * (60.0 / 90.0);
    float drift = uLT * 3.0;                      // slow parallax pan
    const float HOR = 168.0;
    // ---- sky: banded dusk gradient
    float sb = floor(p.y / 6.0) * 6.0 / HOR;
    vec3 col = mix(DEEP * 0.4, PURP * 0.5, smoothstep(0.1, 0.8, sb));
    col = mix(col, vec3(0.95, 0.35, 0.45), smoothstep(0.62, 0.95, sb) * 0.8);
    col = mix(col, GOLD, smoothstep(0.84, 1.0, sb) * 0.8);
    // stars: chunky, twinkling on the beat
    vec2 sc = floor((p + vec2(drift * 0.2, 0.0)) / 10.0);
    float sh = hash2(sc);
    if (sh > 0.86 && p.y < 110.0) {
        vec2 sp = sc * 10.0 + 2.0 + floor(hash2(sc + 3.1) * 6.0) - vec2(drift * 0.2, 0.0);
        vec2 d = abs(p - sp - 0.5);
        float tw = 0.5 + 0.5 * sin(uBeat * PI + sh * 40.0);
        bool big = sh > 0.965;
        float on = (d.x < 1.0 && d.y < 1.0) ? 1.0 : (big && ((d.x < 0.6 && d.y < 3.0) || (d.y < 0.6 && d.x < 3.0))) ? 0.7 : 0.0;
        col = mix(col, mix(LAV, CREAM, tw), on * (0.45 + 0.55 * tw));
    }
    // moon
    vec2 md = p - vec2(266.0 - drift * 0.3, 40.0);
    if (length(md) < 15.0 && length(md - vec2(6.0, -4.0)) > 13.0) col = CREAM;
    // wispy cloud bands
    float cl = fbm(vec2((p.x + uLT * 9.0) * 0.012, p.y * 0.05));
    float cband = smoothstep(0.55, 0.7, cl) * smoothstep(70.0, 110.0, p.y) * (1.0 - smoothstep(140.0, 160.0, p.y));
    col = mix(col, mix(ROYAL, vec3(0.95, 0.5, 0.55), smoothstep(100.0, 150.0, p.y)), floor(cband * 3.0) / 3.0 * 0.6);

    // ---- mountains: a hazy back row and a darker front row, lit from the left, snow on the peaks
    vec3 bk = ivPeaks(p.x + drift * 0.25 + 500.0, HOR - 4.0, 30.0, 62.0, 70.0, 11.0);
    if (p.y > bk.x) {
        col = mix(mix(PLUM, ROYAL, 0.55), mix(ROYAL, LAV, 0.35), bk.y);
        float apex = HOR - 4.0 - bk.z;
        if (p.y < apex + bk.z * 0.28 + sin(p.x * 0.9) * 2.0 && bk.z > 40.0) col = mix(LAV, CREAM, bk.y * 0.8);
        col = mix(col, vec3(0.8, 0.35, 0.55), smoothstep(HOR - 30.0, HOR, p.y) * 0.45);
    }
    vec3 fr = ivPeaks(p.x + drift * 0.55, HOR + 8.0, 16.0, 38.0, 52.0, 23.0);
    if (p.y > fr.x) col = mix(DEEP * 0.9, PLUM, fr.y);
    // ---- rolling mid hills
    float x2 = p.x + drift * 0.8;
    float r2 = 184.0 + 7.0 * sin(x2 * 0.021 + 1.0) + 4.0 * sin(x2 * 0.053 + 2.0);
    if (p.y > r2) {
        float slope = cos(x2 * 0.021 + 1.0) * 0.15 + cos(x2 * 0.053 + 2.0) * 0.21;
        col = mix(DEEP * 0.75, PLUM, ivPaint(0.55 - slope, 3.0));
        if (p.y - r2 < 2.0) col = ROYAL;
        // lit windows scattered on the hills
        vec2 wc = floor(vec2(x2 / 22.0, (p.y - r2) / 9.0));
        if (hash2(wc) > 0.88 && wc.y >= 1.0 && wc.y < 3.0) {
            vec2 wp = vec2(mod(x2, 22.0), mod(p.y - r2, 9.0));
            if (wp.x > 8.0 && wp.x < 11.0 && wp.y > 3.0 && wp.y < 6.0) col = mix(GOLD, CREAM, 0.5 + 0.5 * sin(uT * 5.0 + wc.x));
        }
    }

    // ---- the floating island
    float bob = sin(uLT * 1.3) * 3.0;
    vec2 ic = vec2(160.0, 166.0 + bob);
    vec2 ip = p - ic;
    // rocky underside: an inverted, jagged cone
    float hw = 64.0 * (1.0 - clamp(ip.y / 58.0, 0.0, 1.0));
    hw += (vnoise(vec2(ip.y * 0.25, 3.0)) - 0.5) * 12.0 * clamp(ip.y / 20.0, 0.0, 1.0);
    if (ip.y > -2.0 && ip.y < 58.0 && abs(ip.x) < hw) {
        float side = ip.x / max(hw, 1.0);
        float strata = floor((ip.y + vnoise(vec2(ip.x * 0.1, 1.0)) * 6.0) / 7.0);
        float li = ivPaint(0.55 - side * 0.55 + (hash1(strata) - 0.5) * 0.25 - ip.y * 0.004, 4.0);
        col = li < 0.2 ? DEEP * 0.6 : li < 0.5 ? vec3(0.45, 0.26, 0.42) : li < 0.8 ? vec3(0.72, 0.45, 0.55) : vec3(0.95, 0.66, 0.55);
        if (abs(ip.x) > hw - 2.5 && ip.x < 0.0) col = GOLD * 0.9;            // rim light on the lit edge
        if (abs(ip.x) > hw - 2.0 && ip.x > 0.0) col = DEEP * 0.3;            // dark outline on the shadow edge
        if (ip.y < 3.0) col = mix(GOLD * 0.6, GOLD, step(0.0, -ip.x));   // lit grass lip
    }
    // hanging roots below the tip
    if (ip.y > 44.0 && ip.y < 68.0) {
        for (int r = -1; r <= 1; r++) {
            float rx = abs(ip.x - float(r) * 7.0 - 2.0 * sin(ip.y * 0.3 + float(r)));
            if (rx < 1.2 && ip.y < 68.0 - abs(float(r)) * 9.0) col = PLUM * 1.2;
        }
    }
    // the canopy: a stack of shaded foliage blobs, gold-lit from the upper left
    for (int i = 0; i < 12; i++) {
        float fi = float(i);
        float hx = hash1(fi * 3.1) - 0.5;
        vec2 c = ic + vec2(hx * 104.0, -8.0 - (1.0 - 4.0 * hx * hx) * 16.0 - hash1(fi * 5.7) * 6.0);
        float rr = 13.0 + hash1(fi * 2.3) * 8.0;
        c.x += sin(uLT * 1.1 + fi) * 0.8;
        vec2 d = (p - c) / rr;
        float l2 = dot(d, d);
        float edge = 1.0 - 0.12 * sin(atan(d.y, d.x) * 7.0 + fi);   // bumpy silhouette
        if (l2 < edge * edge && p.y < ic.y + 2.0) {
            vec3 n = vec3(d, sqrt(max(0.0, 1.0 - l2)));
            float li = dot(n, normalize(vec3(-0.6, -0.7, 0.4))) * 0.7 + 0.3 + (vnoise(p * 0.4) - 0.5) * 0.35;
            col = li < 0.3 ? DEEP : li < 0.55 ? PURP * 0.65 : li < 0.8 ? mix(PURP, LAV, 0.35) : li < 0.93 ? mix(LAV, GOLD, 0.5) : GOLD;
        }
    }
    // ---- foreground boulders (in front of the island's roots)
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        vec2 c = vec2(fi * 42.0 - 10.0 + hash1(fi) * 16.0 - mod(drift * 1.4, 42.0) + 21.0, 240.0 - hash1(fi + 5.0) * 8.0);
        float rr = 20.0 + hash1(fi + 9.0) * 12.0;
        vec2 d = (p - c) / rr;
        d.y *= 1.45;
        float l2 = dot(d, d);
        if (l2 < 1.0) {
            vec3 n = vec3(d, sqrt(1.0 - l2));
            float li = ivPaint(dot(n, normalize(vec3(-0.5, -0.7, 0.6))) * 0.85 + 0.2, 4.0);
            col = mix(DEEP * 0.5, mix(ROYAL, LAV, 0.25), li);
            if (fract(d.x * 3.0 + d.y * 5.0 + hash1(fi)) < 0.08 && li > 0.2) col *= 0.7;   // cracks
        }
    }

    // ---- the ESA cube hovering over the island
    float kick = uEnv.w;
    vec2 lc = vec2(160.0, 54.0 + bob * 1.3 + sin(uLT * 2.1) * 2.0);
    float gl = length((p - lc) / vec2(1.0, 0.9));
    col += GOLD * 0.3 * (0.4 + 0.8 * kick) * (1.0 - smoothstep(20.0, 56.0 + 10.0 * kick, gl));
    vec4 lg = logoAt(p, lc, 72.0);
    col = mix(col, lg.rgb, lg.a);

    // ---- text writer: one line per bar, typed at a steady rate with a blinking block cursor
    int line = min(3, int(uLT / BAR));
    float lb = uLT - float(line) * BAR;
    int n = strLen(line);
    float scl = n <= 18 ? 2.0 : 1.5;
    if (float(n) * 8.0 * scl > 312.0) scl = 1.0;
    float w = float(n) * 8.0 * scl;
    vec2 tp = vec2(floor((uRes.x - w) * 0.5), 102.0);
    int typed = clamp(int((lb - 0.12) / 0.075), 0, n);
    vec2 q = (p - tp) / scl;
    float g = ivGlyph(line, q, typed);
    if (g > 0.75) col = mix(CREAM, GOLD, step(4.0, mod(q.y, 8.0)));
    else if (g > 0.25) col = DEEP * 0.4;
    // cursor: solid block while typing, blinks on the beat once the line is done
    bool blink = typed < n || fract(uBeat) < 0.5;
    vec2 cp = tp + vec2(float(typed) * 8.0 * scl, 0.0);
    if (blink && p.x >= cp.x && p.x < cp.x + 7.0 * scl && p.y >= cp.y && p.y < cp.y + 8.0 * scl) col = GOLD;
    return col;
}
