// The intro: CRT on -> BIOS POST -> CMOS setup -> DOS prompt -> SETUP.EXE (Sound Blaster) ->
// sound test (the music starts) -> DOS -> ESA.EXE loader -> mode switch into the demo.
// Everything is drawn from scratch as a pure function of t; sounds come from the same tables.
#include "textmode.h"
#include "timeline.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>

// VGA attributes: (bg << 4) | fg
enum { BLK, BLU, GRN, CYN, RED, MAG, BRN, LGR, DGR, LBL, LGN, LCY, LRD, LMG, YEL, WHT };
#define AT(bg, fg) uint8_t(((bg) << 4) | (fg))

// ---------------------------------------------------------------- screen ops
void Screen::clear(uint8_t attr, uint8_t ch) {
    for (auto& row : c) for (auto& x : row) x = {ch, attr};
    curRow = -1; logo = false;
}
void Screen::putc(int r, int col, uint8_t ch, uint8_t attr) {
    if (r >= 0 && r < 25 && col >= 0 && col < 80) c[r][col] = {ch, attr};
}
void Screen::put(int r, int col, const char* s, uint8_t attr) {
    for (int i = 0; s[i]; i++) putc(r, col + i, (uint8_t)s[i], attr);
}
void Screen::center(int r, const char* s, uint8_t attr, int c0, int c1) {
    int n = (int)strlen(s);
    put(r, c0 + (c1 - c0 + 1 - n) / 2, s, attr);
}
void Screen::fill(int r0, int c0, int r1, int c1, uint8_t ch, uint8_t attr) {
    for (int r = r0; r <= r1; r++) for (int col = c0; col <= c1; col++) putc(r, col, ch, attr);
}
void Screen::attrs(int r0, int c0, int r1, int c1, uint8_t attr) {
    for (int r = r0; r <= r1; r++) for (int col = c0; col <= c1; col++)
        if (r >= 0 && r < 25 && col >= 0 && col < 80) c[r][col].attr = attr;
}
void Screen::box(int r0, int c0, int r1, int c1, uint8_t attr, bool dbl) {
    uint8_t h = dbl ? 0xCD : 0xC4, v = dbl ? 0xBA : 0xB3;
    fill(r0, c0, r1, c1, ' ', attr);
    for (int col = c0 + 1; col < c1; col++) { putc(r0, col, h, attr); putc(r1, col, h, attr); }
    for (int r = r0 + 1; r < r1; r++) { putc(r, c0, v, attr); putc(r, c1, v, attr); }
    putc(r0, c0, dbl ? 0xC9 : 0xDA, attr); putc(r0, c1, dbl ? 0xBB : 0xBF, attr);
    putc(r1, c0, dbl ? 0xC8 : 0xC0, attr); putc(r1, c1, dbl ? 0xBC : 0xD9, attr);
}
void Screen::shadow(int r0, int c0, int r1, int c1) {  // classic 2-column drop shadow
    attrs(r1 + 1, c0 + 2, r1 + 1, c1 + 2, AT(BLK, DGR));
    attrs(r0 + 1, c1 + 1, r1 + 1, c1 + 2, AT(BLK, DGR));
}

// ---------------------------------------------------------------- script data
static double jitter(int i) {  // deterministic human typing wobble
    double x = sin(i * 12.9898 + 78.233) * 43758.5453;
    return (x - floor(x) - 0.5) * 0.05;
}
struct Typed { double t0; const char* text; double cps; };
static double charTime(const Typed& ty, int i) { return ty.t0 + i / ty.cps + (i ? jitter(i + (int)(ty.t0 * 7)) : 0); }
static int typedCount(const Typed& ty, double t) {
    int n = (int)strlen(ty.text), k = 0;
    while (k < n && t >= charTime(ty, k)) k++;
    return k;
}
static std::string typedStr(const Typed& ty, double t) { return std::string(ty.text, typedCount(ty, t)); }

