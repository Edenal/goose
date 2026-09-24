// Part registry: every shaders/parts/*.glsl is a demo sequence. Its header comment carries the metadata:
//   // @id plasma            // @name PLASMA          // @split PLASMA (LiveSplit label)
//   // @bars 4               // @order 30             // @default on|off
//   // @inspired ...         // @desc ...             // @str <row 0-15> <text, {EVENT} {LINE2} {LINE3}>
//   // @special finale       (host-driven behaviour)
#pragma once
#include <string>
#include <vector>

struct PartDef {
    std::string id, name, split, inspired, desc, file, special;
    int bars = 4, order = 500;
    bool defaultOn = false;
    std::vector<std::string> strs;   // rows 0..15
    unsigned prog = 0;               // compiled program (0 = not compiled / failed)
    std::string error;               // compile log if it failed
};

std::vector<PartDef> loadPartDefs(const std::string& dir);   // sorted by @order
int findPart(const std::vector<PartDef>& parts, const std::string& id);
