// @id tunnel
// @name GREETINGS TUNNEL
// @split TUNNEL
// @bars 3
// @order 50
// @default on
// @inspired GOOSE original: texture tunnel built from the cube's E/S/A faces
// @desc Flying down a tube tiled with the logo's faces; greetings zoom out of the vanishing point on every other beat.
// @str 0 GREETINGS TO
// @str 1 RUNNERS
// @str 2 HOSTS
// @str 3 COMMENTATORS
// @str 4 TECH CREW
// @str 5 VOLUNTEERS
// @str 6 VIEWERS

vec3 part(vec2 p) {
    vec2 ctr = uRes * 0.5 + vec2(sin(uT * 0.7) * 34.0, cos(uT * 0.9) * 22.0);
    vec2 c = (p - ctr) / uRes.y;
    float r = length(c), a = atan(c.y, c.x);
    float z = 0.22 / max(r, 1e-3) + uLT * 2.6 + uKickCum * 0.9;
    float u = (a / (2.0 * PI) + 0.5) * 6.0 + uLT * 0.35;
    int face = int(mod(floor(u), 3.0));
    vec2 fuv = vec2(fract(u), fract(z));
    vec4 tx = face == 0 ? texture(uTop, fuv) : face == 1 ? texture(uLeft, fuv) : texture(uRight, fuv);
    vec3 col = mix(DEEP, tx.rgb, tx.a);
    float wht = smoothstep(0.75, 0.95, min(col.r, min(col.g, col.b)));
    col = mix(col, mix(ROYAL, LAV, fract(z) * 0.6), wht * 0.85);
    col *= 0.55 + 0.45 * step(0.5, fract(z * 0.5));
    col += GOLD * 0.6 * uEnv.w * step(fract(z * 0.5), 0.08);
    col *= smoothstep(0.02, 0.45, r) * 0.9;
    // greetings: one name per two beats, zooming out of the tube
    col = drawStrC(col, p, 0, 16.0, 1.0, TS_LAV, 1.0);
    float two = 2.0 * (60.0 / 90.0);
    int i = min(5, int(uLT / two));
    float lb = (uLT - float(i) * two) / two;
    int row = 1 + i;
    float sc = 1.2 + 2.3 * easeOut(lb * 1.6);
    if (strW(row, sc) > 300.0) sc = 300.0 / (float(strLen(row)) * 8.0);
    float al = lb < 0.8 ? 1.0 : 1.0 - (lb - 0.8) / 0.2;
    return drawStr(col, p, row, vec2((uRes.x - strW(row, sc)) * 0.5, 120.0 - 4.0 * sc), sc, TS_CHROME, al);
}
