// @id caustics
// @name UNDERWATER
// @split WATER
// @bars 4
// @order 240
// @default off
// @inspired Pulse - Sunflower (1997)
// @desc The ESA cube sinks into teal water and hovers over a plum seabed laced with gold caustics, under light shafts, swaying kelp and rising bubbles.

const vec3 TEAL = vec3(0.04, 0.60, 0.64);
const vec3 AQUA = vec3(0.45, 0.95, 0.90);

// classic iterated-sine water caustic: bright filaments on a dark field, ~0..1
float causticF(vec2 uv, float time) {
    vec2 p = mod(uv * 6.2831853, 6.2831853) - 250.0;
    vec2 i = p;
    float c = 1.0, inten = 0.005;
    for (int n = 0; n < 4; n++) {
        float t = time * (1.0 - 3.5 / float(n + 1));
        i = p + vec2(cos(t - i.x) + sin(t + i.y), sin(t - i.y) + cos(t + i.x));
        c += 1.0 / length(vec2(p.x / (sin(i.x + t) / inten), p.y / (cos(i.y + t) / inten)));
    }
    c /= 4.0;
    c = 1.17 - pow(c, 1.4);
    return clamp(pow(abs(c), 7.0), 0.0, 1.5);
}

// the cube's pose: sinks in from the surface, then hovers and turns
vec3 cubePos(float t) {
    float sink = easeOut(t / 2.4);
    return vec3(sin(t * 0.45) * 0.5 - 0.1, mix(5.2, 1.5, sink) + sin(t * 1.3) * 0.08 * sink, -4.4);
}
mat3 cubeRot(float t) {
    float a = t * 0.55 + (1.0 - easeOut(t / 2.4)) * 2.5, b = 0.62 + 0.2 * sin(t * 0.7), c = 0.2 * sin(t * 0.5);
    mat3 ry = mat3(cos(a), 0, -sin(a), 0, 1, 0, sin(a), 0, cos(a));
    mat3 rx = mat3(1, 0, 0, 0, cos(b), sin(b), 0, -sin(b), cos(b));
    mat3 rz = mat3(cos(c), sin(c), 0, -sin(c), cos(c), 0, 0, 0, 1);
    return rz * rx * ry;   // world -> cube
}

// ray vs the ESA cube: rgb + t (a < 0: miss)
vec4 hitCube(vec3 ro, vec3 rd, vec3 C, float S, mat3 R, float t) {
    vec3 o = R * (ro - C) / S + 0.5, d = R * rd;
    vec3 inv = 1.0 / d;
    vec3 t0 = -o * inv, t1 = (1.0 - o) * inv;
    vec3 tmn = min(t0, t1), tmx = max(t0, t1);
    float tn = max(max(tmn.x, tmn.y), tmn.z), tf = min(min(tmx.x, tmx.y), tmx.z);
    if (tn > tf || tf < 0.0) return vec4(0.0, 0.0, 0.0, -1.0);
    vec3 q = o + d * tn, n;
    if (tn == tmn.x) n = vec3(-sign(d.x), 0, 0); else if (tn == tmn.y) n = vec3(0, -sign(d.y), 0); else n = vec3(0, 0, -sign(d.z));
    vec4 c = faceColor(q, n);
    if (c.a < 0.5) c.rgb = DEEP * 1.25;
    vec3 nw = transpose(R) * n;
    vec3 wp = ro + rd * tn * S;
    float l = 0.55 + 0.55 * max(dot(nw, normalize(vec3(-0.3, 1.0, 0.4))), 0.0);
    // caustics dance on the faces that look up, a teal bounce on the rest
    float cs = causticF(wp.xz * 0.35 + wp.y * 0.1, t * 0.9);
    vec3 col = c.rgb * l * mix(vec3(0.75, 0.95, 1.0), vec3(1.0), 0.5);
    col += (GOLD * 0.45 + CREAM * 0.2) * cs * (0.15 + 0.6 * max(nw.y, 0.0));
    col = mix(col, TEAL * 0.8, 0.12 + 0.2 * max(-nw.y, 0.0));
    return vec4(col, tn * S);
}

