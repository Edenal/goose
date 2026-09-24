#version 410 core
// Consumer CRT: curved 4:3 tube inside a 16:9 frame, gaussian beam scanlines (width follows brightness),
// composite smear + ringing + RF ghost for the Mega Drive look, RGB misconvergence, aperture grille,
// halation, phosphor persistence. Plus everything that goes wrong with a tube: power on/off with bloom,
// degauss wobble + purity blotches, raster bulge on bright frames, horizontal hold loss, tearing, snow,
// and the vertical roll when the video mode changes.
in vec2 vUV;
out vec4 o;
uniform sampler2D uSrc, uGlow, uPrev;
uniform vec2 uSrcSize, uOut;
uniform float uT, uOnT, uOffT, uRoll, uJitter, uKick;
uniform float uTear, uTearSeed, uRGB, uSnow, uHold, uBulge, uDegauss, uPersist;
uniform int uMode;  // 0 = VGA text (31 kHz monitor, sharp), 1 = mode X graphics (soft)

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float ease(float x) { x = clamp(x, 0.0, 1.0); return x * x * (3.0 - 2.0 * x); }

vec3 texel(float xi, float y) { return lin(texture(uSrc, vec2((xi + 0.5) / uSrcSize.x, y)).rgb); }

vec3 fetchLine(float x, float line) {
    // horizontal reconstruction of one source line; returns linear light
    float W = uSrcSize.x;
    float fx = x * W - 0.5;
    float y = (line + 0.5) / uSrcSize.y;
    if (uMode == 0) {
        float i = floor(fx), f = smoothstep(0.30, 0.70, fx - i);  // sharp-bilinear: crisp VGA text
        return mix(texel(i, y), texel(i + 1.0, y), f);
    }
    // composite: gaussian smear over ~1.5 source pixels blends the ordered dither
    vec3 s = vec3(0.0); float ws = 0.0;
    for (int k = -2; k <= 2; k++) {
        float xi = floor(fx) + float(k), d = fx - xi;
        float w = exp(-d * d / (2.0 * 0.62 * 0.62));
        s += texel(xi, y) * w; ws += w;
    }
    vec3 c = s / ws;
    // sharpness "ringing" (TV peaking circuit) + a faint RF multipath ghost trailing to the right
    vec3 behind = texel(floor(fx - 1.5), y);
    c = max(c + (c - behind) * 0.16, 0.0);
    c += texel(floor(fx - 5.0), y) * 0.045;
    return c;
}

// one beam line with per-gun horizontal offsets (misconvergence / chroma split)
vec3 fetchRGB(float x, float line, float split) {
    if (split < 0.02 / uSrcSize.x) return fetchLine(x, line);
    return vec3(fetchLine(x - split, line).r, fetchLine(x, line).g, fetchLine(x + split, line).b);
}

