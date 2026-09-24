// @id voxel
// @name VOXEL FLIGHT
// @split VOXEL
// @bars 4
// @order 180
// @default off
// @inspired CNCD - Inside (1996)
// @desc A banking flight down a valley of chunky voxel mountains at dusk, water in the valley mirroring a gold-to-purple sky, with the ESA logo glowing in front of the sun.

const float VX_WATER = 3.0;
const vec3 VX_SUN = vec3(0.0, 0.17, 1.0);   // low sun straight down the valley (normalised in use)
const float VX_CELL = 2.0;                  // voxel column width in world units

float vxPath(float z) { return 20.0 * sin(z * 0.019) + 9.0 * sin(z * 0.047 + 1.0); }
float vxPathD(float z) { return 20.0 * 0.019 * cos(z * 0.019) + 9.0 * 0.047 * cos(z * 0.047 + 1.0); }
float vxPathDD(float z) { return -20.0 * 0.019 * 0.019 * sin(z * 0.019) - 9.0 * 0.047 * 0.047 * sin(z * 0.047 + 1.0); }

float vxFbm(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.07 + 13.1; a *= 0.5; } return s; }

// raw terrain height at a voxel cell centre, in whole units
float vxHeight(vec2 cell) {
    vec2 c = (cell + 0.5) * VX_CELL;
    float n = vxFbm(c * 0.028);
    float h = pow(max(n - 0.18, 0.0), 1.4) * 58.0;
    float v = smoothstep(4.0, 24.0, abs(c.x - vxPath(c.y)));   // carve the valley
    h = mix(1.5, h, v);
    return floor(h / 1.5) * 1.5;
}

vec3 vxSky(vec3 rd, vec3 sun) {
    float y = rd.y;
    vec3 col = mix(mix(vec3(1.0, 0.55, 0.20), GOLD, 0.35), PURP * 0.9, smoothstep(0.0, 0.18, y));
    col = mix(col, DEEP * 0.8, smoothstep(0.15, 0.55, y));
    col = mix(col, PLUM, smoothstep(0.0, -0.2, y));
    float sd = dot(rd, sun);
    col += GOLD * 0.35 * pow(max(sd, 0.0), 12.0);
    // big striped sun disc
    if (sd > 0.965) {
        float sy = (dot(rd, vec3(0, 1, 0)) - sun.y) / 0.26;   // -1 bottom .. +1 top of disc
        float stripe = step(0.5, fract(sy * 5.0 - uLT * 0.7)) + step(0.0, sy);
        col = stripe > 0.5 ? mix(mix(CREAM, GOLD, 0.6), vec3(1.0, 0.42, 0.16), smoothstep(0.7, -0.9, sy)) : mix(col, PURP * 0.8, 0.55);
    }
    return col;
}

