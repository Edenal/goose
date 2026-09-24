// @id liquid
// @name LIQUID METAL
// @split LIQUID
// @bars 4
// @order 200
// @default off
// @inspired RealTech - Countdown (1995)
// @desc A ray-marched chrome form melts from torus to twisted knot to blob and back on the bar lines, mirroring the brand gradient; a frame counter ticks in the corner.
// @str 0 FRAME

const float LQ_BAR = 4.0 * (60.0 / 90.0);

float lqTorus(vec3 p, float R, float r) { return length(vec2(length(p.xz) - R, p.y)) - r; }

// (2,3) torus knot: the tube passes the same angle twice, so test both windings
float lqKnot(vec3 p) {
    float r = length(p.xz), a = atan(p.z, p.x);
    float d = 1e9;
    for (int k = 0; k < 2; k++) {
        float th = a + 2.0 * PI * float(k);
        float ph = 1.5 * th + uLT * 0.8;
        vec2 c = vec2(0.78 + 0.34 * cos(ph), 0.34 * sin(ph));
        d = min(d, length(vec2(r, p.y) - c) - 0.21);
    }
    return d * 0.8;
}

float lqBlob(vec3 p) {
    float t = uLT * 1.7;
    float d = length(p) - 0.92;
    d += 0.16 * sin(p.x * 3.1 + t) * sin(p.y * 2.7 - t * 0.8) * sin(p.z * 3.3 + t * 1.2);
    d += 0.07 * sin(p.y * 7.0 + t * 2.0);
    return d * 0.8;
}

float lqShape(int i, vec3 p) {
    if (i == 1) return lqKnot(p);
    if (i == 2) return lqBlob(p);
    return lqTorus(p, 0.86, 0.36);
}

// shape sequence: torus, knot, blob, torus. Each bar melts from the previous shape in its first beat and a half
float lqMorph() {
    int bar = int(uLT / LQ_BAR);
    float lb = uLT - float(bar) * LQ_BAR;
    return easeOut(lb / 1.0);
}

mat3 lqRot() {
    float a = uLT * 0.55 + uKickCum * 0.12, b = 0.95 + 0.3 * sin(uLT * 0.4);
    mat3 ry = mat3(cos(a), 0.0, -sin(a), 0.0, 1.0, 0.0, sin(a), 0.0, cos(a));
    mat3 rx = mat3(1.0, 0.0, 0.0, 0.0, cos(b), sin(b), 0.0, -sin(b), cos(b));
    return rx * ry;
}

float lqMap(vec3 p, int s0, int s1, float w, float wob) {
    float d = mix(lqShape(s0, p), lqShape(s1, p), w);
    float t = uLT * 3.0;
    d += wob * sin(p.x * 5.0 + t) * sin(p.y * 4.3 - t * 0.7) * sin(p.z * 5.2 + t * 1.3);
    return d;
}

vec3 lqEnv(vec3 r) {
    // chrome studio: brand gradient sky, bright horizon, dark plum floor, two hard softboxes
    r.xz = rot2(uLT * 0.4) * r.xz;
    vec3 c;
    if (r.y > 0.0) {
        float y = clamp(r.y, 0.0, 1.0);
        c = y < 0.4 ? mix(GOLD, PURP, y / 0.4) : mix(PURP, LAV * 1.1, (y - 0.4) / 0.6);
    } else {
        float y = clamp(-r.y, 0.0, 1.0);
        c = y < 0.55 ? mix(GOLD * 0.9, vec3(0.5, 0.22, 0.3), y / 0.55) : mix(vec3(0.5, 0.22, 0.3), DEEP * 0.5, (y - 0.55) / 0.45);
        c *= 0.8 + 0.2 * step(0.5, fract(r.x / max(y, 0.05) * 1.5));        // a checker floor in the reflection
    }
    c = mix(c, CREAM, smoothstep(0.06, 0.0, abs(r.y - 0.02)) * 0.9);        // horizon line
    // stripes on the sky: the "studio" rafters that make chrome read as chrome
    if (r.y > 0.15) c *= 0.7 + 0.3 * step(0.5, fract(atan(r.z, r.x) * 1.9));
    float s1 = max(dot(r, normalize(vec3(-0.6, 0.7, 0.4))), 0.0);
    float s2 = max(dot(r, normalize(vec3(0.8, 0.3, -0.5))), 0.0);
    c += vec3(1.0) * step(0.965, s1) * 1.5 + mix(GOLD, CREAM, 0.5) * step(0.975, s2);
    return c;
}

