// Soundtrack = song excerpt placed at MUSIC_AT + synthesised PC sounds from the intro script.
#include "audio.h"
#include "textmode.h"
#include "timeline.h"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>

static uint32_t rngState = 0x12345678u;
static float frand() {  // deterministic white noise in [-1,1]
    rngState ^= rngState << 13; rngState ^= rngState >> 17; rngState ^= rngState << 5;
    return (rngState & 0xFFFFFF) / float(0x7FFFFF) - 1.0f;
}

static bool readWav16(const std::string& path, std::vector<float>& out, int& channels) {
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return false;
    char id[4]; uint32_t sz;
    fread(id, 1, 4, f); fread(&sz, 4, 1, f); fread(id, 1, 4, f);
    int bits = 0; channels = 0; uint32_t rate = 0;
    while (fread(id, 1, 4, f) == 4 && fread(&sz, 4, 1, f) == 1) {
        if (!memcmp(id, "fmt ", 4)) {
            uint16_t fmt, ch, ba, bp; uint32_t br;
            fread(&fmt, 2, 1, f); fread(&ch, 2, 1, f); fread(&rate, 4, 1, f); fread(&br, 4, 1, f);
            fread(&ba, 2, 1, f); fread(&bp, 2, 1, f);
            channels = ch; bits = bp;
            fseek(f, sz - 16, SEEK_CUR);
        } else if (!memcmp(id, "data", 4)) {
            std::vector<int16_t> pcm(sz / 2);
            fread(pcm.data(), 2, pcm.size(), f);
            out.resize(pcm.size());
            for (size_t i = 0; i < pcm.size(); i++) out[i] = pcm[i] / 32768.0f;
            break;
        } else fseek(f, sz + (sz & 1), SEEK_CUR);
    }
    fclose(f);
    return bits == 16 && rate == SR && !out.empty();
}

bool Soundtrack::writeWav(const std::string& path) const {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) return false;
    uint32_t n = (uint32_t)mix.size(), data = n * 2, riff = 36 + data, fmtsz = 16, rate = SR, br = SR * 4;
    uint16_t pcm = 1, ch = 2, ba = 4, bits = 16;
    fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&fmtsz, 4, 1, f);
    fwrite(&pcm, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&rate, 4, 1, f); fwrite(&br, 4, 1, f);
    fwrite(&ba, 2, 1, f); fwrite(&bits, 2, 1, f); fwrite("data", 1, 4, f); fwrite(&data, 4, 1, f);
    std::vector<int16_t> s(n);
    for (uint32_t i = 0; i < n; i++) s[i] = (int16_t)std::lround(std::clamp(mix[i], -1.0f, 1.0f) * 32767.0f);
    fwrite(s.data(), 2, n, f);
    fclose(f);
    return true;
}

// ---------------------------------------------------------------- sfx synthesis
struct Bus {
    std::vector<float>& m;
    void add(double t, float l, float r) {
        long i = lround(t * SR);
        if (i >= 0 && (size_t)(2 * i + 1) < m.size()) { m[2 * i] += l; m[2 * i + 1] += r; }
    }
};

static void keyClick(Bus& b, double t0, float vol, float thockHz, float pan, int seed) {
    rngState = 0x9E3779B9u * (seed + 1);
    float bp1 = 0, bp2 = 0;
    for (int part = 0; part < 2; part++) {          // press, then a softer release
        double ts = t0 + part * (0.075 + 0.02 * (seed % 3));
        float v = part ? vol * 0.45f : vol;
        for (int i = 0; i < SR * 0.06; i++) {
            double tt = i / (double)SR;
            float n = frand();
            bp1 += 0.55f * (n - bp1); bp2 += 0.12f * (bp1 - bp2);
            float click = (bp1 - bp2) * expf(-tt / 0.006f) * 1.6f;
            float thock = sinf(2 * M_PI * thockHz * tt) * expf(-tt / 0.018f) * (part ? 0.2f : 0.7f);
            float s = v * (click + thock);
            b.add(ts + tt, s * (1 - pan), s * (1 + pan));
        }
    }
}

