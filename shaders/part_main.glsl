
// ---- appended after every part: flash, then the Mega Drive 9-bit output (8 non-linear DAC levels per
// channel with ordered dither; the CRT's composite smear blends it back like the real hardware on a TV)
void main() {
    vec2 p = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y);  // pixel coords, y down
    vec3 col = part(p);
    col = mix(col, vec3(1.0), uFlash);
    const float LV[8] = float[](0.0, 0.204, 0.341, 0.455, 0.565, 0.675, 0.808, 1.0);
    float th = bayer4(p);
    vec3 outc;
    for (int ch = 0; ch < 3; ch++) {
        float v = clamp(col[ch], 0.0, 1.0);
        int i = 0;
        for (int k = 0; k < 7; k++) if (v >= LV[k + 1]) i = k + 1;
        float q = LV[i];
        if (i < 7) { float f = (v - LV[i]) / (LV[i + 1] - LV[i]); q = f > th ? LV[i + 1] : LV[i]; }
        outc[ch] = q;
    }
    o = vec4(outc, 1.0);
}
