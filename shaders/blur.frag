#version 410 core
// separable 13-tap gaussian used for CRT halation
in vec2 vUV;
out vec4 o;
uniform sampler2D uSrc;
uniform vec2 uDir;
void main() {
    const float w[7] = float[](0.1996, 0.1760, 0.1210, 0.0648, 0.0270, 0.0088, 0.0022);
    vec3 s = texture(uSrc, vUV).rgb * w[0];
    for (int i = 1; i < 7; i++) {
        vec2 d = uDir * float(i) * 1.6;
        s += (texture(uSrc, vUV + d).rgb + texture(uSrc, vUV - d).rgb) * w[i];
    }
    o = vec4(s, 1.0);
}