static void pcBeep(Bus& b, double t0, double dur) {
    float lp = 0;
    for (int i = 0; i < SR * dur; i++) {
        double tt = i / (double)SR;
        float sq = fmod(tt * 1000.0, 1.0) < 0.5 ? 1.f : -1.f;
        lp += 0.25f * (sq - lp);                       // little cone speaker
        float env = std::min(1.0, tt / 0.003) * std::min(1.0, (dur - tt) / 0.004);
        b.add(t0 + tt, lp * 0.10f * env, lp * 0.10f * env);
    }
}

static void hdd(Bus& b, double t0, double dur, int seed) {
    rngState = 0xABCDu * (seed + 7);
    double t = t0;
    while (t < t0 + dur) {
        float ring = 0, v = 0.05f + 0.05f * fabsf(frand());
        float hz = 1800 + 900 * fabsf(frand());
        for (int i = 0; i < SR * 0.012; i++) {
            double tt = i / (double)SR;
            float s = (frand() * expf(-tt / 0.0012f) + sinf(2 * M_PI * hz * tt) * 0.6f) * expf(-tt / 0.004f) * v;
            ring = s;
            b.add(t + tt, ring * 0.9f, ring * 1.1f);
        }
        t += 0.018 + 0.06 * fabsf(frand());
    }
}

static void relay(Bus& b, double t0, float vol) {
    rngState = 777;
    for (int i = 0; i < SR * 0.03; i++) {
        double tt = i / (double)SR;
        float s = (frand() * expf(-tt / 0.0015f) + sinf(2 * M_PI * 1400 * tt) * expf(-tt / 0.008f) * 0.5f) * vol;
        b.add(t0 + tt, s, s);
        b.add(t0 + 0.009 + tt, s * 0.5f, s * 0.5f);
    }
}

// crackle of the high voltage charging/discharging the tube: sparse sharp ticks that thin out
static void crackle(Bus& b, double t0, double dur, float vol, int seed) {
    rngState = 0x5151u * (seed + 3);
    double t = t0;
    while (t < t0 + dur) {
        double x = (t - t0) / dur;
        float v = vol * (float)(1 - x) * (0.3f + 0.7f * fabsf(frand()));
        for (int i = 0; i < SR * 0.004; i++) {
            double tt = i / (double)SR;
            float s = frand() * expf(-tt / 0.0006f) * v;
            b.add(t + tt, s * (0.8f + 0.4f * frand()), s * (0.8f + 0.4f * frand()));
        }
        t += 0.004 + 0.06 * x * fabsf(frand()) + 0.008 * fabsf(frand());
    }
}

// degauss coil: mains-frequency "BWONG" with metallic partials
static float degaussSample(double tt) {
    return sinf(2 * M_PI * 50 * tt) + 0.6f * sinf(2 * M_PI * 100 * tt) + 0.35f * sinf(2 * M_PI * 150 * tt)
           + 0.18f * sinf(2 * M_PI * 221 * tt) + 0.12f * sinf(2 * M_PI * 347 * tt);
}

static void powerOn(Bus& b, double t0) {
    relay(b, t0, 0.45f);                                       // the power switch
    rngState = 42;
    float lp = 0;
    for (int i = 0; i < SR * 1.6; i++) {                       // thump, then the degauss swell and decay
        double tt = i / (double)SR;
        lp += 0.02f * (frand() - lp);
        float thump = sinf(2 * M_PI * 48 * tt) * expf(-tt / 0.06f) * 0.35f + lp * expf(-tt / 0.04f) * 2.2f;
        double dt = tt - 0.12;
        float env = dt < 0 ? 0 : (float)(std::min(1.0, dt / 0.06) * exp(-dt / 0.42));
        float s = thump + degaussSample(tt) * env * 0.11f;
        b.add(t0 + tt, s, s);
    }
    crackle(b, t0 + 0.18, 0.9, 0.22f, 1);                      // HV charging the tube
    for (int i = 0; i < SR * 1.2; i++) {                       // 15.7 kHz flyback whine fades in
        double tt = i / (double)SR;
        float s = sinf(2 * M_PI * 15734 * tt) * 0.006f * (float)std::min(1.0, tt / 0.8);
        b.add(t0 + 0.25 + tt, s, s);
    }
}

