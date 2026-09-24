// @id letters
// @name FLYING LETTERS
// @split LETTERS
// @bars 4
// @order 250
// @default off
// @inspired Cascada - Holistic (1994)
// @desc Chunky voxel-extruded letters fly in from every direction, tumble and slam onto a glossy grid floor, spelling one word per bar.
// @str 0 ESA
// @str 1 SPEED
// @str 2 RUNS
// @str 3 LIVE

const float BAR = 4.0 * 60.0 / 90.0;
const float DEP = 3.0;                   // extrusion depth in voxels
const vec3 LDIR = vec3(0.45, 0.85, 0.35);

int gN, gCh[6];
float gV;                                // world units per voxel
vec3 gC[6];                              // letter pivots (world)
mat3 gR[6];                              // world -> letter rotation

int wordCh(int row, int k) { return int(texelFetch(uStr, ivec2(k, row), 0).r * 255.0 + 0.5); }

mat3 rotAxis(vec3 a, float ang) {
    a = normalize(a);
    float c = cos(ang), s = sin(ang), ic = 1.0 - c;
    return mat3(c + a.x * a.x * ic, a.y * a.x * ic + a.z * s, a.z * a.x * ic - a.y * s,
                a.x * a.y * ic - a.z * s, c + a.y * a.y * ic, a.z * a.y * ic + a.x * s,
                a.x * a.z * ic + a.y * s, a.y * a.z * ic - a.x * s, c + a.z * a.z * ic);
}

float landT(int k) { return (float(k) + 1.0) * 0.5 * (60.0 / 90.0); }   // slams on the eighth notes

// set up the word and every letter's pose for bar-local time lt
void setupWord(int w, float lt) {
    gN = clamp(strLen(w), 1, 6);
    gV = min(0.22, 5.3 / (float(gN) * 8.0));
    for (int k = 0; k < 6; k++) {
        gCh[k] = k < gN ? wordCh(w, k) : 32;
        vec3 h = hash3(float(k) * 5.3 + float(w) * 17.1);
        vec3 fin = vec3((float(k) - float(gN - 1) * 0.5) * 8.0 * gV + 0.5 * gV, 3.0 * gV, 0.0);   // box centre, glyph row 6 on the floor
        // fly-in: offset shrinks as (1-s)^2, so the letter is fastest when it hits (the slam)
        int dk = int(mod(float(k) + float(w) * 2.0, 5.0));
        vec3 dir = dk == 0 ? vec3(-1.0, 0.35, 0.2) : dk == 1 ? vec3(0.1, 1.0, -0.3) : dk == 2 ? vec3(1.0, 0.25, -0.4)
                 : dk == 3 ? vec3(0.2, 0.3, 1.0) : vec3(-0.3, 0.6, -1.0);
        float s = clamp((lt - (landT(k) - 0.55)) / 0.55, 0.0, 1.0);
        float u = 1.0 - s;
        vec3 pos = fin + normalize(dir) * u * u * 14.0;
        vec3 ax = normalize(h - 0.5 + vec3(0.0, 0.0, 0.01));
        mat3 R = rotAxis(ax, u * u * (5.0 + 4.0 * h.x) * (h.y > 0.5 ? 1.0 : -1.0));
        // after the slam: a quick decaying rock, pivoting on the bottom edge
        float a = max(lt - landT(k), 0.0);
        float rock = s >= 1.0 ? 0.28 * exp(-a * 7.0) * sin(a * 26.0) : 0.0;
        pos.y += abs(rock) * 3.0 * gV;
        R = rotAxis(vec3(1.0, 0.0, 0.0), rock) * R;
        // exit: tip back and fly up and away, staggered
        float e = w == 3 ? 0.0 : clamp((lt - (BAR - 0.5) - float(k) * 0.05) / 0.4, 0.0, 1.0);   // the last word stays for the cut
        pos += vec3((h.z - 0.5) * 6.0, 7.0, -10.0) * e * e;
        R = rotAxis(vec3(1.0, 0.2 * (h.x - 0.5), 0.0), -e * e * 4.0) * R;
        gC[k] = pos;
        gR[k] = R;
    }
}

