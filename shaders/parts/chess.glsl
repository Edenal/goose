// @id chess
// @name CHROME CHESS
// @split CHESS
// @bars 4
// @order 120
// @default off
// @inspired Triton - Crystal Dream 2 (1993)
// @desc Ray-traced chrome pawns and a king on a floating cream and purple board, mirroring the board and a gold-to-purple sky. The camera orbits slowly; the pieces hop one square on every bar.
// @str 0 ANY% CHECKMATE
// @str 1 {EVENT}

// ---------------------------------------------------------------- primitives (analytic)
float ch_sphere(vec3 ro, vec3 rd, vec3 c, float r) {
    vec3 oc = ro - c;
    float b = dot(oc, rd), q = dot(oc, oc) - r * r, h = b * b - q;
    if (h < 0.0) return -1.0;
    h = sqrt(h);
    float t = -b - h;
    return t > 1e-3 ? t : -1.0;
}
// axis-aligned ellipsoid; returns t, writes normal
float ch_ellip(vec3 ro, vec3 rd, vec3 c, vec3 r, out vec3 n) {
    vec3 o = (ro - c) / r, d = rd / r;
    float a = dot(d, d), b = dot(o, d), q = dot(o, o) - 1.0, h = b * b - a * q;
    n = vec3(0, 1, 0);
    if (h < 0.0) return -1.0;
    float t = (-b - sqrt(h)) / a;
    if (t < 1e-3) return -1.0;
    n = normalize((ro + rd * t - c) / (r * r));
    return t;
}
// vertical capped cylinder (y0..y1)
float ch_cyl(vec3 ro, vec3 rd, vec3 c, float r, float y0, float y1, out vec3 n) {
    vec2 o = ro.xz - c.xz, d = rd.xz;
    float a = dot(d, d), b = dot(o, d), q = dot(o, o) - r * r, h = b * b - a * q;
    n = vec3(0, 1, 0);
    float tb = -1.0;
    if (h >= 0.0 && a > 1e-6) {
        float t = (-b - sqrt(h)) / a;
        float y = ro.y + rd.y * t;
        if (t > 1e-3 && y > y0 && y < y1) { tb = t; vec2 e = (o + d * t) / r; n = vec3(e.x, 0.0, e.y); }
    }
    if (abs(rd.y) > 1e-5) {                     // top cap
        float t = (y1 - ro.y) / rd.y;
        vec2 xz = o + d * t;
        if (t > 1e-3 && dot(xz, xz) < r * r && (tb < 0.0 || t < tb)) { tb = t; n = vec3(0, 1, 0); }
    }
    return tb;
}

// ---------------------------------------------------------------- the pieces
const float BAR = 8.0 / 3.0;
const int NP = 7;
// start square (col,row) and step per hop
const vec2 CH_START[NP] = vec2[](vec2(2, 1), vec2(3, 1), vec2(5, 1), vec2(1, 6), vec2(6, 6), vec2(4, 6), vec2(0, 0));
const vec2 CH_STEP[NP]  = vec2[](vec2(0, 1), vec2(0, 1), vec2(0, 1), vec2(0, -1), vec2(0, -1), vec2(-1, 0), vec2(1, 0));

vec3 ch_piecePos(int i) {
    float bar = floor(uLT / BAR), bl = uLT - bar * BAR;
    float hopT = 0.5;
    float k = clamp(bl / hopT, 0.0, 1.0);
    float ke = k * k * (3.0 - 2.0 * k);
    vec2 step = CH_STEP[i];
    if (i == 5 && mod(bar, 2.0) > 0.5) step = -step;      // the king steps left, right, left...
    vec2 back = CH_START[i];
    if (i == 5) back = CH_START[i] + vec2(-1, 0) * mod(bar, 2.0);   // net position alternates
    else back = CH_START[i] + CH_STEP[i] * bar;
    vec2 sq = back + step * ke;
    float y = 4.0 * k * (1.0 - k) * 0.9;
    y += 0.05 * uEnv.w * (k >= 1.0 ? 1.0 : 0.0);
    return vec3(sq.x - 3.5, y, sq.y - 3.5);
}

