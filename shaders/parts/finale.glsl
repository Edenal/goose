// @id finale
// @name FINALE
// @split FINALE
// @bars 1
// @order 1000
// @default on
// @special finale
// @inspired GOOSE original: 3D cube snaps onto the flat brand logo
// @desc The cube flies in and lands exactly on the ESA MARATHON logo on the song's final hit; event name and links type in, then the tube powers off.

vec3 part(vec2 p) {
    vec2 hc = p - vec2(uLogoPos.x, uLogoPos.y + 20.0);
    float h = exp(-dot(hc, hc) / (2.0 * 95.0 * 95.0));
    vec3 col = mix(DEEP * 0.55, PURP * 0.55, h * (0.7 + 0.3 * sin(uT * 1.7)));
    col += stars(p, 0.06, uT, 0.6) * (1.0 - h * 0.6);
    col = floor(col * 16.0) / 16.0;
    // cube: perspective flight blended into the logo's own parallel projection
    vec3 rdw = cameraRay(p);
    vec3 roP = uCubeRot * (uCamPos - uCubeC) / uCubeS + 0.5, rdP = uCubeRot * rdw;
    vec3 roA = uAffP0 * (p.x - uAffS0.x) + uAffP1 * (p.y - uAffS0.y) - uAffD * 4.0, rdA = uAffD;
    vec4 c = traceCube(mix(roP, roA, uSnap), normalize(mix(rdP, rdA, uSnap)), 1.0 - uSnap, transpose(uCubeRot));
    if (uLogoA < 0.5 && c.a > 0.5) col = c.rgb;
    if (uLogoA > 0.5) {   // after the hit: the real 2D logo (with its keyline) and the wordmark
        vec2 lu = ((p - uLogoPos.xy) / uLogoPos.z + vec2(250.0, 249.53) + 50.0) / 600.0;
        if (lu.x >= 0.0 && lu.y >= 0.0 && lu.x <= 1.0 && lu.y <= 1.0) {
            vec4 l = texture(uLogo, lu);
            col = mix(col, l.rgb, smoothstep(0.35, 0.65, l.a));
        }
        vec2 wsz = vec2(textureSize(uWord, 0));
        float ww = 200.0 * uWordAS.y, wh = ww * wsz.y / wsz.x;
        vec2 wu = (p - vec2(160.0 - ww * 0.5, 162.0 - wh * 0.5)) / vec2(ww, wh);
        float m = 0.0, ol = 0.0;
        if (wu.x > -0.05 && wu.x < 1.05 && wu.y > -0.2 && wu.y < 1.2) {
            m = texture(uWord, wu).r;
            for (int k = 0; k < 8; k++) {
                vec2 d = vec2(cos(float(k) * PI / 4.0), sin(float(k) * PI / 4.0)) * vec2(2.2 / ww, 2.2 / wh);
                ol = max(ol, texture(uWord, wu + d).r);
            }
        }
        if (ol > 0.5) col = mix(col, PLUM, uWordAS.x);
        if (m > 0.5) {
            float gy = clamp(wu.y, 0.0, 1.0);
            vec3 g = gy < 0.55 ? mix(UIGOLD, vec3(1.0, 0.85, 0.41), gy / 0.55) : mix(vec3(1.0, 0.85, 0.41), CREAM, (gy - 0.55) / 0.45);
            float glint = step(abs(wu.x * ww - wu.y * wh * 0.6 - (fract(uT * 0.35) * 420.0 - 60.0)), 5.0);
            col = mix(col, mix(g, vec3(1.0), glint * 0.7), uWordAS.x);
        }
    }
    // event name types in, then the two links
    float hh = uT - uHit;
    if (uHit >= 0.0 && hh > 0.9) {
        int n = min(strLen(16), int((hh - 0.9) * 22.0));
        col = drawStrN(col, p, 16, vec2(floor((uRes.x - strW(16, 2.0)) * 0.5), 190.0), 2.0, TS_CHROME, 1.0, n);
    }
    if (hh > 1.9) col = drawStrC(col, p, 17, 212.0, 1.0, TS_WHITE, clamp((hh - 1.9) / 0.2, 0.0, 1.0));
    if (hh > 2.4) col = drawStrC(col, p, 18, 224.0, 1.0, TS_LAV, clamp((hh - 2.4) / 0.2, 0.0, 1.0));
    return col;
}
