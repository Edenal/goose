#!/usr/bin/env python3
"""Export one GOOSE part as a single self-contained web page that loops it (WebGL2, no external files).

  python3 tools/web_export.py halloween out/web/esa-halloween.html [--hold 6] [--title "..."] [--desc "..."]

The page runs the same shaders as the app: common.glsl + the part + part_main.glsl at 320x240, then the
halation blur and crt.frag at window size. Silent (the song can't be embedded); the beat is simulated so
beat-driven motion stays alive. The CRT powers on when the page loads and every loop restart gets a static
burst, like a scene cut in the app. prefers-reduced-motion skips both flashes.
"""
import argparse, base64, html, io, json, os, re
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = lambda *p: os.path.join(ROOT, *p)

ap = argparse.ArgumentParser()
ap.add_argument("part"); ap.add_argument("out")
ap.add_argument("--hold", type=float, default=6.0, help="seconds to hold the finished frame before looping")
ap.add_argument("--title", default=None); ap.add_argument("--desc", default=None)
ap.add_argument("--event", default="ESA WINTER 2027"); ap.add_argument("--line2", default="ESAMARATHON.COM")
ap.add_argument("--line3", default="TWITCH.TV/ESAMARATHON")
ap.add_argument("--music", default=None, help="audio file copied next to the page as music.<ext>, looped on demand")
ap.add_argument("--credit", default="", help="music credit shown on the page (required for CC-BY tracks)")
ap.add_argument("--credit-url", default="", help="link for the credit")
ap.add_argument("--volume", type=float, default=0.6)
ap.add_argument("--playlist", default=None, help="JSON: music playlist (crossfaded) + ambience bed, see out/web/halloween-playlist.json")
a = ap.parse_args()

src = open(R("shaders/parts", a.part + ".glsl")).read()
meta, strs = {}, [""] * 40
for line in src.splitlines():
    m = re.match(r"// @(\w+) ?(.*)", line)
    if not m:
        if line.strip() and not line.startswith("//"): break
        continue
    k, v = m.group(1), m.group(2)
    if k == "str":
        row, _, text = v.partition(" ")
        strs[int(row)] = text
    else:
        meta[k] = v.strip()
sub = lambda s: s.replace("{EVENT}", a.event).replace("{LINE2}", a.line2).replace("{LINE3}", a.line3)
strs = [sub(s)[:256] for s in strs]
strs[16], strs[17], strs[18] = a.event, a.line2, a.line3

ES = "#version 300 es\nprecision highp float;\nprecision highp int;\nprecision highp sampler2D;\n"
def es(s): return re.sub(r"^#version 410 core\n", ES, s)
part_fs = es(open(R("shaders/common.glsl")).read()) + "\n" + src + "\n" + open(R("shaders/part_main.glsl")).read()
blur_fs = es(open(R("shaders/blur.frag")).read())
crt_fs = es(open(R("shaders/crt.frag")).read()).replace(
    "float scrH = uOut.y * 0.965, scrW = scrH * 4.0 / 3.0;",
    "float scrH = min(uOut.y, uOut.x * 0.75) * 0.965, scrW = scrH * 4.0 / 3.0;   // web: fit any window")
assert "min(uOut.y, uOut.x * 0.75)" in crt_fs

