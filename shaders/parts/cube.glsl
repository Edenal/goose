// @id cube
// @name THE CUBE
// @split THE CUBE
// @bars 4
// @order 20
// @default on
// @inspired GOOSE original: ray-cast brand cube on a Mode 7 checkerboard
// @desc The drop: the ESA cube spins over a scrolling checkerboard with its reflection, copper sky and a sine scroller.
// @str 0       *** {EVENT} ***   THE EUROPEAN SPEEDRUNNER ASSEMBLY IS BACK  ...  SPEEDRUNS LIVE FOR CHARITY  ...  GREETINGS TO EVERY RUNNER, HOST, COMMENTATOR, TECH AND VOLUNTEER  ...

vec3 part(vec2 p) {
    vec3 rd = cameraRay(p);
    const float FY = -0.72;
    // sky: stepped gradient + copper bars pulsing with the bass
    float sk = floor(clamp(rd.y * 3.0 + 0.1, 0.0, 1.0) * 10.0) / 10.0;
    vec3 col = mix(PURP * 0.55, DEEP * 0.6, sk);
    col = mix(col, copper(p, col, uT, 40.0, 50.0), 0.55 + 0.3 * uEnv.x);
    if (rd.y < 0.0) {
        float t = (FY - uCamPos.y) / rd.y;
        vec3 P = uCamPos + rd * t;
        float scroll = uLT * 2.2 + uKickCum * 1.4;
        vec2 cc = floor(vec2(P.x * 1.25, P.z * 1.25 - scroll));
        float chk = mod(cc.x + cc.y, 2.0);
        vec3 f = chk > 0.5 ? ROYAL : PLUM;
        f += GOLD * 0.35 * uEnv.w * chk;
        vec4 rc = cubePersp(P, reflect(rd, vec3(0, 1, 0)), 1.0);   // reflection of the cube
        f = mix(f, rc.rgb * 0.9, rc.a * 0.45);
        f *= mix(0.45, 1.0, smoothstep(0.35, 0.95, length(P.xz - uCubeC.xz)));   // contact shadow
        col = mix(PURP * 0.5, f, exp(-t * 0.11));
    }
    vec4 c = cubePersp(uCamPos, rd, 1.0);
    if (c.a > 0.5) col = c.rgb;
    return drawWave(col, p, 0, uRes.x - uLT * 110.0, 204.0, 2.0, 14.0);
}