// timings (trailer seconds)
constexpr double T_POST = 0.90, T_DEL = 3.75, T_CMOS = 4.00, T_REBOOT = 6.35, T_DOS = 6.58;
constexpr double T_SETUP = 8.95, T_SBCFG = 10.75, T_SAVED = 15.45, T_DOS2 = 16.00;
static const Typed TY_CD = {7.15, "cd esa", 9.0};
static const Typed TY_SETUP = {8.15, "setup", 9.5};
static const Typed TY_Y = {5.85, "Y", 10.0};
static const Typed TY_EAS = {16.20, "eas", 9.0};                       // the typo...
static const Typed TY_REM = {16.85, "rem never happened before", 21.0}; // ...and the runner's excuse
static const Typed TY_ESA = {18.30, "esa", 10.0};
constexpr double ENT_CD = 7.95, ENT_SETUP = 8.80, ENT_Y = 6.10, ENT_EAS = 16.62, ENT_REM = 18.15, ENT_ESA = 18.72;
constexpr double T_GARBAGE = BOOT_END - 0.85;                            // VGA mode switch spews garbage
static const double CMOS_KEYS[] = {4.40, 4.62, 4.82, 5.02, 5.22, 5.50};   // right, down x4, enter
static const double CARD_KEYS[] = {9.45, 9.62, 9.79, 9.96, 10.13, 10.55}; // down x5, enter
static const double SB_KEYS[] = {11.15, 11.42, 11.70, 11.95, 12.20, 12.50}; // down, value, down, down, down, tab
constexpr double ENT_TEST = BOOT_MUSIC_AT;  // Enter on [ Test ] starts the music
constexpr double T_ASK = 14.70, ENT_YES = 15.30, KEY_ANY = 15.85;
constexpr double EST = 1.50;  // the sound test's (optimistic) estimate
static const double LOADER_T[] = {18.88, 19.00, 19.12, 19.26, 19.40, 19.54, 19.68, 19.82, 19.96};

static int countKeys(const double* k, int n, double t) { int c = 0; while (c < n && t >= k[c]) c++; return c; }

// ---------------------------------------------------------------- screens
static void post(Screen& s, double t) {
    const uint8_t G = AT(BLK, LGR), W = AT(BLK, WHT);
    s.clear(G);
    s.logo = true;
    s.put(0, 1, "ESA Modular BIOS v4.51PG, An Energy Star Ally", G);
    s.put(1, 1, "Copyright (C) 2011-2027, European Speedrunner Assembly", G);
    s.put(3, 1, "ESAW27 PCI/ISA BIOS Revision 1.02", W);
    s.put(5, 1, "SID-486DX2 CPU at 66MHz", G);
    double mt = (t - T_POST - 0.40) / 1.10;
    if (mt > 0) {
        int kb = mt >= 1 ? 65536 : (int)(mt * 64) * 1024;
        char buf[64];
        snprintf(buf, sizeof buf, "Memory Test :  %5dK%s", kb, mt >= 1 ? " OK" : "");
        s.put(6, 1, buf, G);
    }
    if (t > T_POST + 1.70) {
        s.put(8, 1, "ESA Plug and Play BIOS Extension v1.0A", G);
        s.put(9, 1, "Copyright (C) 2027, European Speedrunner Assembly", G);
    }
    const char* det[4][2] = {{"Primary Master  ", "SPEEDRUN HDD 540MB"}, {"Primary Slave   ", "None"},
                             {"Secondary Master", "ATAPI CD-ROM 4X"}, {"Secondary Slave ", "GOOSEBERT (HONK)"}};
    for (int i = 0; i < 4; i++) {
        double d0 = T_POST + 1.90 + i * 0.20;
        if (t < d0) break;
        char buf[96];
        snprintf(buf, sizeof buf, "   Detecting HDD %s ... %s", det[i][0], t > d0 + 0.14 ? det[i][1] : "");
        s.put(11 + i, 1, buf, G);
    }
    s.put(22, 1, "Press ", G); s.put(22, 7, "DEL", W); s.put(22, 10, " to enter SETUP", G);
    s.put(24, 1, "09/24/26-i486-SID6581-2A4KD000C-00", G);
}

