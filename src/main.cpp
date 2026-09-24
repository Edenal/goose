// ESA trailer — a 90s PC demo in C++ / OpenGL 4.1.
//
//   esa_trailer                     live: window + music (space pause, arrows seek, F fullscreen)
//   esa_trailer --frames T1,T2 pfx  render single frames to pfx_<T>.png
//   esa_trailer --export out.mp4    offline 1920x1080@60 render piped into ffmpeg (+ soundtrack)
//
// Every frame is a pure function of t, so live, stills and export are identical.
#include <SDL3/SDL.h>
#include <OpenGL/gl3.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "audio.h"
#include "textmode.h"
#include "timeline.h"

#define STB_IMAGE_IMPLEMENTATION
#include "third_party/stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "third_party/stb_image_write.h"

// ------------------------------------------------------------------ small math
struct V3 { double x, y, z; };
static V3 operator+(V3 a, V3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
static V3 operator-(V3 a, V3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
static V3 operator*(V3 a, double s) { return {a.x * s, a.y * s, a.z * s}; }
static double dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static V3 cross(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
static V3 norm(V3 a) { return a * (1.0 / sqrt(dot(a, a))); }
struct M3 { V3 r[3]; };  // rows

static M3 transpose(const M3& m) {
    return {{{m.r[0].x, m.r[1].x, m.r[2].x}, {m.r[0].y, m.r[1].y, m.r[2].y}, {m.r[0].z, m.r[1].z, m.r[2].z}}};
}
struct Q { double w, x, y, z; };
static Q qaxis(V3 a, double ang) { a = norm(a); double s = sin(ang / 2); return {cos(ang / 2), a.x * s, a.y * s, a.z * s}; }
static Q qmul(Q a, Q b) {
    return {a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z, a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x, a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w};
}
static Q qslerp(Q a, Q b, double t) {
    double d = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    if (d < 0) { b = {-b.w, -b.x, -b.y, -b.z}; d = -d; }
    if (d > 0.9995) {
        Q r = {a.w + (b.w - a.w) * t, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t};
        double n = sqrt(r.w * r.w + r.x * r.x + r.y * r.y + r.z * r.z);
        return {r.w / n, r.x / n, r.y / n, r.z / n};
    }
    double th = acos(d), s = sin(th), wa = sin((1 - t) * th) / s, wb = sin(t * th) / s;
    return {a.w * wa + b.w * wb, a.x * wa + b.x * wb, a.y * wa + b.y * wb, a.z * wa + b.z * wb};
}
static M3 qmat(Q q) {  // rotation matrix (object -> world)
    double w = q.w, x = q.x, y = q.y, z = q.z;
    return {{{1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)},
             {2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)},
             {2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)}}};
}
static Q matq(const M3& m) {
    double tr = m.r[0].x + m.r[1].y + m.r[2].z;
    Q q;
    if (tr > 0) {
        double s = sqrt(tr + 1.0) * 2;
        q = {0.25 * s, (m.r[2].y - m.r[1].z) / s, (m.r[0].z - m.r[2].x) / s, (m.r[1].x - m.r[0].y) / s};
    } else if (m.r[0].x > m.r[1].y && m.r[0].x > m.r[2].z) {
        double s = sqrt(1.0 + m.r[0].x - m.r[1].y - m.r[2].z) * 2;
        q = {(m.r[2].y - m.r[1].z) / s, 0.25 * s, (m.r[0].y + m.r[1].x) / s, (m.r[0].z + m.r[2].x) / s};
    } else if (m.r[1].y > m.r[2].z) {
        double s = sqrt(1.0 + m.r[1].y - m.r[0].x - m.r[2].z) * 2;
        q = {(m.r[0].z - m.r[2].x) / s, (m.r[0].y + m.r[1].x) / s, 0.25 * s, (m.r[1].z + m.r[2].y) / s};
    } else {
        double s = sqrt(1.0 + m.r[2].z - m.r[0].x - m.r[1].y) * 2;
        q = {(m.r[1].x - m.r[0].y) / s, (m.r[0].z + m.r[2].x) / s, (m.r[1].z + m.r[2].y) / s, 0.25 * s};
    }
    return q;
}
static double clamp01(double x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
static double smooth(double a, double b, double x) { x = clamp01((x - a) / (b - a)); return x * x * (3 - 2 * x); }
static double easeOut(double x) { x = clamp01(x); return 1 - (1 - x) * (1 - x) * (1 - x); }

// ------------------------------------------------------------------ GL helpers
struct Tex { GLuint id = 0; int w = 0, h = 0; };
static Tex loadTex(const std::string& path, bool mip, bool nearest) {
    Tex t; int n;
    unsigned char* px = stbi_load(path.c_str(), &t.w, &t.h, &n, 4);
    if (!px) { fprintf(stderr, "missing texture %s\n", path.c_str()); exit(1); }
    glGenTextures(1, &t.id);
    glBindTexture(GL_TEXTURE_2D, t.id);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, t.w, t.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    stbi_image_free(px);
    if (mip) glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, nearest ? GL_NEAREST : mip ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, nearest ? GL_NEAREST : GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return t;
}
static Tex makeTex(int w, int h, GLenum ifmt, GLenum fmt, GLenum type, GLenum filter) {
    Tex t; t.w = w; t.h = h;
    glGenTextures(1, &t.id);
    glBindTexture(GL_TEXTURE_2D, t.id);
    glTexImage2D(GL_TEXTURE_2D, 0, ifmt, w, h, 0, fmt, type, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return t;
}
struct FB { GLuint fbo = 0; Tex tex; };
static FB makeFB(int w, int h, GLenum filter) {
    FB f; f.tex = makeTex(w, h, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, filter);
    glGenFramebuffers(1, &f.fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, f.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, f.tex.id, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) { fprintf(stderr, "fbo incomplete\n"); exit(1); }
    return f;
}
static std::string readFile(const std::string& p) {
    std::ifstream f(p); std::stringstream s; s << f.rdbuf();
    if (!f) { fprintf(stderr, "missing %s\n", p.c_str()); exit(1); }
    return s.str();
}
static GLuint shader(GLenum type, const std::string& src, const std::string& name) {
    GLuint s = glCreateShader(type);
    const char* c = src.c_str();
    glShaderSource(s, 1, &c, nullptr);
    glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[8192]; glGetShaderInfoLog(s, sizeof log, nullptr, log); fprintf(stderr, "%s:\n%s\n", name.c_str(), log); exit(1); }
    return s;
}
static const char* VS = "#version 410 core\nout vec2 vUV;\nvoid main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);"
                        "vUV=p;gl_Position=vec4(p*2.0-1.0,0.0,1.0);}\n";
static GLuint program(const std::string& fragPath) {
    GLuint p = glCreateProgram();
    glAttachShader(p, shader(GL_VERTEX_SHADER, VS, "vs"));
    glAttachShader(p, shader(GL_FRAGMENT_SHADER, readFile(fragPath), fragPath));
    glLinkProgram(p);
    GLint ok; glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) { char log[4096]; glGetProgramInfoLog(p, sizeof log, nullptr, log); fprintf(stderr, "link %s\n%s\n", fragPath.c_str(), log); exit(1); }
    return p;
}
static GLint U(GLuint p, const char* n) { return glGetUniformLocation(p, n); }
static void bindTex(GLuint p, const char* name, int unit, GLuint tex) {
    glActiveTexture(GL_TEXTURE0 + unit); glBindTexture(GL_TEXTURE_2D, tex); glUniform1i(U(p, name), unit);
}
static void setM3(GLuint p, const char* n, const M3& m) {  // GLSL is column-major: pass transpose of rows
    float f[9] = {(float)m.r[0].x, (float)m.r[1].x, (float)m.r[2].x, (float)m.r[0].y, (float)m.r[1].y,
                  (float)m.r[2].y, (float)m.r[0].z, (float)m.r[1].z, (float)m.r[2].z};
    glUniformMatrix3fv(U(p, n), 1, GL_FALSE, f);
}
static void set3(GLuint p, const char* n, V3 v) { glUniform3f(U(p, n), (float)v.x, (float)v.y, (float)v.z); }