// scene: returns t, normal, material (1 board top, 2 board rim/side, 3 chrome)
float ch_trace(vec3 ro, vec3 rd, out vec3 n, out float mat) {
    float tb = 1e9; mat = 0.0; n = vec3(0, 1, 0);
    // board slab
    {
        vec3 bmin = vec3(-4.25, -0.4, -4.25), bmax = vec3(4.25, 0.0, 4.25);
        vec3 inv = 1.0 / rd;
        vec3 t0 = (bmin - ro) * inv, t1 = (bmax - ro) * inv;
        vec3 tmn = min(t0, t1), tmx = max(t0, t1);
        float tn = max(max(tmn.x, tmn.y), tmn.z), tf = min(min(tmx.x, tmx.y), tmx.z);
        if (tn < tf && tn > 1e-3) {
            tb = tn;
            if (tn == tmn.y) { n = vec3(0, -sign(rd.y), 0); vec3 P = ro + rd * tn; mat = (max(abs(P.x), abs(P.z)) < 4.0 && n.y > 0.0) ? 1.0 : 2.0; }
            else if (tn == tmn.x) { n = vec3(-sign(rd.x), 0, 0); mat = 2.0; }
            else { n = vec3(0, 0, -sign(rd.z)); mat = 2.0; }
        }
    }
    for (int i = 0; i < NP; i++) {
        vec3 c = ch_piecePos(i);
        bool king = i == 5;
        float H = king ? 1.75 : 1.05;
        // bounding sphere reject
        vec3 bc = c + vec3(0, H * 0.5, 0);
        vec3 oc = ro - bc;
        float b = dot(oc, rd), q = dot(oc, oc) - (H * 0.5 + 0.35) * (H * 0.5 + 0.35);
        if (b * b - q < 0.0 || (b > 0.0 && q > 0.0)) continue;
        vec3 nn; float t;
        t = ch_cyl(ro, rd, c, king ? 0.4 : 0.34, c.y, c.y + 0.14, nn);
        if (t > 0.0 && t < tb) { tb = t; n = nn; mat = 3.0; }
        t = ch_ellip(ro, rd, c + vec3(0, king ? 0.72 : 0.42, 0), king ? vec3(0.26, 0.62, 0.26) : vec3(0.24, 0.34, 0.24), nn);
        if (t > 0.0 && t < tb) { tb = t; n = nn; mat = 3.0; }
        if (king) {
            t = ch_cyl(ro, rd, c, 0.3, c.y + 1.2, c.y + 1.3, nn);
            if (t > 0.0 && t < tb) { tb = t; n = nn; mat = 3.0; }
        }
        vec3 hc = c + vec3(0, king ? 1.47 : 0.86, 0);
        float hr = king ? 0.2 : 0.19;
        t = ch_sphere(ro, rd, hc, hr);
        if (t > 0.0 && t < tb) { tb = t; n = normalize(ro + rd * t - hc); mat = 3.0; }
        if (king) {
            vec3 kc = c + vec3(0, 1.74, 0);
            t = ch_sphere(ro, rd, kc, 0.09);
            if (t > 0.0 && t < tb) { tb = t; n = normalize(ro + rd * t - kc); mat = 3.0; }
        }
    }
    return mat > 0.0 ? tb : -1.0;
}

// the sky the chrome reflects: gold horizon, purple dome, plum below, a few bands
vec3 ch_sky(vec3 rd) {
    float y = rd.y;
    vec3 c;
    if (y > 0.0) {
        c = mix(GOLD * 1.1, PURP, smoothstep(0.0, 0.35, y));
        c = mix(c, DEEP * 0.8, smoothstep(0.35, 0.95, y));
        float band = step(0.5, fract(y * 9.0 - uLT * 0.2)) * smoothstep(0.08, 0.2, y) * (1.0 - smoothstep(0.5, 0.8, y));
        c = mix(c, c * 0.72, band);
    } else {
        c = mix(GOLD * 0.9, LAV * 0.9, smoothstep(0.0, 0.18, -y));
        c = mix(c, ROYAL * 0.8, smoothstep(0.18, 0.8, -y));
    }
    c += CREAM * pow(max(dot(rd, normalize(vec3(0.6, 0.35, -0.7))), 0.0), 60.0) * 1.2;   // sun glint
    return c;
}