static void cmos(Screen& s, double t) {
    const uint8_t B = AT(BLU, WHT), Y = AT(BLU, YEL), HL = AT(RED, WHT);
    s.clear(B);
    s.center(0, "ROM PCI/ISA BIOS (2A4KD000)", B);
    s.center(1, "CMOS SETUP UTILITY", B);
    s.center(2, "ESA SOFTWARE, INC.", B);
    s.box(3, 1, 17, 78, B, true);
    for (int r = 4; r < 17; r++) s.putc(r, 39, 0xB3, B);
    const char* L[7] = {"STANDARD CMOS SETUP", "BIOS FEATURES SETUP", "CHIPSET FEATURES SETUP",
                        "POWER MANAGEMENT SETUP", "PNP/PCI CONFIGURATION", "LOAD BIOS DEFAULTS", "LOAD SETUP DEFAULTS"};
    const char* R[7] = {"INTEGRATED PERIPHERALS", "SUPERVISOR PASSWORD", "USER PASSWORD",
                        "PLUM CONFIGURATION", "SAVE & EXIT SETUP", "EXIT WITHOUT SAVING", "SPEEDRUN MODE: ON"};
    int k = countKeys(CMOS_KEYS, 6, t);
    int col = k >= 1 ? 1 : 0, row = k >= 1 ? (k >= 5 ? 4 : k - 1) : 0;
    for (int i = 0; i < 7; i++) {
        bool hl = !col && row == i;
        s.put(4 + 2 * i, 3, hl ? "\x10" : " ", hl ? HL : Y);
        s.put(4 + 2 * i, 5, L[i], hl ? HL : Y);
        hl = col && row == i;
        s.put(4 + 2 * i, 41, hl ? "\x10" : " ", hl ? HL : Y);
        s.put(4 + 2 * i, 43, R[i], hl ? HL : Y);
    }
    s.box(18, 1, 21, 78, B, false);
    s.put(19, 3, "Esc : Quit", B);                     s.put(19, 41, "\x18\x19\x1a\x1b   : Select Item", B);
    s.put(20, 3, "F10 : Save & Exit Setup", B);        s.put(20, 41, "(Shift)F2 : Change Color", B);
    s.box(22, 1, 24, 78, B, false);
    const char* help = !col ? "Time, Date, Hard Disk Type..."
                     : row == 4 ? "Save Data to CMOS & Exit SETUP"
                     : row == 3 ? "Plum-approved settings. Do not touch."
                     : row == 0 ? "Onboard I/O, Goosebert IRQ..." : "Change, Set, or Disable Password";
    s.center(23, help, B, 1, 78);
    if (t >= CMOS_KEYS[5]) {  // Enter on SAVE & EXIT -> the red confirm box
        const uint8_t D = AT(RED, WHT);
        s.box(10, 18, 12, 61, D, true);
        s.shadow(10, 18, 12, 61);
        std::string q = "SAVE to CMOS and EXIT (Y/N)? " + typedStr(TY_Y, t);
        s.put(11, 22, q.c_str(), AT(RED, YEL));
        s.curRow = 11; s.curCol = 22 + (int)q.size();
    }
}

struct Log { std::vector<std::pair<std::string, uint8_t>> lines; };
static void drawLog(Screen& s, const Log& lg, bool cursorAtEnd) {
    int n = (int)lg.lines.size(), first = n > 25 ? n - 25 : 0;
    for (int i = first; i < n; i++) s.put(i - first, 0, lg.lines[i].first.c_str(), lg.lines[i].second);
    if (cursorAtEnd && n) { s.curRow = n - 1 - first; s.curCol = (int)lg.lines.back().first.size(); }
}

static void dosHistory(Log& lg, double t) {
    const uint8_t G = AT(BLK, LGR);
    lg.lines.push_back({"Starting ESA-DOS...", G});
    if (t < T_DOS + 0.45) return;
    lg.lines.push_back({"", G});
    lg.lines.push_back({"C:\\>" + typedStr(TY_CD, t), G});
    if (t < ENT_CD) return;
    lg.lines.push_back({"", G});
    lg.lines.push_back({"C:\\ESA>" + typedStr(TY_SETUP, t), G});
}

static void dos(Screen& s, double t) {
    s.clear(AT(BLK, LGR));
    Log lg;
    dosHistory(lg, t);
    drawLog(s, lg, t >= T_DOS + 0.45);
}