// ------------------------------------------------------------------ text items
enum TStyle { TS_WHITE = 0, TS_CHROME, TS_GOLD, TS_LAV, TS_GREEN, TS_WAVE, TS_RED, TS_GREY };
struct TItem { std::string s; double x, y, scale; int style; double alpha = 1; };
static double textW(const std::string& s, double sc) { return s.size() * 8 * sc; }
static TItem centered(const std::string& s, double y, double sc, int style, double a = 1) {
    return {s, std::floor((GFX_W - textW(s, sc)) / 2), y, sc, style, a};
}

// ------------------------------------------------------------------ the demo
struct Demo {
    Soundtrack st;
    std::vector<double> kickCum;
    GLuint pText, pScene, pBlur, pCRT;
    Tex font16, font8, cubeTop, cubeLeft, cubeRight, logoCube, word, screenTex, strTex;
    FB fbText, fbGfx, fbGlowA, fbGlowB, fbOut[2];
    int cur = 0;  // fbOut ping-pong: the previous frame feeds phosphor persistence
    FB& out() { return fbOut[cur]; }
    Screen scr;
    // logo snap geometry (320x240 pixel space, y down)
    V3 affP0, affP1, affD; double affS0x, affS0y, logoK = 0.235, logoCx = 160, logoCy = 86;
    Q qLogo;

    void init() {
        pText = program("shaders/textmode.frag");
        pScene = program("shaders/scenes.frag");
        pBlur = program("shaders/blur.frag");
        pCRT = program("shaders/crt.frag");
        font16 = loadTex("assets/gen/font_vga9x16.png", false, true);
        font8 = loadTex("assets/gen/font_bios8x8.png", false, true);
        cubeTop = loadTex("assets/gen/cube_top.png", true, false);
        cubeLeft = loadTex("assets/gen/cube_left.png", true, false);
        cubeRight = loadTex("assets/gen/cube_right.png", true, false);
        logoCube = loadTex("assets/gen/logo_cube.png", true, false);
        word = loadTex("assets/gen/word_marathon.png", true, false);
        screenTex = makeTex(80, 25, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, GL_NEAREST);
        strTex = makeTex(64, 24, GL_R8, GL_RED, GL_UNSIGNED_BYTE, GL_NEAREST);
        fbText = makeFB(TXT_W, TXT_H, GL_NEAREST);
        fbGfx = makeFB(GFX_W, GFX_H, GL_NEAREST);
        fbGlowA = makeFB(320, 240, GL_LINEAR);
        fbGlowB = makeFB(320, 240, GL_LINEAR);
        for (FB& f : fbOut) {
            f = makeFB(OUT_W, OUT_H, GL_LINEAR);
            glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        }
        GLuint vao; glGenVertexArrays(1, &vao); glBindVertexArray(vao);

        if (!st.build("assets/gen/song_cut.wav")) exit(1);
        st.writeWav("out/soundtrack.wav");
        kickCum.assign(st.frames() + 1, 0);
        for (int f = 0; f < st.frames(); f++) kickCum[f + 1] = kickCum[f] + st.kick[f] / FPS;
        solveLogo();
    }

