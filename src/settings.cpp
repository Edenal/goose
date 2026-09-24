#include "settings.h"
#include "parts.h"
#include "timeline.h"
#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <sys/stat.h>

std::string appSupportDir() {
    const char* home = getenv("HOME");
    std::string d = std::string(home ? home : ".") + "/Library/Application Support/GOOSE";
    mkdir((std::string(home ? home : ".") + "/Library/Application Support").c_str(), 0755);
    mkdir(d.c_str(), 0755);
    return d;
}

void Settings::reconcile(const std::vector<PartDef>& parts) {
    bool fresh = order.empty();
    std::vector<std::string> keep;
    for (const std::string& id : order) {
        int i = findPart(parts, id);
        if (i >= 0 && parts[i].special != "finale") keep.push_back(id);
    }
    for (const PartDef& p : parts) {
        if (p.special == "finale") continue;
        if (std::find(keep.begin(), keep.end(), p.id) == keep.end()) {
            keep.push_back(p.id);                 // new part: appended (by @order), default state
            if (p.defaultOn) enabled.insert(p.id);
        }
    }
    order = keep;
    for (auto it = enabled.begin(); it != enabled.end();)
        it = findPart(parts, *it) < 0 ? enabled.erase(it) : std::next(it);
    (void)fresh;
    if (outDir.empty()) {
        const char* home = getenv("HOME");
        outDir = std::string(home ? home : ".") + "/Movies/GOOSE";
    }
}

std::vector<int> Settings::playOrder(const std::vector<PartDef>& parts) const {
    std::vector<int> v;
    for (const std::string& id : order)
        if (enabled.count(id)) { int i = findPart(parts, id); if (i >= 0 && parts[i].special != "finale") v.push_back(i); }
    return v;
}

int Settings::finaleIndex(const std::vector<PartDef>& parts) const {
    for (size_t i = 0; i < parts.size(); i++) if (parts[i].special == "finale") return (int)i;
    return -1;
}

Timeline Settings::timeline(const std::vector<PartDef>& parts) const {
    std::vector<int> ord = playOrder(parts), bars;
    for (int i : ord) bars.push_back(parts[i].bars);
    return buildTimeline(boot, finale, ord, bars, finaleIndex(parts));
}

static std::string join(const std::vector<std::string>& v) {
    std::string s;
    for (size_t i = 0; i < v.size(); i++) s += (i ? "," : "") + v[i];
    return s;
}
static std::vector<std::string> split(const std::string& s) {
    std::vector<std::string> v; std::stringstream ss(s); std::string t;
    while (std::getline(ss, t, ',')) if (!t.empty()) v.push_back(t);
    return v;
}

bool Settings::load(const std::string& path) {
    std::ifstream f(path);
    if (!f) return false;
    std::string line;
    while (std::getline(f, line)) {
        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string k = line.substr(0, eq), v = line.substr(eq + 1);
        if (k == "boot") boot = v == "1";
        else if (k == "finale") finale = v == "1";
        else if (k == "scan") scan = std::clamp(atoi(v.c_str()), 0, 200);
        else if (k == "fx") fx = std::clamp(atoi(v.c_str()), 0, 200);
        else if (k == "glitch") glitch = std::clamp(atoi(v.c_str()), 0, 200);
        else if (k == "event") event = v;
        else if (k == "line2") line2 = v;
        else if (k == "line3") line3 = v;
        else if (k == "quality") master = v == "master";
        else if (k == "outdir") outDir = v;
        else if (k == "order") order = split(v);
        else if (k == "enabled") { auto e = split(v); enabled = std::set<std::string>(e.begin(), e.end()); }
    }
    return true;
}

bool Settings::save(const std::string& path) const {
    std::ofstream f(path);
    if (!f) return false;
    f << "boot=" << (boot ? 1 : 0) << "\nfinale=" << (finale ? 1 : 0) << "\nscan=" << scan << "\nfx=" << fx
      << "\nglitch=" << glitch << "\nevent=" << event << "\nline2=" << line2 << "\nline3=" << line3
      << "\nquality=" << (master ? "master" : "web") << "\noutdir=" << outDir << "\norder=" << join(order)
      << "\nenabled=" << join(std::vector<std::string>(enabled.begin(), enabled.end())) << "\n";
    return true;
}
