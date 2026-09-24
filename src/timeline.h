// Timing + content contract for the ESA trailer. Everything is a pure function of t (seconds).
#pragma once

// ---- editable trailer copy -------------------------------------------------
#define EVENT_NAME   "ESA WINTER 2027"
#define EVENT_LINE2  "ESAMARATHON.COM"
#define EVENT_LINE3  "TWITCH.TV/ESAMARATHON"

// ---- output ----------------------------------------------------------------
constexpr int    OUT_W = 1920, OUT_H = 1080, FPS = 60;
constexpr double LENGTH = 75.0;
constexpr int    GFX_W = 320, GFX_H = 240;     // VGA mode X
constexpr int    TXT_W = 720, TXT_H = 400;     // VGA text mode 80x25, 9x16 cells

// ---- music (mirrors tools/build_assets.py) ---------------------------------
// Song = Machinae Supremacy - SIDology Episode 1: SID Evolution, 90 BPM.
// song_cut.wav starts on song bar 102 (4:32.00) and is placed at MUSIC_AT.
constexpr double BEAT     = 60.0 / 90.0;
constexpr double BAR      = 4.0 * BEAT;
constexpr double MUSIC_AT = 13.0;                  // "Test" pressed in SETUP.EXE
constexpr double T_DEMO   = MUSIC_AT + 3 * BAR;    // 21.000  song bar 105 lift: demo starts
constexpr double T_DROP   = MUSIC_AT + 4 * BAR;    // 23.667  song bar 106
constexpr double T_PLASMA = MUSIC_AT + 8 * BAR;    // 34.333
constexpr double T_STAGE  = MUSIC_AT + 12 * BAR;   // 45.000
constexpr double T_TUNNEL = MUSIC_AT + 16 * BAR;   // 55.667
constexpr double T_FINALE = MUSIC_AT + 19 * BAR;   // 63.667
constexpr double T_HIT    = 3979.0 / FPS;          // 66.3167 = frame 3979, the measured ending hit (66.318)
constexpr double T_OFF    = 73.30;                 // CRT power-off (bloom surge -> line -> dot)

inline double beatAt(double t) { return (t - MUSIC_AT) / BEAT; }

enum Scene { SC_TEXT = 0, SC_TITLE, SC_DROP, SC_PLASMA, SC_STAGE, SC_TUNNEL, SC_FINALE, SC_BLACK };

inline Scene sceneAt(double t, double* t0 = nullptr) {
    struct { double s; Scene sc; } cues[] = {
        {0, SC_TEXT}, {T_DEMO - 0.55, SC_BLACK}, {T_DEMO, SC_TITLE}, {T_DROP, SC_DROP},
        {T_PLASMA, SC_PLASMA}, {T_STAGE, SC_STAGE}, {T_TUNNEL, SC_TUNNEL}, {T_FINALE, SC_FINALE}};
    int n = sizeof(cues) / sizeof(cues[0]), i = 0;
    while (i + 1 < n && t >= cues[i + 1].s) i++;
    if (t0) *t0 = cues[i].s;
    return cues[i].sc;
}
