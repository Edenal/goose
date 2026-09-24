// OpenGL 4.1 helpers: textures, framebuffers, shader programs.
#pragma once
#ifndef GL_SILENCE_DEPRECATION
#define GL_SILENCE_DEPRECATION
#endif
#include <OpenGL/gl3.h>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include "mathx.h"
#include "third_party/stb_image.h"

struct Tex { GLuint id = 0; int w = 0, h = 0; };
inline Tex loadTex(const std::string& path, bool mip, bool nearest) {
    Tex t; int n;
    unsigned char* px = stbi_load(path.c_str(), &t.w, &t.h, &n, 4);
    if (!px) { fprintf(stderr, "missing texture %s\n", path.c_str()); exit(1); }
    glGenTextures(1, &t.id);
    glBindTexture(GL_TEXTURE_2D, t.id);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, t.w, t.h, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
    stbi_image_free(px);
    if (mip) glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, nearest ? GL_NEAREST : mip ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, nearest ? GL_NEAREST : GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return t;
}
inline Tex makeTex(int w, int h, GLenum ifmt, GLenum fmt, GLenum type, GLenum filter) {
    Tex t; t.w = w; t.h = h;
    glGenTextures(1, &t.id);
    glBindTexture(GL_TEXTURE_2D, t.id);
    glTexImage2D(GL_TEXTURE_2D, 0, ifmt, w, h, 0, fmt, type, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return t;
}
struct FB { GLuint fbo = 0; Tex tex; };
inline FB makeFB(int w, int h, GLenum filter) {
    FB f; f.tex = makeTex(w, h, GL_RGBA8, GL_RGBA, GL_UNSIGNED_BYTE, filter);
    glGenFramebuffers(1, &f.fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, f.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, f.tex.id, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) { fprintf(stderr, "fbo incomplete\n"); exit(1); }
    return f;
}
inline std::string readFile(const std::string& p) {
    std::ifstream f(p); std::stringstream s; s << f.rdbuf();
    if (!f) { fprintf(stderr, "missing %s\n", p.c_str()); exit(1); }
    return s.str();
}
inline GLuint shader(GLenum type, const std::string& src, const std::string& name) {
    GLuint s = glCreateShader(type);
    const char* c = src.c_str();
    glShaderSource(s, 1, &c, nullptr);
    glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[8192]; glGetShaderInfoLog(s, sizeof log, nullptr, log); fprintf(stderr, "%s:\n%s\n", name.c_str(), log); exit(1); }
    return s;
}
inline const char* VS = "#version 410 core\nout vec2 vUV;\nvoid main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);"
                        "vUV=p;gl_Position=vec4(p*2.0-1.0,0.0,1.0);}\n";
inline GLuint program(const std::string& fragPath) {
    GLuint p = glCreateProgram();
    glAttachShader(p, shader(GL_VERTEX_SHADER, VS, "vs"));
    glAttachShader(p, shader(GL_FRAGMENT_SHADER, readFile(fragPath), fragPath));
    glLinkProgram(p);
    GLint ok; glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) { char log[4096]; glGetProgramInfoLog(p, sizeof log, nullptr, log); fprintf(stderr, "link %s\n%s\n", fragPath.c_str(), log); exit(1); }
    return p;
}
inline GLint U(GLuint p, const char* n) { return glGetUniformLocation(p, n); }
inline void bindTex(GLuint p, const char* name, int unit, GLuint tex) {
    glActiveTexture(GL_TEXTURE0 + unit); glBindTexture(GL_TEXTURE_2D, tex); glUniform1i(U(p, name), unit);
}
inline void setM3(GLuint p, const char* n, const M3& m) {  // GLSL is column-major: pass transpose of rows
    float f[9] = {(float)m.r[0].x, (float)m.r[1].x, (float)m.r[2].x, (float)m.r[0].y, (float)m.r[1].y,
                  (float)m.r[2].y, (float)m.r[0].z, (float)m.r[1].z, (float)m.r[2].z};
    glUniformMatrix3fv(U(p, n), 1, GL_FALSE, f);
}
inline void set3(GLuint p, const char* n, V3 v) { glUniform3f(U(p, n), (float)v.x, (float)v.y, (float)v.z); }


// Build a program from fragment source; returns 0 and fills err instead of exiting (used for parts).
inline GLuint programFromSource(const std::string& frag, std::string& err) {
    GLuint fs = glCreateShader(GL_FRAGMENT_SHADER);
    const char* c = frag.c_str();
    glShaderSource(fs, 1, &c, nullptr);
    glCompileShader(fs);
    GLint ok; glGetShaderiv(fs, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[8192]; glGetShaderInfoLog(fs, sizeof log, nullptr, log); err = log; glDeleteShader(fs); return 0; }
    GLuint p = glCreateProgram();
    glAttachShader(p, shader(GL_VERTEX_SHADER, VS, "vs"));
    glAttachShader(p, fs);
    glLinkProgram(p);
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) { char log[4096]; glGetProgramInfoLog(p, sizeof log, nullptr, log); err = log; glDeleteProgram(p); return 0; }
    return p;
}
