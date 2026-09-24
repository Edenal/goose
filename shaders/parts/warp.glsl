// @id warp
// @name CHECKER WARP
// @split WARP
// @bars 4
// @order 150
// @default off
// @inspired Cascada - Hex Appeal (1993)
// @desc A full-screen checkerboard waving like a rubber flag, with a credits roll scrolling up through the same warp. The distortion swells on every kick.
// @str 0 {EVENT}
// @str 1 SPEEDRUNS
// @str 2 FOR CHARITY
// @str 3 RUNNERS
// @str 4 HOSTS
// @str 5 COMMENTARY
// @str 6 TECH CREW
// @str 7 VOLUNTEERS
// @str 8 VIEWERS
// @str 9 GOTTA GO FAST
// @str 10 ESA

const int WARP_LINES = 11;
const float WARP_GAP = 56.0;

float warpAmp() { return (1.0 + 0.9 * uEnv.w) * (0.85 + 0.15 * uFx); }

// the rubber-sheet field: three travelling sine layers, returns an offset in pixels
vec2 warpField(vec2 p, float t, float amp) {
    vec2 d;
    d.x = sin(p.y * 0.031 + t * 1.9 + sin(p.x * 0.013 + t * 0.7) * 1.6) * 11.0
        + sin((p.x + p.y) * 0.022 - t * 1.3) * 6.0;
    d.y = sin(p.x * 0.027 - t * 1.6 + sin(p.y * 0.017 - t * 0.5) * 1.8) * 12.0
        + sin((p.x - p.y) * 0.019 + t * 1.1) * 6.0;
    return d * amp;
}

vec3 checkAt(vec2 w, float t, float bi) {
    const float CS = 26.0;
    vec2 c = floor(w / CS);
    vec2 f = fract(w / CS);
    float chk = mod(c.x + c.y, 2.0);
    vec3 grey = vec3(0.60, 0.57, 0.68);
    vec3 col = chk > 0.5 ? grey : PLUM * 1.05;
    // grey cells get a brushed-steel ramp so the sheet reads like the old metal checker
    if (chk > 0.5) col *= 0.80 + 0.30 * (1.0 - f.y);
    // gold accent cells that march with the beat
    float h = hash2(c + bi * 7.31);   // a new set of accent cells on every bar
    float beat = floor(uBeat);
    if (h < 0.10 && hash1(beat + h * 91.0) < 0.6) col = mix(GOLD, UIGOLD * 0.8, f.y);
    if (h > 0.955) col = mix(PURP, ROYAL, f.y);
    // bevelled edge on each cell
    float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    if (e < 0.06) col *= 0.72;
    return col;
}

vec3 part(vec2 p) {
    float bar = 4.0 * (60.0 / 90.0);
    float bi = floor(uLT / bar), lb = uLT - bi * bar;
    // the sheet lurches forward on every bar line, plus a push on each kick
    float t = uLT + uKickCum * 0.35 + (bi + (bi > 0.0 ? easeOut(lb / 0.6) : 1.0)) * 1.6;
    float amp = warpAmp();
    vec2 d = warpField(p, t, amp);
    vec2 w = p + d + vec2(uLT * 14.0, -uLT * 22.0);
    vec3 col = checkAt(w, t, bi);
    // light the sheet by the slope of the field (like a waving flag)
    vec2 dx = warpField(p + vec2(3.0, 0.0), t, amp) - d;
    vec2 dy = warpField(p + vec2(0.0, 3.0), t, amp) - d;
    float sh = clamp(1.0 + (dx.x + dy.y) * 0.09 - (dx.y - dy.x) * 0.03, 0.45, 1.45);
    col *= sh;
    col = mix(col, col * vec3(0.95, 0.85, 1.1), 0.35);   // plum tint

    // credits roll: big chrome lines scrolling up, bent by the same (gentler) field
    vec2 tp = p + d * 0.55;
    float scroll = uLT * 44.0;
    float y0 = 30.0 - scroll;
    for (int i = 0; i < WARP_LINES; i++) {
        float y = y0 + float(i) * WARP_GAP;
        if (tp.y < y - 8.0 || tp.y > y + 48.0) continue;
        float sc = i == WARP_LINES - 1 ? 5.0 : i == 0 ? 4.0 : 3.0;
        if (strW(i, sc) > 300.0) sc = floor(300.0 / (float(strLen(i)) * 8.0) * 2.0) * 0.5;
        int style = (i == 0 || i == WARP_LINES - 1) ? TS_GOLD : TS_CHROME;
        vec2 pos = vec2(floor((uRes.x - strW(i, sc)) * 0.5), y);
        // heavy dark outline so the text survives the busy checker
        vec2 q = floor((tp - pos) / sc);
        float ol = 0.0;
        for (int k = 0; k < 4; k++) {
            vec2 o = vec2(k == 0 ? 1.0 : k == 1 ? -1.0 : 0.0, k == 2 ? 1.0 : k == 3 ? -1.0 : 0.0);
            ol = max(ol, strAt(i, q + o, 0, 256));
        }
        ol = max(ol, strAt(i, q - vec2(2.0), 0, 256));
        if (ol > 0.5) col = DEEP * 0.5;
        col = drawStr(col, tp, i, pos, sc, style, 1.0);
    }
    // kick flash on the gold accents
    col += GOLD * 0.10 * uEnv.w;
    return col;
}
