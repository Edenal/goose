#include "renderer.h"
#include <algorithm>
#include <cmath>
#include <cstring>

static void drawQuad() { glDrawArrays(GL_TRIANGLES, 0, 3); }

static std::string subst(std::string s, const Look& look) {
    auto rep = [&](const std::string& k, const std::string& v) {
        for (size_t p; (p = s.find(k)) != std::string::npos;) s.replace(p, k.size(), v);
    };
    rep("{EVENT}", look.event); rep("{LINE2}", look.line2); rep("{LINE3}", look.line3);
    return s;
}

bool Renderer::init(const std::string& resDir, std::string& err) {
    res = resDir;
    auto R = [&](const char* p) { return res + "/" + p; };
    pText = program(R("shaders/textmode.frag"));
    pBlur = program(R("shaders/blur.frag"));
    pCRT = program(R("shaders/crt.frag"));
    font16 = loadTex(R("assets/gen/font_vga9x16.png"), false, true);
    font8 = loadTex(R("assets/gen/font_bios8x8.png"), false, true);
    cubeTop = loadTex(R("assets/gen/cube_top.png"), true, false);
    cubeLeft = loadTex(R("assets/gen/cube_left.png"), true, false);
    cubeRight = loadTex(R("assets/gen/cube_right.png"), true, false);
    logoCube = loadTex(R("assets/gen/logo_cube.png"), true, false);
    word = loadTex(R("assets/gen/word_marathon.png"), true, false);
    screenTex = makeTex(80, 25, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, GL_NEAREST);
    strTex = makeTex(256, 40, GL_R8, GL_RED, GL_UNSIGNED_BYTE, GL_NEAREST);
    fbText = makeFB(TXT_W, TXT_H, GL_NEAREST);
    fbGfx = makeFB(GFX_W, GFX_H, GL_NEAREST);
    fbGlowA = makeFB(320, 240, GL_LINEAR);
    fbGlowB = makeFB(320, 240, GL_LINEAR);
    for (FB* f : {&fbOut[0], &fbOut[1], &fbMenu[0], &fbMenu[1]}) {
        *f = makeFB(OUT_W, OUT_H, GL_LINEAR);
        glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    }
    GLuint vao; glGenVertexArrays(1, &vao); glBindVertexArray(vao);
    solveLogo();
    loadParts();
    (void)err;
    return true;
}

void Renderer::loadParts() {
    for (PartDef& p : parts) if (p.prog) glDeleteProgram(p.prog);
    parts = loadPartDefs(res + "/shaders/parts");
    std::string common = readFile(res + "/shaders/common.glsl"), tail = readFile(res + "/shaders/part_main.glsl");
    for (PartDef& p : parts) {
        std::string src = common + "\n#line 1 1\n" + readFile(p.file) + "\n#line 1 2\n" + tail;
        p.prog = programFromSource(src, p.error);
        if (!p.prog) fprintf(stderr, "part %s failed to compile:\n%s\n", p.id.c_str(), p.error.c_str());
    }
}

void Renderer::resetDemoHistory() {
    for (FB& f : fbOut) { glBindFramebuffer(GL_FRAMEBUFFER, f.fbo); glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT); }
}

// The brand cube is an axonometric drawing, not a true projection of a cube. Solve the parallel projection
// that maps cube space [0,1]^3 onto it exactly, so the 3D cube can land on the logo.
void Renderer::solveLogo() {
    const double Fx = 250, Fy = 201, Lx = 57.46, Ly = 120.48, Rx = 442.54, Ry = 120.48, Bx = 250, By = 459.1;
    const double Pcx = 250, Pcy = 249.53, k = logoK;
    double sx = logoCx + k * ((Lx + Rx + Bx - 2 * Fx) - Pcx), sy = logoCy + k * ((Ly + Ry + By - 2 * Fy) - Pcy);
    V3 mx = {k * (Fx - Lx), k * (Fy - Ly), 0}, my = {k * (Fx - Bx), k * (Fy - By), 0}, mz = {k * (Fx - Rx), k * (Fy - Ry), 0};
    V3 row0 = {mx.x, my.x, mz.x}, row1 = {mx.y, my.y, mz.y};
    affD = norm(cross(row0, row1));
    if (affD.x > 0) affD = affD * -1.0;
    double a = dot(row0, row0), b = dot(row0, row1), d = dot(row1, row1), det = a * d - b * b;
    affP0 = row0 * (d / det) + row1 * (-b / det);
    affP1 = row0 * (-b / det) + row1 * (a / det);
    affS0x = sx; affS0y = sy;
    V3 right = norm(affP0 - affD * dot(affP0, affD));
    V3 up = norm(cross(affD * -1.0, right));
    qLogo = matq(M3{{right, up, affD * -1.0}});
}