    // The brand cube is an axonometric drawing, not a true projection of a cube. Solve the parallel
    // projection that maps cube space [0,1]^3 onto it exactly, so the 3D cube can land on the logo.
    void solveLogo() {
        const double Fx = 250, Fy = 201, Lx = 57.46, Ly = 120.48, Rx = 442.54, Ry = 120.48, Bx = 250, By = 459.1;
        const double Pcx = 250, Pcy = 249.53, k = logoK;
        auto S = [&](double x, double y, double& sx, double& sy) { sx = logoCx + k * (x - Pcx); sy = logoCy + k * (y - Pcy); };
        double s0x, s0y; S(Lx + Rx + Bx - 2 * Fx, Ly + Ry + By - 2 * Fy, s0x, s0y);
        V3 mx = {k * (Fx - Lx), k * (Fy - Ly), 0}, my = {k * (Fx - Bx), k * (Fy - By), 0}, mz = {k * (Fx - Rx), k * (Fy - Ry), 0};
        V3 row0 = {mx.x, my.x, mz.x}, row1 = {mx.y, my.y, mz.y};
        affD = norm(cross(row0, row1));
        if (affD.x > 0) affD = affD * -1.0;
        // pseudo-inverse columns: P = M^T (M M^T)^-1
        double a = dot(row0, row0), b = dot(row0, row1), d = dot(row1, row1), det = a * d - b * b;
        double i00 = d / det, i01 = -b / det, i11 = a / det;
        affP0 = row0 * i00 + row1 * i01;  // column for screen x
        affP1 = row0 * i01 + row1 * i11;  // column for screen y (down)
        affS0x = s0x; affS0y = s0y;
        // rotation that shows the cube along affD with screen-up = -affP1 (for the perspective lead-in)
        V3 right = norm(affP0 - affD * dot(affP0, affD));
        V3 fwdc = affD;                       // cube-space direction pointing into the screen
        V3 up = norm(cross(fwdc * -1.0, right));  // right x up = back, a proper rotation
        M3 R = {{right, up, fwdc * -1.0}};         // cube -> camera/world (rows)
        qLogo = matq(R);
        fprintf(stderr, "logo solve: d=(%.3f %.3f %.3f) up.P1=%.3f\n", affD.x, affD.y, affD.z, dot(up, affP1 * -1.0));
    }

    float env(const std::vector<float>& v, double t) const {
        int f = std::clamp((int)std::floor(t * FPS + 1e-6), 0, (int)v.size() - 1);
        return v[f];
    }
    double kickSum(double t) const {
        int f = std::clamp((int)std::floor(t * FPS + 1e-6), 0, (int)kickCum.size() - 1);
        return kickCum[f];
    }

    void drawQuad() { glDrawArrays(GL_TRIANGLES, 0, 3); }

