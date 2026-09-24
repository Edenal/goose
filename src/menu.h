// GOOSE SETUP: the settings menu, drawn in VGA text mode like a 90s game setup program.
#pragma once
#include <string>
#include <vector>
#include "parts.h"
#include "settings.h"
#include "textmode.h"
#include "timeline.h"

enum MenuAction { MA_NONE, MA_CHANGED, MA_PLAY_ALL, MA_PLAY_FROM, MA_EXPORT, MA_CANCEL_EXPORT, MA_QUIT,
                  MA_DOWNLOAD, MA_OPEN_FOLDER, MA_RELOAD };

struct MenuState {                 // everything the menu shows that it doesn't own
    Settings* s = nullptr;
    const std::vector<PartDef>* parts = nullptr;
    Timeline tl;
    std::string music;             // READY / MISSING / DOWNLOADING... / error
    bool musicReady = false;
    std::string ffmpeg;            // "" = not found
    bool exporting = false;
    double exportFrac = 0, exportEta = 0;
    std::string exportPath, message;
};

struct Menu {
    int pane = 0;                  // 0 = sequences, 1 = output
    int seqRow = 0, seqScroll = 0, optRow = 0;
    bool editing = false;
    std::string edit;
    double playFrom = 0;           // set with MA_PLAY_FROM

    MenuAction key(int key, bool shift, MenuState& m);   // SDL keycodes
    MenuAction text(const char* utf8, MenuState& m);
    MenuAction click(int col, int row, bool dbl, MenuState& m);
    MenuAction wheel(int dy, MenuState& m);
    void draw(Screen& s, const MenuState& m, double t);

private:
    std::vector<std::string> rows(const MenuState& m) const;   // "#boot", part ids..., "#finale"
    MenuAction toggleRow(MenuState& m);
    MenuAction moveRow(MenuState& m, int dir);
    MenuAction activateOpt(MenuState& m);
    MenuAction adjustOpt(MenuState& m, int delta);
    void scrollToCursor(const MenuState& m);
};