def png_b64(path, size=None):
    im = Image.open(path).convert("RGBA")
    if size: im = im.resize((size, size), Image.LANCZOS)
    b = io.BytesIO(); im.save(b, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(b.getvalue()).decode()
font = png_b64(R("assets/gen/font_bios8x8.png"))
logo = png_b64(R("assets/gen/logo_cube.png"), 512)
bars = int(meta.get("bars", 4))
import subprocess
title = a.title or meta.get("name", a.part).title()
def lufs(path):   # integrated loudness (EBU R128)
    out = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128", "-f", "null", "-"], capture_output=True, text=True).stderr
    vals = re.findall(r"^\s+I:\s+(-?[\d.]+) LUFS", out, re.M)
    return float(vals[-1]) if vals else -18.0
PL = None
if a.playlist:
    PL = json.load(open(a.playlist))
elif a.music:
    PL = {"cross": 2.0, "master": a.volume / 0.6 * 0.85, "music": [{"file": a.music, "credit": a.credit, "url": a.credit_url, "repeat": 1}], "ambience": []}
tracks = []   # (source file, published base name)
if PL:
    for kind, target, key in (("music", -18.0, "m"), ("ambience", -33.0, "a")):
        for i, t in enumerate(PL.get(kind, [])):
            t["name"] = f"{key}{i}"
            t["gain"] = round(min(2.5, 10 ** ((target - lufs(t["file"]) + t.get("gain_db", 0)) / 20)), 3)
            tracks.append((t["file"], t["name"]))
    pl_js = {"cross": PL.get("cross", 2.0), "master": PL.get("master", 0.85),
             "music": [{k: t.get(k) for k in ("name", "credit", "url", "repeat", "trimEnd", "gain")} for t in PL["music"]],
             "amb": [{k: t.get(k) for k in ("name", "credit", "url", "gain")} for t in PL.get("ambience", [])]}
else:
    pl_js = None
sound_html = ('<button id="snd" aria-pressed="false" title="Sound (M)">&#9834; SOUND OFF</button>'
              '<a id="credit" target="_blank" rel="noopener"></a>'
              '<div id="gate" role="button" tabindex="0"><span>&#9654; CLICK TO POWER ON</span><small>sound on &middot; {}</small></div>'
              .format(html.escape(title))) if PL else ""
title = a.title or meta.get("name", a.part).title()
desc = a.desc or meta.get("desc", "")

page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<meta name="description" content="{html.escape(desc)}">
<meta property="og:title" content="{html.escape(title)}">
<meta property="og:description" content="{html.escape(desc)}">
<style>
  html, body {{ margin: 0; height: 100%; background: #000; overflow: hidden; }}
  canvas {{ display: block; width: 100vw; height: 100vh; }}
  #fallback {{ display: none; color: #fdbb1c; font: 16px/1.5 monospace; padding: 2em; white-space: pre-line; }}
  #snd {{ position: fixed; right: 14px; bottom: 12px; font: 12px/1 monospace; letter-spacing: .08em; color: #fdbb1c;
         background: rgba(20,12,30,.75); border: 1px solid #fdbb1c55; border-radius: 3px; padding: 7px 10px; cursor: pointer; }}
  #snd[aria-pressed="true"] {{ color: #1b1028; background: #fdbb1c; }}
  #hint {{ position: fixed; left: 50%; bottom: 12px; transform: translateX(-50%); font: 12px monospace; letter-spacing: .15em;
          color: #fff6dd; opacity: .8; transition: opacity 1.5s; pointer-events: none; }}
  #credit {{ position: fixed; left: 14px; bottom: 12px; font: 11px monospace; color: #c7adff; opacity: .55; text-decoration: none; }}
  #credit:hover {{ opacity: 1; }}
  #gate {{ position: fixed; inset: 0; display: none; flex-direction: column; align-items: center; justify-content: center; gap: 14px;
          background: #000; cursor: pointer; color: #fdbb1c; font: 20px monospace; letter-spacing: .2em; text-align: center; }}
  #gate:focus {{ outline: none; }}
  #gate span {{ animation: blink 1.1s steps(2, start) infinite; }}
  #gate small {{ font-size: 12px; letter-spacing: .12em; color: #c7adff; opacity: .7; }}
  @keyframes blink {{ to {{ visibility: hidden; }} }}
</style>
</head>
<body>
<canvas id="c" aria-label="{html.escape(desc)}" role="img"></canvas>
<div id="fallback">{html.escape(desc)}</div>
{sound_html}
<script>
// {html.escape(title)} - generated by GOOSE (github.com/Edenal/goose), part "{a.part}". Same shaders as the app.
const PART_FS = {json.dumps(part_fs)};
const BLUR_FS = {json.dumps(blur_fs)};
const CRT_FS = {json.dumps(crt_fs)};
const STRS = {json.dumps(strs)};
const FONT = "{font}";
const LOGO = "{logo}";
const BEAT = 60 / 90, LEN = {bars} * 4 * BEAT, HOLD = {a.hold}, PERIOD = LEN + HOLD;
const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
const PL = {json.dumps(pl_js)};

const canvas = document.getElementById("c");
const gl = canvas.getContext("webgl2", {{ antialias: false, alpha: false }});
if (!gl) {{ canvas.style.display = "none"; document.getElementById("fallback").style.display = "block"; throw new Error("no WebGL2"); }}

const VS = "#version 300 es\\nout vec2 vUV;\\nvoid main(){{vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);vUV=p;gl_Position=vec4(p*2.0-1.0,0.0,1.0);}}";
function program(fs, name) {{
  const p = gl.createProgram();
  for (const [type, s] of [[gl.VERTEX_SHADER, VS], [gl.FRAGMENT_SHADER, fs]]) {{
    const sh = gl.createShader(type); gl.shaderSource(sh, s); gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(name + ": " + gl.getShaderInfoLog(sh));
    gl.attachShader(p, sh);
  }}
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(name + ": " + gl.getProgramInfoLog(p));
  const u = {{}};
  const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
  for (let i = 0; i < n; i++) {{ const nm = gl.getActiveUniform(p, i).name.replace(/\\[0\\]$/, ""); u[nm] = gl.getUniformLocation(p, nm); }}
  return {{ p, u }};
}}
function tex(w, h, filter, data = null, fmt = gl.RGBA8, f2 = gl.RGBA) {{
  const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t);
  gl.texImage2D(gl.TEXTURE_2D, 0, fmt, w, h, 0, f2, gl.UNSIGNED_BYTE, data);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  return t;
}}
function fbo(w, h, filter) {{
  const t = tex(w, h, filter), f = gl.createFramebuffer();
  gl.bindFramebuffer(gl.FRAMEBUFFER, f); gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
  return {{ f, t }};
}}
function image(url, mip) {{
  return new Promise(ok => {{ const im = new Image(); im.onload = () => {{
    const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, im);
    if (mip) gl.generateMipmap(gl.TEXTURE_2D);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, mip ? gl.LINEAR_MIPMAP_LINEAR : gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, mip ? gl.LINEAR : gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    ok(t); }}; im.src = url; }});
}}

const P = program(PART_FS, "part"), B = program(BLUR_FS, "blur"), C = program(CRT_FS, "crt");
gl.bindVertexArray(gl.createVertexArray());
const gfx = fbo(320, 240, gl.NEAREST), glowA = fbo(320, 240, gl.LINEAR), glowB = fbo(320, 240, gl.LINEAR);
const dummy = tex(1, 1, gl.NEAREST, new Uint8Array([0, 0, 0, 255]));
const sbuf = new Uint8Array(256 * 40).fill(32), lens = new Int32Array(40);
STRS.forEach((s, r) => {{ for (let i = 0; i < s.length && i < 256; i++) sbuf[r * 256 + i] = s.charCodeAt(i) & 255; lens[r] = Math.min(256, s.length); }});
gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
const strTex = tex(256, 40, gl.NEAREST, sbuf, gl.R8, gl.RED);

function bind(prog, name, unit, t) {{ if (prog.u[name] === undefined) return; gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, t); gl.uniform1i(prog.u[name], unit); }}
function set(prog, name, ...v) {{ const l = prog.u[name]; if (l === undefined) return; gl["uniform" + v.length + "f"](l, ...v); }}
const ID3 = new Float32Array([1, 0, 0, 0, 1, 0, 0, 0, 1]);