// ------------------------------------------------------------------ glitches + flashes (pure functions of t)
// Glitches live at the start (power-on, reboot, the VGA mode switch), at scene transitions, and at the end
// (signal breakdown before the power-off). Inside a part the picture stays clean: the content is the focus.
Renderer::Glitch Renderer::glitchAt(double t, const Timeline& tl) const {
    Glitch g;
    g.seed = (int)floor(t * FPS + 1e-6) % 997;
    auto pulse = [&](double c, double len) { return (t >= c && t < c + len) ? 1 - (t - c) / len : 0.0; };
    if (t > 0.12 && t < 2.2) { double d = t - 0.12; g.degauss = std::min(1.0, d / 0.08) * exp(-d / 0.38) * 0.7; }
    if (tl.boot) {
        double rb = pulse(6.35, 0.18);
        g.hold = rb * 0.8; g.snow = 0.55 * sqrt(rb);
        double ms = t - tl.demoStart;
        if (ms > -0.85 && ms < -0.55) { double x = (ms + 0.85) / 0.3; g.hold = x; g.jitter = 0.4 * x; g.rgb = 1.5 * x; }
        if (ms >= -0.55 && ms < 0) g.snow = 0.65 * (1 - clamp01((ms + 0.10) / 0.10)) + 0.3 * pulse(tl.demoStart - 0.55, 0.05);
        if (ms >= 0 && ms < 0.42) g.roll = (1 - easeOut(ms / 0.42)) * 0.9;
        g.hold = std::max(g.hold, 0.35 * pulse(tl.demoStart + 0.38, 0.3));
    }
    for (double c : tl.cuts) {
        double d = t - c;
        if (d <= -0.12 || d >= 0.20) continue;
        double outk = d < 0 ? (d + 0.12) / 0.12 : 0, ink = d >= 0 ? 1 - d / 0.20 : 0;
        double k = std::max(outk * outk, ink * ink);
        g.rgb = std::max(g.rgb, 4.0 * k);
        g.hold = std::max(g.hold, 0.5 * k);
        if (fabs(d) < 0.05) g.tear = std::max(g.tear, 0.9);
        g.snow = std::max(g.snow, 0.6 * exp(-(d / 0.04) * (d / 0.04)) + 0.12 * k);
        if (d >= 0 && d < 0.12) g.roll = std::max(g.roll, 0.04 * (1 - d / 0.12));
    }
    if (tl.hit >= 0) {
        double lh = pulse(tl.hit, 0.15);
        g.rgb = std::max(g.rgb, 2.5 * lh * lh);
        if (t >= tl.hit && t < tl.hit + 0.035) g.tear = std::max(g.tear, 0.5);
    }
    double pre = t - (tl.off - 0.7);
    if (pre >= 0 && t < tl.off) {
        double x = pre / 0.7;
        g.hold = std::max(g.hold, 0.5 * x * x);
        g.snow = std::max(g.snow, 0.45 * x * x);
        double tr = std::max(pulse(tl.off - 0.52, 0.05), pulse(tl.off - 0.20, 0.07));
        g.tear = 0.8 * tr; g.rgb = 3.0 * tr + 1.5 * x;
    }
    return g;
}

double Renderer::flashAt(double t, const Timeline& tl) const {
    double f = 0;
    std::vector<double> flashes = {tl.demoStart};
    for (double c : tl.cuts) if (c != tl.finaleStart) flashes.push_back(c);   // the finale enters on its own
    for (double c : flashes) if (t >= c) f = std::max(f, exp(-(t - c) * 9.0) * 0.3);
    if (tl.hit >= 0 && t >= tl.hit) f = std::max(f, exp(-(t - tl.hit) * 4.0) * 0.7);
    return f;
}