    // ---------------------------------------------------------------- per-scene layout
    std::vector<TItem> sceneText(Scene sc, double t, double lt) {
        std::vector<TItem> v;
        double beat = beatAt(t);
        switch (sc) {
            case SC_TITLE: {
                std::string a = "EUROPEAN SPEEDRUNNER ASSEMBLY";
                int n = std::min((int)a.size(), (int)(lt / (2 * BEAT / a.size())));
                TItem it = centered(a, 92, 1, TS_WHITE);
                it.s = a.substr(0, n);
                v.push_back(it);
                if (lt >= 2 * BEAT) v.push_back(centered("PRESENTS", 124, 2, TS_CHROME));
                break;
            }
            case SC_DROP: {
                std::string s = "      *** " EVENT_NAME " ***   THE EUROPEAN SPEEDRUNNER ASSEMBLY IS BACK  ...  "
                                "SPEEDRUNS LIVE FOR CHARITY  ...  GREETINGS TO EVERY RUNNER, HOST, COMMENTATOR, "
                                "TECH AND VOLUNTEER  ...  ";
                double x = GFX_W - lt * 110.0;
                int skip = std::max(0, (int)(-x / 16));
                v.push_back({s.substr(std::min<size_t>(skip, s.size()), 40), x + skip * 16, 204, 2, TS_WAVE});
                break;
            }
            case SC_PLASMA: {
                const char* W[4] = {"SPEEDRUNS", "LIVE ON TWITCH", "FOR CHARITY", EVENT_NAME};
                int i = std::min(3, (int)(lt / (4 * BEAT)));
                double lb = lt - i * 4 * BEAT;
                double sc = strlen(W[i]) > 11 ? 2 : 3;
                double drop = (1 - easeOut(lb / 0.35)) * -60 + sin(std::min(1.0, lb / 0.5) * M_PI) * 4;
                v.push_back(centered(W[i], 112 - 4 * sc + drop, sc, TS_CHROME));
                break;
            }
            case SC_STAGE: {
                double el = t;  // the run timer is the trailer clock itself
                char buf[32];
                v.push_back({EVENT_NAME, 10, 10, 1, TS_GOLD});
                v.push_back({"TRAILER - ANY%", 10, 20, 1, TS_GREY});
                struct Sp { const char* n; double at; } sp[] = {
                    {"BIOS POST", 3.55}, {"SOUND TEST", MUSIC_AT}, {"MODE X", T_DEMO}, {"THE CUBE", T_DROP},
                    {"PLASMA", T_PLASMA}, {"THE STAGE", T_STAGE}, {"FINALE", T_FINALE}};
                for (int i = 0; i < 7; i++) {
                    double y = 34 + i * 10;
                    bool done = t >= sp[i].at + (i == 5 ? 1e9 : 0);
                    bool cur = i == 5;
                    v.push_back({sp[i].n, 10, y, 1, cur ? TS_WHITE : TS_GREY});
                    if (done) {
                        snprintf(buf, sizeof buf, "%d:%05.2f", (int)(sp[i].at / 60), fmod(sp[i].at, 60.0));
                        v.push_back({buf, 150 - textW(buf, 1), y, 1, i == 3 ? TS_GOLD : TS_GREEN});
                    } else v.push_back({"-", 142, y, 1, TS_GREY});
                }
                snprintf(buf, sizeof buf, "%d:%05.2f", (int)(el / 60), fmod(el, 60.0));
                v.push_back({buf, 150 - textW(buf, 2), 110, 2, TS_GREEN});
                break;
            }
            case SC_TUNNEL: {
                const char* G[6] = {"RUNNERS", "HOSTS", "COMMENTATORS", "TECH CREW", "VOLUNTEERS", "VIEWERS"};
                v.push_back(centered("GREETINGS TO", 16, 1, TS_LAV));
                int i = std::min(5, (int)(lt / (2 * BEAT)));
                double lb = (lt - i * 2 * BEAT) / (2 * BEAT);
                double sc = 1.2 + 2.3 * easeOut(lb * 1.6);
                if (strlen(G[i]) * 8 * sc > 300) sc = 300.0 / (strlen(G[i]) * 8);
                double a = lb < 0.8 ? 1 : 1 - (lb - 0.8) / 0.2;
                TItem it = {G[i], (GFX_W - textW(G[i], sc)) / 2, 120 - 4 * sc, sc, TS_CHROME, a};
                v.push_back(it);
                break;
            }
            case SC_FINALE: {
                double h = t - T_HIT;
                if (h > 0.9) {
                    std::string e = EVENT_NAME;
                    int n = std::min((int)e.size(), (int)((h - 0.9) * 22));
                    TItem it = centered(e, 190, 2, TS_CHROME);
                    it.s = e.substr(0, n);
                    v.push_back(it);
                }
                if (h > 1.9) v.push_back(centered(EVENT_LINE2, 212, 1, TS_WHITE, clamp01((h - 1.9) / 0.2)));
                if (h > 2.4) v.push_back(centered(EVENT_LINE3, 224, 1, TS_LAV, clamp01((h - 2.4) / 0.2)));
                break;
            }
            default: break;
        }
        (void)beat;
        return v;
    }

