// GOOSE renderer: text mode + mode X parts -> halation blur -> CRT, all as pure functions of t.
#pragma once
#include <string>
#include <vector>
#include "audio.h"
#include "gl_util.h"
#include "parts.h"
#include "textmode.h"
#include "timeline.h"

struct Look {                  // the three sliders, 1.0 = the reference look
    float scan = 1, fx = 1, glitch = 1;
    std::string event, line2, line3;
};

class Renderer {
public:
    std::string res;           // resource root (contains shaders/ and assets/)
    std::vector<PartDef> parts;

    bool init(const std::string& resDir, std::string& err);
    void loadParts();          // (re)scan shaders/parts and compile every part
    // one demo frame into the demo CRT chain (phosphor persistence follows the previous demo frame)
    void renderDemo(double t, const Timeline& tl, const Soundtrack& st, const Look& look);
    // a text screen (the setup menu) through its own CRT chain
    void renderText(const Screen& s, double t, const Look& look, bool blank = false);
    GLuint demoFBO() const { return fbOut[cur].fbo; }
    GLuint menuFBO() const { return fbMenu[mcur].fbo; }
    void resetDemoHistory();   // clear persistence (after a seek)

private:
    GLuint pText = 0, pBlur = 0, pCRT = 0;
    Tex font16, font8, cubeTop, cubeLeft, cubeRight, logoCube, word, screenTex, strTex;
    FB fbText, fbGfx, fbGlowA, fbGlowB, fbOut[2], fbMenu[2];
    int cur = 0, mcur = 0;
    double curT = 0;
    Screen scr;
    V3 affP0, affP1, affD;
    double affS0x = 0, affS0y = 0, logoK = 0.235, logoCx = 160, logoCy = 86;
    Q qLogo{1, 0, 0, 0};

    void solveLogo();
    void uploadText(const Screen& s);
    void drawTextPass(double t, bool blank, bool logo, int curCol, int curRow);
    void crtPass(GLuint src, int srcW, int srcH, int mode, double onT, double offT, const Look& look, float kick,
                 double tear, double seed, double rgb, double snow, double hold, double degauss, double jitter,
                 double roll, bool menu, bool persistOff);
    struct Glitch { double tear = 0, seed = 0, rgb = 0, snow = 0, hold = 0, degauss = 0, jitter = 0, roll = 0; };
    Glitch glitchAt(double t, const Timeline& tl) const;
    double flashAt(double t, const Timeline& tl) const;
};