// ---- SETUP.EXE -------------------------------------------------------------
static void setupFrame(Screen& s) {
    s.clear(AT(BLU, LBL), 0xB0);
    s.fill(0, 0, 0, 79, ' ', AT(LGR, BLK));
    s.put(0, 1, "ESA MARATHON SETUP", AT(LGR, BLK));
    s.put(0, 67, "Version 2.7", AT(LGR, BLK));
    s.fill(24, 0, 24, 79, ' ', AT(LGR, BLK));
    s.put(24, 1, "\x18\x19 Move   \x11\xD9 Select   Esc Back", AT(LGR, BLK));
    s.put(24, 60, "F1 Help", AT(LGR, BLK));
    s.put(24, 60, "F1", AT(LGR, RED));
}
static void dialog(Screen& s, int r0, int c0, int r1, int c1, const char* title) {
    s.box(r0, c0, r1, c1, AT(LGR, BLK), true);
    s.shadow(r0, c0, r1, c1);
    if (title) {
        std::string tt = std::string(" ") + title + " ";
        s.center(r0, tt.c_str(), AT(LGR, BLU), c0, c1);
    }
}
static void button(Screen& s, int r, int c, const char* label, bool focus) {
    s.put(r, c, label, focus ? AT(BLU, WHT) : AT(LGR, BLK));
}

static void setupCards(Screen& s, double t) {
    setupFrame(s);
    dialog(s, 5, 22, 20, 57, "Select Sound Card");
    const char* cards[9] = {"None", "PC Speaker", "AdLib", "Sound Blaster", "Sound Blaster Pro",
                            "Sound Blaster 16", "Gravis UltraSound", "Roland MT-32", "MOS SID 6581"};
    int sel = countKeys(CARD_KEYS, 5, t);
    for (int i = 0; i < 9; i++) {
        bool hl = i == sel;
        if (hl) s.fill(7 + i, 24, 7 + i, 55, ' ', AT(BLU, WHT));
        s.put(7 + i, 26, cards[i], hl ? AT(BLU, WHT) : AT(LGR, BLK));
    }
    s.put(17, 25, "Auto-detect found:", AT(LGR, DGR));
    s.put(18, 25, "Sound Blaster 16 at 220h", AT(LGR, BLK));
}

static void setupSB(Screen& s, double t) {
    setupFrame(s);
    dialog(s, 5, 18, 19, 61, "Sound Blaster 16 Settings");
    int k = countKeys(SB_KEYS, 6, t);
    // focus: 0 port, 1 irq, (k==2 changes irq), 2 dma8, 3 dma16, 4 music, 5 test button
    int focus = k == 0 ? 0 : k <= 2 ? 1 : k - 1;
    const char* irq = k >= 2 ? "5 " : "7 ";
    const char* lab[5] = {"I/O Port  ", "IRQ       ", "8-bit DMA ", "16-bit DMA", "Music     "};
    const char* val[5] = {"220h", irq, "1", "5", "SID 6581 emulation"};
    for (int i = 0; i < 5; i++) {
        s.put(7 + 2 * i, 22, lab[i], AT(LGR, BLK));
        s.put(7 + 2 * i, 33, ":", AT(LGR, BLK));
        bool f = focus == i && k < 6;
        std::string v = std::string(" ") + val[i] + " ";
        s.put(7 + 2 * i, 35, v.c_str(), f ? AT(BLU, WHT) : AT(LGR, BLU));
    }
    bool testFocus = k >= 6;
    button(s, 17, 24, "[  Test  ]", testFocus);
    button(s, 17, 36, "[   OK   ]", false);
    button(s, 17, 48, "[ Cancel ]", false);
    if (t >= ENT_TEST - 0.12 && testFocus) s.attrs(17, 24, 17, 33, AT(CYN, WHT));  // key-down flash
}

static void vuBar(Screen& s, int r, int c, int w, float v, const char* label) {
    s.put(r, c, label, AT(LGR, BLK));
    int n = (int)(std::min(1.0f, v) * w + 0.5f);
    for (int i = 0; i < w; i++) {
        uint8_t fg = i < w * 0.6 ? GRN : i < w * 0.85 ? BRN : RED;
        if (i < n) fg = fg == GRN ? LGN : fg == BRN ? YEL : LRD;
        s.putc(r, c + 3 + i, i < n ? 0xDB : 0xFA, AT(LGR, i < n ? fg : DGR));
    }
}

