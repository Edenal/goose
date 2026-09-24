// @id julia
// @name JULIA DREAM
// @split JULIA
// @bars 4
// @order 170
// @default off
// @inspired Electromotive Force - Verses (1994)
// @desc A morphing Julia set in a palette-cycled gold-to-purple ramp, slowly zooming and turning. Its constant orbits a path and hops to a new region on every bar.
// @str 0 {EVENT}

// constant centres: one region per bar (all on the edge of the Mandelbrot set, where Julias are richest)
vec2 juliaC(float lt, out float lb) {
    float bar = 4.0 * (60.0 / 90.0);
    int i = int(clamp(floor(lt / bar), 0.0, 3.0));
    lb = lt - float(i) * bar;
    const vec2 C[4] = vec2[](vec2(-0.790, 0.150), vec2(0.280, 0.010), vec2(-0.120, 0.750), vec2(-0.835, -0.232));
    const float R[4] = float[](0.030, 0.012, 0.035, 0.025);
    float a = lt * 1.3 + float(i) * 1.7;
    return C[i] + R[i] * vec2(cos(a), sin(a * 1.3));
}

vec3 part(vec2 p) {
    float lb;
    vec2 c = juliaC(uLT, lb);
    float punch = uLT > 2.0 ? exp(-lb * 5.0) : 0.0;                       // hop: a quick zoom punch on the bar line
    float zoom = 1.45 * exp(-lb * 0.10) * (1.0 + 0.35 * punch) * (1.0 - 0.03 * uEnv.w);
    vec2 uv = screenUV(floor(p / 2.0) * 2.0 + 1.0);       // chunky 160x120 like a VGA mode-X fractal
    vec2 z = rot2(uLT * 0.22) * uv * zoom;
    float n = 0.0;
    float m2 = 0.0;
    const int IT = 88;
    for (int i = 0; i < IT; i++) {
        z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        m2 = dot(z, z);
        if (m2 > 256.0) break;
        n += 1.0;
    }
    vec3 col;
    if (n >= float(IT)) {
        // inside: deep plum with slow purple rings from the orbit's final radius
        float ring = fract(sqrt(m2) * 2.0 - uLT * 0.5);
        col = mix(DEEP * 0.7, PLUM * 1.2, step(0.5, ring) * 0.6);
    } else {
        float sn = n - log2(log2(m2)) + 4.0;             // smooth iteration count
        float x = sn * 0.055 - uT * 0.45;                // palette cycling
        float idx = floor(fract(x) * 24.0) / 24.0;       // stepped like a 256-colour ramp
        col = cyclePal(idx);
        // near the set the ramp brightens toward cream, the far field sinks to plum
        col = mix(col, CREAM, smoothstep(30.0, 70.0, sn) * 0.45);
        col = mix(mix(DEEP * 0.9, PLUM * 1.3, step(0.5, fract(sn * 0.5 - uT * 0.9))), col, smoothstep(3.0, 13.0, sn));
        col *= 0.85 + 0.35 * uEnv.w * step(0.5, fract(x * 3.0));
    }
    col += CREAM * punch * 0.35;                         // flash on the hop
    // small caption with a dark band
    if (p.y > 206.0 && p.y < 230.0) col = mix(col, DEEP * 0.6, 0.65);
    col = drawStrC(col, p, 0, 210.0, 2.0, TS_GOLD, 1.0);
    return col;
}
