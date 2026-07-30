#!/usr/bin/env python3
"""Generate the MeshmoreXR icon as a VectorDrawable — a 3D render of the app's
own symbology.

The 2D mark in brand/_gen.py is signal rings + three linked satellites + a
central diamond. This is the SAME mark carried into three dimensions, using the
SAME primitives the HORIZON actually draws (Prims.kt):

    signal rings  -> HALO   (torus, seen in perspective)
    links         -> SPUR   (square-section tube)
    satellites    -> MOTE   (faceted sphere)
    central node  -> the flat diamond becomes an OCTAHEDRON

Shading is baked exactly as Prims.Facets does: per-facet lambert against the
same fixed key direction, same 0.42 ambient floor. So the icon is not an
illustration OF the app -- it is a frame OF the app, rendered offline.

Facets are depth-sorted (painter's algorithm) and consecutive facets sharing a
quantised shade are merged into one <path>, which keeps a VectorDrawable that
would otherwise be ~350 paths down to a few dozen.
"""
import math
import pathlib

# --- HALO FIELD ------------------------------------------------------------
GROUND = (0x07, 0x0B, 0x10)
ACCENT = (0x35, 0xE0, 0xF0)
ALT = (0x7C, 0xFF, 0x6B)

KEY = (0.35, 0.75, 0.55)
_kl = math.sqrt(sum(c * c for c in KEY))
KEY = tuple(c / _kl for c in KEY)

# 3/4 view, looking down onto the ring
YAW, PITCH = math.radians(24), math.radians(-30)
CAM_D, FOCAL = 6.0, 3.05


def rot(p):
    x, y, z = p
    x, z = x * math.cos(YAW) - z * math.sin(YAW), x * math.sin(YAW) + z * math.cos(YAW)
    y, z = y * math.cos(PITCH) - z * math.sin(PITCH), y * math.sin(PITCH) + z * math.cos(PITCH)
    return (x, y, z)


def project(p):
    x, y, z = rot(p)
    s = FOCAL / (CAM_D - z)
    return (x * s, -y * s, z)


def norm(a, b, c):
    u = [b[i] - a[i] for i in range(3)]
    v = [c[i] - a[i] for i in range(3)]
    n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
    l = math.sqrt(sum(k * k for k in n)) or 1.0
    return [k / l for k in n]


FACETS = []  # (depth, shade, colour, [(x,y),(x,y),(x,y)])


def tri(a, b, c, colour):
    n = norm(a, b, c)
    lam = max(0.0, sum(n[i] * KEY[i] for i in range(3)))
    shade = 0.42 + 0.58 * lam                       # identical to Prims.Facets

    # BACK-FACE CULL. These are closed solids, so roughly half of every facet
    # set faces away and can never be seen. Emitting them anyway doubled the
    # path count of a launcher icon for nothing.
    ra, rb, rc = rot(a), rot(b), rot(c)
    rn = norm(ra, rb, rc)
    cen = [(ra[i] + rb[i] + rc[i]) / 3.0 for i in range(3)]
    view = [-cen[0], -cen[1], CAM_D - cen[2]]
    if sum(rn[i] * view[i] for i in range(3)) <= 0:
        return

    pa, pb, pc = project(a), project(b), project(c)
    depth = (pa[2] + pb[2] + pc[2]) / 3.0
    FACETS.append((depth, shade, colour, [(pa[0], pa[1]), (pb[0], pb[1]), (pc[0], pc[1])]))


def quad(a, b, c, d, colour):
    tri(a, b, c, colour); tri(a, c, d, colour)


def sphere(cx, cy, cz, r, colour, rings=5, seg=8):
    def p(i, j):
        phi, th = math.pi * i / rings, 2 * math.pi * j / seg
        return (cx + r * math.sin(phi) * math.cos(th),
                cy + r * math.cos(phi),
                cz + r * math.sin(phi) * math.sin(th))
    for i in range(rings):
        for j in range(seg):
            a, b, c, d = p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)
            if i == 0: tri(a, b, c, colour)
            elif i == rings - 1: tri(a, b, d, colour)
            else: quad(a, b, c, d, colour)


def torus(R, tube, colour, seg=22, sides=5, y=0.0):
    def p(i, j):
        u, v = 2 * math.pi * i / seg, 2 * math.pi * j / sides
        rr = R + tube * math.cos(v)
        return (rr * math.cos(u), y + tube * math.sin(v), rr * math.sin(u))
    for i in range(seg):
        for j in range(sides):
            quad(p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1), colour)


