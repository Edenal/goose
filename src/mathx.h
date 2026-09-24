// Tiny vector / matrix / quaternion helpers for the cube camera.
#pragma once
#include <cmath>

struct V3 { double x, y, z; };
inline V3 operator+(V3 a, V3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
inline V3 operator-(V3 a, V3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline V3 operator*(V3 a, double s) { return {a.x * s, a.y * s, a.z * s}; }
inline double dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
inline V3 norm(V3 a) { return a * (1.0 / sqrt(dot(a, a))); }
struct M3 { V3 r[3]; };  // rows

inline M3 transpose(const M3& m) {
    return {{{m.r[0].x, m.r[1].x, m.r[2].x}, {m.r[0].y, m.r[1].y, m.r[2].y}, {m.r[0].z, m.r[1].z, m.r[2].z}}};
}
struct Q { double w, x, y, z; };
inline Q qaxis(V3 a, double ang) { a = norm(a); double s = sin(ang / 2); return {cos(ang / 2), a.x * s, a.y * s, a.z * s}; }
inline Q qmul(Q a, Q b) {
    return {a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z, a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x, a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w};
}
inline Q qslerp(Q a, Q b, double t) {
    double d = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z;
    if (d < 0) { b = {-b.w, -b.x, -b.y, -b.z}; d = -d; }
    if (d > 0.9995) {
        Q r = {a.w + (b.w - a.w) * t, a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t};
        double n = sqrt(r.w * r.w + r.x * r.x + r.y * r.y + r.z * r.z);
        return {r.w / n, r.x / n, r.y / n, r.z / n};
    }
    double th = acos(d), s = sin(th), wa = sin((1 - t) * th) / s, wb = sin(t * th) / s;
    return {a.w * wa + b.w * wb, a.x * wa + b.x * wb, a.y * wa + b.y * wb, a.z * wa + b.z * wb};
}
inline M3 qmat(Q q) {  // rotation matrix (object -> world)
    double w = q.w, x = q.x, y = q.y, z = q.z;
    return {{{1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)},
             {2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)},
             {2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)}}};
}
inline Q matq(const M3& m) {
    double tr = m.r[0].x + m.r[1].y + m.r[2].z;
    Q q;
    if (tr > 0) {
        double s = sqrt(tr + 1.0) * 2;
        q = {0.25 * s, (m.r[2].y - m.r[1].z) / s, (m.r[0].z - m.r[2].x) / s, (m.r[1].x - m.r[0].y) / s};
    } else if (m.r[0].x > m.r[1].y && m.r[0].x > m.r[2].z) {
        double s = sqrt(1.0 + m.r[0].x - m.r[1].y - m.r[2].z) * 2;
        q = {(m.r[2].y - m.r[1].z) / s, 0.25 * s, (m.r[0].y + m.r[1].x) / s, (m.r[0].z + m.r[2].x) / s};
    } else if (m.r[1].y > m.r[2].z) {
        double s = sqrt(1.0 + m.r[1].y - m.r[0].x - m.r[2].z) * 2;
        q = {(m.r[0].z - m.r[2].x) / s, (m.r[0].y + m.r[1].x) / s, 0.25 * s, (m.r[1].z + m.r[2].y) / s};
    } else {
        double s = sqrt(1.0 + m.r[2].z - m.r[0].x - m.r[1].y) * 2;
        q = {(m.r[1].x - m.r[0].y) / s, (m.r[0].z + m.r[2].x) / s, (m.r[1].z + m.r[2].y) / s, 0.25 * s};
    }
    return q;
}
inline double clamp01(double x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
inline double smooth(double a, double b, double x) { x = clamp01((x - a) / (b - a)); return x * x * (3 - 2 * x); }
inline double easeOut(double x) { x = clamp01(x); return 1 - (1 - x) * (1 - x) * (1 - x); }

