// @id dots
// @name DOT MORPH
// @split DOTS
// @bars 4
// @order 140
// @default off
// @inspired Iguana - HeartQuake (1994)
// @desc 1,536 depth-shaded vector dots morph on every bar line: sphere, torus, cube, then a twisted helix. Near dots are big gold bobs, far dots small purple ones.
// @str 0 DOTS
// @str 1 SPHERE
// @str 2 TORUS
// @str 3 CUBE
// @str 4 HELIX
// @str 5 {EVENT}

const float DT_BAR = 8.0 / 3.0;
const int DT_G = 48, DT_M = 32;  // 48 patches of 4x8 dots = 1,536 dots
// Every shape lays its dots out in the same 48 compact 4x8 patches, so a whole patch can be culled per pixel
// with one bounding sphere. GR = that sphere's radius around the patch centre, per shape.
const float DT_GR[5] = float[](0.24, 0.57, 0.46, 0.42, 0.38);

// shape s (0 grid, 1 sphere, 2 torus, 3 cube, 4 helix), patch g (0..47), member m = (0..3, 0..7); m = (1.5, 3.5) is the centre
vec3 dt_shape(int s, float g, vec2 m) {
    if (s == 0 || s == 2) {                          // 12 x 4 patches over a 48 x 32 lattice
        float gy = floor((g + 0.5) / 12.0), gx = g - gy * 12.0;
        vec2 c = (vec2(gx * 4.0, gy * 8.0) + m + 0.5) / vec2(48.0, 32.0);
        if (s == 0) return vec3((c.x - 0.5) * 2.4, (c.y - 0.5) * 1.6, 0.0);     // flat dot grid
        float a = c.x * 2.0 * PI, b = c.y * 2.0 * PI;                          // torus
        float R = 0.82 + 0.34 * cos(b);
        return vec3(cos(a) * R, sin(b) * 0.34, sin(a) * R);
    }
    if (s == 1 || s == 3) {                          // 6 faces x 8 patches (4 x 2) of a 16 x 16 face
        float f = floor((g + 0.5) / 8.0), qd = g - f * 8.0;
        float qy = floor((qd + 0.5) / 4.0), qx = qd - qy * 4.0;
        vec2 q = (vec2(qx * 4.0, qy * 8.0) + m + 0.5) / 8.0 - 1.0;
        vec3 P = f < 0.5 ? vec3(1, q) : f < 1.5 ? vec3(-1, q.yx) : f < 2.5 ? vec3(q.y, 1, q.x)
               : f < 3.5 ? vec3(q.x, -1, q.y) : f < 4.5 ? vec3(q, 1) : vec3(q.yx, -1);
        return s == 1 ? normalize(P) * 1.08 : P * 0.72;
    }
    // helix: a twisted ribbon (helicoid), 96 along x 16 across as 24 x 2 patches
    float gy = floor((g + 0.5) / 24.0), gx = g - gy * 24.0;
    float k = (gx * 4.0 + m.x + 0.5) / 96.0, j = (gy * 8.0 + m.y + 0.5) / 16.0;
    float a = k * 2.0 * PI * 1.75;
    float w = (j * 2.0 - 1.0) * 0.72;
    return vec3(cos(a) * w, -1.05 + 2.1 * k, sin(a) * w);
}