vec3 waterCol(vec3 rd, float t) {
    float up = clamp(rd.y * 1.6 + 0.35, 0.0, 1.0);
    return mix(mix(DEEP * 0.9, PLUM * 0.9, 0.3), mix(TEAL * 0.55, TEAL, up), smoothstep(0.0, 1.0, up));
}

vec3 part(vec2 p) {
    float t = uLT;
    float T = uT;
    // refraction wobble over the whole view
    vec2 pw = p + vec2(sin(p.y * 0.07 + T * 2.6) * 2.2, cos(p.x * 0.06 + T * 2.1) * 1.6);
    vec2 uv = screenUV(pw);
    vec3 ro = vec3(0.0, 1.6, 0.0);
    vec3 rd = normalize(vec3(uv * 0.85, -1.0));
    float pitch = -0.2;
    rd.yz = mat2(cos(pitch), sin(pitch), -sin(pitch), cos(pitch)) * rd.yz;

    vec3 C = cubePos(t);
    mat3 R = cubeRot(t);
    const float S = 1.45;
    float kick = uEnv.w;

    vec3 col = waterCol(rd, t);
    float tHit = 1e9;
    if (rd.y < 0.0) {                          // the seabed
        float tf = -ro.y / rd.y;
        vec3 P = ro + rd * tf;
        vec2 sxz = P.xz + vec2(0.0, -t * 0.35);
        float dune = sin(sxz.x * 1.6 + sin(sxz.y * 0.9) * 1.5) * 0.5 + 0.5;
        vec3 sand = mix(PLUM * 1.05, ROYAL * 0.95, dune * 0.6 + 0.3 * vnoise(sxz * 3.0));
        float cs = causticF(sxz * 0.28, T * 0.8);
        // the cube's soft shadow on the sand (light from above)
        float sh = smoothstep(0.35, 1.25, length(P.xz - C.xz) / (0.6 + 0.12 * C.y));
        vec3 f = sand * (0.55 + 0.45 * sh);
        f += mix(GOLD, CREAM, 0.35) * cs * sh * (0.75 + 0.6 * kick);
        float fog = 1.0 - exp(-tf * 0.075);
        col = mix(f, waterCol(rd, t), fog);
        tHit = tf;
    } else {                                   // looking up at the surface
        float ts = (4.2 - ro.y) / rd.y;
        vec3 P = ro + rd * ts;
        float cs = causticF(P.xz * 0.2 + vec2(0.0, -t * 0.1), T * 0.6);
        float fog = exp(-ts * 0.06);
        col = mix(col, mix(AQUA, CREAM, 0.4), clamp(cs * 0.8 + 0.35, 0.0, 1.0) * fog);
    }

    // the cube
    vec4 cb = hitCube(ro, rd, C, S, R, T);
    if (cb.a > 0.0 && cb.a < tHit) {
        col = mix(cb.rgb, waterCol(rd, t), 1.0 - exp(-cb.a * 0.03));
        tHit = cb.a;
    }

    // god rays fanning down from a sun above the top edge
    vec2 sun = vec2(210.0 + 30.0 * sin(t * 0.3), -90.0);
    vec2 dv = p - sun;
    float ang = atan(dv.x, dv.y);
    float rays = pow(vnoise(vec2(ang * 16.0 + t * 0.35, t * 0.25)), 3.0) * 1.6
               + pow(vnoise(vec2(ang * 31.0 - t * 0.5, 7.0)), 4.0) * 0.8;
    float rf = exp(-max(p.y, 0.0) / 150.0) * (0.55 + 0.35 * uEnv.x + 0.3 * kick);
    col += mix(AQUA, GOLD, 0.35) * rays * rf * 0.55;

    // kelp silhouettes swaying at the edges
    for (int k = 0; k < 6; k++) {
        vec3 h = hash3(float(k) * 3.7 + 1.0);
        float x0 = k < 3 ? 8.0 + h.x * 58.0 : 256.0 + h.x * 58.0;
        float top = 60.0 + h.y * 90.0;
        if (p.y < top) continue;
        float s = (240.0 - p.y) / (240.0 - top);
        float xs = x0 + sin(p.y * 0.035 + T * 1.1 + h.z * 6.0) * 14.0 * s + sin(T * 0.7 + h.x * 5.0) * 6.0 * s;
        float w = mix(7.0, 2.5, s);
        float dx = p.x - xs;
        bool inside = abs(dx) < w;
        // blades angled up and out, alternating sides
        for (int n = 0; n < 2; n++) {
            float cell = floor(p.y / 24.0 + h.z) + float(n);
            float yc = (cell - h.z) * 24.0;
            if (yc < top + 6.0) continue;
            float side = mod(cell, 2.0) * 2.0 - 1.0;
            float sc2 = (240.0 - yc) / (240.0 - top);
            float xc = x0 + sin(yc * 0.035 + T * 1.1 + h.z * 6.0) * 14.0 * sc2 + sin(T * 0.7 + h.x * 5.0) * 6.0 * sc2;
            vec2 lc = vec2(xc + side * 9.0, yc - 5.0);
            vec2 d = rot2(side * (0.55 + 0.15 * sin(T * 1.7 + cell))) * (p - lc);
            if (dot(d / vec2(11.0, 3.6), d / vec2(11.0, 3.6)) < 1.0) inside = true;
        }
        if (inside) {
            col = mix(DEEP * 0.45, PURP * 0.4, 0.25 + 0.1 * float(k % 2));
            if (abs(dx) < w && dx < -w + 1.8) col = mix(col, TEAL * 0.6, 0.6);   // rim light
        }
    }

    // bubbles: a steady drift plus a burst out of the cube on every bar line
    float barLen = 4.0 * 60.0 / 90.0;
    for (int k = 0; k < 34; k++) {
        vec3 h = hash3(float(k) * 1.91 + 0.3);
        vec2 bp;
        float r;
        if (k < 22) {
            float y = 260.0 - fract(h.y + T * (0.12 + 0.1 * h.z)) * 300.0;
            bp = vec2(h.x * 320.0 + sin(y * 0.05 + h.z * 9.0) * 5.0, y);
            r = 1.8 + 3.2 * h.z * h.z;
        } else {
            // burst from the cube (screen position from the projection of its centre)
            float bt = mod(t, barLen);
            float age = bt + h.y * 0.15;
            vec3 rel = C - ro;
            rel.yz = mat2(cos(-pitch), sin(-pitch), -sin(-pitch), cos(-pitch)) * rel.yz;
            vec2 sc = rel.xy / (-rel.z) / 0.85;
            vec2 cs = vec2(sc.x, -sc.y) * uRes.y * 0.5 + uRes * 0.5;
            bp = cs + vec2((h.x - 0.5) * 60.0 * sqrt(age) + sin(age * 6.0 + h.z * 9.0) * 4.0, -30.0 - age * (70.0 + 50.0 * h.z));
            r = 2.0 + 3.0 * h.z;
            if (age > 2.2) continue;
        }
        float d = length(p - bp);
        if (d < r + 1.0) {
            if (d > r - 1.2) col = mix(col, mix(AQUA, CREAM, 0.6), 0.85);                 // rim
            else col = mix(col, AQUA, 0.18);
            if (length(p - bp + vec2(r, r) * 0.38) < max(r * 0.3, 1.0)) col = CREAM;       // glint
        }
    }

    // light from the surface: a bright band at the very top
    col += mix(AQUA, CREAM, 0.5) * smoothstep(40.0, 0.0, p.y) * 0.25;
    return col;
}
