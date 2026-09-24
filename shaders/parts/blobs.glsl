// @id blobs
// @name PHONG BLOBS
// @split BLOBS
// @bars 4
// @order 130
// @default off
// @inspired Complex - Dope (1995)
// @desc Morphing metaballs with phong and environment-mapped shading in gold, purple and cream, pulsing on the kick in front of a rotating ring of brand-coloured fire.
// @str 0 PERSONAL
// @str 1 BEST
// @str 2 SUM OF
// @str 3 BEST
// @str 4 GOLD
// @str 5 SPLITS
// @str 6 WORLD
// @str 7 RECORD
// @str 8 {EVENT}

const float BL_BAR = 8.0 / 3.0;

float bl_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

vec3 bl_ctr(int i, float t) {
    float fi = float(i);
    return vec3(sin(t * (0.61 + fi * 0.13) + fi * 1.7) * 0.8,
                sin(t * (0.83 - fi * 0.07) + fi * 2.9) * 0.58,
                cos(t * (0.47 + fi * 0.11) + fi * 0.8) * 0.6);
}

float bl_map(vec3 p, float t, float pulse) {
    float d = 1e9;
    for (int i = 0; i < 5; i++) {
        float r = (0.42 + 0.1 * sin(t * 1.3 + float(i) * 2.1)) * pulse;
        d = bl_smin(d, length(p - bl_ctr(i, t)) - r, 0.55);
    }
    // slow organic ripple so the surface keeps morphing
    d += 0.035 * sin(p.x * 4.0 + t * 2.0) * sin(p.y * 4.3 - t * 1.6) * sin(p.z * 3.7 + t);
    return d;
}

vec3 bl_normal(vec3 p, float t, float pulse) {
    const vec2 e = vec2(0.004, -0.004);
    return normalize(e.xyy * bl_map(p + e.xyy, t, pulse) + e.yyx * bl_map(p + e.yyx, t, pulse) +
                     e.yxy * bl_map(p + e.yxy, t, pulse) + e.xxx * bl_map(p + e.xxx, t, pulse));
}

// environment map: brand gradient sky, dark plum floor, a cream window highlight
vec3 bl_env(vec3 r) {
    vec3 c = mix(esaGrad(0.95 - 1.5 * r.y), LAV, 0.25 * smoothstep(0.3, 0.0, abs(r.y)));
    c = mix(c, DEEP * 0.6, smoothstep(-0.2, -0.8, r.y));
    float win = smoothstep(0.93, 0.97, dot(r, normalize(vec3(-0.5, 0.6, 0.62))));
    c = mix(c, CREAM * 1.2, win);
    c += GOLD * 0.4 * smoothstep(0.8, 1.0, dot(r, normalize(vec3(0.8, -0.1, 0.4))));   // warm fire bounce
    return c;
}

// the fire ring behind the blob
vec3 bl_fire(vec2 p, float t) {
    vec2 c = p - uRes * 0.5;
    c.y *= 1.08;
    float r = length(c), a = atan(c.y, c.x);
    float R = 92.0 + 6.0 * uEnv.w;
    // flame noise in polar space, streaming outward and swirling
    // seamless around the circle: cross-fade the noise with its copy one turn away
    float x = a * 5.0 / PI;                                   // -5..5
    vec2 q = vec2(x + t * 0.35, r * 0.045 - t * 1.6);
    vec2 q2 = q - vec2(10.0, 0.0);
    float w = (x + 5.0) / 10.0;
    float n = mix(fbm(q + vec2(0.0, fbm(q * 0.7) * 1.4)), fbm(q2 + vec2(0.0, fbm(q2 * 0.7) * 1.4)), w);
    float band = 1.0 - abs(r - R) / (26.0 + 18.0 * n);
    float heat = clamp(band * 1.0 + (n - 0.5) * 1.1, 0.0, 1.0);
    heat = floor(heat * 8.0) / 8.0;                          // stepped like an 8-bit fire palette
    vec3 col = heat < 0.25 ? mix(DEEP * 0.5, PLUM, heat / 0.25)
             : heat < 0.5 ? mix(PLUM, PURP, (heat - 0.25) / 0.25)
             : heat < 0.8 ? mix(PURP, GOLD, (heat - 0.5) / 0.3)
             : mix(GOLD, CREAM, (heat - 0.8) / 0.2);
    // inner dark disc and faint rotating spokes behind the blob
    float spokes = 0.5 + 0.5 * sin(a * 8.0 + t * 0.9 + r * 0.02);
    vec3 bg = mix(DEEP * 0.45, PLUM * 0.7, spokes * smoothstep(20.0, 80.0, r) * (1.0 - smoothstep(80.0, 180.0, r)));
    bg = mix(bg, DEEP * 0.3, smoothstep(130.0, 200.0, r));
    return mix(bg, col, smoothstep(0.05, 0.3, heat));
}

