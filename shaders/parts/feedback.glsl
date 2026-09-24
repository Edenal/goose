// @id feedback
// @name COLOUR FEEDBACK
// @split FEEDBACK
// @bars 4
// @order 210
// @default off
// @inspired Orange - X14 (1995)
// @desc A video-feedback swirl without feedback: the spinning ESA cube and its orbiting sparks are redrawn sixteen times under stacked rotate, zoom and hue shifts, and the twist flips on every bar.
// @str 0 {EVENT}

const float FB_BAR = 4.0 * (60.0 / 90.0);
const int FB_N = 16;

// orbit phase: a triangle wave that always runs against the twist, so the echoes smear into arms
float fbOrbit(float t) {
    float k = floor(t / FB_BAR), lb = t - k * FB_BAR;
    return 1.9 * (mod(k, 2.0) < 0.5 ? -lb : lb - FB_BAR);
}

// the "live camera" image: the logo spinning in place, a dashed ring and three orbiting sparks. rgba, a = coverage
vec4 fbBase(vec2 q, float t) {
    vec4 c = vec4(0.0);
    // three sparks on an orbit that breathes with the bass
    float orb = 74.0 + 10.0 * sin(t * 1.3);
    for (int k = 0; k < 3; k++) {
        float a = fbOrbit(t) + float(k) * 2.0944;
        vec2 sp = vec2(cos(a), sin(a)) * orb;
        float d = length(q - sp);
        float m = 1.0 - smoothstep(9.0, 13.0, d);
        if (m > c.a) c = vec4(k == 0 ? GOLD : k == 1 ? PURP : CREAM, m);
    }
    // dashed ring: its dashes turn the twist into visible spiral arms
    float r = length(q), ang = atan(q.y, q.x);
    float ring = (1.0 - smoothstep(3.0, 5.5, abs(r - 46.0))) * step(0.45, fract(ang / (2.0 * PI) * 6.0 - t * 0.3));
    if (ring > c.a) c = vec4(LAV, ring);
    // the logo, turning in the plane
    vec4 lg = logoAt(rot2(t * 0.9) * q, vec2(0.0), 62.0);
    if (lg.a > 0.02) c = vec4(mix(c.rgb, lg.rgb, lg.a), max(c.a, lg.a));
    return c;
}

vec3 part(vec2 p) {
    int bar = int(uLT / FB_BAR);
    float lb = uLT - float(bar) * FB_BAR;
    // twist direction flips on every bar line, swinging over through the first beat
    float dirNow = mod(float(bar), 2.0) < 0.5 ? 1.0 : -1.0;
    float dir = bar == 0 ? 1.0 : mix(-dirNow, dirNow, smoothstep(0.0, 0.6, lb));
    vec2 ctr = uRes * 0.5 + vec2(sin(uLT * 0.8) * 14.0, cos(uLT * 0.6) * 8.0);
    vec2 q0 = p - ctr;
    float r0 = length(q0);

    // background: a slow dark swirl so the corners are never flat
    float sw = atan(q0.y, q0.x) + dir * 3.0 / (1.0 + r0 * 0.02) + uLT * 0.5 * dir;
    float bgv = sin(sw * 3.0 + log(r0 + 1.0) * 4.0 - uLT * 2.0);
    vec3 bg = mix(DEEP * 0.35, PLUM * 0.9, smoothstep(-0.2, 1.0, bgv)) * (0.8 + 0.4 * uEnv.x);

    // stacked feedback copies, newest on top: copy i is i frames old, magnified z^i and turned by i steps
    float zoom = 1.09 + 0.04 * uEnv.w;
    vec3 acc = vec3(0.0);
    float accA = 0.0;
    vec2 q = q0;
    for (int i = 0; i < FB_N; i++) {
        float fi = float(i);
        float ti = uLT - fi * 0.045;
        vec4 b = fbBase(q, ti);
        vec3 c;
        if (i == 0) c = b.rgb;
        else {
            // hue-shifted echo: the palette rolls one step per generation and slowly over time
            float lum = dot(b.rgb, vec3(0.3, 0.5, 0.2));
            c = cyclePal(fi * 0.065 + uLT * 0.18 + lum * 0.25) * (1.25 - fi * 0.04);
            c = mix(c, CREAM, smoothstep(0.85, 1.0, lum) * 0.3);
        }
        float a = b.a * (i == 0 ? 1.0 : 0.92);
        acc += (1.0 - accA) * a * c;
        accA += (1.0 - accA) * a;
        if (accA > 0.98) break;
        // step into the previous frame: swirl (stronger near the centre), then zoom
        float rq = length(q);
        float step_ = dir * (0.1 + 0.42 / (1.0 + rq * 0.03));
        q = rot2(step_) * q / zoom;
    }
    vec3 col = acc + (1.0 - accA) * bg;
    // one flash of the event name at the start of each bar, riding the swirl
    float tsc = strW(0, 2.0) <= 304.0 ? 2.0 : 1.0;
    if (lb < 0.45 && bar > 0) col = drawStrC(col, p, 0, 208.0, tsc, TS_CHROME, 1.0);
    return col;
}
