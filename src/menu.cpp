#include "menu.h"
#include <SDL3/SDL_keycode.h>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>

enum { BLK, BLU, GRN, CYN, RED, MAG, BRN, LGR, DGR, LBL, LGN, LCY, LRD, LMG, YEL, WHT };
#define AT(bg, fg) uint8_t(((bg) << 4) | (fg))

// layout (80x25 cells)
static const int SEQ_R0 = 2, SEQ_C0 = 1, SEQ_R1 = 21, SEQ_C1 = 43, SEQ_VIS = SEQ_R1 - SEQ_R0 - 1;
static const int DET_R0 = 2, DET_C0 = 45, DET_R1 = 10, DET_C1 = 78;
static const int OUT_R0 = 11, OUT_C0 = 45, OUT_R1 = 21, OUT_C1 = 78, OUT_N = 9;
static const int VAL_C = 58, SLIDER_C = 59;
enum Opt { O_SCAN, O_FX, O_GLITCH, O_EVENT, O_LINE2, O_LINE3, O_QUALITY, O_MUSIC, O_OUTDIR };
static const char* OPT_LABEL[OUT_N] = {"Scanlines", "Effects", "Glitches", "Event", "Line 2", "Line 3", "Quality", "Music", "Save to"};

static std::string fit(const std::string& s, size_t n) { return s.size() <= n ? s : s.substr(0, n - 1) + "\xAF"; }
static std::string homeShort(const std::string& p) {
    const char* h = getenv("HOME");
    if (h && p.rfind(h, 0) == 0) return "~" + p.substr(strlen(h));
    return p;
}
static std::vector<std::string> wrap(const std::string& s, size_t w) {
    std::vector<std::string> out; std::string line, word;
    auto flush = [&]() { if (!word.empty()) { if (line.size() + word.size() + (line.empty() ? 0 : 1) > w) { out.push_back(line); line.clear(); } line += (line.empty() ? "" : " ") + word; word.clear(); } };
    for (char c : s) { if (c == ' ') flush(); else word += c; }
    flush();
    if (!line.empty()) out.push_back(line);
    return out;
}

std::vector<std::string> Menu::rows(const MenuState& m) const {
    std::vector<std::string> r = {"#boot"};
    for (const std::string& id : m.s->order) r.push_back(id);
    r.push_back("#finale");
    return r;
}

void Menu::scrollToCursor(const MenuState& m) {
    int n = (int)rows(m).size();
    seqRow = std::clamp(seqRow, 0, n - 1);
    if (seqRow < seqScroll) seqScroll = seqRow;
    if (seqRow >= seqScroll + SEQ_VIS) seqScroll = seqRow - SEQ_VIS + 1;
    seqScroll = std::clamp(seqScroll, 0, std::max(0, n - SEQ_VIS));
}

MenuAction Menu::toggleRow(MenuState& m) {
    std::string id = rows(m)[seqRow];
    if (id == "#boot") m.s->boot = !m.s->boot;
    else if (id == "#finale") m.s->finale = !m.s->finale;
    else if (m.s->enabled.count(id)) m.s->enabled.erase(id);
    else m.s->enabled.insert(id);
    return MA_CHANGED;
}

MenuAction Menu::moveRow(MenuState& m, int dir) {
    int i = seqRow - 1;   // index into order (row 0 is the boot)
    auto& o = m.s->order;
    if (i < 0 || i >= (int)o.size() || i + dir < 0 || i + dir >= (int)o.size()) return MA_NONE;
    std::swap(o[i], o[i + dir]);
    seqRow += dir;
    scrollToCursor(m);
    return MA_CHANGED;
}

static int* sliderOf(Settings& s, int opt) { return opt == O_SCAN ? &s.scan : opt == O_FX ? &s.fx : opt == O_GLITCH ? &s.glitch : nullptr; }
static std::string* fieldOf(Settings& s, int opt) { return opt == O_EVENT ? &s.event : opt == O_LINE2 ? &s.line2 : opt == O_LINE3 ? &s.line3 : nullptr; }