bool vox(int ch, ivec3 c) {
    if (c.x < 0 || c.y < 0 || c.z < 0 || c.x > 7 || c.y > 7 || float(c.z) >= DEP) return false;
    return glyphBit(ch, ivec2(c.x, 7 - c.y)) > 0.5;
}

// march one letter; returns world distance (1e9 = miss), local normal in n, cell in cell
float traceLetter(int k, vec3 ro, vec3 rd, float tMax, out vec3 n, out vec3 cell) {
    n = vec3(0.0); cell = vec3(0.0);
    if (gCh[k] == 32) return 1e9;
    vec3 piv = vec3(4.0, 4.0, DEP * 0.5);
    vec3 o = gR[k] * (ro - gC[k]) / gV + piv;
    vec3 d = gR[k] * rd;
    d = mix(d, vec3(1e-4), step(abs(d), vec3(1e-5)));
    vec3 inv = 1.0 / d;
    vec3 t0 = -o * inv, t1 = (vec3(8.0, 8.0, DEP) - o) * inv;
    vec3 tmn = min(t0, t1), tmx = max(t0, t1);
    float tn = max(max(tmn.x, tmn.y), tmn.z), tf = min(min(tmx.x, tmx.y), tmx.z);
    if (tn > tf || tf < 0.0 || tn * gV > tMax) return 1e9;
    float tc = max(tn, 0.0);
    vec3 nn = tn == tmn.x ? vec3(-sign(d.x), 0, 0) : tn == tmn.y ? vec3(0, -sign(d.y), 0) : vec3(0, 0, -sign(d.z));
    vec3 pp = o + d * (tc + 1e-3);
    vec3 c = floor(pp);
    vec3 st = sign(d);
    vec3 td = abs(inv);
    vec3 tm = (c + max(st, 0.0) - pp) * inv + tc;
    int ch = gCh[k];
    for (int i = 0; i < 22; i++) {
        if (c.x < -0.5 || c.y < -0.5 || c.z < -0.5 || c.x > 7.5 || c.y > 7.5 || c.z > DEP - 0.5) break;
        if (vox(ch, ivec3(c))) { n = nn; cell = c; return tc * gV; }
        if (tm.x < tm.y && tm.x < tm.z) { tc = tm.x; c.x += st.x; tm.x += td.x; nn = vec3(-st.x, 0, 0); }
        else if (tm.y < tm.z)           { tc = tm.y; c.y += st.y; tm.y += td.y; nn = vec3(0, -st.y, 0); }
        else                            { tc = tm.z; c.z += st.z; tm.z += td.z; nn = vec3(0, 0, -st.z); }
    }
    return 1e9;
}

float traceAll(vec3 ro, vec3 rd, float tMax, out int hk, out vec3 hn, out vec3 hc) {
    float best = tMax;
    hk = -1; hn = vec3(0.0); hc = vec3(0.0);
    for (int k = 0; k < 6; k++) {
        if (k >= gN) break;
        vec3 n, c;
        float t = traceLetter(k, ro, rd, best, n, c);
        if (t < best) { best = t; hk = k; hn = n; hc = c; }
    }
    return best;
}

vec3 shadeLetter(int k, vec3 n, vec3 c) {
    vec3 nw = transpose(gR[k]) * n;
    vec3 col;
    if (abs(n.z) > 0.5)      col = esaGrad(clamp((7.0 - c.y) / 6.0, 0.0, 1.0) * 0.9 + 0.05);   // face: the brand gradient
    else if (abs(n.y) > 0.5) col = n.y > 0.0 ? mix(CREAM, GOLD, 0.35) : PURP * 0.35;          // tops / undersides
    else                     col = mix(PURP * 0.55, ROYAL * 0.7, 0.4);                         // sides
    float l = 0.7 + 0.45 * max(dot(nw, normalize(LDIR)), 0.0);
    return col * l;
}

