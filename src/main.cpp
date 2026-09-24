// GOOSE — Glitchy Old-School Output Scene Engine. A DemoScene Maker.
//
//   goose                               the app: GOOSE SETUP menu, preview, export
//   goose --export out.mp4 [--web]      offline render of the saved arrangement (--defaults: factory settings)
//   goose --frames T1,T2 prefix         stills at trailer times
//   goose --part ID --frames T1,T2 pfx  one part on its own, times local to the part (for authoring parts)
//   goose --list                        list the parts
#include <SDL3/SDL.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <mutex>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <vector>

#include "audio.h"
#include "menu.h"
#include "music.h"
#include "renderer.h"
#include "settings.h"
#include "timeline.h"

#include "third_party/stb_image_write.h"

static bool fileExists(const std::string& p) { struct stat st; return stat(p.c_str(), &st) == 0; }

static std::string findResources() {
    const char* base = SDL_GetBasePath();   // .app: Contents/Resources/ ; dev: build/
    std::string b = base ? base : "./";
    for (const std::string& c : {b, b + "../", b + "../Resources/", std::string("./")})
        if (fileExists(c + "shaders/common.glsl")) return c.back() == '/' ? c.substr(0, c.size() - 1) : c;
    return ".";
}

static std::string findFfmpeg() {
    for (const char* p : {"/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"})
        if (fileExists(p)) return p;
    FILE* f = popen("command -v ffmpeg 2>/dev/null", "r");
    char buf[512] = {0};
    if (f) { if (!fgets(buf, sizeof buf, f)) buf[0] = 0; pclose(f); }
    std::string s = buf;
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) s.pop_back();
    return s;
}

static Look lookOf(const Settings& s) {
    Look l;
    l.scan = s.scan / 100.0f; l.fx = s.fx / 100.0f; l.glitch = s.glitch / 100.0f;
    l.event = s.event; l.line2 = s.line2; l.line3 = s.line3;
    return l;
}

