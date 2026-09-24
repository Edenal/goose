// @id spiral
// @name TILE SPIRAL
// @split SPIRAL
// @bars 4
// @order 160
// @default off
// @inspired Orange - Project XYZ (1995)
// @desc A rotating galaxy of square tiles textured with the ESA cube's faces, streaming out of the core with motion blur. The arms wind tighter or looser on every bar.
// @str 0 {EVENT}

const float SP_N = 18.0;     // tiles around the circle
const float SP_ARM = 6.0;    // tiles per arm period (3 arms)

// arm shear per bar: how tightly the log-spiral winds
float spiralShear(float lt) {
    float bar = 4.0 * (60.0 / 90.0);
    const float K[5] = float[](0.55, 1.65, 0.85, 2.3, 1.2);
    int i = int(clamp(floor(lt / bar), 0.0, 3.0));
    float f = (lt - float(i) * bar) / 0.9;
    float e = f >= 1.0 ? 1.0 : easeOut(f) + sin(clamp(f, 0.0, 1.0) * PI) * 0.12;   // small overshoot
    float k0 = i == 0 ? 1.1 : K[i - 1];
    return mix(k0, K[i], e);
}

vec4 spiralTiles(vec2 p, float lt, float kick) {
    vec2 ctr = uRes * 0.5 + vec2(sin(lt * 0.5) * 18.0, cos(lt * 0.4) * 10.0);
    vec2 c = (p - ctr) / uRes.y;
    float r = max(length(c), 1e-4);
    float th = atan(c.y, c.x) + lt * 0.55 + kick * 0.12;
    float k = spiralShear(lt);
    float v = log(r) * SP_N / (2.0 * PI) - lt * 1.25 - kick * 0.35;   // tiles stream outwards and grow
    float u = th * SP_N / (2.0 * PI) + k * v;
    vec2 cell = floor(vec2(u, v));
    vec2 f = fract(vec2(u, v));
    float a = mod(cell.x, SP_ARM);
    float arm = floor(mod(cell.x, SP_N) / SP_ARM);
    float h = hash2(vec2(mod(cell.x, SP_N), cell.y));
    bool on = a < 2.0 && h > 0.12;
    // stray tiles drifting between the arms
    if (!on && a == 3.0 && h > 0.82) on = true;
    if (!on) return vec4(0.0);
    // square tile with a gap
    float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    if (e < 0.07) return vec4(0.0);
    int face = int(mod(cell.x + cell.y, 3.0));
    vec2 tuv = (f - 0.07) / 0.86;
    vec4 tx = face == 0 ? texture(uTop, tuv) : face == 1 ? texture(uLeft, tuv) : texture(uRight, tuv);
    vec3 tint = arm < 0.5 ? GOLD : arm < 1.5 ? PURP : LAV;
    vec3 col = mix(DEEP, tx.rgb, tx.a);
    float wht = smoothstep(0.70, 0.92, min(col.r, min(col.g, col.b)));
    col = mix(col, tint * mix(0.75, 1.0, 1.0 - f.y), wht * 0.9);
    if (e < 0.13) col = mix(col, CREAM, 0.55);          // bright bevel
    col *= 0.55 + 0.6 * smoothstep(0.02, 0.35, r);      // darker in the core
    return vec4(col, smoothstep(0.035, 0.09, r));
}

vec3 part(vec2 p) {
    vec2 c = (p - uRes * 0.5) / uRes.y;
    float r = length(c);
    // deep space: plum haze, faint arm glow, stars, a hot core
    vec3 bg = mix(PLUM * 0.9, DEEP * 0.55, smoothstep(0.0, 0.8, r));
    bg += stars(p, 0.05, uT, 0.55);
    bg += GOLD * (0.9 + 0.8 * uEnv.w) * exp(-r * 9.0);
    bg += PURP * 0.35 * exp(-r * 3.0);

    // fake motion blur: the tiles at four slightly earlier times, the newest one on top
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 4; i++) {
        float dt = float(i) * 0.045 * (1.0 + 0.8 * uEnv.w);
        vec4 s = spiralTiles(p, uLT - dt, uKickCum - dt * uEnv.w * 2.0);
        float w = i == 0 ? 1.0 : 0.55 / float(i);
        acc += mix(bg, s.rgb, s.a) * w;
        wsum += w;
    }
    vec3 col = acc / wsum;
    vec4 s0 = spiralTiles(p, uLT, uKickCum);
    col = mix(col, s0.rgb, s0.a * 0.55);   // keep the current frame crisp
    col = drawStrC(col, p, 0, 216.0, 2.0, TS_CHROME, 1.0);
    return col;
}
