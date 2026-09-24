// VGA text mode (80x25) screen model + the DOS/BIOS intro script.
#pragma once
#include <cstdint>
#include <vector>

struct Cell { uint8_t ch, attr; };

struct Screen {
    Cell c[25][80];
    int curRow = -1, curCol = 0;   // curRow < 0: hardware cursor hidden
    bool logo = false;             // BIOS energy-star style logo in the top-right corner
    float vu[2] = {0, 0};          // set by the caller (audio envelope) for the sound test

    void clear(uint8_t attr, uint8_t ch = ' ');
    void put(int r, int c, const char* s, uint8_t attr);
    void putc(int r, int c, uint8_t ch, uint8_t attr);
    void center(int r, const char* s, uint8_t attr, int c0 = 0, int c1 = 79);
    void fill(int r0, int c0, int r1, int c1, uint8_t ch, uint8_t attr);
    void attrs(int r0, int c0, int r1, int c1, uint8_t attr);
    void box(int r0, int c0, int r1, int c1, uint8_t attr, bool dbl);
    void shadow(int r0, int c0, int r1, int c1);
};

enum SfxKind { SFX_KEY, SFX_ENTER, SFX_BEEP, SFX_HDD, SFX_POWER_ON, SFX_RELAY, SFX_POWER_OFF, SFX_STATIC, SFX_DEGAUSS_SMALL };
struct Sfx { double t; SfxKind kind; float dur; };

// Fill the screen for time t (0 <= t < T_DEMO). Returns false if the text screen is blank.
bool drawTextMode(Screen& s, double t, float vuL, float vuR);
// All scripted sound effects (keys, beeps, disk) for the whole trailer.
std::vector<Sfx> buildSfx();