function resize() {{
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  let w = Math.floor(innerWidth * dpr), h = Math.floor(innerHeight * dpr);
  const s = Math.min(1, 2560 / Math.max(w, h)); w = Math.floor(w * s); h = Math.floor(h * s);
  if (canvas.width !== w || canvas.height !== h) {{ canvas.width = w; canvas.height = h; }}
}}

// ---- soundtrack: a crossfading music playlist over a looping ambience bed (Web Audio, loudness-normalised).
// Browsers block sound until the first interaction, so where autoplay is blocked the page opens on a powered-off
// tube: the click that powers the CRT on also starts the music. Where autoplay works (OBS browser source, kiosk)
// both start at once.
let showStart = null;                       // set when the show (CRT power-on + music) begins
const SOUND = PL && location.protocol.startsWith("http") && window.AudioContext;
if (SOUND) {{
  const btn = document.getElementById("snd"), credit = document.getElementById("credit"), gate = document.getElementById("gate");
  const EXT = new Audio().canPlayType('audio/ogg; codecs="opus"') ? ".ogg" : ".mp3";
  const ac = new AudioContext();
  const comp = ac.createDynamicsCompressor();          // soft limiter so normalised tracks never clip
  comp.threshold.value = -3; comp.knee.value = 6; comp.ratio.value = 12; comp.attack.value = 0.003; comp.release.value = 0.25;
  const master = ac.createGain(); master.gain.value = 0; master.connect(comp); comp.connect(ac.destination);
  const bufs = {{}};
  const load = n => bufs[n] || (bufs[n] = fetch(n + EXT).then(r => {{ if (!r.ok) throw new Error(n + EXT + " " + r.status); return r.arrayBuffer(); }})
                                                          .then(b => ac.decodeAudioData(b)));
  // bake a seamless loop: the last xf seconds are equal-power crossfaded into the start
  function loopBuf(buf, xf, trimEnd) {{
    const sr = buf.sampleRate, L = Math.floor((buf.duration - (trimEnd || 0)) * sr), X = Math.min(Math.floor(xf * sr), Math.floor(L / 4));
    const out = ac.createBuffer(buf.numberOfChannels, L - X, sr);
    for (let c = 0; c < buf.numberOfChannels; c++) {{
      const a = buf.getChannelData(c), o = out.getChannelData(c);
      for (let i = 0; i < X; i++) {{ const t = i / X; o[i] = a[i] * Math.sin(t * Math.PI / 2) + a[L - X + i] * Math.cos(t * Math.PI / 2); }}
      o.set(a.subarray(X, L - X), X);
    }}
    return out;
  }}
  const ambNames = PL.amb.map(x => x.credit).join(", ");
  function showCredit(m) {{
    credit.textContent = "\u266a " + m.credit + (ambNames ? " \u00b7 ambience: " + ambNames + " (CC0)" : "");
    credit.href = m.url || "#";
  }}
  let i = 0, at = 0;
  async function nextTrack() {{
    const m = PL.music[i % PL.music.length]; i++;
    const b = loopBuf(await load(m.name), 0.03, m.trimEnd), X = PL.cross, dur = b.duration * (m.repeat || 1);
    const s = ac.createBufferSource(), g = ac.createGain();
    s.buffer = b; s.loop = true; s.connect(g); g.connect(master);
    const t = Math.max(at, ac.currentTime + 0.05);
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(m.gain, t + X);
    g.gain.setValueAtTime(m.gain, t + dur); g.gain.linearRampToValueAtTime(0, t + dur + X);
    s.start(t); s.stop(t + dur + X + 0.1);
    setTimeout(() => showCredit(m), Math.max(0, (t - ac.currentTime) * 1000));
    at = t + dur;                                           // the next track starts as this one fades out
    load(PL.music[i % PL.music.length].name).catch(() => {{}});   // preload
    setTimeout(nextTrack, Math.max(0, (at - ac.currentTime - 8) * 1000));
  }}
  async function ambience() {{
    for (const a of PL.amb) load(a.name).then(buf => {{
      const s = ac.createBufferSource(), g = ac.createGain();
      s.buffer = loopBuf(buf, 3.0, 0); s.loop = true; s.connect(g); g.connect(master);
      g.gain.setValueAtTime(0, ac.currentTime); g.gain.setTargetAtTime(a.gain, ac.currentTime, 1.5); s.start();
    }}).catch(e => console.warn(e));
  }}
  let on = false;
  function show() {{ btn.setAttribute("aria-pressed", on); btn.innerHTML = on ? "&#9834; SOUND ON" : "&#9834; SOUND OFF"; }}
  function setOn(v) {{
    on = v; show();
    master.gain.cancelScheduledValues(ac.currentTime);
    master.gain.setTargetAtTime(on ? PL.master : 0, ac.currentTime, on ? 0.4 : 0.15);
  }}
  let begun = false;
  async function begin() {{                      // the show starts: CRT power-on + soundtrack
    if (begun) return; begun = true;
    gate.style.display = "none";
    showStart = performance.now();
    await ac.resume();
    ambience(); nextTrack().catch(e => console.warn(e));
    setOn(true);
  }}
  btn.addEventListener("click", e => {{ e.stopPropagation(); if (!begun) begin(); else setOn(!on); }});
  addEventListener("keydown", e => {{
    if (!begun) {{ begin(); return; }}
    if (e.key === "m" || e.key === "M") setOn(!on);
  }});
  gate.addEventListener("click", begin);
  gate.addEventListener("keydown", e => {{ if (e.key === "Enter" || e.key === " ") begin(); }});
  if (ac.state === "running") begin();          // autoplay allowed: start right away
  else {{ gate.style.display = "flex"; gate.focus(); }}
}} else showStart = performance.now();          // silent build (or opened from disk): just run

