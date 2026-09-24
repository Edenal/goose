#pragma once
#include <string>
#include <vector>
#include "timeline.h"

constexpr int SR = 44100;

struct Soundtrack {
    std::vector<float> mix;           // interleaved stereo, LENGTH seconds
    // per video frame (FPS) envelopes of the MUSIC only, 0..1-ish
    std::vector<float> low, mid, high, kick, vuL, vuR;
    std::vector<double> kickCum;      // integral of kick, per frame (+1)
    void build(const Timeline& tl, const std::vector<float>& song);   // song + synthesised sfx, mixed
    bool writeWav(const std::string& path) const;
    int frames() const { return (int)low.size(); }
    float env(const std::vector<float>& v, double t) const {
        if (v.empty()) return 0;
        int f = (int)(t * FPS + 1e-6); f = f < 0 ? 0 : f >= (int)v.size() ? (int)v.size() - 1 : f;
        return v[f];
    }
    double kickSum(double t) const {
        if (kickCum.empty()) return 0;
        int f = (int)(t * FPS + 1e-6); f = f < 0 ? 0 : f >= (int)kickCum.size() ? (int)kickCum.size() - 1 : f;
        return kickCum[f];
    }
};
