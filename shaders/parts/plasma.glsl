// @id plasma
// @name PLASMA
// @split PLASMA
// @bars 4
// @order 30
// @default on
// @inspired GOOSE original: palette-cycled plasma with a raster text band
// @desc Chunky 160x120 plasma cycling through the brand palette; one big chrome word per bar drops into a raster band.
// @str 0 SPEEDRUNS
// @str 1 LIVE ON TWITCH
// @str 2 FOR CHARITY
// @str 3 {EVENT}

vec3 part(vec2 p) {
    float t = uT;
    vec2 q = floor(p / 2.0) * 2.0;
    float v = sin(q.x * 0.045 + t * 1.3) + sin(q.y * 0.061 - t * 0.9) + sin((q.x + q.y) * 0.031 + t * 0.7)
            + sin(length(q - vec2(160.0 + 80.0 * sin(t * 0.6), 120.0 + 60.0 * cos(t * 0.5))) * 0.065);
    float idx = floor(fract(v * 0.18 + t * 0.12) * 16.0) / 16.0;
    vec3 col = cyclePal(idx) * (0.75 + 0.35 * uEnv.x);
    float band = smoothstep(84.0, 88.0, p.y) * (1.0 - smoothstep(140.0, 144.0, p.y));
    col = mix(col, mix(DEEP * 0.6, DEEP * 1.1, mod(floor(p.y / 2.0), 2.0)), band * 0.85);
    if (abs(p.y - 86.0) < 1.0 || abs(p.y - 142.0) < 1.0) col = mix(GOLD, CREAM, 0.5 + 0.5 * sin(p.x * 0.1 - t * 8.0));
    // one word per bar, dropping in with a small bounce
    float bar = 4.0 * (60.0 / 90.0);
    int i = min(3, int(uLT / bar));
    float lb = uLT - float(i) * bar;
    float sc = strLen(i) > 11 ? 2.0 : 3.0;
    float drop = (1.0 - easeOut(lb / 0.35)) * -60.0 + sin(min(1.0, lb / 0.5) * PI) * 4.0;
    return drawStrC(col, p, i, 112.0 - 4.0 * sc + drop, sc, TS_CHROME, 1.0);
}
