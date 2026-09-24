#include "music.h"
#include "settings.h"
#include <cstdio>
#include <cstdlib>
#include <sys/stat.h>

#define MINIMP3_IMPLEMENTATION
#define MINIMP3_FLOAT_OUTPUT
#include "third_party/minimp3_ex.h"

static bool exists(const std::string& p) { struct stat st; return stat(p.c_str(), &st) == 0 && st.st_size > 100000; }

std::string downloadedSongPath() { return appSupportDir() + "/" + SONG_FILE; }

std::string findSong(const std::string& resDir) {
    for (const std::string& p : {resDir + "/assets/" + SONG_FILE, downloadedSongPath()})
        if (exists(p)) return p;
    return "";
}

bool downloadSong(std::string& err) {
    std::string dst = downloadedSongPath(), tmp = dst + ".part";
    std::string cmd = "/usr/bin/curl -sSL --fail --max-time 120 -o \"" + tmp + "\" \"" + SONG_URL + "\" 2>&1";
    FILE* p = popen(cmd.c_str(), "r");
    if (!p) { err = "cannot run curl"; return false; }
    char buf[256]; std::string out;
    while (fgets(buf, sizeof buf, p)) out += buf;
    int rc = pclose(p);
    if (rc != 0 || !exists(tmp)) { err = out.empty() ? "download failed" : out; remove(tmp.c_str()); return false; }
    rename(tmp.c_str(), dst.c_str());
    return true;
}

bool decodeSong(const std::string& path, std::vector<float>& out, std::string& err) {
    mp3dec_t d;
    mp3dec_file_info_t info;
    if (mp3dec_load(&d, path.c_str(), &info, nullptr, nullptr) || !info.buffer) { err = "cannot decode " + path; return false; }
    if (info.channels != 2 || info.hz != 44100) { err = "unexpected mp3 format"; free(info.buffer); return false; }
    out.assign(info.buffer, info.buffer + info.samples);
    free(info.buffer);
    return true;
}