vec3 part(vec2 p) {
    int bar = min(3, int(uLT / LQ_BAR));
    const int SEQ[5] = int[](2, 0, 1, 2, 0);   // bar 0 melts a droplet into the torus
    int s0 = SEQ[bar], s1 = SEQ[bar + 1];
    float w = lqMorph();
    float wob = 0.03 + 0.09 * sin(w * PI) + 0.05 * uEnv.w;

    // background: dark room, faint purple glow behind the object, slow floor streaks
    vec2 uv = screenUV(p);
    vec3 col = mix(DEEP * 0.55, vec3(0.02, 0.01, 0.04), smoothstep(0.1, 1.3, length(uv)));
    col += PURP * 0.18 * (1.0 - smoothstep(0.0, 0.9, length(uv - vec2(0.0, 0.05)))) * (0.7 + 0.6 * uEnv.x);
    if (uv.y < -0.55) {
        float z = 1.0 / (-uv.y);
        float ln = fract(z * 2.0 + uLT * 1.2);
        col += ROYAL * 0.18 * step(ln, 0.12) * smoothstep(-0.55, -1.0, uv.y);
    }

    vec3 ro = vec3(0.0, 0.0, 3.3);
    vec3 rd = normalize(vec3(uv * 0.44, -1.0));
    mat3 R = lqRot();
    vec3 o = R * ro, d = R * rd;
    float t = 1.6, hit = 0.0;
    for (int i = 0; i < 64; i++) {
        vec3 q = o + d * t;
        float h = lqMap(q, s0, s1, w, wob);
        if (h < 0.002) { hit = 1.0; break; }
        t += h * 0.8;
        if (t > 5.2) break;
    }
    if (hit > 0.5) {
        vec3 q = o + d * t;
        const vec2 e = vec2(0.002, -0.002);
        vec3 n = normalize(e.xyy * lqMap(q + e.xyy, s0, s1, w, wob) + e.yyx * lqMap(q + e.yyx, s0, s1, w, wob)
                         + e.yxy * lqMap(q + e.yxy, s0, s1, w, wob) + e.xxx * lqMap(q + e.xxx, s0, s1, w, wob));
        // back to view space so the reflections stay put while the object turns
        vec3 nv = transpose(R) * n;
        vec3 rv = reflect(rd, nv);
        float fr = pow(1.0 - max(dot(-rd, nv), 0.0), 3.0);
        vec3 c = lqEnv(rv) * (0.78 + 0.35 * fr);
        // hard white specular and a gold rim, brighter on the kick
        float sp = pow(max(dot(rv, normalize(vec3(-0.4, 0.6, 0.7))), 0.0), 40.0);
        c += vec3(1.0) * step(0.5, sp) * (0.8 + 0.6 * uEnv.w);
        c = mix(c, GOLD, smoothstep(0.55, 0.95, fr) * 0.45);
        col = c;
    }

    // corner frame counter: frames at 60 fps since the part started
    if (p.x >= 6.0 && p.x < 102.0 && p.y >= 6.0 && p.y < 22.0) {
        col = mix(col, DEEP * 0.5, 0.85);
        if (p.x < 7.0 || p.x >= 101.0 || p.y < 7.0 || p.y >= 21.0) col = ROYAL;
    }
    col = drawStr(col, p, 0, vec2(10.0, 10.0), 1.0, TS_GREY, 1.0);
    int fnum = int(floor(uLT * 60.0));
    for (int k = 0; k < 5; k++) {
        int dv = fnum;
        for (int j = 0; j < 4 - k; j++) dv /= 10;
        col = drawChar(col, p, 48 + dv % 10, vec2(56.0 + float(k) * 8.0, 10.0), 1.0, TS_GOLD);
    }
    return col;
}