vec3 part(vec2 p) {
    float t = uLT + uKickCum * 0.25;
    float pulse = 1.0 + 0.14 * uEnv.w * uFx;
    vec3 col = bl_fire(p, uT);

    // camera
    vec3 ro = vec3(0.0, 0.0, 3.7);
    vec2 uv = screenUV(p);
    vec3 rd = normalize(vec3(uv * 0.62, -1.0));
    float a = uLT * 0.4;
    mat3 R = mat3(cos(a), 0, -sin(a), 0, 1, 0, sin(a), 0, cos(a));
    ro = R * ro; rd = R * rd;

    // bounding sphere reject
    float b = dot(ro, rd), q = dot(ro, ro) - 2.1 * 2.1, h = b * b - q;
    if (h > 0.0) {
        h = sqrt(h);
        float tt = max(-b - h, 0.0), tEnd = -b + h;
        bool hit = false;
        for (int i = 0; i < 56; i++) {
            float d = bl_map(ro + rd * tt, t, pulse);
            if (d < 0.002) { hit = true; break; }
            tt += d * 0.9;
            if (tt > tEnd) break;
        }
        if (hit) {
            vec3 P = ro + rd * tt;
            vec3 n = bl_normal(P, t, pulse);
            vec3 rv = reflect(rd, n);
            // camera-relative env lookup so the highlight stays put while the camera orbits
            vec3 rc = transpose(R) * rv, nc = transpose(R) * n;
            vec3 L = normalize(vec3(-0.5, 0.6, 0.62));
            float dif = max(dot(nc, L), 0.0);
            float fres = pow(1.0 - max(dot(-rd, n), 0.0), 2.0);
            vec3 base = mix(PURP * 0.55, mix(PURP, LAV, 0.4), 0.5 + 0.5 * nc.y);
            vec3 c = base * (0.25 + 0.55 * dif);
            c = mix(c, bl_env(rc), 0.55 + 0.35 * fres);
            float sp = pow(max(dot(rc, L), 0.0), 36.0);
            c += CREAM * sp * 1.1;
            // fire rim light from behind
            c += GOLD * 0.5 * pow(fres, 1.5) * (0.6 + 0.4 * uEnv.w);
            col = c;
        }
    }

    // caption: a speedrun term per bar in the top-left, the event bottom-right
    int bar = int(min(3.0, floor(uLT / BL_BAR)));
    float lb = uLT - float(bar) * BL_BAR;
    float slide = (1.0 - easeOut(lb / 0.4)) * -140.0;
    col = drawStr(col, p, bar * 2, vec2(14.0 + slide, 14.0), 2.0, TS_CHROME, 1.0);
    col = drawStr(col, p, bar * 2 + 1, vec2(14.0 + slide * 1.3, 32.0), 2.0, TS_GOLD, 1.0);
    col = drawStr(col, p, 8, vec2(uRes.x - 14.0 - strW(8, 1.0), 218.0), 1.0, TS_LAV, 1.0);
    return col;
}