vec3 part(vec2 p) {
    vec2 pp = floor(p / 2.0) * 2.0 + 1.0;   // chunky 160x120 columns
    float bar = 4.0 * (60.0 / 90.0);
    float bp = fract(uLT / bar);
    float cz = 40.0 + uLT * 15.0 + uKickCum * 1.2;
    vec3 ro = vec3(vxPath(cz), VX_WATER + 8.5 + 3.5 * cos(bp * 2.0 * PI) + 1.5 * sin(uLT * 0.9), cz);
    vec3 fw = normalize(vec3(vxPathD(cz + 8.0), -0.16, 1.0));
    float roll = clamp(-vxPathDD(cz + 6.0) * 22.0, -0.2, 0.2);
    vec3 up0 = vec3(sin(roll), cos(roll), 0.0);
    vec3 rt = normalize(cross(up0, fw));
    vec3 up = cross(fw, rt);
    vec2 uv = screenUV(pp);
    vec3 rd = normalize(fw + (uv.x * rt + uv.y * up) * 0.85);
    vec3 sun = normalize(VX_SUN + vec3(vxPathD(cz + 8.0) * 0.4, 0.0, 0.0));

    // march the voxel height field
    float t = 0.8, tPrev = 0.8;
    float hit = 0.0, hh = 0.0;
    vec2 cell = vec2(0.0);
    for (int i = 0; i < 64; i++) {
        vec3 P = ro + rd * t;
        cell = floor(P.xz / VX_CELL);
        hh = max(vxHeight(cell), VX_WATER);
        if (P.y < hh) { hit = 1.0; break; }
        if (P.y > 60.0 && rd.y > 0.0) break;
        tPrev = t;
        t += 0.35 + t * 0.045;
        if (t > 170.0) break;
    }
    vec3 col;
    vec3 sky = vxSky(rd, sun);
    if (hit > 0.5) {
        // top face or side wall?  If the ray crossed the cell's top inside this step it hit the top.
        float tTop = rd.y < 0.0 ? (hh - ro.y) / rd.y : -1.0;
        bool top = tTop >= tPrev && tTop <= t;
        float tH = top ? tTop : t;
        if (hh <= VX_WATER + 0.01) {
            // water: mirror the sky, ripples in the reflection, glints on the kick
            vec3 P = ro + rd * tH;
            vec3 rr = reflect(rd, vec3(0.0, 1.0, 0.0));
            rr.x += sin(P.z * 0.9 + uLT * 3.0) * 0.03;
            rr.y = abs(rr.y + sin(P.x * 1.3 + P.z * 0.4 - uLT * 4.0) * 0.02);
            col = vxSky(normalize(rr), sun) * vec3(0.75, 0.70, 0.95);
            col *= 0.72 + 0.28 * step(0.0, sin(P.z * 2.2 + sin(P.x * 0.7) * 1.5 - uLT * 5.0));   // ripple bands
            float band = step(0.93, sin(P.z * 1.7 - uLT * 6.0) * sin(P.x * 0.9));
            col += GOLD * band * (0.25 + 0.6 * uEnv.w) * pow(max(dot(normalize(rr), sun), 0.0), 3.0);
        } else {
            float h = hh;
            // normal from the neighbouring columns
            float hx = max(vxHeight(cell + vec2(1, 0)), VX_WATER) - max(vxHeight(cell - vec2(1, 0)), VX_WATER);
            float hz = max(vxHeight(cell + vec2(0, 1)), VX_WATER) - max(vxHeight(cell - vec2(0, 1)), VX_WATER);
            vec3 n = normalize(vec3(-hx, 2.0 * VX_CELL, -hz));
            float hn = clamp(h / 30.0, 0.0, 1.0);
            vec3 base = mix(PLUM * 1.5, ROYAL, smoothstep(0.0, 0.35, hn));
            base = mix(base, LAV * 0.9, smoothstep(0.45, 0.75, hn));
            base = mix(base, CREAM, smoothstep(0.78, 0.95, hn));      // snow caps
            if (h < VX_WATER + 2.0) base = mix(GOLD * 0.7, PLUM, 0.35); // beach
            float key = max(dot(n, normalize(vec3(-0.6, 0.8, -0.35))), 0.0);   // lavender sky fill from behind
            float dif = max(dot(n, sun), 0.0);
            col = base * (0.55 + 0.6 * key) * (top ? 1.0 : 0.6);             // voxel side walls are darker
            col += GOLD * 0.6 * pow(dif, 2.0) * (0.8 + 0.4 * uEnv.w) * (top ? 1.0 : 0.5);   // gold light from the low sun
            // checker the tops very gently so the voxel grid reads
            col *= 0.93 + 0.07 * mod(cell.x + cell.y, 2.0);
        }
        float fog = 1.0 - exp(-tH * 0.014);
        col = mix(col, mix(PURP * 0.8, vec3(1.0, 0.55, 0.20), 0.35), fog * 0.85);
    } else {
        col = sky;
        // the ESA logo glowing in front of the sun
        vec3 lc = vec3(dot(sun, rt), dot(sun, up), dot(sun, fw));
        vec2 ls = lc.xy / lc.z / 0.85;
        vec2 lpx = vec2(ls.x, -ls.y) * uRes.y * 0.5 + uRes * 0.5 + vec2(0.0, 0.0);
        float sz = 46.0 * (1.0 + 0.06 * exp(-bp * bar * 4.0));
        vec4 lg = logoAt(p, lpx, sz);
        float glow = exp(-length(p - lpx) / 34.0);
        col += GOLD * glow * (0.35 + 0.35 * uEnv.w);
        col = mix(col, lg.rgb, lg.a);
    }
    return col;
}
