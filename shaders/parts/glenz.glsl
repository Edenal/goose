// @id glenz
// @name GLENZ VECTORS
// @split GLENZ
// @bars 4
// @order 110
// @default off
// @inspired Future Crew - Second Reality (1993)
// @desc Two nested see-through polyhedra, front and back faces blended in gold, purple and cream checkers, bouncing and squashing on every beat over a plum grid floor.
// @str 0 {EVENT}
// @str 1 NO GLITCHES  -  JUST GLASS

// ---- analytic convex polyhedra: a 24-face tetrakis hexahedron (normals = permutations of (0,1,2))
// and an octahedron nested inside it. Faces are traced entry + exit so the far side shows through.
const ivec3 GZ_PERM[6] = ivec3[](ivec3(0, 1, 2), ivec3(1, 2, 0), ivec3(2, 0, 1),
                                ivec3(0, 2, 1), ivec3(2, 1, 0), ivec3(1, 0, 2));

vec3 gz_tetrakisN(int i) {
    ivec3 pm = GZ_PERM[i / 4];          // pm.x = axis holding 0, pm.y = axis holding 1, pm.z = axis holding 2
    int s = i % 4;
    vec3 n = vec3(0.0);
    n[pm.y] = (s & 1) == 0 ? 1.0 : -1.0;
    n[pm.z] = (s & 2) == 0 ? 2.0 : -2.0;
    return n;
}

// ray (object space, rd NOT normalised) against planes dot(n,x) <= d; returns tNear, tFar, face ids
vec4 gz_traceTetrakis(vec3 ro, vec3 rd) {
    float tn = -1e9, tf = 1e9, fn = -1.0, ff = -1.0;
    for (int i = 0; i < 24; i++) {
        vec3 n = gz_tetrakisN(i);
        float dn = dot(n, rd), dist = 3.0 - dot(n, ro);
        if (abs(dn) < 1e-6) { if (dist < 0.0) return vec4(1.0, -1.0, 0.0, 0.0); continue; }
        float t = dist / dn;
        if (dn < 0.0) { if (t > tn) { tn = t; fn = float(i); } }
        else          { if (t < tf) { tf = t; ff = float(i); } }
    }
    return vec4(tn, tf, fn, ff);
}
vec3 gz_octN(int i) { return vec3((i & 1) == 0 ? 1.0 : -1.0, (i & 2) == 0 ? 1.0 : -1.0, (i & 4) == 0 ? 1.0 : -1.0); }
vec4 gz_traceOct(vec3 ro, vec3 rd, float r) {
    float tn = -1e9, tf = 1e9, fn = -1.0, ff = -1.0;
    for (int i = 0; i < 8; i++) {
        vec3 n = gz_octN(i);
        float dn = dot(n, rd), dist = r - dot(n, ro);
        if (abs(dn) < 1e-6) { if (dist < 0.0) return vec4(1.0, -1.0, 0.0, 0.0); continue; }
        float t = dist / dn;
        if (dn < 0.0) { if (t > tn) { tn = t; fn = float(i); } }
        else          { if (t < tf) { tf = t; ff = float(i); } }
    }
    return vec4(tn, tf, fn, ff);
}

// face colour: a 2-colouring of the faces (gold / purple), each triangle split into a triangular checker
// (from its barycentrics): coloured sub-triangles are nearly solid, the cream ones are clear glass
vec4 gz_faceCol(vec3 bary, float parity, float N, bool back) {
    vec3 q = floor(clamp(bary, 0.0, 0.999) * N);
    float chk = mod(q.x + q.y + q.z, 2.0);
    vec3 base = parity > 0.5 ? GOLD : PURP;
    vec4 c = chk < 0.5 ? vec4(mix(CREAM, LAV, 0.25), 0.25) : vec4(base, 0.85);
    if (back) c.rgb *= 0.6;
    return c;
}
// barycentrics on a tetrakis face: apex (on the "2" axis at 1.5) + two cube corners
vec3 gz_baryT(vec3 P, int i) {
    ivec3 pm = GZ_PERM[i / 4];
    float s1 = (i & 1) == 0 ? 1.0 : -1.0;
    float X = P[pm.x], Y = s1 * P[pm.y];
    return vec3(1.0 - Y, 0.5 * (Y + X), 0.5 * (Y - X));
}
vec3 gz_baryO(vec3 P, vec3 n, float r) { return P * n / r; }