MenuAction Menu::adjustOpt(MenuState& m, int delta) {
    if (int* v = sliderOf(*m.s, optRow)) { *v = std::clamp(*v + delta, 0, 200); return MA_CHANGED; }
    if (optRow == O_QUALITY) { m.s->master = !m.s->master; return MA_CHANGED; }
    return MA_NONE;
}

MenuAction Menu::activateOpt(MenuState& m) {
    if (std::string* f = fieldOf(*m.s, optRow)) { editing = true; edit = *f; return MA_NONE; }
    if (optRow == O_QUALITY) return adjustOpt(m, 1);
    if (optRow == O_MUSIC) return m.musicReady ? MA_NONE : MA_DOWNLOAD;
    if (optRow == O_OUTDIR) return MA_OPEN_FOLDER;
    return MA_NONE;
}

MenuAction Menu::key(int k, bool shift, MenuState& m) {
    if (m.exporting) return k == SDLK_ESCAPE ? MA_CANCEL_EXPORT : MA_NONE;
    if (editing) {
        if (k == SDLK_ESCAPE) { editing = false; return MA_NONE; }
        if (k == SDLK_RETURN || k == SDLK_KP_ENTER) { *fieldOf(*m.s, optRow) = edit; editing = false; return MA_CHANGED; }
        if (k == SDLK_BACKSPACE && !edit.empty()) edit.pop_back();
        return MA_NONE;
    }
    int n = (int)rows(m).size();
    switch (k) {
        case SDLK_ESCAPE: return MA_QUIT;
        case SDLK_TAB: pane ^= 1; return MA_NONE;
        case SDLK_F5: return MA_PLAY_ALL;
        case SDLK_F9: return MA_EXPORT;
        case SDLK_F12: return MA_RELOAD;
    }
    if (pane == 0) {
        switch (k) {
            case SDLK_UP: if (shift) return moveRow(m, -1); seqRow--; break;
            case SDLK_DOWN: if (shift) return moveRow(m, 1); seqRow++; break;
            case SDLK_PAGEUP: seqRow -= SEQ_VIS; break;
            case SDLK_PAGEDOWN: seqRow += SEQ_VIS; break;
            case SDLK_HOME: seqRow = 0; break;
            case SDLK_END: seqRow = n - 1; break;
            case SDLK_SPACE: return toggleRow(m);
            case SDLK_RIGHT: pane = 1; break;
            case SDLK_RETURN: case SDLK_KP_ENTER: {
                std::string id = rows(m)[seqRow];
                playFrom = 0;
                if (id == "#finale") playFrom = m.tl.finaleStart >= 0 ? m.tl.finaleStart : 0;
                else if (id != "#boot") {
                    int pi = findPart(*m.parts, id);
                    for (const Cue& c : m.tl.cues) if (c.part == pi) playFrom = c.t0;
                }
                return MA_PLAY_FROM;
            }
        }
        scrollToCursor(m);
        return MA_NONE;
    }
    switch (k) {
        case SDLK_UP: optRow = (optRow + OUT_N - 1) % OUT_N; break;
        case SDLK_DOWN: optRow = (optRow + 1) % OUT_N; break;
        case SDLK_LEFT: if (sliderOf(*m.s, optRow) || optRow == O_QUALITY) return adjustOpt(m, shift ? -1 : -10); pane = 0; break;
        case SDLK_RIGHT: return adjustOpt(m, shift ? 1 : 10);
        case SDLK_RETURN: case SDLK_KP_ENTER: case SDLK_SPACE: return activateOpt(m);
    }
    return MA_NONE;
}

MenuAction Menu::text(const char* utf8, MenuState& m) {
    if (!editing) return MA_NONE;
    for (const char* c = utf8; *c; c++)
        if ((unsigned char)*c >= 32 && (unsigned char)*c < 127 && edit.size() < 30) edit += (char)toupper(*c);
    (void)m;
    return MA_NONE;
}