def octahedron(cx, cy, cz, r, colour):
    """The 2D mark's diamond, given a third dimension."""
    t = (cx, cy + r, cz); bm = (cx, cy - r, cz)
    eq = [(cx + r * math.cos(a), cy, cz + r * math.sin(a))
          for a in [i * math.pi / 2 for i in range(4)]]
    for i in range(4):
        a, b = eq[i], eq[(i + 1) % 4]
        tri(t, a, b, colour); tri(bm, b, a, colour)


def spur(a, b, r, colour):
    d = [b[i] - a[i] for i in range(3)]
    l = math.sqrt(sum(k * k for k in d)) or 1.0
    d = [k / l for k in d]
    h = (0, 1, 0) if abs(d[1]) < 0.9 else (1, 0, 0)
    u = [h[1] * d[2] - h[2] * d[1], h[2] * d[0] - h[0] * d[2], h[0] * d[1] - h[1] * d[0]]
    ul = math.sqrt(sum(k * k for k in u)) or 1.0
    u = [k / ul for k in u]
    v = [d[1] * u[2] - d[2] * u[1], d[2] * u[0] - d[0] * u[2], d[0] * u[1] - d[1] * u[0]]
    def corner(t, s):
        base = [a[i] + (b[i] - a[i]) * t for i in range(3)]
        su = -r if s in (0, 3) else r
        sv = -r if s < 2 else r
        return tuple(base[i] + u[i] * su + v[i] * sv for i in range(3))
    for s in range(4):
        n = (s + 1) % 4
        quad(corner(0, s), corner(0, n), corner(1, n), corner(1, s), colour)


# --- the mark ---------------------------------------------------------------
SAT = [(0.0, 0.0, -1.30), (-1.13, 0.0, 0.65), (1.13, 0.0, 0.65)]

torus(1.62, 0.055, ACCENT, seg=26, sides=5)        # outer signal ring
torus(1.06, 0.045, ACCENT, seg=22, sides=5)        # inner signal ring
for s in SAT:
    spur((0, 0, 0), s, 0.045, ALT)                 # links
for s in SAT:
    sphere(*s, 0.20, ACCENT, rings=5, seg=8)       # satellites
octahedron(0, 0, 0, 0.40, ACCENT)                  # central node


def emit(path, size, inset):
    """Depth-sort, merge equal-shade runs, write a VectorDrawable."""
    FACETS.sort(key=lambda f: f[0])                # far -> near
    xs = [p[0] for f in FACETS for p in f[3]]
    ys = [p[1] for f in FACETS for p in f[3]]
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    k = (size - 2 * inset) / span
    ox = size / 2 - (min(xs) + max(xs)) / 2 * k
    oy = size / 2 - (min(ys) + max(ys)) / 2 * k

    runs, cur = [], None
    for depth, shade, colour, pts in FACETS:
        q = round(shade * 5) / 5                   # coarse quantise -> longer runs
        rgb = "#%02X%02X%02X" % tuple(min(255, int(c * q)) for c in colour)
        d = "M%.2f,%.2f L%.2f,%.2f L%.2f,%.2f Z" % tuple(
            v for p in pts for v in (p[0] * k + ox, p[1] * k + oy))
        if cur and cur[0] == rgb:
            cur[1].append(d)
        else:
            cur = [rgb, [d]]
            runs.append(cur)

    body = "\n".join(
        f'    <path android:fillColor="{c}" android:pathData="{" ".join(ds)}"/>'
        for c, ds in runs)
    pathlib.Path(path).write_text(
        f'<?xml version="1.0" encoding="utf-8"?>\n'
        f'<!-- GENERATED by tools/gen_icon.py — do not edit by hand. -->\n'
        f'<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        f'    android:width="{size}dp" android:height="{size}dp"\n'
        f'    android:viewportWidth="{size}" android:viewportHeight="{size}">\n'
        f'{body}\n</vector>\n')
    print(f"{path}: {len(FACETS)} facets -> {len(runs)} paths")
    return runs, size


if __name__ == "__main__":
    import sys
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    # Adaptive icons are 108dp with only the central 66dp guaranteed visible,
    # so the mark is inset hard to survive circular and squircle masks.
    emit(out / "ic_launcher_foreground.xml", 108, 27)
    # Splash icons are 288dp with the inner 2/3 visible, same ratio as above.
    emit(out / "ic_splash.xml", 288, 72)

    # SVG preview of the same geometry, for review outside a device.
    runs, size = emit(out / "_preview.tmp", 108, 14)
    (out / "_preview.tmp").unlink()
    body = "\n".join(
        f'  <path fill="{c}" d="{" ".join(ds)}"/>' for c, ds in runs)
    (out / "icon-preview.svg").write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" '
        f'width="{size}" height="{size}">\n{body}\n</svg>\n')
    print("icon-preview.svg written")
