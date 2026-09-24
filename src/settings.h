// User settings (GOOSE SETUP), persisted as a small INI in ~/Library/Application Support/GOOSE/.
#pragma once
#include <set>
#include <string>
#include <vector>

struct PartDef;
struct Timeline;

struct Settings {
    bool boot = true, finale = true;
    std::vector<std::string> order;     // every non-finale part id, in play order
    std::set<std::string> enabled;
    int scan = 100, fx = 100, glitch = 100;   // sliders, percent (100 = the reference look), 0..200
    std::string event = "ESA WINTER 2027", line2 = "ESAMARATHON.COM", line3 = "TWITCH.TV/ESAMARATHON";
    bool master = false;                // export quality: false = web (24 Mbps), true = master (CRF 14)
    std::string outDir;

    void reconcile(const std::vector<PartDef>& parts);   // add new parts, drop missing ones, apply defaults
    bool load(const std::string& path);
    bool save(const std::string& path) const;
    Timeline timeline(const std::vector<PartDef>& parts) const;
    std::vector<int> playOrder(const std::vector<PartDef>& parts) const;   // enabled part indices (no finale)
    int finaleIndex(const std::vector<PartDef>& parts) const;
};

std::string appSupportDir();   // ~/Library/Application Support/GOOSE (created)