MenuAction Menu::click(int col, int row, bool dbl, MenuState& m) {
    if (m.exporting || editing) return MA_NONE;
    if (row > SEQ_R0 && row < SEQ_R1 && col > SEQ_C0 && col < SEQ_C1) {
        pane = 0;
        int r = seqScroll + row - SEQ_R0 - 1;
        if (r >= (int)rows(m).size()) return MA_NONE;
        seqRow = r;
        if (col >= 3 && col <= 5) return toggleRow(m);
        return dbl ? key(SDLK_RETURN, false, m) : MA_NONE;
    }
    if (row > OUT_R0 && row < OUT_R1 && col > OUT_C0 && col < OUT_C1) {
        pane = 1;
        optRow = row - OUT_R0 - 1;
        if (int* v = sliderOf(*m.s, optRow)) {
            if (col >= SLIDER_C && col < SLIDER_C + 10) { *v = (col - SLIDER_C + 1) * 20; return MA_CHANGED; }
            return MA_NONE;
        }
        return activateOpt(m);
    }
    if (row == 24) {   // help bar: F5 Play / F9 Export are clickable
        if (col >= helpCol[0] && col < helpCol[1]) return MA_PLAY_ALL;
        if (col >= helpCol[5] && col < helpCol[6]) return MA_EXPORT;
    }
    return MA_NONE;
}

MenuAction Menu::wheel(int dy, MenuState& m) {
    seqScroll = std::clamp(seqScroll - dy * 3, 0, std::max(0, (int)rows(m).size() - SEQ_VIS));
    return MA_NONE;
}

static void dialogBox(Screen& s, int r0, int c0, int r1, int c1, const char* title, bool shadow = false) {
    s.box(r0, c0, r1, c1, AT(LGR, BLK), true);
    if (shadow) s.shadow(r0, c0, r1, c1);
    std::string t = std::string(" ") + title + " ";
    s.center(r0, t.c_str(), AT(LGR, BLU), c0, c1);
}

