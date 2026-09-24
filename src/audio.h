#pragma once
#include <string>
#include <vector>

constexpr int SR = 44100;

struct Soundtrack {
    std::vector<float> mix;           // interleaved stereo, LENGTH seconds
    // per video frame (FPS) envelopes of the MUSIC only, 0..1-ish
    std::vector<float> low, mid, high, kick, vuL, vuR;
    bool build(const std::string& songWav);   // loads the song cut, synthesises sfx, mixes
    bool writeWav(const std::string& path) const;
    int frames() const { return (int)low.size(); }
};