vec3 part(vec2 p) {
    int w = clamp(int(uLT / BAR), 0, 3);
    float lt = uLT - float(w) * BAR;
    setupWord(w, lt);

    // camera: slow sway, kicked by every slam
    float shake = 0.0;
    for (int k = 0; k < 6; k++) {
        if (k >= gN) break;
        float a = lt - landT(k);
        if (a > 0.0) shake += exp(-a * 11.0);
    }
    float yaw = 0.32 * sin(uLT * 0.45 + 0.6) + 0.05 * sin(uLT * 1.3);
    vec3 tgt = vec3(0.0, 0.62, 0.0) + vec3(hash1(floor(uLT * 40.0)) - 0.5, hash1(floor(uLT * 40.0) + 3.0) - 0.5, 0.0) * 0.09 * shake;
    vec3 ro = vec3(sin(yaw) * 5.0, 1.45 + 0.15 * sin(uLT * 0.6), cos(yaw) * 5.0);
    vec3 fw = normalize(tgt - ro), rt = normalize(cross(fw, vec3(0, 1, 0))), up = cross(rt, fw);
    vec2 uv = screenUV(p);
    vec3 rd = normalize(uv.x * rt + uv.y * up + 2.2 * fw);

    // backdrop: deep plum sky with a low purple glow over the horizon
    vec3 col = mix(DEEP * 0.35, PURP * 0.45, exp(-max(rd.y + 0.02, 0.0) * 9.0));
    col = mix(col, DEEP * 0.2, smoothstep(0.1, 0.5, rd.y));
    if (rd.y > 0.02) col += stars(p, 0.04, uT, 0.55) * smoothstep(0.02, 0.2, rd.y);

    int hk; vec3 hn, hc;
    float tl = traceAll(ro, rd, 40.0, hk, hn, hc);
    float tfl = rd.y < 0.0 ? -ro.y / rd.y : 1e9;

    if (tfl < tl) {
        // glossy floor: grid, shadows, slam shockwaves and a dim reflection of the letters
        vec3 P = ro + rd * tfl;
        vec2 g = abs(fract(P.xz * 2.0 + vec2(0.0, uLT * 0.0)) - 0.5);
        float fade = exp(-tfl * 0.09);
        float line = step(0.44, max(g.x, g.y)) * fade;
        vec3 f = mix(DEEP * 0.55, PLUM * 0.8, fade);
        f = mix(f, mix(PURP, GOLD, 0.25 + 0.2 * sin(P.x * 0.6 + uT)), line * 0.55);
        for (int k = 0; k < 6; k++) {
            if (k >= gN) break;
            float a = lt - landT(k);
            if (a > 0.0 && a < 0.9) {
                vec2 base = gC[k].xz;
                float r = length(P.xz - base);
                float ring = 1.0 - smoothstep(0.0, 0.09, abs(r - a * 5.0));
                f += GOLD * ring * (1.0 - a / 0.9) * 0.9;
            }
        }
        int sk; vec3 sn, sc;
        float ts = traceAll(P + vec3(0.0, 1e-3, 0.0), normalize(LDIR), 20.0, sk, sn, sc);
        if (sk >= 0) f *= 0.35;
        int rk; vec3 rn, rc;
        vec3 rrd = reflect(rd, vec3(0, 1, 0));
        float tr = traceAll(P + vec3(0.0, 1e-3, 0.0), rrd, 20.0, rk, rn, rc);
        if (rk >= 0) f = mix(f, shadeLetter(rk, rn, rc), 0.32 * exp(-tr * 0.6));
        col = mix(col, f, exp(-max(tfl - 4.0, 0.0) * 0.05));
    } else if (hk >= 0) {
        col = shadeLetter(hk, hn, hc);
    }
    return col;
}