static void setupTest(Screen& s, double t) {
    setupFrame(s);
    dialog(s, 4, 12, 20, 67, "Sound Test");
    s.center(6, "Testing Sound Blaster 16 at 220h, IRQ 5, DMA 1", AT(LGR, BLK), 12, 67);
    s.center(8, "Now playing:", AT(LGR, DGR), 12, 67);
    s.center(9, "\x0E SIDOLOGY EPISODE 1: SID EVOLUTION \x0E", AT(LGR, BLU), 12, 67);
    s.center(10, "by Machinae Supremacy", AT(LGR, BLK), 12, 67);
    vuBar(s, 12, 16, 46, s.vu[0], "L");
    vuBar(s, 13, 16, 46, s.vu[1], "R");
    double el = t - BOOT_MUSIC_AT;
    char buf[48];
    snprintf(buf, sizeof buf, "%02d:%05.2f", (int)(el / 60), fmod(el, 60.0));
    bool over = el > EST;
    s.put(15, 16, "Elapsed", AT(LGR, DGR));
    s.put(15, 24, buf, AT(LGR, over ? RED : BLK));
    snprintf(buf, sizeof buf, "%02d:%05.2f", (int)(EST / 60), fmod(EST, 60.0));
    s.put(15, 44, "Estimate", AT(LGR, DGR));
    s.put(15, 53, buf, AT(LGR, BLK));
    if (over && fmod(el - EST, 0.46) < 0.30)   // blinks like a text-mode attribute
        s.center(16, "\x13 OVER ESTIMATE \x13", AT(RED, YEL), 12, 67);
    if (t >= T_ASK) {
        s.center(17, "Can you hear the music?", AT(LGR, BLK), 12, 67);
        bool pressed = t >= ENT_YES;
        button(s, 18, 28, "[  Yes  ]", !pressed || true);
        button(s, 18, 42, "[  No  ]", false);
        if (pressed) s.attrs(18, 28, 18, 36, AT(CYN, WHT));
    }
}

static void setupSaved(Screen& s, double t) {
    setupFrame(s);
    dialog(s, 9, 20, 15, 59, "Setup");
    s.center(11, "Settings saved to C:\\ESA\\ESA.CFG", AT(LGR, BLK), 20, 59);
    s.center(13, "Press any key to return to DOS", AT(LGR, DGR), 20, 59);
    (void)t;
}

static void dos2(Screen& s, double t) {
    const uint8_t G = AT(BLK, LGR), W = AT(BLK, WHT), OK = AT(BLK, LGN);
    s.clear(G);
    const uint8_t WARN = AT(BLK, YEL);
    Log lg;
    dosHistory(lg, 1e9);
    lg.lines.push_back({"", G});
    lg.lines.push_back({"C:\\ESA>" + typedStr(TY_EAS, t), G});
    if (t >= ENT_EAS) {
        lg.lines.push_back({"Bad command or file name", G});
        lg.lines.push_back({"", G});
        lg.lines.push_back({"C:\\ESA>" + typedStr(TY_REM, t), G});
    }
    if (t >= ENT_REM) {
        lg.lines.push_back({"", G});
        lg.lines.push_back({"C:\\ESA>" + typedStr(TY_ESA, t), G});
    }
    if (t >= ENT_ESA) {
        const char* L[10] = {"", "ESA.EXE  -  European Speedrunner Assembly demo loader v27.0",
                             "(C) 2011-2027 ESA. All rights reversed.", "",
                             "Checking CPU ..................... 486DX2/66", "Checking memory .................. 64512K XMS",
                             "Sound Blaster 16 ................. 220h / IRQ 5 / DMA 1", "Checking estimate ................ 1:15",
                             "Speedrun timer ................... armed", "Switching to VGA mode X (320x240)..."};
        for (int i = 0; i < 10 && (i < 1 || t >= LOADER_T[i - 1]); i++) lg.lines.push_back({L[i], i == 1 || i == 9 ? W : G});
    }
    drawLog(s, lg, true);
    // status flags after the finished checks: OK in green, the estimate check fails (of course)
    int n = (int)lg.lines.size(), first = n > 25 ? n - 25 : 0;
    for (int i = first; i < n; i++) {
        const std::string& l = lg.lines[i].first;
        if (l.find(" ....") == std::string::npos || (i == n - 1 && t < LOADER_T[8])) continue;
        if (l.rfind("Checking estimate", 0) == 0) s.put(i - first, 58, "OVER ESTIMATE", WARN);
        else s.put(i - first, 58, "OK", OK);
    }
}

