// @id stage
// @name THE STAGE
// @split THE STAGE
// @bars 4
// @order 40
// @default on
// @inspired GOOSE original: Mega Drive parallax platformer with a LiveSplit HUD
// @desc Dusk parallax hills with line-scroll heat haze; the cube hops along with speed-shoes afterimages while LiveSplit shows the trailer's real splits.
// @str 0 TRAILER - ANY%

float layerH(float x, float a, float b, float c) { return a + b * sin(x * c) + b * 0.45 * sin(x * c * 2.7 + 1.3); }

vec3 part(vec2 p) {
    float sp = uLT * 150.0 + uKickCum * 40.0;
    float sb = floor(p.y / 12.0) * 12.0 / 150.0;
    vec3 col = mix(DEEP, PURP * 0.75, clamp(sb, 0.0, 1.0));
    col = mix(col, vec3(1.0, 0.45, 0.25), smoothstep(0.55, 1.05, sb));
    vec2 sd = p - vec2(236.0, 104.0);
    if (length(sd) < 36.0) {
        bool cut = sd.y > 0.0 && mod(p.y, 7.0) < (sd.y / 36.0) * 4.0 + 0.5;
        if (!cut) col = mix(GOLD, vec3(1.0, 0.35, 0.3), clamp((sd.y + 36.0) / 72.0, 0.0, 1.0));
    }
    float x1 = p.x + sp * 0.12;
    if (p.y > layerH(x1, 118.0, 16.0, 0.021)) col = PLUM * 0.95;
    float x2 = p.x + sp * 0.42 + sin(p.y * 0.35 + uT * 7.0) * 1.2;
    float h2 = layerH(x2, 150.0, 12.0, 0.017);
    if (p.y > h2) {
        vec2 c2 = floor(vec2(x2, p.y - h2) / 12.0);
        col = mod(c2.x + c2.y, 2.0) > 0.5 ? ROYAL : PLUM;
        if (p.y - h2 < 3.0) col = GOLD * 0.85;
    }
    float gy = 198.0;
    if (p.y > gy) {
        vec2 c3 = floor(vec2((p.x + sp) / 16.0, (p.y - gy) / 8.0));
        col = mod(c3.x + c3.y, 2.0) > 0.5 ? vec3(0.70, 0.37, 0.05) : vec3(0.47, 0.22, 0.04);
        if (p.y - gy < 5.0) col = mix(PURP, LAV, step(p.y - gy, 1.0));
    }
    // runner: the ESA cube hopping every other beat, with an afterimage trail
    for (int k = 3; k >= 0; k--) {
        float ph = fract((uBeat - float(k) * 0.12) / 2.0);
        vec2 o = vec2(182.0 - float(k) * 11.0, gy - 30.0 - 44.0 * 4.0 * ph * (1.0 - ph));
        vec2 lp = (p - o) / 30.0;
        if (lp.x >= 0.0 && lp.y >= 0.0 && lp.x < 1.0 && lp.y < 1.0) {
            vec4 l = texture(uLogo, (lp - 0.5) * 0.92 + 0.5);
            if (l.a > 0.5) col = mix(col, k == 0 ? l.rgb : mix(PURP, LAV, 0.4), k == 0 ? 1.0 : 0.45 - float(k) * 0.1);
        }
    }
    // LiveSplit: the arrangement's own splits, 7 rows around the current one
    int first = clamp(uSplitCur - 5, 0, max(0, uSplitN - 7));
    if (p.x > 4.0 && p.x < 156.0 && p.y > 4.0 && p.y < 130.0) {
        col = mix(col, DEEP * 0.55, 0.82);
        if (p.y > 30.0 && p.y < 31.0) col = ROYAL;
        float cur = 34.0 + float(uSplitCur - first) * 10.0;
        if (p.y > cur - 2.0 && p.y < cur + 9.0) col = mix(col, PURP * 0.6, 0.8);
    }
    col = drawStr(col, p, 16, vec2(10.0, 10.0), 1.0, TS_GOLD, 1.0);
    col = drawStr(col, p, 0, vec2(10.0, 20.0), 1.0, TS_GREY, 1.0);
    for (int j = 0; j < 7; j++) {
        int i = first + j;
        if (i >= uSplitN) break;
        float y = 34.0 + float(j) * 10.0;
        bool cur = i == uSplitCur;
        col = drawStr(col, p, 20 + i, vec2(10.0, y), 1.0, cur ? TS_WHITE : TS_GREY, 1.0);
        if (!cur && uT >= uSplitT[i]) col = drawTime(col, p, uSplitT[i], 150.0, y, 1.0, j == 3 ? TS_GOLD : TS_GREEN);
        else col = drawChar(col, p, 45, vec2(142.0, y), 1.0, TS_GREY);
    }
    return drawTime(col, p, uT, 150.0, 110.0, 2.0, TS_GREEN);
}