// ------------------------------------------------------------------ passes
void Renderer::uploadText(const Screen& s) {
    uint8_t buf[25][80][4];
    for (int r = 0; r < 25; r++) for (int c = 0; c < 80; c++) {
        buf[r][c][0] = s.c[r][c].ch; buf[r][c][1] = s.c[r][c].attr; buf[r][c][2] = 0; buf[r][c][3] = 0;
    }
    glBindTexture(GL_TEXTURE_2D, screenTex.id);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 80, 25, GL_RGBA, GL_UNSIGNED_BYTE, buf);
}

void Renderer::drawTextPass(double t, bool blank, bool logo, int curCol, int curRow) {
    glBindFramebuffer(GL_FRAMEBUFFER, fbText.fbo);
    glViewport(0, 0, TXT_W, TXT_H);
    glUseProgram(pText);
    bindTex(pText, "uScreen", 0, screenTex.id);
    bindTex(pText, "uFont", 1, font16.id);
    bindTex(pText, "uLogo", 2, logoCube.id);
    glUniform1f(U(pText, "uT"), (float)t);
    glUniform3i(U(pText, "uCursor"), curCol, curRow, blank ? 0 : 1);
    glUniform1i(U(pText, "uShowLogo"), logo ? 1 : 0);
    glUniform1i(U(pText, "uBlank"), blank ? 1 : 0);
    drawQuad();
}

void Renderer::crtPass(GLuint src, int srcW, int srcH, int mode, double onT, double offT, const Look& look, float kick,
                       double tear, double seed, double rgb, double snow, double hold, double degauss, double jitter,
                       double roll, bool menu, bool persistOff) {
    glUseProgram(pBlur);
    glBindFramebuffer(GL_FRAMEBUFFER, fbGlowA.fbo); glViewport(0, 0, 320, 240);
    bindTex(pBlur, "uSrc", 0, src);
    glUniform2f(U(pBlur, "uDir"), 1.0f / 320, 0);
    drawQuad();
    glBindFramebuffer(GL_FRAMEBUFFER, fbGlowB.fbo);
    bindTex(pBlur, "uSrc", 0, fbGlowA.tex.id);
    glUniform2f(U(pBlur, "uDir"), 0, 1.0f / 240);
    drawQuad();

    FB* chain = menu ? fbMenu : fbOut;
    int& c = menu ? mcur : cur;
    GLuint prevTex = chain[c].tex.id;
    c ^= 1;
    glBindFramebuffer(GL_FRAMEBUFFER, chain[c].fbo);
    glViewport(0, 0, OUT_W, OUT_H);
    glUseProgram(pCRT);
    bindTex(pCRT, "uSrc", 0, src);
    bindTex(pCRT, "uGlow", 1, fbGlowB.tex.id);
    bindTex(pCRT, "uPrev", 2, prevTex);
    glUniform2f(U(pCRT, "uSrcSize"), (float)srcW, (float)srcH);
    glUniform2f(U(pCRT, "uOut"), OUT_W, OUT_H);
    glUniform1f(U(pCRT, "uT"), (float)curT);
    glUniform1i(U(pCRT, "uMode"), mode);
    glUniform1f(U(pCRT, "uOnT"), menu ? 10.0f : (float)onT);
    glUniform1f(U(pCRT, "uOffT"), (float)offT);
    float gl = look.glitch;
    glUniform1f(U(pCRT, "uRoll"), (float)(roll * std::min(1.0f, gl)));
    glUniform1f(U(pCRT, "uJitter"), (float)(jitter * gl));
    glUniform1f(U(pCRT, "uTear"), (float)std::min(1.0, tear * gl));
    glUniform1f(U(pCRT, "uTearSeed"), (float)seed);
    glUniform1f(U(pCRT, "uRGB"), (float)(rgb * gl));
    glUniform1f(U(pCRT, "uSnow"), (float)std::min(1.0, snow * gl));
    glUniform1f(U(pCRT, "uHold"), (float)(hold * gl));
    glUniform1f(U(pCRT, "uBulge"), 0.0f);
    glUniform1f(U(pCRT, "uDegauss"), (float)std::min(1.0, degauss * gl));
    glUniform1f(U(pCRT, "uPersist"), persistOff ? 0.0f : std::min(0.85f, (mode == 0 ? 0.35f : 0.5f) * look.fx));
    glUniform1f(U(pCRT, "uKick"), kick);
    glUniform1f(U(pCRT, "uScan"), look.scan);
    glUniform1f(U(pCRT, "uFx"), look.fx);
    drawQuad();
}