bool drawTextMode(Screen& s, double t, float vuL, float vuR, float glitch) {
    s.vu[0] = vuL; s.vu[1] = vuR;
    s.clear(AT(BLK, LGR));
    if (t < T_POST) return false;
    if (t < T_CMOS) {
        post(s, t);
        if (t >= T_DEL && t < T_DEL + 0.12) s.put(22, 7, "DEL", AT(BLK, YEL));
    } else if (t < T_REBOOT) cmos(s, t);
    else if (t < T_DOS) return false;  // reboot blank
    else if (t < T_SETUP) dos(s, t);
    else if (t < T_SBCFG) setupCards(s, t);
    else if (t < ENT_TEST) setupSB(s, t);
    else if (t < T_SAVED) setupTest(s, t);
    else if (t < T_DOS2) setupSaved(s, t);
    else if (t < BOOT_END - 0.55) {
        dos2(s, t);
        if (t >= T_GARBAGE) {  // the mode switch half-happens: VGA memory read as text
            int fr = (int)(t * 60);
            double p = (t - T_GARBAGE) / 0.30;
            for (int r = 0; r < 25; r++) for (int c = 0; c < 80; c++) {
                double h = sin((r * 80 + c) * 12.9898 + fr * 78.233) * 43758.5453;
                h -= floor(h);
                double band = sin(r * 1.7 + fr * 0.9) * 0.5 + 0.5;
                if (h < p * (0.35 + 0.65 * band) * glitch) {
                    double h2 = sin((r * 80 + c) * 3.13 + fr * 1.7) * 9631.7; h2 -= floor(h2);
                    s.c[r][c] = {(uint8_t)(h2 * 255), (uint8_t)(h * 1000.0)};
                }
            }
            s.curRow = -1;
        }
    }
    else return false;
    return true;
}

std::vector<Sfx> bootSfx() {
    std::vector<Sfx> v;
    auto typed = [&](const Typed& ty) { for (int i = 0; ty.text[i]; i++) v.push_back({charTime(ty, i), SFX_KEY, 0}); };
    v.push_back({T_POST + 1.55, SFX_BEEP, 0.16f});                // POST ok beep after the memory test
    v.push_back({T_POST + 1.85, SFX_HDD, 0.90f});                 // IDE detection
    v.push_back({T_DEL, SFX_KEY, 0});
    for (int i = 0; i < 5; i++) v.push_back({CMOS_KEYS[i], SFX_KEY, 0});
    v.push_back({CMOS_KEYS[5], SFX_ENTER, 0});
    typed(TY_Y);
    v.push_back({ENT_Y, SFX_ENTER, 0});
    v.push_back({T_REBOOT + 0.05, SFX_RELAY, 0});
    v.push_back({T_DOS - 0.05, SFX_HDD, 0.55f});
    typed(TY_CD);
    v.push_back({ENT_CD, SFX_ENTER, 0});
    typed(TY_SETUP);
    v.push_back({ENT_SETUP, SFX_ENTER, 0});
    v.push_back({ENT_SETUP + 0.03, SFX_HDD, 0.30f});
    for (int i = 0; i < 5; i++) v.push_back({CARD_KEYS[i], SFX_KEY, 0});
    v.push_back({CARD_KEYS[5], SFX_ENTER, 0});
    for (double k : SB_KEYS) v.push_back({k, SFX_KEY, 0});
    v.push_back({ENT_TEST - 0.03, SFX_ENTER, 0});
    v.push_back({ENT_YES, SFX_ENTER, 0});
    v.push_back({KEY_ANY, SFX_KEY, 0});
    v.push_back({T_DOS2 + 0.02, SFX_HDD, 0.2f});
    typed(TY_EAS);
    v.push_back({ENT_EAS, SFX_ENTER, 0});
    typed(TY_REM);
    v.push_back({ENT_REM, SFX_ENTER, 0});
    typed(TY_ESA);
    v.push_back({ENT_ESA, SFX_ENTER, 0});
    v.push_back({ENT_ESA + 0.05, SFX_HDD, 1.1f});
    v.push_back({T_GARBAGE, SFX_STATIC, 0.85f});                  // garbage + sync loss hiss
    v.push_back({BOOT_END - 0.55, SFX_RELAY, 0});                   // monitor re-syncs to mode X
    v.push_back({BOOT_END, SFX_DEGAUSS_SMALL, 0});                  // the tube settles on the new mode
    v.push_back({6.35, SFX_STATIC, 0.20f, 0.8f});                  // reboot sync loss
    return v;
}