Promise.all([image(FONT, false), image(LOGO, true)]).then(([font, logo]) => {{
  function frame(now) {{
    resize();
    if (showStart === null) {{                 // powered off until the show begins
      gl.bindFramebuffer(gl.FRAMEBUFFER, null); gl.viewport(0, 0, canvas.width, canvas.height);
      gl.clearColor(0, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT);
      requestAnimationFrame(frame); return;
    }}
    const t = Math.max(0, (now - showStart) / 1000);
    const lt = t % PERIOD, ult = Math.min(lt, LEN - 0.02);
    const kick = Math.exp(-((t / BEAT) % 1) * 5) * 0.8;
    // ---- the part at 320x240
    gl.useProgram(P.p); gl.bindFramebuffer(gl.FRAMEBUFFER, gfx.f); gl.viewport(0, 0, 320, 240);
    bind(P, "uFont8", 0, font); bind(P, "uStr", 1, strTex); bind(P, "uTop", 2, dummy); bind(P, "uLeft", 3, dummy);
    bind(P, "uRight", 4, dummy); bind(P, "uLogo", 5, logo); bind(P, "uWord", 6, dummy);
    if (P.u.uStrLen) gl.uniform1iv(P.u.uStrLen, lens);
    set(P, "uRes", 320, 240); set(P, "uT", t); set(P, "uLT", ult); set(P, "uLen", LEN); set(P, "uBeat", t / BEAT);
    set(P, "uFlash", 0); set(P, "uKickCum", t * 0.4); set(P, "uEnv", 0.5, 0.5, 0.4, kick); set(P, "uFx", 1); set(P, "uHit", -1);
    if (P.u.uSplitN) gl.uniform1i(P.u.uSplitN, 0);
    for (const m of ["uCubeRot", "uCamRot"]) if (P.u[m]) gl.uniformMatrix3fv(P.u[m], false, ID3);
    set(P, "uCubeC", 0, 0, 0); set(P, "uCamPos", 0, 0, 3); set(P, "uCubeS", 1); set(P, "uFov", 0.55); set(P, "uSnap", 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    // ---- halation
    gl.useProgram(B.p); gl.viewport(0, 0, 320, 240);
    gl.bindFramebuffer(gl.FRAMEBUFFER, glowA.f); bind(B, "uSrc", 0, gfx.t); set(B, "uDir", 1 / 320, 0); gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.bindFramebuffer(gl.FRAMEBUFFER, glowB.f); bind(B, "uSrc", 0, glowA.t); set(B, "uDir", 0, 1 / 240); gl.drawArrays(gl.TRIANGLES, 0, 3);
    // ---- glitches: a static burst around each loop restart (like a scene cut), degauss after power-on
    let tear = 0, rgb = 0, hold = 0, snow = 0, roll = 0, degauss = 0;
    if (!calm) {{
      if (t > 0.12 && t < 2.2) {{ const d = t - 0.12; degauss = Math.min(1, d / 0.08) * Math.exp(-d / 0.38) * 0.7; }}
      const ds = t > PERIOD ? [lt, lt - PERIOD] : [lt - PERIOD];
      for (const d of ds) {{
        if (d <= -0.12 || d >= 0.2) continue;
        const k = Math.max(d < 0 ? ((d + 0.12) / 0.12) ** 2 : 0, d >= 0 ? (1 - d / 0.2) ** 2 : 0);
        rgb = Math.max(rgb, 4 * k); hold = Math.max(hold, 0.5 * k);
        if (Math.abs(d) < 0.05) tear = 0.9;
        snow = Math.max(snow, 0.6 * Math.exp(-((d / 0.04) ** 2)) + 0.12 * k);
        if (d >= 0 && d < 0.12) roll = 0.04 * (1 - d / 0.12);
      }}
    }}
    // ---- the tube
    gl.useProgram(C.p); gl.bindFramebuffer(gl.FRAMEBUFFER, null); gl.viewport(0, 0, canvas.width, canvas.height);
    bind(C, "uSrc", 0, gfx.t); bind(C, "uGlow", 1, glowB.t); bind(C, "uPrev", 2, dummy);
    set(C, "uSrcSize", 320, 240); set(C, "uOut", canvas.width, canvas.height); set(C, "uT", t);
    if (C.u.uMode) gl.uniform1i(C.u.uMode, 1);
    set(C, "uOnT", calm ? 10 : t); set(C, "uOffT", -1); set(C, "uRoll", roll); set(C, "uJitter", 0); set(C, "uTear", tear);
    set(C, "uTearSeed", Math.floor(t * 60) % 997); set(C, "uRGB", rgb); set(C, "uSnow", Math.min(1, snow)); set(C, "uHold", hold);
    set(C, "uBulge", 0); set(C, "uDegauss", degauss); set(C, "uPersist", 0); set(C, "uKick", kick); set(C, "uScan", 1); set(C, "uFx", 1);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    requestAnimationFrame(frame);
  }}
  requestAnimationFrame(frame);
}});
</script>
</body>
</html>
"""
os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
outdir = os.path.dirname(os.path.abspath(a.out))
for src_file, base in tracks:   # every track as Ogg Opus (gapless decode) + MP3 (for browsers without Ogg)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src_file, "-c:a", "libopus", "-b:a", "128k", os.path.join(outdir, base + ".ogg")], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src_file, "-c:a", "libmp3lame", "-b:a", "192k", os.path.join(outdir, base + ".mp3")], check=True)
open(a.out, "w").write(page)
print(f"{a.out}: {len(page) // 1024} KB, part '{a.part}', {bars} bars + {a.hold:g} s hold")