// the power-on backwards: a degauss swell rises INTO the switch-off, then the collapse zap and the discharge
static void powerOff(Bus& b, double t0) {
    for (int i = 0; i < SR * 0.25; i++) {
        double tt = i / (double)SR;
        float s = degaussSample(tt) * (float)pow(tt / 0.25, 2.0) * 0.09f;
        b.add(t0 + tt, s, s);
    }
    relay(b, t0 + 0.25, 0.45f);
    double ph = 0;
    for (int i = 0; i < SR * 0.45; i++) {                      // collapse: descending "pew"
        double tt = i / (double)SR;
        double hz = 1100 * exp(-tt * 9) + 40;
        ph += 2 * M_PI * hz / SR;
        float s = sinf(ph) * expf(-tt / 0.16f) * 0.16f;
        b.add(t0 + 0.25 + tt, s, s);
    }
    rngState = 4242;
    float lp = 0;
    for (int i = 0; i < SR * 0.12; i++) {
        double tt = i / (double)SR;
        lp += 0.05f * (frand() - lp);
        float s = (sinf(2 * M_PI * 55 * tt) * 0.3f + lp * 1.5f) * expf(-tt / 0.04f);
        b.add(t0 + 0.25 + tt, s, s);
    }
    crackle(b, t0 + 0.35, 1.2, 0.2f, 2);                       // the tube discharging
}

static void staticBurst(Bus& b, double t0, double dur) {       // sync loss hiss with a 60 Hz buzz
    rngState = 31337;
    float bp1 = 0, bp2 = 0;
    for (int i = 0; i < SR * dur; i++) {
        double tt = i / (double)SR;
        bp1 += 0.5f * (frand() - bp1); bp2 += 0.05f * (bp1 - bp2);
        float buzz = 0.6f + 0.4f * (fmod(tt * 60, 1.0) < 0.5 ? 1.f : -1.f);
        float env = (float)(std::min(1.0, tt / 0.05) * std::min(1.0, (dur - tt) / 0.08));
        float s = (bp1 - bp2) * buzz * env * 0.16f;
        b.add(t0 + tt, s * (0.9f + 0.2f * frand()), s * (0.9f + 0.2f * frand()));
    }
}

static void degaussSmall(Bus& b, double t0) {
    for (int i = 0; i < SR * 0.5; i++) {
        double tt = i / (double)SR;
        float s = degaussSample(tt) * expf(-tt / 0.14f) * 0.05f * (float)std::min(1.0, tt / 0.02);
        b.add(t0 + tt, s, s);
    }
}

static void fanBed(Bus& b, double t0, double t1, double fadeFrom) {   // PC fan + spindle
    rngState = 99;
    float lp1 = 0, lp2 = 0;
    for (long i = lround(t0 * SR); i < lround(t1 * SR); i++) {
        double t = i / (double)SR;
        lp1 += 0.03f * (frand() - lp1); lp2 += 0.03f * (lp1 - lp2);
        float spindle = sinf(2 * M_PI * 120 * t) * 0.004f;
        float env = std::min(1.0, (t - t0) / 1.0) * (t > fadeFrom ? std::max(0.0, 1 - (t - fadeFrom) / (t1 - fadeFrom)) : 1.0);
        float s = (lp2 * 0.35f + spindle) * env;
        b.add(t, s, s * 0.95f);
    }
}

