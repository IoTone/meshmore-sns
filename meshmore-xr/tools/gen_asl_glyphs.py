#!/usr/bin/env python3
# Copyright (c) 2026 IoTone, Inc.
# SPDX-License-Identifier: MIT
"""Extract the Gallaudet ASL hand shapes into AslGlyphs.kt.

    python3 tools/gen_asl_glyphs.py asl.svg > .../AslGlyphs.kt

SOURCE
    https://commons.wikimedia.org/wiki/File:Asl_alphabet_gallaudet.svg
    Ds13 (2004), vectorised by Marnanel, from the Gallaudet-TT font.
    PUBLIC DOMAIN, no conditions.

    Fetch with:
      curl -sSL "https://commons.wikimedia.org/wiki/Special:FilePath/Asl_alphabet_gallaudet.svg"

WHY THIS SCRIPT EXISTS
    The first three glyphs were extracted by hand and the file said "GENERATED
    — do not hand-edit" with no generator to point at, which makes it neither
    generated nor editable. This is the method, written down and rerunnable.

WHAT IT KEEPS AND DROPS
    Each hand is drawn twice: a skin fill (#ffb380) beneath black line art.
    ONLY THE LINE ART IS KEPT. Dropping the fill is not a palette choice — a
    skin tone is a claim about whose hand this is, and a reference diagram
    should not make one. What is left takes the theme's ink, and on additive
    optics reads as a diagram rather than a glowing blob.

WHY IT IS EXACT
    Every group transform in this file is a pure scale+translate, and no path
    uses an elliptical arc. So the whole pipeline — transform, then normalise
    into a 100-unit box — is affine and curve-preserving: nothing is flattened
    or resampled, and a control point in equals a control point out. The script
    ASSERTS both of those rather than assuming them, because the day the source
    changes is the day silently-wrong artwork ships.
"""
import re
import sys
from lxml import etree

SVG = "{http://www.w3.org/2000/svg}"
SKIN = "#ffb380"
BOX = 100.0
MARGIN = 0.0        # the box IS the glyph; AslIcon adds its own margin
PREC = 1            # 0.1 of a percent of the box — far below a pixel


