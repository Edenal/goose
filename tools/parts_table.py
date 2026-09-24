#!/usr/bin/env python3
"""Regenerate the parts table in README.md from the @ headers in shaders/parts/*.glsl."""
import glob, os, re
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rows = []
for f in glob.glob(os.path.join(ROOT, "shaders/parts/*.glsl")):
    meta = {}
    for line in open(f):
        m = re.match(r"// @(\w+) ?(.*)", line)
        if m: meta.setdefault(m.group(1), m.group(2).strip())
        elif line.strip() and not line.startswith("//"): break
    rows.append((int(meta.get("order", 500)), meta))
rows.sort(key=lambda r: r[0])
out = ["| Part | Bars | Inspired by | What it does | Default |", "|---|---|---|---|---|"]
for _, m in rows:
    out.append(f"| **{m.get('name')}** (`{m.get('id')}`) | {m.get('bars', 4)} | {m.get('inspired', '')} | {m.get('desc', '')} | {'on' if m.get('default') == 'on' else 'off'} |")
table = "\n".join(out)
readme = os.path.join(ROOT, "README.md")
s = open(readme).read()
start, end = "<!-- parts:start -->", "<!-- parts:end -->"
if start in s:
    s = s[:s.index(start) + len(start)] + "\n" + table + "\n" + s[s.index(end):]
else:
    s = s.replace("PARTS_TABLE", start + "\n" + table + "\n" + end)
open(readme, "w").write(s)
print(f"{len(rows)} parts")