struct GzObj { mat3 R; vec3 C, S; };

vec3 gz_shade(vec3 c, vec3 nObj, GzObj o, bool back) {
    vec3 nw = normalize((o.R * nObj) / o.S);
    if (back) nw = -nw;
    float l = 0.55 + 0.6 * max(dot(nw, normalize(vec3(-0.5, 0.8, 0.6))), 0.0);
    return c * l;
}

vec3 part(vec2 p) {
    const float BAR = 8.0 / 3.0;
    float f = fract(uBeat);
    float bar = floor(uLT / BAR);
    // bounce: parabola per beat, impact on the integer beat with a squash/stretch
    float h = 4.0 * f * (1.0 - f);
    float imp = exp(-f * 14.0) + exp(-(1.0 - f) * 30.0) * 0.4;
    float sq = 1.0 - 0.28 * imp * (0.7 + 0.3 * uFx) + 0.10 * h * (1.0 - h);
    vec3 S = vec3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq));
    const float FLOOR = -2.05;
    float rad = 1.3;                                   // object scale (tetrakis spans ~1.73 * rad)
    vec3 C = vec3(sin(uLT * 0.55) * 0.9, FLOOR + 1.62 * rad * sq + h * 0.6, 0.0);

    // rotation: steady spin with a kick push, tumbling axis changes each bar
    float blz = uLT - bar * BAR;
    float a1 = uLT * 0.9 + uKickCum * 0.35;
    float a2 = uLT * 0.63 + 0.8 * (bar - 1.0 + easeOut(blz / 0.35));   // a quick extra tumble on every bar line
    mat3 Ry = mat3(cos(a1), 0, -sin(a1), 0, 1, 0, sin(a1), 0, cos(a1));
    mat3 Rx = mat3(1, 0, 0, 0, cos(a2), sin(a2), 0, -sin(a2), cos(a2));
    GzObj O = GzObj(Ry * Rx, C, S * rad);
    float a3 = -uLT * 1.7;
    mat3 Rz = mat3(cos(a3), sin(a3), 0, -sin(a3), cos(a3), 0, 0, 0, 1);
    GzObj I = GzObj(Rx * Rz * transpose(Ry), C, S * rad);

    // camera
    vec3 ro = vec3(0.0, 1.1, 6.8);
    vec2 uv = screenUV(p);
    vec3 rd = normalize(vec3(uv * 0.62, -1.0));
    rd.yz = rot2(-0.19) * rd.yz;

    // ---- background: plum sky with thin raster lines, perspective grid floor
    vec3 col;
    if (rd.y > -0.02 || (FLOOR - ro.y) / rd.y > 60.0) {
        float y = p.y;
        col = mix(DEEP * 0.55, PLUM * 1.05, smoothstep(10.0, 150.0, y));
        for (int k = 0; k < 5; k++) {
            float yc = 30.0 + float(k) * 22.0 + 6.0 * sin(uT * 1.3 + float(k));
            float d = abs(y - yc);
            vec3 lc = esaGrad(float(k) / 4.0);
            col = mix(col, lc * (0.55 + 0.45 * uEnv.x), smoothstep(1.6, 0.4, d) * 0.55);
        }
        // horizon glow
        col += GOLD * 0.35 * exp(-abs(rd.y + 0.02) * 40.0);
    } else {
        float t = (FLOOR - ro.y) / rd.y;
        vec3 P = ro + rd * t;
        vec2 g = P.xz * vec2(1.0, 1.0) + vec2(0.0, uLT * 1.2);
        vec2 gd = abs(fract(g) - 0.5);
        float fw = 0.018 * t + 0.02;
        float line = smoothstep(0.5 - fw * 1.8, 0.5 - fw * 0.4, max(gd.x, gd.y));
        vec3 fl = mix(DEEP * 0.75, PURP * (0.38 + 0.35 * uEnv.w), line);
        // shadow of the glenz (blob under the object, shrinking with height)
        float sr = length((P.xz - C.xz) / vec2(1.5 * S.x, 0.9 * S.x));
        fl *= mix(1.0, 0.45 - 0.2 * h, smoothstep(1.0 - 0.25 * h, 0.4, sr) * (1.0 - 0.5 * h));
        col = mix(PLUM * 1.05 + GOLD * 0.12, fl, exp(-t * 0.06));
    }

    // ---- glenz layers: outer front, inner front, inner back, outer back (composited back to front)
    vec3 roO = transpose(O.R) * ((ro - O.C) / O.S), rdO = transpose(O.R) * (rd / O.S);
    vec3 roI = transpose(I.R) * ((ro - I.C) / I.S), rdI = transpose(I.R) * (rd / I.S);
    vec4 ho = gz_traceTetrakis(roO, rdO);
    vec4 hi = gz_traceOct(roI, rdI, 0.95);
    const int PAR[6] = int[](0, 0, 0, 1, 1, 1);          // parity of each permutation
    if (ho.x < ho.y && ho.y > 0.0) {
        // outer back face
        int fb = int(ho.w);
        vec3 nb = gz_tetrakisN(fb);
        vec3 Pb = roO + rdO * ho.y;
        vec4 kb = gz_faceCol(gz_baryT(Pb, fb), float(PAR[fb / 4]), 3.0, true);
        col = mix(col, gz_shade(kb.rgb, nb, O, true), kb.a);
        if (hi.x < hi.y && hi.y > 0.0) {
            int ib = int(hi.w), iF = int(hi.z);
            vec3 nib = gz_octN(ib), nif = gz_octN(iF);
            float pib = (nib.x * nib.y * nib.z) > 0.0 ? 1.0 : 0.0, pif = (nif.x * nif.y * nif.z) > 0.0 ? 1.0 : 0.0;
            vec4 kib = gz_faceCol(gz_baryO(roI + rdI * hi.y, nib, 0.95), 1.0 - pib, 2.0, true);
            col = mix(col, gz_shade(kib.rgb, nib, I, true), kib.a);
            vec4 kif = gz_faceCol(gz_baryO(roI + rdI * hi.x, nif, 0.95), 1.0 - pif, 2.0, false);
            col = mix(col, gz_shade(kif.rgb, nif, I, false), kif.a * 0.85);
        }
        // outer front face
        int ff = int(ho.z);
        vec3 nf = gz_tetrakisN(ff);
        vec3 Pf = roO + rdO * ho.x;
        float par = float(PAR[ff / 4]);
        vec4 kf = gz_faceCol(gz_baryT(Pf, ff), par, 3.0, false);
        col = mix(col, gz_shade(kf.rgb, nf, O, false), kf.a);
        // specular glint on the front
        vec3 nw = normalize((O.R * nf) / O.S);
        float sp = pow(max(dot(reflect(rd, nw), normalize(vec3(-0.5, 0.8, 0.6))), 0.0), 24.0);
        col += CREAM * sp * 0.6;
    }

    // ---- captions
    col = drawStrC(col, p, 0, 12.0, strLen(0) > 19 ? 1.0 : 2.0, TS_CHROME, 1.0);
    float bl = uLT - bar * BAR;
    int n = int(bl * 18.0);
    col = drawStrN(col, p, 1, vec2(floor((uRes.x - strW(1, 1.0)) * 0.5), 222.0), 1.0, TS_GOLD, 1.0, n);
    return col;
}