float ch_checker(vec2 xz) {
    vec2 w = fwidth(xz) + 1e-4;
    vec2 i = 2.0 * (abs(fract((xz - 0.5 * w) * 0.5) - 0.5) - abs(fract((xz + 0.5 * w) * 0.5) - 0.5)) / w;
    return 0.5 - 0.5 * i.x * i.y;     // box-filtered checker: fades to grey where it would alias
}

vec3 ch_boardCol(vec3 P, float mat) {
    if (mat > 1.5) {
        return GOLD * (0.8 + 0.25 * step(-0.06, P.y));
    }
    float chk = ch_checker(P.xz + 4.0);
    vec3 c = mix(CREAM * 0.86, PURP * 0.62, chk);
    // contact shadows under the pieces
    for (int i = 0; i < NP; i++) {
        vec3 pc = ch_piecePos(i);
        float d = length(P.xz - pc.xz);
        float sh = smoothstep(0.55 + pc.y * 0.3, 0.2, d) * (1.0 - 0.6 * pc.y);
        c *= 1.0 - 0.6 * sh;
    }
    return c;
}

vec3 part(vec2 p) {
    float ang = 0.35 + uLT * 0.2;
    vec3 tgt = vec3(0.0, 0.9, 0.0);
    vec3 ro = vec3(sin(ang) * 5.4, 2.2 + 0.4 * sin(uLT * 0.35), cos(ang) * 5.4);
    vec3 fw = normalize(tgt - ro), rt = normalize(cross(fw, vec3(0, 1, 0))), up = cross(rt, fw);
    vec2 uv = screenUV(p);
    vec3 rd = normalize(fw + (uv.x * rt + uv.y * up) * 0.6);

    vec3 acc = vec3(0.0), thr = vec3(1.0);
    for (int b = 0; b < 3; b++) {
        vec3 n; float mat;
        float t = ch_trace(ro, rd, n, mat);
        if (t < 0.0) {
            vec3 sk = ch_sky(rd);
            if (b == 0 && rd.y < 0.0)    // seen directly, the void under the horizon is dark; chrome still mirrors it bright
                sk = mix(GOLD * 0.7, mix(PLUM * 0.8, DEEP * 0.6, smoothstep(0.1, 0.5, -rd.y)), smoothstep(0.0, 0.06, -rd.y));
            acc += thr * sk; break;
        }
        vec3 P = ro + rd * t;
        if (mat > 2.5) {
            // chrome: slightly lavender-tinted mirror with a fresnel lift and a hard highlight
            float fr = 0.84 + 0.16 * pow(1.0 - max(dot(-rd, n), 0.0), 3.0);
            vec3 L = normalize(vec3(0.6, 0.8, -0.3));
            float sp = pow(max(dot(reflect(rd, n), L), 0.0), 40.0);
            acc += thr * CREAM * sp * 0.8;
            thr *= mix(vec3(0.92, 0.9, 1.0), vec3(1.0), fr) * fr;
            ro = P + n * 2e-3;
            rd = reflect(rd, n);
        } else {
            vec3 bc = ch_boardCol(P, mat);
            float l = mat > 1.5 ? 0.7 + 0.3 * max(n.y, 0.0) + 0.2 * abs(n.x) : 1.0;
            float refl = mat > 1.5 ? 0.15 : 0.28;
            acc += thr * bc * l * (1.0 - refl);
            thr *= refl;
            ro = P + n * 2e-3;
            rd = reflect(rd, n);
            if (b == 2) acc += thr * ch_sky(rd);
        }
        if (b == 2 && mat > 2.5) acc += thr * ch_sky(rd);
    }
    vec3 col = acc;

    // captions
    float bar = floor(uLT / BAR), bl = uLT - bar * BAR;
    col = drawStrC(col, p, 1, 10.0, strLen(1) > 19 ? 1.0 : 2.0, TS_CHROME, 1.0);
    int n = int(bl * 16.0);
    col = drawStrN(col, p, 0, vec2(floor((uRes.x - strW(0, 1.0)) * 0.5), 30.0), 1.0, TS_WHITE, 1.0, n);
    return col;
}
