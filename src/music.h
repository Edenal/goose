// The song is not redistributed with GOOSE: it is found locally or downloaded from Remix.Kwed.Org.
#pragma once
#include <atomic>
#include <string>
#include <vector>

constexpr const char* SONG_URL =
    "https://remix.kwed.org/files/RKOfiles/machinae%20supremacy%20-%20sidology%20episode%201%20-%20sid%20evolution%20(128kbs).mp3";
constexpr const char* SONG_FILE = "sidology-sid-evolution.mp3";

std::string findSong(const std::string& resDir);      // "" if not found
std::string downloadedSongPath();                      // where a download lands (Application Support)
bool downloadSong(std::string& err);                   // blocking; run it on a thread
// decode to interleaved stereo float at 44.1 kHz (minimp3; bit-identical to ffmpeg's decode for this file)
bool decodeSong(const std::string& path, std::vector<float>& out, std::string& err);
