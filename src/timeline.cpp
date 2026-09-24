#include "timeline.h"
#include <cmath>
#include <cstdio>

const Cue* Timeline::cueAt(double t) const {
    const Cue* c = nullptr;
    for (const Cue& q : cues) if (t >= q.t0) c = &q;
    return c;
}

// The song is back-timed: the finale's hit lands on the song's final hit (bar 122), so adding parts moves the
// song's entry point earlier instead of stretching anything. Every part is a whole number of bars, so every
// cut stays on the beat.
Timeline buildTimeline(bool boot, bool finale, const std::vector<int>& order, const std::vector<int>& partBars,
                       int finalePart) {
    Timeline tl;
    tl.boot = boot;
    tl.finale = finale && finalePart >= 0;
    tl.musicAt = boot ? BOOT_MUSIC_AT : NOBOOT_START;
    tl.demoStart = boot ? BOOT_END : NOBOOT_START;
    double t = tl.demoStart;
    int bars = 0;
    for (size_t i = 0; i < order.size(); i++) {
        double len = partBars[i] * BAR;
        tl.cues.push_back({order[i], t, t + len});
        t += len;
        bars += partBars[i];
    }
    int musicBarsBeforeEnd = (boot ? BOOT_MUSIC_BARS : 0) + bars;
    if (tl.finale) {
        tl.finaleStart = t;
        double hitGrid = t + FINALE_LEAD_BARS * BAR;
        int hitFrame = (int)std::lround((hitGrid - HIT_EARLY) * FPS);
        tl.hit = hitFrame / (double)FPS;
        int offFrame = hitFrame + OFF_AFTER_HIT_FRAMES;
        tl.off = offFrame / (double)FPS;
        tl.frames = offFrame + END_AFTER_OFF_FRAMES;
        tl.cues.push_back({finalePart, t, tl.frames / (double)FPS});
        musicBarsBeforeEnd += FINALE_LEAD_BARS;
    } else {
        int offFrame = (int)std::lround(t * FPS) + OFF_AFTER_LAST_FRAMES;
        tl.off = offFrame / (double)FPS;
        tl.frames = offFrame + END_AFTER_OFF_FRAMES;
        if (!tl.cues.empty()) tl.cues.back().t1 = tl.frames / (double)FPS;
    }
    tl.length = tl.frames / (double)FPS;
    // the song bar that plays at musicAt
    int startBar = SONG_HIT_BAR - musicBarsBeforeEnd;
    if (startBar < 0) { startBar = 0; tl.songTooShort = true; }
    tl.songStart = SONG_BAR0 + startBar * BAR;
    for (size_t i = 1; i < tl.cues.size(); i++) tl.cuts.push_back(tl.cues[i].t0);
    return tl;
}

std::string fmtTime(double s) {
    char b[32];
    if (s < 0) s = 0;
    snprintf(b, sizeof b, "%d:%04.1f", (int)(s / 60), fmod(s, 60.0));
    return b;
}
