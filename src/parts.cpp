#include "parts.h"
#include <algorithm>
#include <dirent.h>
#include <fstream>
#include <sstream>

static std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r\n"), b = s.find_last_not_of(" \t\r\n");
    return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}

std::vector<PartDef> loadPartDefs(const std::string& dir) {
    std::vector<PartDef> out;
    DIR* d = opendir(dir.c_str());
    if (!d) return out;
    while (dirent* e = readdir(d)) {
        std::string n = e->d_name;
        if (n.size() < 6 || n.substr(n.size() - 5) != ".glsl") continue;
        PartDef p;
        p.file = dir + "/" + n;
        p.id = n.substr(0, n.size() - 5);
        std::ifstream f(p.file);
        std::string line;
        while (std::getline(f, line)) {
            size_t at = line.find("// @");
            if (at != 0) { if (!trim(line).empty() && line.rfind("//", 0) != 0) break; continue; }
            std::string rest = line.substr(4);
            size_t sp = rest.find(' ');
            std::string key = rest.substr(0, sp), val = sp == std::string::npos ? "" : rest.substr(sp + 1);
            if (key == "id") p.id = trim(val);
            else if (key == "name") p.name = trim(val);
            else if (key == "split") p.split = trim(val);
            else if (key == "bars") p.bars = std::max(1, atoi(val.c_str()));
            else if (key == "order") p.order = atoi(val.c_str());
            else if (key == "default") p.defaultOn = trim(val) == "on";
            else if (key == "inspired") p.inspired = trim(val);
            else if (key == "desc") p.desc = trim(val);
            else if (key == "special") p.special = trim(val);
            else if (key == "str") {
                size_t s2 = val.find(' ');
                int row = atoi(val.substr(0, s2).c_str());
                if (row >= 0 && row < 16) {
                    if ((int)p.strs.size() <= row) p.strs.resize(row + 1);
                    p.strs[row] = s2 == std::string::npos ? "" : val.substr(s2 + 1);   // keep leading spaces
                }
            }
        }
        if (p.name.empty()) p.name = p.id;
        if (p.split.empty()) p.split = p.name;
        out.push_back(p);
    }
    closedir(d);
    std::sort(out.begin(), out.end(), [](const PartDef& a, const PartDef& b) {
        return a.order != b.order ? a.order < b.order : a.id < b.id;
    });
    return out;
}

int findPart(const std::vector<PartDef>& parts, const std::string& id) {
    for (size_t i = 0; i < parts.size(); i++) if (parts[i].id == id) return (int)i;
    return -1;
}