void Menu::draw(Screen& s, const MenuState& m, double t) {
    const Settings& S = *m.s;
    const auto& parts = *m.parts;
    s.clear(AT(BLU, LBL), 0xB0);
    s.curRow = -1;
    s.fill(0, 0, 0, 79, ' ', AT(LGR, BLK));
    s.put(0, 1, "GOOSE SETUP", AT(LGR, BLK));
    s.put(0, 14, "Glitchy Old-School Output Scene Engine", AT(LGR, DGR));
    s.put(0, 67, "v1.0  Honk!", AT(LGR, BLK));

    // ---- sequences
    dialogBox(s, SEQ_R0, SEQ_C0, SEQ_R1, SEQ_C1, "Sequences");
    std::vector<std::string> R = rows(m);
    for (int v = 0; v < SEQ_VIS; v++) {
        int i = seqScroll + v, r = SEQ_R0 + 1 + v;
        if (i >= (int)R.size()) break;
        const std::string& id = R[i];
        bool on, err = false; std::string name; double len = 0, start = -1;
        if (id == "#boot") { on = S.boot; name = "BOOT SEQUENCE (DOS)"; len = BOOT_END; if (on) start = 0; }
        else if (id == "#finale") { on = S.finale; name = "FINALE (LOGO)"; len = FINALE_LEAD_BARS * BAR + (OFF_AFTER_HIT_FRAMES + END_AFTER_OFF_FRAMES) / (double)FPS; start = m.tl.finaleStart; }
        else {
            int pi = findPart(parts, id);
            on = S.enabled.count(id) > 0;
            name = parts[pi].name; len = parts[pi].bars * BAR; err = parts[pi].prog == 0;
            for (const Cue& c : m.tl.cues) if (c.part == pi) start = c.t0;
        }
        bool sel = i == seqRow;
        uint8_t base = sel ? (pane == 0 ? AT(BLU, WHT) : AT(CYN, BLK)) : AT(LGR, on ? BLK : DGR);
        s.fill(r, SEQ_C0 + 1, r, SEQ_C1 - 1, ' ', base);
        s.put(r, 3, on ? "[\xFB]" : "[ ]", sel ? base : AT(LGR, on ? BLU : DGR));
        s.put(r, 7, fit(name, 22).c_str(), base);
        char b[32];
        snprintf(b, sizeof b, "%5.1fs", len);
        s.put(r, 30, b, base);
        if (err) s.put(r, 37, " ERROR", sel ? base : AT(LGR, RED));
        else if (on && start >= 0) s.put(r, 37, fmtTime(start).c_str(), base);
        else s.put(r, 37, "   -  ", base);
    }
    if (seqScroll > 0) s.putc(SEQ_R0, SEQ_C1 - 2, 0x18, AT(LGR, BLU));
    if (seqScroll + SEQ_VIS < (int)R.size()) s.putc(SEQ_R1, SEQ_C1 - 2, 0x19, AT(LGR, BLU));

    // ---- details of the selected row
    dialogBox(s, DET_R0, DET_C0, DET_R1, DET_C1, "Details");
    {
        const std::string& id = R[std::clamp(seqRow, 0, (int)R.size() - 1)];
        std::string name, insp, desc; int bars = 0; std::string error;
        if (id == "#boot") { name = "BOOT SEQUENCE"; insp = "90s PC: BIOS, CMOS, DOS, SETUP.EXE"; desc = "Power-on, POST, Sound Blaster setup; the music starts on Test. Easter eggs: Goosebert, Plum, over estimate."; }
        else if (id == "#finale") { name = "FINALE"; insp = "GOOSE original"; desc = "The cube lands on the logo on the song's final hit; event text types in; CRT power-off."; bars = FINALE_LEAD_BARS; }
        else { const PartDef& p = parts[findPart(parts, id)]; name = p.name; insp = p.inspired; desc = p.desc; bars = p.bars; error = p.error; }
        const int W = DET_C1 - DET_C0 - 3;
        s.put(DET_R0 + 1, DET_C0 + 2, fit(name, W).c_str(), AT(LGR, BLU));
        auto il = wrap("\x10 " + insp, W);
        int r = DET_R0 + 2;
        for (size_t i = 0; i < il.size() && i < 2; i++) s.put(r++, DET_C0 + 2, il[i].c_str(), AT(LGR, DGR));
        auto dl = wrap(error.empty() ? desc : "SHADER ERROR: " + error, W);
        for (size_t i = 0; i < dl.size() && r < DET_R1 - 1; i++) s.put(r++, DET_C0 + 2, fit(dl[i], W).c_str(), AT(LGR, error.empty() ? BLK : RED));
        char b[64];
        if (bars) snprintf(b, sizeof b, "%d bar%s  %.1f s", bars, bars > 1 ? "s" : "", bars * BAR);
        else snprintf(b, sizeof b, "%.1f s", BOOT_END);
        s.put(DET_R1 - 1, DET_C0 + 2, b, AT(LGR, DGR));
    }

    // ---- output options
    dialogBox(s, OUT_R0, OUT_C0, OUT_R1, OUT_C1, "Output");
    for (int i = 0; i < OUT_N; i++) {
        int r = OUT_R0 + 1 + i;
        bool sel = pane == 1 && i == optRow;
        uint8_t base = sel ? AT(BLU, WHT) : AT(LGR, BLK);
        s.fill(r, OUT_C0 + 1, r, OUT_C1 - 1, ' ', base);
        s.put(r, OUT_C0 + 2, OPT_LABEL[i], base);
        int* v = sliderOf(*m.s, i);
        if (v) {
            s.putc(r, VAL_C, '[', base);
            for (int k = 0; k < 10; k++) s.putc(r, SLIDER_C + k, k < (*v + 10) / 20 ? 0xDB : 0xB0, sel ? AT(BLU, YEL) : AT(LGR, BLU));
            s.putc(r, SLIDER_C + 10, ']', base);
            char b[16]; snprintf(b, sizeof b, "%3d%%", *v);
            s.put(r, SLIDER_C + 12, b, base);
        } else if (const std::string* f = fieldOf(*m.s, i)) {
            bool ed = editing && sel;
            std::string val = ed ? edit : *f;
            if (ed && val.size() > 19) val = val.substr(val.size() - 19);   // keep the cursor end in view
            s.put(r, VAL_C, (ed ? val : fit(val, 20)).c_str(), ed ? AT(BLK, YEL) : base);
            if (ed) { s.curRow = r; s.curCol = VAL_C + (int)std::min<size_t>(val.size(), 19); }
        } else if (i == O_QUALITY) {
            s.put(r, VAL_C, S.master ? "MASTER  CRF 14" : "WEB  24 Mbps", base);
        } else if (i == O_MUSIC) {
            s.put(r, VAL_C, fit(m.music, 20).c_str(), sel ? base : AT(LGR, m.musicReady ? GRN : RED));
        } else if (i == O_OUTDIR) {
            s.put(r, VAL_C, fit(homeShort(S.outDir), 20).c_str(), base);
        }
    }

    // ---- summary, message, help
    int nParts = (int)m.tl.cues.size();
    char b[160];
    snprintf(b, sizeof b, " TOTAL %s   %d PART%s   SONG %s-%s   %s 1080p60", fmtTime(m.tl.length).c_str(), nParts,
             nParts == 1 ? "" : "S", fmtTime(m.tl.songStart).c_str(), fmtTime(m.tl.songAt(m.tl.length)).c_str(),
             S.master ? "MASTER" : "WEB");
    s.fill(22, 0, 22, 79, ' ', AT(BLU, YEL));
    s.put(22, 0, b, AT(BLU, YEL));
    s.fill(23, 0, 23, 79, ' ', AT(BLU, LCY));
    std::string msg = m.message;
    if (msg.empty() && m.tl.songTooShort) msg = "Longer than the song: the ending won't land on the final hit.";
    if (msg.empty() && m.ffmpeg.empty()) msg = "Export needs ffmpeg:  brew install ffmpeg";
    if (msg.empty() && !m.musicReady) msg = "Music missing: select Music and press Enter to download it.";
    s.put(23, 1, fit(msg, 78).c_str(), AT(BLU, m.tl.songTooShort || m.ffmpeg.empty() || !m.musicReady ? LRD : LCY));
    s.fill(24, 0, 24, 79, ' ', AT(LGR, BLK));
    struct H { const char* k; const char* t; } help[] = {
        {"F5", "Play"}, {"\x11\xD9", "From here"}, {"Space", "On/off"}, {"Shift+\x18\x19", "Move"},
        {"Tab", "Pane"}, {"F9", "Export"}, {"Esc", "Quit"}};
    int hc = 2;
    for (const H& h : help) {
        s.put(24, hc, h.k, AT(LGR, RED));
        s.put(24, hc + (int)strlen(h.k) + 1, h.t, AT(LGR, BLK));
        helpCol[&h - help] = hc;
        hc += (int)strlen(h.k) + (int)strlen(h.t) + 2;
    }

    // ---- export progress
    if (m.exporting) {
        dialogBox(s, 8, 12, 15, 67, "Exporting", true);
        int w = 50, n = (int)(m.exportFrac * w + 0.5);
        for (int k = 0; k < w; k++) s.putc(10, 15 + k, k < n ? 0xDB : 0xB0, AT(LGR, k < n ? BLU : DGR));
        snprintf(b, sizeof b, "%5.1f%%   %d / %d frames   ETA %s", m.exportFrac * 100, (int)(m.exportFrac * m.tl.frames),
                 m.tl.frames, fmtTime(m.exportEta).c_str());
        s.put(11, 15, b, AT(LGR, BLK));
        s.put(12, 15, fit(homeShort(m.exportPath), 50).c_str(), AT(LGR, DGR));
        s.put(14, 15, "Esc cancels", AT(LGR, DGR));
    }
    (void)t;
}