void Renderer::renderText(const Screen& s, double t, const Look& look, bool blank) {
    curT = t;
    uploadText(s);
    drawTextPass(t, blank, s.logo, s.curCol, s.curRow);
    crtPass(fbText.tex.id, TXT_W, TXT_H, 0, t, -1, look, 0, 0, 0, 0, 0, 0, 0, 0, 0, true, false);
}

// ------------------------------------------------------------------ one demo frame
void Renderer::renderDemo(double t, const Timeline& tl, const Soundtrack& st, const Look& look) {
    curT = t;
    float eL = st.env(st.low, t), eM = st.env(st.mid, t), eH = st.env(st.high, t), eK = st.env(st.kick, t);
    GLuint src = fbGfx.tex.id; int srcW = GFX_W, srcH = GFX_H, mode = 1;
    const Cue* cue = tl.cueAt(t);
    bool textMode = tl.boot && t < tl.demoStart - 0.55;
    const PartDef* part = (!textMode && cue && t >= tl.demoStart) ? &parts[cue->part] : nullptr;

    if (textMode) {
        bool blank = !drawTextMode(scr, t, st.env(st.vuL, t) * 0.9f, st.env(st.vuR, t) * 0.9f, look.glitch);
        uploadText(scr);
        drawTextPass(t, blank, scr.logo, scr.curCol, scr.curRow);
        src = fbText.tex.id; srcW = TXT_W; srcH = TXT_H; mode = 0;
    } else if (!part || !part->prog) {
        glBindFramebuffer(GL_FRAMEBUFFER, fbGfx.fbo);
        glViewport(0, 0, GFX_W, GFX_H);
        glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    } else {
        double lt = t - cue->t0;
        GLuint P = part->prog;
        // strings: 0-15 the part's own, 16-18 event lines, 20-35 split labels
        static uint8_t sbuf[40][256];
        memset(sbuf, ' ', sizeof sbuf);
        int lens[40] = {0};
        auto put = [&](int row, const std::string& s) {
            size_t n = std::min<size_t>(256, s.size());
            memcpy(sbuf[row], s.data(), n); lens[row] = (int)n;
        };
        for (size_t i = 0; i < part->strs.size() && i < 16; i++) put((int)i, subst(part->strs[i], look));
        put(16, look.event); put(17, look.line2); put(18, look.line3);
        std::vector<std::pair<std::string, double>> splits;
        if (tl.boot) { splits.push_back({"BIOS POST", 3.55}); splits.push_back({"SOUND TEST", tl.musicAt}); }
        for (const Cue& q : tl.cues) splits.push_back({parts[q.part].split, q.t0});
        int curSplit = 0;
        for (size_t i = 0; i < splits.size() && i < 16; i++) {
            put(20 + (int)i, splits[i].first);
            if (t >= splits[i].second) curSplit = (int)i;
        }
        float splitT[16] = {0};
        for (size_t i = 0; i < splits.size() && i < 16; i++) splitT[i] = (float)splits[i].second;
        glBindTexture(GL_TEXTURE_2D, strTex.id);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 256, 40, GL_RED, GL_UNSIGNED_BYTE, sbuf);

        glBindFramebuffer(GL_FRAMEBUFFER, fbGfx.fbo);
        glViewport(0, 0, GFX_W, GFX_H);
        glUseProgram(P);
        bindTex(P, "uFont8", 0, font8.id);
        bindTex(P, "uStr", 1, strTex.id);
        bindTex(P, "uTop", 2, cubeTop.id);
        bindTex(P, "uLeft", 3, cubeLeft.id);
        bindTex(P, "uRight", 4, cubeRight.id);
        bindTex(P, "uLogo", 5, logoCube.id);
        bindTex(P, "uWord", 6, word.id);
        glUniform1iv(U(P, "uStrLen"), 40, lens);
        glUniform1fv(U(P, "uSplitT"), 16, splitT);
        glUniform1i(U(P, "uSplitN"), (int)std::min<size_t>(16, splits.size()));
        glUniform1i(U(P, "uSplitCur"), curSplit);
        glUniform2f(U(P, "uRes"), GFX_W, GFX_H);
        glUniform1f(U(P, "uT"), (float)t);
        glUniform1f(U(P, "uLT"), (float)lt);
        glUniform1f(U(P, "uLen"), (float)(cue->t1 - cue->t0));
        glUniform1f(U(P, "uBeat"), (float)tl.beatAt(t));
        glUniform1f(U(P, "uFlash"), (float)(flashAt(t, tl) * std::min(1.5f, look.fx)));
        glUniform1f(U(P, "uKickCum"), (float)st.kickSum(t));
        glUniform4f(U(P, "uEnv"), eL, eM, eH, eK);
        glUniform1f(U(P, "uFx"), look.fx);
        glUniform1f(U(P, "uHit"), (float)tl.hit);
        // the cube: finale flies it onto the logo, every other part gets it spinning on a stage
        M3 cubeRot, camRot; V3 cubeC, camPos; double cubeS, fov = 0.55, snap = 0;
        double ks = st.kickSum(t);
        if (part->special == "finale" && tl.hit >= 0) {
            double hit = tl.hit, fs = tl.finaleStart;
            double tin = clamp01((t - fs) / (hit - 0.35 - fs));
            double z = -14.0 * (1 - easeOut(tin));
            Q spin = qmul(qaxis({0.3, 1, 0.15}, (hit - t) * 7.5 + 0.8 * ks), qaxis({1, 0, 0}, (hit - t) * 3.1));
            Q q = qslerp(spin, qLogo, smooth(fs + 0.8, hit - 0.33, t));
            cubeRot = transpose(qmat(q));
            camPos = {0, 0, 3.0};
            camRot = {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}};
            double kpx = (GFX_H / 2.0) / (fov * 3.0);
            cubeS = logoK * 330 / kpx / 1.35;
            cubeC = V3{(logoCx - GFX_W / 2.0) / kpx, -(logoCy - GFX_H / 2.0) / kpx, 0} + V3{0, 0, z};
            snap = smooth(hit - 0.34, hit - 0.02, t);
        } else {
            Q q = qmul(qaxis({0, 1, 0}, lt * 0.9 + ks * 1.6), qaxis({1, 0, 0.3}, lt * 0.55 + ks * 0.5));
            cubeRot = transpose(qmat(q));
            cubeS = 1.15;
            cubeC = {0, 0.25 + 0.12 * sin(tl.beatAt(t) * M_PI), 0};
            V3 eye = {sin(lt * 0.35) * 1.4, 1.05, 3.6};
            V3 fwd = norm(V3{0, 0.1, 0} - eye), right = norm(cross(fwd, {0, 1, 0})), up = cross(right, fwd);
            camPos = eye;
            camRot = transpose(M3{{right, up, fwd * -1.0}});
        }
        setM3(P, "uCubeRot", cubeRot); set3(P, "uCubeC", cubeC); glUniform1f(U(P, "uCubeS"), (float)cubeS);
        set3(P, "uCamPos", camPos); setM3(P, "uCamRot", camRot);
        glUniform1f(U(P, "uFov"), (float)fov); glUniform1f(U(P, "uSnap"), (float)snap);
        glUniform2f(U(P, "uAffS0"), (float)affS0x, (float)affS0y);
        set3(P, "uAffP0", affP0); set3(P, "uAffP1", affP1); set3(P, "uAffD", affD);
        glUniform3f(U(P, "uLogoPos"), (float)logoCx, (float)logoCy, (float)logoK);
        double h = tl.hit >= 0 ? t - tl.hit : -1;
        glUniform1f(U(P, "uLogoA"), (float)(h >= 0 ? 1 : 0));
        glUniform2f(U(P, "uWordAS"), (float)(h < 0 ? 0 : 1), (float)(h < 0 ? 1 : 1 + 0.22 * exp(-h * 10) * cos(h * 20)));
        drawQuad();
    }
    Glitch g = tl.solo ? Glitch{} : glitchAt(t, tl);
    bool rasterAnim = !tl.solo && (t < 0.6 || t >= tl.off);
    crtPass(src, srcW, srcH, mode, tl.solo ? 10.0 : t, (!tl.solo && t >= tl.off) ? t - tl.off : -1.0, look, eK,
            g.tear, g.seed, g.rgb, g.snow, g.hold, g.degauss, g.jitter, g.roll, false, rasterAnim);
}