    // ---------------------------------------------------------------- cube placement
    struct CubeCam { M3 cubeRot; V3 cubeC; double cubeS; V3 camPos; M3 camRot; double fov, snap; };
    CubeCam cubeCam(Scene sc, double t, double lt) {
        CubeCam c;
        c.fov = 0.55; c.snap = 0;
        double ks = kickSum(t);
        if (sc == SC_FINALE) {
            // fly in along -z, spin down, slerp into the logo orientation, then snap to the logo's projection
            double tin = clamp01((t - T_FINALE) / (T_HIT - 0.35 - T_FINALE));
            double z = -14.0 * pow(1 - easeOut(tin), 1.0);
            Q spin = qmul(qaxis({0.3, 1, 0.15}, (T_HIT - t) * 7.5 + 0.8 * ks), qaxis({1, 0, 0}, (T_HIT - t) * 3.1));
            double s = smooth(T_FINALE + 0.8, T_HIT - 0.33, t);
            Q q = qslerp(spin, qLogo, s);
            M3 objToWorld = qmat(q);
            c.cubeRot = transpose(objToWorld);  // world -> cube
            c.camPos = {0, 0, 3.0};
            c.camRot = {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}};
            // world size so the perspective cube roughly matches the logo size / position at the snap
            double D = 3.0, kpx = (GFX_H / 2.0) / (c.fov * D);
            c.cubeS = logoK * 330 / kpx / 1.35;
            V3 center = {(logoCx - GFX_W / 2.0) / kpx, -(logoCy - GFX_H / 2.0) / kpx, 0};
            c.cubeC = center + V3{0, 0, z};
            c.snap = smooth(T_HIT - 0.34, T_HIT - 0.02, t);
        } else {
            Q q = qmul(qaxis({0, 1, 0}, lt * 0.9 + ks * 1.6), qaxis({1, 0, 0.3}, lt * 0.55 + ks * 0.5));
            c.cubeRot = transpose(qmat(q));
            c.cubeS = 1.15;
            c.cubeC = {0, 0.25 + 0.12 * sin(beatAt(t) * M_PI), 0};
            V3 eye = {sin(lt * 0.35) * 1.4, 1.05, 3.6};
            V3 fwd = norm(V3{0, 0.1, 0} - eye);
            V3 right = norm(cross(fwd, {0, 1, 0}));
            V3 up = cross(right, fwd);
            c.camPos = eye;
            // camRot columns = right, up, -fwd  (camera looks down -z)
            c.camRot = transpose(M3{{right, up, fwd * -1.0}});
        }
        return c;
    }

    double flashAt(double t) {
        double f = 0;
        const double cuts[] = {T_DEMO, T_DROP, T_PLASMA, T_STAGE, T_TUNNEL};
        for (double c : cuts) if (t >= c) f = std::max(f, exp(-(t - c) * 9.0) * 0.3);
        if (t >= T_HIT) f = std::max(f, exp(-(t - T_HIT) * 4.0) * 0.7);
        return f;
    }

    // ---------------------------------------------------------------- glitches (pure function of t)
    struct Glitch { double tear = 0, seed = 0, rgb = 0, snow = 0, hold = 0, bulge = 0, degauss = 0, jitter = 0, roll = 0; };
    static double hashd(double n) { double x = sin(n * 91.345 + 3.7) * 47453.5453; return x - floor(x); }
    // Glitches live at the start (power-on, reboot, the VGA mode switch), at scene transitions, and at the end
    // (signal breakdown before the power-off). Inside a part the picture stays clean: the content is the focus.
    Glitch glitchAt(double t) {
        Glitch g;
        g.seed = (int)floor(t * FPS + 1e-6) % 997;
        auto pulse = [&](double c, double len) { return (t >= c && t < c + len) ? 1 - (t - c) / len : 0.0; };
        // power-on degauss: follows the coil's sound (swells at 0.12 s, decays over ~0.4 s)
        if (t > 0.12 && t < 2.2) { double d = t - 0.12; g.degauss = std::min(1.0, d / 0.08) * exp(-d / 0.38) * 0.7; }
        // reboot: a short horizontal hold slip
        double rb = pulse(6.35, 0.18);
        g.hold = rb * 0.8; g.snow = 0.55 * sqrt(rb);
        // VGA mode switch: garbage with hold loss -> black with light snow -> one vertical roll -> hold settles
        double ms = t - T_DEMO;
        if (ms > -0.85 && ms < -0.55) { double x = (ms + 0.85) / 0.3; g.hold = x; g.jitter = 0.4 * x; g.rgb = 1.5 * x; }
        if (ms >= -0.55 && ms < 0) g.snow = 0.65 * (1 - clamp01((ms + 0.10) / 0.10)) + 0.3 * pulse(T_DEMO - 0.55, 0.05);
        if (ms >= 0 && ms < 0.42) g.roll = (1 - easeOut(ms / 0.42)) * 0.9;
        g.hold = std::max(g.hold, 0.35 * pulse(T_DEMO + 0.38, 0.3));
        // scene transitions: the signal glitches out of the old part and settles into the new one.
        // Builds for ~0.12 s into the cut, tears for ~3 frames around it, then a small vertical jolt settles.
        const double cuts[] = {T_DROP, T_PLASMA, T_STAGE, T_TUNNEL, T_FINALE};
        for (double c : cuts) {
            double d = t - c;
            if (d <= -0.12 || d >= 0.20) continue;
            double outk = d < 0 ? (d + 0.12) / 0.12 : 0, ink = d >= 0 ? 1 - d / 0.20 : 0;
            double k = std::max(outk * outk, ink * ink);
            g.rgb = std::max(g.rgb, 4.0 * k);
            g.hold = std::max(g.hold, 0.5 * k);
            if (fabs(d) < 0.05) g.tear = std::max(g.tear, 0.9);
            g.snow = std::max(g.snow, 0.6 * exp(-(d / 0.04) * (d / 0.04)) + 0.12 * k);   // static burst on the cut
            if (d >= 0 && d < 0.12) g.roll = std::max(g.roll, 0.04 * (1 - d / 0.12));
        }
        // the cube landing on the logo is a transition too, a lighter one
        double lh = pulse(T_HIT, 0.15);
        g.rgb = std::max(g.rgb, 2.5 * lh * lh);
        if (t >= T_HIT && t < T_HIT + 0.035) g.tear = std::max(g.tear, 0.5);
        // the end: the signal starts breaking up in the last 0.7 s before the power-off
        double pre = t - (T_OFF - 0.7);
        if (pre >= 0 && t < T_OFF) {
            double x = pre / 0.7;
            g.hold = std::max(g.hold, 0.5 * x * x);
            g.snow = std::max(g.snow, 0.45 * x * x);
            double tr = std::max(pulse(T_OFF - 0.52, 0.05), pulse(T_OFF - 0.20, 0.07));
            g.tear = 0.8 * tr; g.rgb = 3.0 * tr + 1.5 * x;
        }
        return g;
    }

    // ---------------------------------------------------------------- one frame -> out()
    void render(double t) {
        double t0;
        Scene sc = sceneAt(t, &t0);
        double lt = t - t0;
        float eL = env(st.low, t), eM = env(st.mid, t), eH = env(st.high, t), eK = env(st.kick, t);
        GLuint src = 0; int srcW = GFX_W, srcH = GFX_H, mode = 1;
        bool blank = false;

        if (sc == SC_TEXT) {
            blank = !drawTextMode(scr, t, env(st.vuL, t) * 0.9f, env(st.vuR, t) * 0.9f);
            uint8_t buf[25][80][4];
            for (int r = 0; r < 25; r++) for (int c = 0; c < 80; c++) {
                buf[r][c][0] = scr.c[r][c].ch; buf[r][c][1] = scr.c[r][c].attr; buf[r][c][2] = 0; buf[r][c][3] = 0;
            }
            glBindTexture(GL_TEXTURE_2D, screenTex.id);
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 80, 25, GL_RGBA, GL_UNSIGNED_BYTE, buf);
            glBindFramebuffer(GL_FRAMEBUFFER, fbText.fbo);
            glViewport(0, 0, TXT_W, TXT_H);
            glUseProgram(pText);
            bindTex(pText, "uScreen", 0, screenTex.id);
            bindTex(pText, "uFont", 1, font16.id);
            bindTex(pText, "uLogo", 2, logoCube.id);
            glUniform1f(U(pText, "uT"), (float)t);
            glUniform3i(U(pText, "uCursor"), scr.curCol, scr.curRow, blank ? 0 : 1);
            glUniform1i(U(pText, "uShowLogo"), scr.logo ? 1 : 0);
            glUniform1i(U(pText, "uBlank"), blank ? 1 : 0);
            drawQuad();
            src = fbText.tex.id; srcW = TXT_W; srcH = TXT_H; mode = 0;
        } else {
            std::vector<TItem> items = sceneText(sc, t, lt);
            uint8_t sbuf[24][64];
            memset(sbuf, ' ', sizeof sbuf);
            int n = std::min<int>(24, (int)items.size());
            for (int i = 0; i < n; i++) memcpy(sbuf[i], items[i].s.data(), std::min<size_t>(64, items[i].s.size()));
            glBindTexture(GL_TEXTURE_2D, strTex.id);
            glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 64, 24, GL_RED, GL_UNSIGNED_BYTE, sbuf);
            glBindFramebuffer(GL_FRAMEBUFFER, fbGfx.fbo);
            glViewport(0, 0, GFX_W, GFX_H);
            glUseProgram(pScene);
            bindTex(pScene, "uFont8", 0, font8.id);
            bindTex(pScene, "uStr", 1, strTex.id);
            bindTex(pScene, "uTop", 2, cubeTop.id);
            bindTex(pScene, "uLeft", 3, cubeLeft.id);
            bindTex(pScene, "uRight", 4, cubeRight.id);
            bindTex(pScene, "uLogo", 5, logoCube.id);
            bindTex(pScene, "uWord", 6, word.id);
            glUniform2f(U(pScene, "uRes"), GFX_W, GFX_H);
            glUniform1i(U(pScene, "uScene"), (int)sc);
            glUniform1f(U(pScene, "uT"), (float)t);
            glUniform1f(U(pScene, "uLT"), (float)lt);
            glUniform1f(U(pScene, "uBeat"), (float)beatAt(t));
            glUniform1f(U(pScene, "uFlash"), (float)flashAt(t));
            glUniform1f(U(pScene, "uKickCum"), (float)kickSum(t));
            glUniform4f(U(pScene, "uEnv"), eL, eM, eH, eK);
            float tx[24 * 4], tx2[24 * 2];
            for (int i = 0; i < n; i++) {
                tx[4 * i] = (float)items[i].x; tx[4 * i + 1] = (float)items[i].y;
                tx[4 * i + 2] = (float)items[i].scale; tx[4 * i + 3] = (float)items[i].style;
                tx2[2 * i] = (float)std::min<size_t>(64, items[i].s.size()); tx2[2 * i + 1] = (float)items[i].alpha;
            }
            glUniform1i(U(pScene, "uTxtN"), n);
            if (n) { glUniform4fv(U(pScene, "uTxt"), n, tx); glUniform2fv(U(pScene, "uTxtX"), n, tx2); }
            if (sc == SC_DROP || sc == SC_FINALE) {
                CubeCam c = cubeCam(sc, t, lt);
                setM3(pScene, "uCubeRot", c.cubeRot);
                set3(pScene, "uCubeC", c.cubeC);
                glUniform1f(U(pScene, "uCubeS"), (float)c.cubeS);
                set3(pScene, "uCamPos", c.camPos);
                setM3(pScene, "uCamRot", c.camRot);
                glUniform1f(U(pScene, "uFov"), (float)c.fov);
                glUniform1f(U(pScene, "uSnap"), (float)c.snap);
            }
            glUniform2f(U(pScene, "uAffS0"), (float)affS0x, (float)affS0y);
            set3(pScene, "uAffP0", affP0); set3(pScene, "uAffP1", affP1); set3(pScene, "uAffD", affD);
            glUniform3f(U(pScene, "uLogoPos"), (float)logoCx, (float)logoCy, (float)logoK);
            double h = t - T_HIT;
            glUniform1f(U(pScene, "uLogoA"), (float)(h >= 0 ? 1 : 0));
            double wa = h < 0 ? 0 : 1, ws = h < 0 ? 1 : 1 + 0.22 * exp(-h * 10) * cos(h * 20);
            glUniform2f(U(pScene, "uWordAS"), (float)wa, (float)ws);
            glUniform1i(U(pScene, "uBlackout"), sc == SC_BLACK ? 1 : 0);
            drawQuad();
            src = fbGfx.tex.id;
        }

        // glow (halation) source: blurred copy of the picture
        glUseProgram(pBlur);
        glBindFramebuffer(GL_FRAMEBUFFER, fbGlowA.fbo); glViewport(0, 0, 320, 240);
        bindTex(pBlur, "uSrc", 0, src);
        glUniform2f(U(pBlur, "uDir"), 1.0f / 320, 0);
        drawQuad();
        glBindFramebuffer(GL_FRAMEBUFFER, fbGlowB.fbo);
        bindTex(pBlur, "uSrc", 0, fbGlowA.tex.id);
        glUniform2f(U(pBlur, "uDir"), 0, 1.0f / 240);
        drawQuad();

        // CRT
        GLuint prevTex = fbOut[cur].tex.id;
        cur ^= 1;
        glBindFramebuffer(GL_FRAMEBUFFER, fbOut[cur].fbo);
        glViewport(0, 0, OUT_W, OUT_H);
        glUseProgram(pCRT);
        bindTex(pCRT, "uSrc", 0, src);
        bindTex(pCRT, "uGlow", 1, fbGlowB.tex.id);
        bindTex(pCRT, "uPrev", 2, prevTex);
        glUniform2f(U(pCRT, "uSrcSize"), (float)srcW, (float)srcH);
        glUniform2f(U(pCRT, "uOut"), OUT_W, OUT_H);
        glUniform1f(U(pCRT, "uT"), (float)t);
        glUniform1i(U(pCRT, "uMode"), mode);
        glUniform1f(U(pCRT, "uOnT"), (float)t);
        glUniform1f(U(pCRT, "uOffT"), (float)(t >= T_OFF ? t - T_OFF : -1.0));
        Glitch g = glitchAt(t);
        glUniform1f(U(pCRT, "uRoll"), (float)g.roll);
        glUniform1f(U(pCRT, "uJitter"), (float)g.jitter);
        glUniform1f(U(pCRT, "uTear"), (float)std::min(1.0, g.tear));
        glUniform1f(U(pCRT, "uTearSeed"), (float)g.seed);
        glUniform1f(U(pCRT, "uRGB"), (float)g.rgb);
        glUniform1f(U(pCRT, "uSnow"), (float)std::min(1.0, g.snow));
        glUniform1f(U(pCRT, "uHold"), (float)g.hold);
        glUniform1f(U(pCRT, "uBulge"), (float)g.bulge);
        glUniform1f(U(pCRT, "uDegauss"), (float)g.degauss);
        // persistence off while the raster itself is animating (on/off), or the shrinking raster leaves stairs
        bool rasterAnim = t < 0.6 || t >= T_OFF;
        glUniform1f(U(pCRT, "uPersist"), rasterAnim ? 0.0f : mode == 0 ? 0.35f : 0.5f);
        glUniform1f(U(pCRT, "uKick"), eK);
        drawQuad();
    }
};

