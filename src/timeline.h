// Timing contract. The arrangement (which parts, in which order) comes from Settings; everything else is
// derived here, so the renderer, the audio and the glitch schedule all read the same numbers.
#pragma once
#include <string>
#include <vector>

// ---- output ----------------------------------------------------------------
constexpr int OUT_W = 1920, OUT_H = 1080, FPS = 60;
constexpr int GFX_W = 320, GFX_H = 240;     // VGA mode X
constexpr int TXT_W = 720, TXT_H = 400;     // VGA text mode 80x25, 9x16 cells

// ---- music -----------------------------------------------------------------
// Machinae Supremacy - SIDology Episode 1: SID Evolution. 90 BPM, bar grid measured from the audio:
// song bar k starts at SONG_BAR0 + k * BAR, and the song's final hit is bar SONG_HIT_BAR.
constexpr double BEAT = 60.0 / 90.0;
constexpr double BAR = 4.0 * BEAT;
constexpr double SONG_BAR0 = 261.337 - 98 * BAR;   // 0.0037 s
constexpr int SONG_HIT_BAR = 122;                  // 5:25.3
constexpr double HIT_EARLY = 0.015;                // the hit's onset lands 15 ms before its bar line
constexpr double SONG_FADE = 3.0;                  // music fades out over the last seconds of the video

// ---- the boot sequence (fixed script, see textmode.cpp) --------------------
constexpr double BOOT_MUSIC_AT = 13.0;             // "Test" pressed in SETUP.EXE
constexpr int BOOT_MUSIC_BARS = 3;                 // sound test + DOS + loader under the music
constexpr double BOOT_END = BOOT_MUSIC_AT + BOOT_MUSIC_BARS * BAR;   // 21.0: mode X
constexpr double NOBOOT_START = 0.9;               // without the boot, the first part starts after power-on

// ---- the ending --------------------------------------------------------------
constexpr int FINALE_LEAD_BARS = 1;                // cube flies in for one bar, lands on the hit
constexpr int OFF_AFTER_HIT_FRAMES = 419;          // power-off starts ~7 s after the hit
constexpr int END_AFTER_OFF_FRAMES = 102;          // and the video ends 1.7 s later
constexpr int OFF_AFTER_LAST_FRAMES = 24;          // without the finale: power-off 0.4 s after the last part

struct Cue {
    int part;          // index into the part registry
    double t0, t1;     // trailer seconds
};

struct Timeline {
    bool boot = true, finale = true;
    std::vector<Cue> cues;          // graphics parts in order (the finale is the last cue when enabled)
    std::vector<double> cuts;       // start times of every cue after the first (scene transitions)
    double demoStart = BOOT_END;    // first graphics frame (mode X when booting)
    double musicAt = BOOT_MUSIC_AT; // trailer time the song starts
    double songStart = 0;           // song time at musicAt
    double hit = -1;                // finale: the cube lands on the logo (frame-exact); -1 without finale
    double finaleStart = -1;
    double off = 0;                 // CRT power-off starts
    double length = 0;              // total seconds (whole frames)
    int frames = 0;
    bool songTooShort = false;      // arrangement longer than the song: the ending no longer lands on the hit
    bool solo = false;              // part preview: no power on/off, no glitches

    double songAt(double t) const { return songStart + (t - musicAt); }
    double beatAt(double t) const { return (t - musicAt) / BEAT; }
    const Cue* cueAt(double t) const;
};

// partBars[i] = length in bars of the i-th part in play order (finale excluded; it is appended when enabled).
Timeline buildTimeline(bool boot, bool finale, const std::vector<int>& order, const std::vector<int>& partBars,
                       int finalePart);
std::string fmtTime(double s);   // m:ss.s