def numbers(s):
    return [float(x) for x in re.findall(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", s)]


def parse_path(d):
    """SVG path -> list of absolute segments [(cmd, coords...)] using M/L/C/Q/Z."""
    toks = re.findall(r"([MmLlHhVvCcSsQqTtZz])|([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)", d)
    out, nums, cmd = [], [], None
    x = y = sx = sy = 0.0
    px = py = None          # last control point, for S/T
    i = 0
    seq = []
    for c, n in toks:
        if c:
            seq.append(("c", c))
        else:
            seq.append(("n", float(n)))

    def take(k):
        nonlocal i
        vals = []
        while len(vals) < k:
            kind, v = seq[i]
            assert kind == "n", f"expected number, got {v}"
            vals.append(v)
            i += 1
        return vals

    while i < len(seq):
        kind, v = seq[i]
        if kind == "c":
            cmd = v
            i += 1
        rel = cmd.islower()
        C = cmd.upper()
        if C == "M":
            a, b = take(2)
            x, y = (x + a, y + b) if rel else (a, b)
            sx, sy = x, y
            out.append(("M", x, y))
            px = py = None
            cmd = "l" if rel else "L"    # extra pairs are implicit linetos
        elif C == "L":
            a, b = take(2)
            x, y = (x + a, y + b) if rel else (a, b)
            out.append(("L", x, y))
            px = py = None
        elif C == "H":
            (a,) = take(1)
            x = x + a if rel else a
            out.append(("L", x, y))
            px = py = None
        elif C == "V":
            (a,) = take(1)
            y = y + a if rel else a
            out.append(("L", x, y))
            px = py = None
        elif C == "C":
            a, b, c2, d2, e, f = take(6)
            if rel:
                a, b, c2, d2, e, f = x + a, y + b, x + c2, y + d2, x + e, y + f
            out.append(("C", a, b, c2, d2, e, f))
            px, py = c2, d2
            x, y = e, f
        elif C == "S":
            c2, d2, e, f = take(4)
            if rel:
                c2, d2, e, f = x + c2, y + d2, x + e, y + f
            a, b = (2 * x - px, 2 * y - py) if px is not None else (x, y)
            out.append(("C", a, b, c2, d2, e, f))
            px, py = c2, d2
            x, y = e, f
        elif C == "Q":
            a, b, e, f = take(4)
            if rel:
                a, b, e, f = x + a, y + b, x + e, y + f
            out.append(("Q", a, b, e, f))
            px, py = a, b
            x, y = e, f
        elif C == "T":
            e, f = take(2)
            if rel:
                e, f = x + e, y + f
            a, b = (2 * x - px, 2 * y - py) if px is not None else (x, y)
            out.append(("Q", a, b, e, f))
            px, py = a, b
            x, y = e, f
        elif C == "Z":
            out.append(("Z",))
            x, y = sx, sy
            px = py = None
        else:
            raise AssertionError(f"unsupported command {cmd!r} — arcs are not handled")
    return out


def apply(segs, fn):
    out = []
    for s in segs:
        if s[0] == "Z":
            out.append(s)
            continue
        cs = []
        for k in range(1, len(s), 2):
            cs.extend(fn(s[k], s[k + 1]))
        out.append((s[0], *cs))
    return out


def bbox(segs):
    xs, ys = [], []
    for s in segs:
        for k in range(1, len(s), 2):
            xs.append(s[k]); ys.append(s[k + 1])
    return min(xs), min(ys), max(xs), max(ys)


def emit(segs):
    parts = []
    for s in segs:
        if s[0] == "Z":
            parts.append("Z")
            continue
        nums = " ".join(
            (f"%.{PREC}f" % v).rstrip("0").rstrip(".") or "0" for v in s[1:]
        )
        parts.append(f"{s[0]}{nums}")
    return " ".join(parts)


def main(path):
    root = etree.parse(path).getroot()
    layer = [g for g in root.iter(SVG + "g") if g.get("id") == "layer2"][0]

    labels = []
    for t in root.iter(SVG + "text"):
        ch = "".join(t.itertext()).strip()
        if len(ch) == 1:
            labels.append((ch, float(t.get("x")), float(t.get("y"))))

    glyphs = {}
    for g in [e for e in layer if e.tag == SVG + "g"]:
        m = g.get("transform") or ""
        n = numbers(m)
        assert m.startswith("matrix(") and len(n) == 6, f"unexpected transform {m!r}"
        a, b, c, d, e, f = n
        assert abs(b) < 1e-9 and abs(c) < 1e-9, (
            "the transform rotates or skews; this script only handles "
            "scale+translate, which is what makes the extraction exact"
        )

        segs = []
        for p in g.iter(SVG + "path"):
            style = (p.get("style") or "") + (p.get("fill") or "")
            if SKIN in style:
                continue                      # the skin fill, deliberately dropped
            segs += parse_path(p.get("d"))
        if not segs:
            continue
        segs = apply(segs, lambda X, Y: (a * X + e, d * Y + f))

        x0, y0, x1, y1 = bbox(segs)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        # The label sits under its hand; take the nearest one below.
        best = min(
            (l for l in labels if l[2] > y0),
            key=lambda l: abs(l[1] - cx) + 0.15 * (l[2] - y1),
            default=None,
        )
        assert best, f"no label under glyph at {cx:.1f},{cy:.1f}"
        ch = best[0]

        # Normalise: uniform scale, centred, aspect preserved.
        span = max(x1 - x0, y1 - y0)
        k = (BOX - 2 * MARGIN) / span
        ox = MARGIN + (BOX - 2 * MARGIN - (x1 - x0) * k) / 2
        oy = MARGIN + (BOX - 2 * MARGIN - (y1 - y0) * k) / 2
        segs = apply(segs, lambda X, Y: ((X - x0) * k + ox, (Y - y0) * k + oy))
        assert ch not in glyphs, f"two glyphs claim {ch!r}"
        glyphs[ch] = emit(segs)

    order = [chr(c) for c in range(ord("a"), ord("z") + 1)] + [str(i) for i in range(10)]
    missing = [c for c in order if c not in glyphs]
    assert not missing, f"missing glyphs: {missing}"

    out = []
    out.append(HEADER)
    out.append("object AslGlyphs {\n")
    out.append("    /** Path data in a 0..100 box. Parse with androidx PathParser. */")
    out.append("    val PATHS: Map<Char, String> = mapOf(")
    for ch in order:
        lines = wrap(glyphs[ch])
        out.append(f"        '{ch}' to")
        for k, chunk in enumerate(lines):
            last = k == len(lines) - 1
            # THE TRAILING SPACE IS LOAD-BEARING. Kotlin concatenates adjacent
            # literals with nothing between them, so a line ending "45.1" and
            # the next beginning "20.2" become the number 45.120.2 — which
            # parses, draws, and is wrong. Caught by the box test rather than
            # by looking, because a glyph corrupted this way still renders.
            out.append(f'            "{chunk}{"" if last else " "}"{"," if last else " +"}')
    out.append("    )\n")
    out.append(BODY)
    print("\n".join(out))


def wrap(d, width=88):
    words, lines, cur = d.split(" "), [], ""
    for w in words:
        if len(cur) + len(w) + 1 > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    if cur:
        lines.append(cur)
    return lines


HEADER = '''// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
//
// GENERATED by tools/gen_asl_glyphs.py — do not hand-edit.
//
//   https://commons.wikimedia.org/wiki/File:Asl_alphabet_gallaudet.svg
//   Ds13 (2004), vectorised by Marnanel, derived from the Gallaudet-TT font.
//   PUBLIC DOMAIN — released by its author for any purpose, no conditions.
//
// The original draws each hand twice: a skin fill (#ffb380) under black line
// art. ONLY THE LINE ART IS KEPT. Dropping the fill is not merely a palette
// choice — a skin tone is a claim about whose hand this is, and a reference
// diagram should not make one. What remains is a contour drawing that takes
// whatever ink colour the theme is using, so it reads on any ground and on an
// additive display where a filled shape would glow as a solid blob.
//
// All 36 shapes the chart carries: a-z and 0-9. Each is normalised into a
// 100x100 box, centred, aspect preserved, rounded to 0.1 units — a tenth of a
// percent of the box, far below a pixel at any size these are drawn.
//
// The extraction is EXACT, not resampled: every transform in the source is a
// pure scale+translate and no path uses an arc, so curves survive as curves.
// The generator asserts both, because the day that stops being true is the day
// silently-wrong artwork would ship.
package com.iotj.meshmore.xr.spatial
'''

BODY = '''    /** The authoring box every path is expressed in. */
    const val BOX = 100f

    fun has(c: Char) = PATHS.containsKey(c.lowercaseChar())

    operator fun get(c: Char): String? = PATHS[c.lowercaseChar()]
}'''


if __name__ == "__main__":
    main(sys.argv[1])
