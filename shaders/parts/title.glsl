// @id title
// @name TITLE
// @split MODE X
// @bars 1
// @order 10
// @default on
// @inspired GOOSE original: starfield + copper list opener
// @desc Stars accelerate through stepped copper bars while EUROPEAN SPEEDRUNNER ASSEMBLY types out, then PRESENTS in chrome.
// @str 0 EUROPEAN SPEEDRUNNER ASSEMBLY
// @str 1 PRESENTS

vec3 part(vec2 p) {
    float boost = smoothstep(uLen - 0.47, uLen - 0.01, uLT);
    vec3 col = stars(p, 0.35 + 2.5 * boost * boost, uT, 1.0);
    col = copper(p, col, uT * 1.3, 90.0, 120.0) * 0.55 + col * 0.45;
    // the name types out over the first two beats, PRESENTS lands on beat 3
    int n = strLen(0);
    int shown = min(n, int(uLT / (2.0 * (60.0 / 90.0) / float(n))));
    col = drawStrN(col, p, 0, vec2(floor((uRes.x - strW(0, 1.0)) * 0.5), 92.0), 1.0, TS_WHITE, 1.0, shown);
    if (uLT >= 2.0 * (60.0 / 90.0)) col = drawStrC(col, p, 1, 124.0, 2.0, TS_CHROME, 1.0);
    return col;
}