vec3 part(vec2 p) {
    // background: plum gradient with a slow raster of darker bands and a gold horizon line
    float y = p.y;
    vec3 col = mix(DEEP * 0.5, PLUM * 0.95, smoothstep(0.0, 240.0, y));
    col *= 0.85 + 0.15 * step(0.5, fract(y / 16.0 + uT * 0.25));
    col = mix(col, GOLD * 0.6, smoothstep(1.5, 0.0, abs(y - 196.0)) * 0.6);

    // bar / morph state: shape sA morphs into sB at each bar line
    int bar = int(min(floor(uLT / DT_BAR), 3.0));
    float bl = uLT - float(bar) * DT_BAR;
    int sA = bar, sB = bar + 1;

    // rotation: steady tumble with a push on the drums
    float a1 = uLT * 0.7 + uKickCum * 0.25, a2 = 0.45 + 0.35 * sin(uLT * 0.5);
    mat3 Ry = mat3(cos(a1), 0, -sin(a1), 0, 1, 0, sin(a1), 0, cos(a1));
    mat3 Rx = mat3(1, 0, 0, 0, cos(a2), sin(a2), 0, -sin(a2), cos(a2));
    mat3 M = Rx * Ry;
    float zoom = 1.0 + 0.06 * uEnv.w;

    vec2 ctr = vec2(160.0, 112.0);
    const float CAM = 3.6, FOC = 220.0, RMAX = 3.2;
    float bestN = -1.0; vec2 bestD = vec2(0.0); float bestR = 1.0;
    for (int g = 0; g < DT_G; g++) {
        float fg = float(g);
        // per-patch morph progress (patches leave one after another); uniform across the screen
        float h = hash1(fg * 0.731 + 4.1);
        float e = clamp((bl - h * 0.5) / 0.6, 0.0, 1.0);
        e = 1.0 - (1.0 - e) * (1.0 - e) * (1.0 - e);
        int mode = e <= 0.0 ? 0 : (e >= 1.0 ? 1 : 2);
        mat2 sw = rot2(4.0 * e * (1.0 - e) * (h - 0.4));      // mid-morph swirl (rigid per patch)
        vec3 c; float rr;
        if (mode == 0)      { c = dt_shape(sA, fg, vec2(1.5, 3.5)); rr = DT_GR[sA]; }
        else if (mode == 1) { c = dt_shape(sB, fg, vec2(1.5, 3.5)); rr = DT_GR[sB]; }
        else                { c = mix(dt_shape(sA, fg, vec2(1.5, 3.5)), dt_shape(sB, fg, vec2(1.5, 3.5)), e); rr = max(DT_GR[sA], DT_GR[sB]); }
        c.xz = sw * c.xz;
        c = M * (c * zoom);
        rr *= zoom;
        float zc = CAM - c.z;
        vec2 sc = ctr + vec2(c.x, -c.y) * (FOC / zc);
        float srad = FOC * rr / (zc - rr) + RMAX + 1.0;
        if (dot(p - sc, p - sc) > srad * srad) continue;
        for (int i = 0; i < DT_M; i++) {
            float fi = float(i);
            float my = floor((fi + 0.5) / 4.0);
            vec2 m = vec2(fi - my * 4.0, my);
            vec3 P;
            if (mode == 0) P = dt_shape(sA, fg, m);
            else if (mode == 1) P = dt_shape(sB, fg, m);
            else P = mix(dt_shape(sA, fg, m), dt_shape(sB, fg, m), e);
            P.xz = sw * P.xz;
            P = M * (P * zoom);
            float z = CAM - P.z;
            vec2 d = p - ctr - vec2(P.x, -P.y) * (FOC / z);
            float near = clamp((P.z + 1.25) * 0.4, 0.0, 1.0);
            float r = 1.6 + 1.6 * near;
            if (dot(d, d) < r * r && near > bestN) { bestN = near; bestD = d; bestR = r; }
        }
    }
    if (bestN >= 0.0) {
        // a shaded "bob": sphere shading + a highlight, colour by depth (far purple -> near gold)
        vec2 q = bestD / bestR;
        float s = sqrt(max(1.0 - dot(q, q), 0.0));
        vec3 base = esaGrad(1.0 - bestN);
        float lum = mix(0.55, 1.05, bestN);
        vec3 c = base * lum * (0.55 + 0.55 * s);
        c += CREAM * smoothstep(0.55, 0.0, length(q + vec2(0.35, 0.35))) * 0.55 * bestN;
        col = c;
    }

    // counter: "1,536 DOTS" (counts up as the first shape forms), shape name top-left
    int cnt = int(float(DT_G * DT_M) * clamp(uLT / 1.2, 0.0, 1.0));
    int dg[5] = int[](48 + cnt / 1000, 44, 48 + (cnt / 100) % 10, 48 + (cnt / 10) % 10, 48 + cnt % 10);
    float x0 = 160.0 - (10.0 * 8.0 * 2.0) * 0.5;
    for (int k = (cnt < 1000 ? 2 : 0); k < 5; k++) col = drawChar(col, p, dg[k], vec2(x0 + float(k) * 16.0, 206.0), 2.0, TS_CHROME);
    col = drawStr(col, p, 0, vec2(x0 + 6.0 * 16.0, 206.0), 2.0, TS_CHROME, 1.0);
    int typed = int(max(bl - 0.2, 0.0) * 20.0);
    col = drawStrN(col, p, 1 + bar, vec2(14.0, 12.0), 2.0, TS_GOLD, 1.0, typed);
    col = drawStr(col, p, 5, vec2(uRes.x - 14.0 - strW(5, 1.0), 16.0), 1.0, TS_LAV, 1.0);
    return col;
}
