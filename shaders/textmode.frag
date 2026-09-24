#version 410 core
// VGA text mode 80x25 with the 9x16 IBM VGA font, standard 16-colour palette, blinking cursor,
// and a BIOS "energy star" corner logo in the POST screen.
in vec2 vUV;
out vec4 o;
uniform sampler2D uScreen;  // 80x25: r = char, g = attribute
uniform sampler2D uFont;    // 144x256 CP437 atlas (16x16 cells of 9x16)
uniform sampler2D uLogo;
uniform float uT;
uniform ivec3 uCursor;      // col, row, enabled
uniform int uShowLogo, uBlank;

const vec3 PAL[16] = vec3[](
    vec3(0x00,0x00,0x00), vec3(0x00,0x00,0xAA), vec3(0x00,0xAA,0x00), vec3(0x00,0xAA,0xAA),
    vec3(0xAA,0x00,0x00), vec3(0xAA,0x00,0xAA), vec3(0xAA,0x55,0x00), vec3(0xAA,0xAA,0xAA),
    vec3(0x55,0x55,0x55), vec3(0x55,0x55,0xFF), vec3(0x55,0xFF,0x55), vec3(0x55,0xFF,0xFF),
    vec3(0xFF,0x55,0x55), vec3(0xFF,0x55,0xFF), vec3(0xFF,0xFF,0x55), vec3(0xFF,0xFF,0xFF));

float bayer4(ivec2 p) {
    int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
    return (float(m[(p.y & 3) * 4 + (p.x & 3)]) + 0.5) / 16.0;
}

void main() {
    if (uBlank == 1) { o = vec4(0, 0, 0, 1); return; }
    ivec2 px = ivec2(gl_FragCoord.x, 400.0 - gl_FragCoord.y);  // y down
    ivec2 cell = ivec2(px.x / 9, px.y / 16), g = ivec2(px.x % 9, px.y % 16);
    vec4 c = texelFetch(uScreen, cell, 0);
    int ch = int(c.r * 255.0 + 0.5), at = int(c.g * 255.0 + 0.5);
    int fg = at & 15, bg = (at >> 4) & 7;
    float on = texelFetch(uFont, ivec2((ch % 16) * 9 + g.x, (ch / 16) * 16 + g.y), 0).r;
    // hardware cursor: scanlines 14-15 of the cell, blinks every 16 vsyncs at 70 Hz
    if (uCursor.z == 1 && cell == uCursor.xy && g.y >= 14 && fract(uT / 0.457) < 0.5) on = 1.0;
    vec3 col = on > 0.5 ? PAL[fg] : PAL[bg];
    col /= 255.0;
    if (uShowLogo == 1) {
        // 128x128 logo in the top-right corner, reduced to the 64-colour EGA palette with ordered dither
        vec2 lp = (vec2(px) - vec2(574.0, 4.0)) / 128.0;
        if (lp.x >= 0.0 && lp.y >= 0.0 && lp.x < 1.0 && lp.y < 1.0) {
            vec4 l = texture(uLogo, lp);
            if (l.a > 0.5) {
                vec3 e = floor(l.rgb * 3.0 + bayer4(px)) / 3.0;
                col = e;
            }
        }
    }
    o = vec4(col, 1.0);
}
