// @id hyperspace
// @name HYPERSPACE
// @split HYPER
// @bars 4
// @order 220
// @default off
// @inspired Acme - 303 (1997)
// @desc A radial-blurred speed-line starburst explodes from the centre, a glossy hexagon floor and ceiling rush past, light bursts on the kick and a speedrun word slams in on every bar.
// @str 0 GO!
// @str 1 SPEED
// @str 2 RUN
// @str 3 {EVENT}

const float HS_BAR = 4.0 * (60.0 / 90.0);

// hex grid: returns (distance to the cell edge 0..0.5, cell id hash)
vec2 hsHex(vec2 x) {
    const vec2 s = vec2(1.0, 1.7320508);
    vec4 hc = floor(vec4(x, x - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
    vec4 h = vec4(x - hc.xy * s, x - (hc.zw + 0.5) * s);
    vec4 c = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 9.73);
    vec2 a = abs(c.xy);
    float e = 0.5 - max(dot(a, s * 0.5), a.x);
    return vec2(e, hash2(c.zw));
}

// the scene behind the radial blur: hex floor + ceiling rushing past and the white-hot core
vec3 hsScene(vec2 uv, float floorAmt) {
    float r = length(uv);
    vec3 col = mix(PURP * 0.35, DEEP * 0.3, smoothstep(0.0, 1.2, r));
    if (floorAmt > 0.0 && abs(uv.y) > 0.02) {
        float t = 0.55 / abs(uv.y);
        vec2 w = vec2(uv.x * t * 1.1, t * 1.1 + uLT * 5.0 + uKickCum * 1.5);
        vec2 hx = hsHex(w);
        float beat = floor(uBeat);
        float lit = step(0.82, hash1(hx.y * 91.0 + beat)) * (1.0 - fract(uBeat));   // tiles flash on the beat
        vec3 tile = mix(DEEP * 0.8, PURP * 0.6, hx.y);
        tile = mix(tile, mix(PURP, LAV, 0.3), smoothstep(0.16, 0.08, hx.x));             // raised bevel
        tile += GOLD * lit * 0.8;
        tile = mix(tile, uv.y < 0.0 ? GOLD : LAV, 1.0 - smoothstep(0.035, 0.05 + 0.015 * t, hx.x));   // bright seams
        float fog = exp(-t * 0.35);
        col = mix(col, tile, floorAmt * fog * smoothstep(0.02, 0.12, abs(uv.y)));
    }
    // the core: white-hot, swelling on the kick
    float core = exp(-r / (0.05 + 0.13 * uEnv.w));
    col += mix(GOLD, CREAM, 0.6) * core * 1.6;
    return col;
}

vec3 part(vec2 p) {
    int bar = min(3, int(uLT / HS_BAR));
    float lb = uLT - float(bar) * HS_BAR;
    vec2 ctr = uRes * 0.5 + vec2(sin(uLT * 1.1) * 10.0, cos(uLT * 0.8) * 6.0);
    vec2 uv = (p - ctr) / (uRes.y * 0.5) * vec2(1.0, -1.0);
    float r = length(uv), ang = atan(uv.y, uv.x);
    float floorAmt = smoothstep(0.6, 2.6, uLT);

    // radial blur: average the scene along the ray back to the centre; stretches harder on the kick
    float blur = 0.005 + 0.012 * uEnv.w + 0.045 * (1.0 - floorAmt);
    vec3 col = vec3(0.0);
    for (int k = 0; k < 8; k++) col += hsScene(uv * (1.0 - float(k) * blur), floorAmt);
    col /= 8.0;

    // speed lines: thin angular sectors with streaks flying outward, faster on the drums
    float sec = ang / (2.0 * PI) * 120.0;
    float id = floor(sec);
    float h = hash1(id * 1.31 + 7.0);
    float lane = abs(fract(sec) - 0.5);
    float u = log(r + 0.02) * 1.3 - uLT * (1.4 + 1.2 * h) - uKickCum * 0.5 - h * 9.0;
    float len = 0.25 + 0.35 * hash1(id + 3.0);
    float streak = step(fract(u), len) * step(lane, 0.28) * step(0.35 + 0.2 * floorAmt, h);
    float burst = 1.0 - floorAmt * 0.35;                         // the opening starburst is densest
    vec3 sc = h > 0.8 ? CREAM : h > 0.6 ? GOLD : mix(PURP, LAV, 0.5);
    float onFloor = floorAmt * smoothstep(0.15, 0.45, abs(uv.y));
    col += sc * streak * smoothstep(0.08, 0.35, r) * (0.55 + 0.7 * uEnv.w) * burst * (1.0 - 0.6 * onFloor) * (0.6 + fract(u) / len * 0.5);

    // the word for this bar slams in big, with a purple zoom echo trailing out of it
    float sc0 = max(1.0, floor(min(6.0, 300.0 / (float(strLen(bar)) * 8.0))));
    float punch = 1.0 + 0.8 * (1.0 - easeOut(lb / 0.25));
    float on = step(0.0, lb) * step(fract(uBeat), 0.85);          // blinks off just before each beat
    for (int j = 1; j >= 0; j--) {
        float s = floor(sc0 * punch * (1.0 + float(j) * 0.35) + 0.5);
        if (j == 0) s = min(s, max(1.0, floor(312.0 / (float(strLen(bar)) * 8.0))));   // the word itself always fits
        vec2 pos = floor(ctr - vec2(strW(bar, s), 8.0 * s) * 0.5);
        if (j > 0 && sc0 < 3.0) continue;
        if (j > 0) {
            vec2 q = floor((p - pos) / s);
            if (strAt(bar, q, 0, 256) > 0.5) col = mix(col, PURP * 0.8, 0.5);
        } else if (on > 0.5) {
            // dark keyline so the word never drowns in the streaks or the core
            vec2 q = floor((p - pos) / s);
            float ol = 0.0;
            for (int y = -1; y <= 1; y++)
                for (int x = -1; x <= 1; x++) ol = max(ol, strAt(bar, q + vec2(x, y), 0, 256));
            if (ol > 0.5) col = DEEP * 0.35;
            bool flash = fract(uBeat) < 0.12;
            col = drawStr(col, p, bar, pos, s, flash ? TS_WHITE : TS_CHROME, 1.0);
        }
    }
    return col;
}