// ------------------------------------------------------------------ export (shared by CLI and app)
struct Export {
    FILE* ff = nullptr;
    int frame = 0, total = 0;
    std::string path;
    std::vector<uint8_t> px;
    std::chrono::steady_clock::time_point t0;
    bool start(const std::string& ffmpeg, const std::string& wav, const std::string& out, bool master, int frames, double length) {
        char cmd[4096];
        snprintf(cmd, sizeof cmd,
                 "\"%s\" -v error -y -f rawvideo -pix_fmt rgba -s %dx%d -framerate %d -i - -i \"%s\" "
                 "-vf vflip,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p -c:v libx264 -preset slow %s "
                 "-colorspace bt709 -color_primaries bt709 -color_trc bt709 -c:a aac -b:a %s -t %.3f "
                 "-movflags +faststart \"%s\"",
                 ffmpeg.c_str(), OUT_W, OUT_H, FPS, wav.c_str(), master ? "-crf 14" : "-b:v 24M -maxrate 30M -bufsize 48M",
                 master ? "320k" : "256k", length, out.c_str());
        ff = popen(cmd, "w");
        frame = 0; total = frames; path = out;
        px.resize((size_t)OUT_W * OUT_H * 4);
        t0 = std::chrono::steady_clock::now();
        return ff != nullptr;
    }
    bool frameOut(GLuint fbo) {
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glReadPixels(0, 0, OUT_W, OUT_H, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
        return fwrite(px.data(), 1, px.size(), ff) == px.size();
    }
    int finish() { int rc = ff ? pclose(ff) : -1; ff = nullptr; return rc; }
    double elapsed() const { return std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count(); }
};

// ------------------------------------------------------------------ audio out
struct AudioOut {
    const std::vector<float>* mix = nullptr;
    std::atomic<long> pos{0};
    std::atomic<bool> playing{false};
    std::mutex m;
};
static void SDLCALL audioCb(void* ud, SDL_AudioStream* s, int additional, int) {
    AudioOut* a = (AudioOut*)ud;
    int frames = additional / 8;
    std::vector<float> buf(frames * 2, 0.0f);
    std::lock_guard<std::mutex> lk(a->m);
    if (a->playing && a->mix) {
        long p = a->pos;
        for (int i = 0; i < frames; i++, p++)
            if (p >= 0 && (size_t)(2 * p + 1) < a->mix->size()) { buf[2 * i] = (*a->mix)[2 * p]; buf[2 * i + 1] = (*a->mix)[2 * p + 1]; }
        a->pos = p;
    }
    SDL_PutAudioStreamData(s, buf.data(), frames * 8);
}

// ------------------------------------------------------------------ main
int main(int argc, char** argv) {
    std::string exportPath, framesArg, framesPrefix, partId, wavPath;
    bool web = false, defaults = false, list = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--export") && i + 1 < argc) exportPath = argv[++i];
        else if (!strcmp(argv[i], "--frames") && i + 2 < argc) { framesArg = argv[++i]; framesPrefix = argv[++i]; }
        else if (!strcmp(argv[i], "--part") && i + 1 < argc) partId = argv[++i];
        else if (!strcmp(argv[i], "--web")) web = true;
        else if (!strcmp(argv[i], "--defaults")) defaults = true;
        else if (!strcmp(argv[i], "--list")) list = true;
        else if (!strcmp(argv[i], "--wav") && i + 1 < argc) wavPath = argv[++i];
    }
    bool cli = !exportPath.empty() || !framesArg.empty() || list || !wavPath.empty();
    if (!SDL_Init(SDL_INIT_VIDEO | (cli ? 0 : SDL_INIT_AUDIO))) { fprintf(stderr, "SDL: %s\n", SDL_GetError()); return 1; }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG);
    SDL_Window* win = SDL_CreateWindow("GOOSE - Glitchy Old-School Output Scene Engine", 1280, 720,
                                       SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY |
                                           (cli ? SDL_WINDOW_HIDDEN : 0));
    if (!win) { fprintf(stderr, "window: %s\n", SDL_GetError()); return 1; }
    SDL_GLContext ctx = SDL_GL_CreateContext(win);
    if (!ctx) { fprintf(stderr, "gl: %s\n", SDL_GetError()); return 1; }

    std::string res = findResources();
    Renderer R;
    std::string err;
    if (!R.init(res, err)) { fprintf(stderr, "init: %s\n", err.c_str()); return 1; }
    std::string settingsPath = appSupportDir() + "/settings.ini";
    Settings S;
    if (!defaults) S.load(settingsPath);
    S.reconcile(R.parts);

    if (list) {
        for (const PartDef& p : R.parts)
            printf("%-12s %-22s %d bars %s %s\n", p.id.c_str(), p.name.c_str(), p.bars, p.defaultOn ? "on " : "off",
                   p.prog ? "" : "(SHADER ERROR)");
        return 0;
    }

    // the song
    std::vector<float> song;
    std::string songPath = findSong(res);
    if (!songPath.empty() && !decodeSong(songPath, song, err)) fprintf(stderr, "%s\n", err.c_str());

    Timeline tl;
    if (!partId.empty()) {   // one part on its own
        int pi = findPart(R.parts, partId);
        if (pi < 0) { fprintf(stderr, "no part '%s' (see --list)\n", partId.c_str()); return 1; }
        if (!R.parts[pi].prog) { fprintf(stderr, "part '%s' failed to compile:\n%s\n", partId.c_str(), R.parts[pi].error.c_str()); return 1; }
        tl = buildTimeline(false, false, {pi}, {R.parts[pi].bars}, -1);
        tl.solo = true;
    } else tl = S.timeline(R.parts);
    Soundtrack st;
    st.build(tl, song);
    Look look = lookOf(S);
    if (!wavPath.empty()) {
        st.writeWav(wavPath);
        fprintf(stderr, "timeline: %.3f s, %d frames, music at %.3f from song %.4f, hit %.4f, off %.4f\n", tl.length, tl.frames,
                tl.musicAt, tl.songStart, tl.hit, tl.off);
        return 0;
    }

    // ---------------------------------------------------------------- CLI: stills
    if (!framesArg.empty()) {
        std::stringstream ss(framesArg); std::string tok;
        std::vector<uint8_t> px((size_t)OUT_W * OUT_H * 4);
        while (std::getline(ss, tok, ',')) {
            double t = atof(tok.c_str()) + (tl.solo ? tl.demoStart : 0);
            auto t0 = std::chrono::steady_clock::now();
            for (int w = 6; w >= 1; w--) if (t - w / (double)FPS >= 0) R.renderDemo(t - w / (double)FPS, tl, st, look);
            R.renderDemo(t, tl, st, look);
            glBindFramebuffer(GL_FRAMEBUFFER, R.demoFBO());
            glReadPixels(0, 0, OUT_W, OUT_H, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
            double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count() / 7;
            stbi_flip_vertically_on_write(1);
            char name[1024]; snprintf(name, sizeof name, "%s_%06.2f.png", framesPrefix.c_str(), atof(tok.c_str()));
            stbi_write_png(name, OUT_W, OUT_H, 4, px.data(), OUT_W * 4);
            fprintf(stderr, "wrote %s  (%.1f ms/frame)\n", name, ms);
        }
        return 0;
    }
    // ---------------------------------------------------------------- CLI: export
    if (!exportPath.empty()) {
        std::string ff = findFfmpeg();
        if (ff.empty()) { fprintf(stderr, "ffmpeg not found (brew install ffmpeg)\n"); return 1; }
        std::string wav = exportPath + ".soundtrack.wav";
        st.writeWav(wav);
        Export ex;
        if (!ex.start(ff, wav, exportPath, !web, tl.frames, tl.length)) { perror("ffmpeg"); return 1; }
        for (int f = 0; f < tl.frames; f++) {
            R.renderDemo(f / (double)FPS, tl, st, look);
            if (!ex.frameOut(R.demoFBO())) { fprintf(stderr, "pipe write failed at %d\n", f); return 1; }
            if (f % 600 == 0) fprintf(stderr, "frame %d/%d  %.1fs\n", f, tl.frames, ex.elapsed());
        }
        int rc = ex.finish();
        remove(wav.c_str());
        fprintf(stderr, "export done rc=%d frames=%d -> %s\n", rc, tl.frames, exportPath.c_str());
        return rc == 0 ? 0 : 1;
    }

    // ================================================================ the app
    enum Mode { MENU, PLAY, EXPORTING } mode = MENU;
    Menu menu;
    MenuState ms;
    ms.s = &S; ms.parts = &R.parts;
    ms.ffmpeg = findFfmpeg();
    ms.musicReady = !song.empty();
    ms.music = ms.musicReady ? "READY" : "MISSING";
    ms.tl = tl;
    bool dirty = false;   // soundtrack needs a rebuild
    std::atomic<int> dl{0};   // 0 idle, 1 downloading, 2 done ok, 3 failed
    std::string dlErr;
    std::vector<float> dlSong;
    std::thread dlThread;

    AudioOut ao;
    ao.mix = &st.mix;
    SDL_AudioSpec spec{SDL_AUDIO_F32, 2, SR};
    SDL_AudioStream* as = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audioCb, &ao);
    if (as) SDL_ResumeAudioStreamDevice(as);
    SDL_GL_SetSwapInterval(1);
    SDL_StartTextInput(win);
    Screen scr;
    Export ex;
    std::string exWav;
    bool paused = false, run = true, fs = false;
    uint64_t lastClick = 0;
    auto start = std::chrono::steady_clock::now();
    auto clock = [&]() { return std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count(); };

    auto rebuild = [&]() {
        tl = S.timeline(R.parts);
        ms.tl = tl;
        std::lock_guard<std::mutex> lk(ao.m);
        st.build(tl, song);
        ao.mix = &st.mix;
        dirty = false;
    };
    auto play = [&](double from) {
        if (dirty) rebuild();
        R.resetDemoHistory();
        std::lock_guard<std::mutex> lk(ao.m);
        ao.pos = (long)(from * SR);
        if (as) SDL_ClearAudioStream(as);
        ao.playing = true;
        paused = false;
        mode = PLAY;
    };
    auto stopPlay = [&]() { std::lock_guard<std::mutex> lk(ao.m); ao.playing = false; mode = MENU; };
    auto startExport = [&]() {
        if (ms.ffmpeg.empty()) { ms.message = "ffmpeg not found: brew install ffmpeg"; return; }
        if (dirty) rebuild();
        mkdir(S.outDir.c_str(), 0755);
        char name[64]; time_t now = time(nullptr);
        strftime(name, sizeof name, "goose-%Y%m%d-%H%M%S.mp4", localtime(&now));
        std::string out = S.outDir + "/" + name;
        exWav = appSupportDir() + "/export-soundtrack.wav";
        st.writeWav(exWav);
        if (!ex.start(ms.ffmpeg, exWav, out, S.master, tl.frames, tl.length)) { ms.message = "could not start ffmpeg"; return; }
        R.resetDemoHistory();
        ms.exporting = true; ms.exportPath = out; ms.exportFrac = 0; ms.message.clear();
        mode = EXPORTING;
    };

    while (run) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_EVENT_QUIT) run = false;
            if (mode == PLAY && e.type == SDL_EVENT_KEY_DOWN) {
                SDL_Keycode k = e.key.key;
                if (k == SDLK_ESCAPE) stopPlay();
                else if (k == SDLK_SPACE) { paused = !paused; ao.playing = !paused; }
                else if (k == SDLK_F) { fs = !fs; SDL_SetWindowFullscreen(win, fs); }
                else if (k == SDLK_LEFT || k == SDLK_RIGHT || k == SDLK_HOME) {
                    long p = k == SDLK_HOME ? 0 : ao.pos + (k == SDLK_LEFT ? -5 : 5) * SR;
                    std::lock_guard<std::mutex> lk(ao.m);
                    ao.pos = std::clamp<long>(p, 0, (long)(tl.length * SR));
                    if (as) SDL_ClearAudioStream(as);
                    R.resetDemoHistory();
                }
                continue;
            }
            if (mode == PLAY) continue;
            MenuAction a = MA_NONE;
            if (e.type == SDL_EVENT_KEY_DOWN) {
                if (e.key.key == SDLK_F && (e.key.mod & SDL_KMOD_GUI)) { fs = !fs; SDL_SetWindowFullscreen(win, fs); }
                a = menu.key((int)e.key.key, (e.key.mod & SDL_KMOD_SHIFT) != 0, ms);
            } else if (e.type == SDL_EVENT_TEXT_INPUT) a = menu.text(e.text.text, ms);
            else if (e.type == SDL_EVENT_MOUSE_WHEEL) a = menu.wheel((int)e.wheel.y, ms);
            else if (e.type == SDL_EVENT_MOUSE_BUTTON_DOWN && e.button.button == SDL_BUTTON_LEFT) {
                // window -> output pixel -> tube uv -> through the same curvature the CRT shader applies -> cell
                int ww, wh; SDL_GetWindowSize(win, &ww, &wh);
                double s = std::min(ww / (double)OUT_W, wh / (double)OUT_H);
                double ox = (e.button.x - (ww - OUT_W * s) / 2) / s, oy = OUT_H - (e.button.y - (wh - OUT_H * s) / 2) / s;
                double scrH = OUT_H * 0.965, scrW = scrH * 4 / 3;
                double ux = (ox - OUT_W / 2.0) / scrW * 2, uy = (oy - OUT_H / 2.0) / scrH * 2;
                double k = std::min(look.fx, 1.6f);
                double cx = ux * (1 + 0.055 * k * uy * uy), cy = uy * (1 + 0.075 * k * ux * ux);
                int col = (int)floor((cx * 0.5 + 0.5) * 80), row = (int)floor((1 - (cy * 0.5 + 0.5)) * 25);
                uint64_t now = SDL_GetTicks();
                a = menu.click(col, row, now - lastClick < 350, ms);
                lastClick = now;
            }
            switch (a) {
                case MA_CHANGED: dirty = true; look = lookOf(S); S.save(settingsPath); tl = S.timeline(R.parts); ms.tl = tl; break;
                case MA_PLAY_ALL: play(0); break;
                case MA_PLAY_FROM: play(menu.playFrom); break;
                case MA_EXPORT: startExport(); break;
                case MA_CANCEL_EXPORT:
                    ex.finish(); remove(ex.path.c_str()); ms.exporting = false; mode = MENU; ms.message = "Export cancelled.";
                    break;
                case MA_QUIT: run = false; break;
                case MA_OPEN_FOLDER: mkdir(S.outDir.c_str(), 0755); system(("open \"" + S.outDir + "\"").c_str()); break;
                case MA_RELOAD: R.loadParts(); S.reconcile(R.parts); dirty = true; tl = S.timeline(R.parts); ms.tl = tl; ms.message = "Parts reloaded."; break;
                case MA_DOWNLOAD:
                    if (dl == 0 || dl == 3) {
                        dl = 1; ms.music = "DOWNLOADING...";
                        if (dlThread.joinable()) dlThread.join();
                        dlThread = std::thread([&]() {
                            std::string e2;
                            if (downloadSong(e2) && decodeSong(downloadedSongPath(), dlSong, e2)) dl = 2;
                            else { dlErr = e2; dl = 3; }
                        });
                    }
                    break;
                default: break;
            }
        }
        if (dl == 2) {   // download finished: swap the song in
            if (dlThread.joinable()) dlThread.join();
            song.swap(dlSong);
            ms.musicReady = true; ms.music = "READY"; ms.message = "Music downloaded."; dirty = true; dl = 0;
        } else if (dl == 3) {
            if (dlThread.joinable()) dlThread.join();
            ms.music = "DOWNLOAD FAILED"; ms.message = dlErr; dl = 4;
        }

        GLuint showFBO;
        if (mode == PLAY) {
            long queued = as ? SDL_GetAudioStreamQueued(as) / 8 : 0;
            double t = std::clamp((ao.pos - queued) / (double)SR, 0.0, tl.length - 1e-3);
            if (t >= tl.length - 0.02) stopPlay();
            R.renderDemo(t, tl, st, look);
            showFBO = R.demoFBO();
        } else {
            if (mode == EXPORTING) {   // render a slice of frames per UI frame
                auto sliceStart = std::chrono::steady_clock::now();
                while (ex.frame < ex.total && std::chrono::steady_clock::now() - sliceStart < std::chrono::milliseconds(60)) {
                    R.renderDemo(ex.frame / (double)FPS, tl, st, look);
                    if (!ex.frameOut(R.demoFBO())) { ms.message = "export failed (ffmpeg pipe)"; ex.frame = ex.total; break; }
                    ex.frame++;
                }
                ms.exportFrac = ex.frame / (double)std::max(1, ex.total);
                ms.exportEta = ex.frame ? ex.elapsed() / ex.frame * (ex.total - ex.frame) : 0;
                if (ex.frame >= ex.total) {
                    int rc = ex.finish();
                    remove(exWav.c_str());
                    ms.exporting = false; mode = MENU;
                    ms.message = rc == 0 ? "Saved " + ex.path : "ffmpeg failed (code " + std::to_string(rc) + ")";
                    if (rc == 0) system(("open -R \"" + ex.path + "\"").c_str());
                }
            }
            menu.draw(scr, ms, clock());
            R.renderText(scr, clock(), look);
            showFBO = R.menuFBO();
        }
        int ww, wh; SDL_GetWindowSizeInPixels(win, &ww, &wh);
        double s = std::min(ww / (double)OUT_W, wh / (double)OUT_H);
        int dw = (int)(OUT_W * s), dh = (int)(OUT_H * s), dx = (ww - dw) / 2, dy = (wh - dh) / 2;
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        glViewport(0, 0, ww, wh);
        glClearColor(0, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, showFBO);
        glBlitFramebuffer(0, 0, OUT_W, OUT_H, dx, dy, dx + dw, dy + dh, GL_COLOR_BUFFER_BIT, GL_LINEAR);
        SDL_GL_SwapWindow(win);
    }
    if (ex.ff) { ex.finish(); remove(ex.path.c_str()); }
    if (dlThread.joinable()) dlThread.join();
    S.save(settingsPath);
    SDL_Quit();
    return 0;
}