// ---------------------------------------------------------------- build
bool Soundtrack::build(const std::string& songWav) {
    const size_t N = (size_t)(LENGTH * SR);
    mix.assign(2 * N, 0.0f);
    std::vector<float> song; int ch = 0;
    if (!readWav16(songWav, song, ch) || ch != 2) { fprintf(stderr, "cannot read %s\n", songWav.c_str()); return false; }
    std::vector<float> music(2 * N, 0.0f);
    size_t off = (size_t)lround(MUSIC_AT * SR);
    for (size_t i = 0; i + off < N && 2 * i + 1 < song.size(); i++) {
        music[2 * (i + off)] = song[2 * i] * 0.92f;
        music[2 * (i + off) + 1] = song[2 * i + 1] * 0.92f;
    }
    Bus b{mix};
    int seed = 0;
    for (const Sfx& s : buildSfx()) {
        switch (s.kind) {
            case SFX_KEY: keyClick(b, s.t, 0.22f, 190, -0.1f, seed++); break;
            case SFX_ENTER: keyClick(b, s.t, 0.30f, 120, 0.15f, seed++); break;
            case SFX_BEEP: pcBeep(b, s.t, s.dur); break;
            case SFX_HDD: hdd(b, s.t, s.dur, seed++); break;
            case SFX_POWER_ON: powerOn(b, s.t); break;
            case SFX_RELAY: relay(b, s.t, 0.35f); break;
            case SFX_POWER_OFF: powerOff(b, s.t); break;
            case SFX_STATIC: staticBurst(b, s.t, s.dur); break;
            case SFX_DEGAUSS_SMALL: degaussSmall(b, s.t); break;
        }
    }
    fanBed(b, 0.05, T_DEMO, MUSIC_AT + 1.0);
    // sfx under the music get ducked a little so the music stays on top
    for (size_t i = 0; i < 2 * N; i++) {
        double t = (i / 2) / (double)SR;
        float duck = t > MUSIC_AT && t < T_OFF ? 0.6f : 1.0f;
        float x = music[i] + mix[i] * duck;
        // soft-knee limiter: key clicks and the power-off thump can land on the song's peaks
        float ax = fabsf(x);
        if (ax > 0.88f) x = copysignf(0.88f + 0.11f * tanhf((ax - 0.88f) / 0.11f), x);
        mix[i] = x;
    }

    // ---- per-frame envelopes of the music only
    int F = (int)(LENGTH * FPS);
    low.assign(F, 0); mid.assign(F, 0); high.assign(F, 0); kick.assign(F, 0); vuL.assign(F, 0); vuR.assign(F, 0);
    float lpL = 0, lpM = 0, hpPrev = 0, hpOut = 0;
    const float aL = 1 - expf(-2 * M_PI * 150.f / SR), aM = 1 - expf(-2 * M_PI * 2000.f / SR);
    const float aH = expf(-2 * M_PI * 4000.f / SR);
    int spf = SR / FPS;
    std::vector<float> rl(F), rm(F), rh(F), rL(F), rR(F);
    for (int f = 0; f < F; f++) {
        double sl = 0, sm = 0, sh = 0, sL = 0, sR = 0;
        for (int k = 0; k < spf; k++) {
            size_t i = (size_t)f * spf + k;
            float L = music[2 * i], R = music[2 * i + 1], x = 0.5f * (L + R);
            lpL += aL * (x - lpL); lpM += aM * (x - lpM);
            hpOut = aH * (hpOut + x - hpPrev); hpPrev = x;
            sl += lpL * lpL; sm += (lpM - lpL) * (lpM - lpL); sh += hpOut * hpOut; sL += L * L; sR += R * R;
        }
        rl[f] = sqrtf(sl / spf); rm[f] = sqrtf(sm / spf); rh[f] = sqrtf(sh / spf);
        rL[f] = sqrtf(sL / spf); rR[f] = sqrtf(sR / spf);
    }
    auto norm = [&](std::vector<float>& src, std::vector<float>& dst, float release) {
        std::vector<float> s = src; std::sort(s.begin(), s.end());
        float ref = std::max(1e-6f, s[(size_t)(s.size() * 0.98)]);
        float e = 0;
        for (int f = 0; f < F; f++) { float v = src[f] / ref; e = v > e ? v : e * release + v * (1 - release); dst[f] = e; }
    };
    norm(rl, low, 0.80f); norm(rm, mid, 0.85f); norm(rh, high, 0.75f);
    norm(rL, vuL, 0.80f); norm(rR, vuR, 0.80f);
    // kick = positive jump of the raw low band, decaying
    std::vector<float> s = rl; std::sort(s.begin(), s.end());
    float ref = std::max(1e-6f, s[(size_t)(s.size() * 0.98)]), k = 0;
    for (int f = 1; f < F; f++) {
        float d = std::max(0.0f, (rl[f] - rl[f - 1]) / ref) * 4.0f;
        k = std::max(k * 0.86f, std::min(1.0f, d));
        kick[f] = k;
    }
    return true;
}