void main() {
    vec2 frag = gl_FragCoord.xy;
    float scrH = uOut.y * 0.965, scrW = scrH * 4.0 / 3.0;
    vec2 uv = (frag - uOut * 0.5) / vec2(scrW, scrH) * 2.0;   // -1..1 across the tube, y up

    // ---- power on (dot -> line -> overexposed raster that settles) and its exact reverse at power off
    float sx = 1.0, sy = 1.0, gain = 1.0, wash = 0.0, halo = 0.0, dotOnly = 0.0;
    if (uOnT < 1.6) {
        float t = uOnT;
        sx = mix(0.004, 1.0, ease((t - 0.10) / 0.14));
        sy = mix(0.005, 1.0, ease((t - 0.24) / 0.24));
        dotOnly = 1.0 - step(0.10, t);
        gain = 1.0 + 3.2 * (1.0 - ease((t - 0.35) / 1.0));
        wash = 0.55 * (1.0 - ease((t - 0.30) / 0.75)) * step(0.10, t);
        halo = (1.0 - ease((t - 0.30) / 0.6)) * smoothstep(0.0, 0.05, t);
    }
    if (uOffT >= 0.0) {
        float t = uOffT;
        gain = 1.0 + 3.2 * ease(t / 0.25);
        wash = 0.55 * ease((t - 0.05) / 0.20);
        sy = mix(1.0, 0.005, ease((t - 0.25) / 0.20));
        sx = mix(1.0, 0.004, ease((t - 0.45) / 0.15));
        halo = ease(t / 0.3) * (1.0 - ease((t - 0.6) / 0.8));
        dotOnly = step(0.60, t);
    }
    float fade = uOffT >= 0.0 ? 1.0 - ease((uOffT - 0.60) / 0.8) : 1.0;

    // raster bulge: bright pictures sag the high voltage and the picture grows
    vec2 uvc = uv / (vec2(sx, sy) * (1.0 + 0.018 * uBulge));
    // degauss: the whole raster wobbles while the coil field decays
    uvc += uDegauss * 0.035 * vec2(sin(uvc.y * 7.0 + uT * 43.0), sin(uvc.x * 5.0 + uT * 37.0));

    // tube curvature
    vec2 cuv = uvc * (1.0 + vec2(0.055, 0.075) * (uvc.yx * uvc.yx));
    vec2 q = abs(cuv) - vec2(1.0) + 0.035;
    float edge = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.035;
    float inside = 1.0 - smoothstep(-0.004, 0.004, edge);

    vec2 sc = cuv * 0.5 + 0.5;                 // 0..1, y up (GL texture convention: v=1 is the top row)
    // vertical roll on a mode change, horizontal hold loss, tearing bands, sync jitter
    sc.y = fract(sc.y + uRoll);
    float vblank = uRoll > 0.0 ? smoothstep(0.0, 0.02, sc.y) * smoothstep(1.0, 0.98, sc.y) : 1.0;
    sc.x += uHold * 0.02 * sin(sc.y * 23.0 + uT * 61.0) * sin(uT * 7.0 + sc.y * 3.0);
    float band = floor(sc.y * 28.0);
    float bh = hash(vec2(band, uTearSeed));
    if (bh < uTear * 0.4) sc.x += (hash(vec2(band + 7.0, uTearSeed)) - 0.5) * 0.16 * uTear;
    if (uJitter > 0.0) sc.x += (hash(vec2(floor(sc.y * 60.0), floor(uT * 60.0))) - 0.5) * 0.02 * uJitter;

    float srcLine = (1.0 - sc.y) * uSrcSize.y - 0.5;   // continuous source line coordinate, top = 0
    float l0 = floor(srcLine), f = srcLine - l0;
    // RGB misconvergence grows toward the edges; uRGB adds a glitch split (in source pixels)
    float split = (abs(sc.x - 0.5) * 0.9 + uRGB) / uSrcSize.x;
    vec3 col = vec3(0.0);
    float beamBase = uMode == 0 ? 0.30 : 0.27;
    for (int k = 0; k <= 1; k++) {
        float line = clamp(l0 + float(k), 0.0, uSrcSize.y - 1.0);
        vec3 c = fetchRGB(sc.x, uSrcSize.y - 1.0 - line, split);
        float d = abs(f - float(k));
        vec3 sigma = beamBase + 0.16 * sqrt(c);                     // bright lines bloom wider
        col += c * exp(-d * d / (2.0 * sigma * sigma));
    }
    col *= uMode == 0 ? 1.45 : 1.75;
    if (dotOnly > 0.5) col = vec3(0.0);

    // degauss purity blotches: slow rainbow patches across the face
    if (uDegauss > 0.0) {
        float a = atan(uv.y, uv.x) * 2.0 + length(uv) * 5.0 - uT * 9.0;
        vec3 rb = 0.5 + 0.5 * cos(a + vec3(0.0, 2.1, 4.2));
        col *= mix(vec3(1.0), rb * 1.6, uDegauss * 0.65);
    }

    // aperture grille (subtle: survives YouTube)
    int m = int(mod(frag.x, 3.0));
    vec3 mask = vec3(m == 0 ? 1.0 : 0.82, m == 1 ? 1.0 : 0.82, m == 2 ? 1.0 : 0.82);
    col *= mask * 1.08;

    // halation (+ extra while the tube is overdriven)
    vec3 glow = lin(texture(uGlow, sc).rgb);
    col += glow * ((uMode == 0 ? 0.22 : 0.34) * (1.0 + 0.25 * uKick) + (gain - 1.0) * 0.6);

    // overdriven raster at power on/off: everything lifts toward white
    col = col * gain + vec3(0.80, 0.86, 1.0) * wash;

    // snow + sync-loss noise
    if (uSnow > 0.0) {
        float n = hash(floor(frag / vec2(3.0, 2.0)) + fract(uT * 13.7) * 311.0);
        float streak = hash(vec2(floor(frag.y / 2.0), floor(uT * 60.0)));
        col = mix(col, vec3(n * n) * (0.6 + 0.8 * step(0.97, streak)), uSnow);
    }

    // vignette + a visible 60 Hz hum bar rolling up the screen + fine noise
    vec2 v = sc * (1.0 - sc);
    col *= pow(clamp(v.x * v.y * 16.0, 0.0, 1.0), 0.18);
    float hum = abs(fract(sc.y * 0.5 - uT * 0.23) - 0.5);
    col *= 1.0 - 0.045 * smoothstep(0.30, 0.5, hum);
    col += (hash(frag + fract(uT) * 91.0) - 0.5) * 0.012;
    col *= vblank * inside * fade;

    // the beam itself while the raster is a dot or a line: a hot core with a soft halo
    vec2 dd = max(abs(uv) - vec2(sx, sy), 0.0);
    float r2 = dot(dd, dd);
    col += vec3(0.85, 0.9, 1.0) * halo * fade * (exp(-r2 / 0.00004) * 2.2 + exp(-r2 / 0.004) * 0.35);

    // phosphor persistence: the previous frame decays instead of vanishing
    vec3 prev = lin(texture(uPrev, frag / uOut).rgb);
    col = max(col, prev * uPersist);

    // subtle glass reflection on the curved face
    float refl = smoothstep(0.9, 0.0, length((uv - vec2(-0.55, 0.62)) * vec2(1.0, 1.6))) * 0.005;
    col += refl * inside * step(0.3, uOnT) * fade;
    o = vec4(pow(max(col, 0.0), vec3(1.0 / 2.2)), 1.0);
}