// ------------------------------------------------------------------ app
struct AudioOut {
    const std::vector<float>* mix;
    std::atomic<long> pos{0};
    std::atomic<bool> paused{false};
};
static void SDLCALL audioCb(void* ud, SDL_AudioStream* s, int additional, int) {
    AudioOut* a = (AudioOut*)ud;
    int frames = additional / 8;
    std::vector<float> buf(frames * 2, 0.0f);
    if (!a->paused) {
        long p = a->pos;
        for (int i = 0; i < frames; i++, p++)
            if (p >= 0 && (size_t)(2 * p + 1) < a->mix->size()) { buf[2 * i] = (*a->mix)[2 * p]; buf[2 * i + 1] = (*a->mix)[2 * p + 1]; }
        a->pos = p;
    }
    SDL_PutAudioStreamData(s, buf.data(), frames * 8);
}

int main(int argc, char** argv) {
    std::string exportPath, framesArg, framesPrefix;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--export") && i + 1 < argc) exportPath = argv[++i];
        else if (!strcmp(argv[i], "--frames") && i + 2 < argc) { framesArg = argv[++i]; framesPrefix = argv[++i]; }
    }
    bool offline = !exportPath.empty() || !framesArg.empty();
    if (!SDL_Init(SDL_INIT_VIDEO | (offline ? 0 : SDL_INIT_AUDIO))) { fprintf(stderr, "SDL: %s\n", SDL_GetError()); return 1; }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
    SDL_Window* win = SDL_CreateWindow("GOOSE - Glitchy Old-School Output Scene Engine", 1280, 720,
                                       SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY |
                                           (offline ? SDL_WINDOW_HIDDEN : 0));
    if (!win) { fprintf(stderr, "window: %s\n", SDL_GetError()); return 1; }
    SDL_GLContext ctx = SDL_GL_CreateContext(win);
    if (!ctx) { fprintf(stderr, "gl: %s\n", SDL_GetError()); return 1; }
    fprintf(stderr, "GL %s | %s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));

    Demo demo;
    demo.init();

    if (!framesArg.empty()) {
        std::stringstream ss(framesArg); std::string tok;
        std::vector<uint8_t> px(OUT_W * OUT_H * 4);
        while (std::getline(ss, tok, ',')) {
            double t = atof(tok.c_str());
            for (int w = 6; w >= 1; w--) if (t - w / (double)FPS >= 0) demo.render(t - w / (double)FPS);
            demo.render(t);
            glBindFramebuffer(GL_FRAMEBUFFER, demo.out().fbo);
            glReadPixels(0, 0, OUT_W, OUT_H, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
            stbi_flip_vertically_on_write(1);
            char name[512]; snprintf(name, sizeof name, "%s_%06.2f.png", framesPrefix.c_str(), t);
            stbi_write_png(name, OUT_W, OUT_H, 4, px.data(), OUT_W * 4);
            fprintf(stderr, "wrote %s\n", name);
        }
        return 0;
    }

    if (!exportPath.empty()) {
        char cmd[2048];
        snprintf(cmd, sizeof cmd,
                 "ffmpeg -v error -y -f rawvideo -pix_fmt rgba -s %dx%d -framerate %d -i - -i out/soundtrack.wav "
                 "-vf vflip,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p -c:v libx264 -preset slow -crf 14 "
                 "-colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a aac -b:a 320k -t %.3f "
                 "-movflags +faststart \"%s\"",
                 OUT_W, OUT_H, FPS, LENGTH, exportPath.c_str());
        FILE* ff = popen(cmd, "w");
        if (!ff) { perror("ffmpeg"); return 1; }
        int total = (int)std::lround(LENGTH * FPS);
        std::vector<uint8_t> px(OUT_W * OUT_H * 4);
        auto t0 = std::chrono::steady_clock::now();
        for (int f = 0; f < total; f++) {
            demo.render(f / (double)FPS);
            glBindFramebuffer(GL_FRAMEBUFFER, demo.out().fbo);
            glReadPixels(0, 0, OUT_W, OUT_H, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
            if (fwrite(px.data(), 1, px.size(), ff) != px.size()) { fprintf(stderr, "pipe write failed at %d\n", f); return 1; }
            if (f % 300 == 0) {
                double el = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
                fprintf(stderr, "frame %d/%d  %.1fs\n", f, total, el);
            }
        }
        int rc = pclose(ff);
        fprintf(stderr, "export done rc=%d frames=%d -> %s\n", rc, total, exportPath.c_str());
        return rc == 0 ? 0 : 1;
    }

    // ---- live
    AudioOut ao; ao.mix = &demo.st.mix;
    SDL_AudioSpec spec{SDL_AUDIO_F32, 2, SR};
    SDL_AudioStream* as = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audioCb, &ao);
    if (as) { SDL_ResumeAudioStreamDevice(as); fprintf(stderr, "audio: playing via default device\n"); }
    else fprintf(stderr, "audio: %s (running silent)\n", SDL_GetError());
    SDL_GL_SetSwapInterval(1);
    bool run = true, fs = false;
    while (run) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_EVENT_QUIT) run = false;
            if (e.type == SDL_EVENT_KEY_DOWN) {
                SDL_Keycode k = e.key.key;
                if (k == SDLK_ESCAPE) run = false;
                if (k == SDLK_SPACE) ao.paused = !ao.paused;
                if (k == SDLK_F) { fs = !fs; SDL_SetWindowFullscreen(win, fs); }
                if (k == SDLK_LEFT || k == SDLK_RIGHT || k == SDLK_HOME) {
                    long p = k == SDLK_HOME ? 0 : ao.pos + (k == SDLK_LEFT ? -5 : 5) * SR;
                    ao.pos = std::clamp<long>(p, 0, (long)(LENGTH * SR));
                    if (as) SDL_ClearAudioStream(as);
                }
            }
        }
        long queued = as ? SDL_GetAudioStreamQueued(as) / 8 : 0;
        double t = std::clamp((ao.pos - queued) / (double)SR, 0.0, LENGTH - 1e-3);
        if (t >= LENGTH - 0.01 && !ao.paused) { /* hold on the last frame */ }
        demo.render(t);
        int ww, wh; SDL_GetWindowSizeInPixels(win, &ww, &wh);
        double s = std::min(ww / (double)OUT_W, wh / (double)OUT_H);
        int dw = (int)(OUT_W * s), dh = (int)(OUT_H * s), dx = (ww - dw) / 2, dy = (wh - dh) / 2;
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        glViewport(0, 0, ww, wh);
        glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, demo.out().fbo);
        glBlitFramebuffer(0, 0, OUT_W, OUT_H, dx, dy, dx + dw, dy + dh, GL_COLOR_BUFFER_BIT, GL_LINEAR);
        SDL_GL_SwapWindow(win);
    }
    SDL_Quit();
    return 0;
}
