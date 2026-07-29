#!/usr/bin/env python3
"""Pack dist/ into ONE self-contained HTML file.

Used to publish the prototype as a Claude Artifact, where a strict CSP blocks
every external host — no CDN, no font file, no fetch. Everything must be inline.

Two non-obvious requirements:

1. FONTS AS DATA URIs. The Japanese face is 616 kB and cannot be linked. A
   missing face renders as tofu and throws nothing, so it has to be embedded.

2. PURE ASCII OUTPUT. The host page owns <head>, so we cannot emit a
   <meta charset>. Without one, a UTF-8 payload can be decoded as latin-1, and
   then every CJK literal is mojibake — which surfaces as
   "Invalid regular expression: Range out of order in character class",
   because the kana/kanji ranges in i18n.js get mangled into garbage.
   So every non-ASCII codepoint is escaped: \\uXXXX in JS (valid inside both
   string and regex literals) and &#xXXXX; in HTML text.

Usage:  npm run build && python3 scripts/pack-artifact.py <out.html>
"""
import base64
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIST = ROOT / 'dist'


def _units(ch: str):
    """UTF-16 code units of a character (handles astral planes)."""
    n = ord(ch)
    if n < 0x10000:
        return [n]
    n -= 0x10000
    return [0xD800 + (n >> 10), 0xDC00 + (n & 0x3FF)]


def js_escape(s: str) -> str:
    """Escape non-ASCII as \\uXXXX. Valid in JS string AND regex literals."""
    out = []
    for c in s:
        if ord(c) < 128:
            out.append(c)
        else:
            out.extend(f'\\u{u:04x}' for u in _units(c))
    return ''.join(out)


def html_escape(s: str) -> str:
    return ''.join(c if ord(c) < 128 else f'&#x{ord(c):x};' for c in s)


def main() -> int:
    out_path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / 'dist' / 'artifact.html')

    js = next(DIST.glob('assets/*.js')).read_text(encoding='utf-8')
    css = next(DIST.glob('assets/*.css')).read_text(encoding='utf-8')
    html = (ROOT / 'index.html').read_text(encoding='utf-8')
    style = re.search(r'<style>(.*?)</style>', html, re.S).group(1)
    body = re.search(r'<body>(.*?)<script', html, re.S).group(1)

    for f in DIST.glob('assets/*.woff2'):
        b64 = base64.b64encode(f.read_bytes()).decode()
        css = css.replace(f'./{f.name}', f'data:font/woff2;base64,{b64}')
    # Drop the .woff fallbacks; every browser that runs WebGL2 has woff2.
    css = re.sub(r',\s*url\(\./[^)]*\.woff\)\s*format\("woff"\)', '', css)

    if 'url(./' in css:
        print('ERROR: unresolved asset reference left in CSS', file=sys.stderr)
        return 1

    doc = (
        '<title>AiRspace UI &#x2014; spatial widget prototype</title>\n'
        '<style>\n'
        'html, body { margin:0; height:100%; background:#05070a; overflow:hidden; }\n'
        f'{html_escape(css)}\n{html_escape(style)}\n'
        '</style>\n'
        f'{html_escape(body)}\n'
        '<script type="module">\n'
        f'{js_escape(js)}\n'
        '</script>\n'
    )

    non_ascii = [c for c in doc if ord(c) > 127]
    if non_ascii:
        print(f'ERROR: {len(non_ascii)} non-ASCII chars survived escaping', file=sys.stderr)
        return 1

    out_path.write_text(doc, encoding='ascii')
    print(f'{out_path}  {len(doc)/1024/1024:.2f} MB  fonts={css.count("data:font/woff2")}  ascii-only=yes')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
