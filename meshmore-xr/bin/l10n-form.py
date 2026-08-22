#!/usr/bin/env python3
# Copyright (c) 2026 IoTone, Inc.
# SPDX-License-Identifier: MIT
"""
THE JAPANESE REVIEW FORM — a thing a reviewer WORKS IN, not a table they read.

The first sheet was a table with an empty column, which asks a native speaker
to retype 331 keys into a spreadsheet and hand it back. This one is the same
shape as the Diana review page the operator already uses: every line is a
CANDIDATE, each row is approved or rewritten in place, progress is counted, and
the result comes back out as one paste.

Generated from the resources, like the sheet was. Regenerating is how it stays
true after the next commit.

    python3 bin/l10n-form.py > /tmp/ja-form.html
"""
import html, json, re, sys, xml.etree.ElementTree as ET

def cells(t):
    n = 0
    for ch in t:
        cp = ord(ch)
        if 0x1F300 <= cp <= 0x1FAFF or 0x2600 <= cp <= 0x27BF: n += 3
        elif (0x1100 <= cp <= 0x115F or 0x2E80 <= cp <= 0x303E or 0x3041 <= cp <= 0x33FF
              or 0x3400 <= cp <= 0x4DBF or 0x4E00 <= cp <= 0x9FFF or 0xAC00 <= cp <= 0xD7A3
              or 0xF900 <= cp <= 0xFAFF or 0xFE30 <= cp <= 0xFE6F or 0xFF00 <= cp <= 0xFF60
              or 0xFFE0 <= cp <= 0xFFE6): n += 2
        else: n += 1
    return n

def fill(t):
    return re.sub(r'%\d+\$d', '99', re.sub(r'%\d+\$s', '名前', t))

def load(p):
    r = ET.parse(p).getroot()
    s = {e.get('name'): ''.join(e.itertext()) for e in r.iter('string')}
    a = {e.get('name'): [''.join(i.itertext()) for i in e.iter('item')]
         for e in r.iter('string-array')}
    return s, a

EN, ENA = load('app/src/main/res/values/strings.xml')
JA, JAA = load('app/src/main/res/values-ja/strings.xml')

# prefix, title, cell budget, what the surface IS — the context a reviewer needs
SURF = [
 ('n_',    'Notice band', 30,
  'One head-locked line across the view, for a few seconds after an action. The app '
  'talking back. Terse; it is read while doing something else.'),
 ('a_',    'Hand menu verbs', 12,
  'The floating menu at your hand. Each is a VERB you pinch. Twelve cells is about six '
  'kanji — the tightest surface in the app.'),
 ('d_',    'Dock captions', 10,
  'Labels under the pips near your wrist, read at a glance while walking.'),
 ('t_',    'Panel titles', 28, 'The heading of a settings panel.'),
 ('f_',    'Panel footers', 30,
  'The line under a panel. Says what a pinch will do, or warns before it does.'),
 ('r_',    'Setting rows', 26, 'A row in a settings panel: name left, state right.'),
 ('rr_',   'Radio rows', 26,
  'The RADIO panel — frequency, bandwidth, spreading factor, region. Wrong settings here '
  'make a radio deaf, so these are read carefully rather than glanced at.'),
 ('c_',    'Channel rows', 26, 'Making, joining and deleting channels.'),
 ('telem_','Telemetry permissions', 26,
  'Who may ask this radio about itself — battery, location, environment. A privacy '
  'control; the words decide whether somebody understands what they are allowing.'),
 ('wx_',   'Mesh weather', 26,
  'Weather gathered from other people’s radios, and the census explaining who could '
  'not be asked.'),
 ('tx_',   'Message delivery', 26,
  'What became of messages you sent. Mostly nouns beside numbers.'),
 ('ab_',   'About & safety', 26,
  'Version, firmware, and the safety copy. The regulatory lines must stay accurate.'),
 ('al_',   'Alerts log', None, 'A scrolling log of notable events. Wider than a row.'),
 ('ls_',   'Link state', 12, 'The radio connection state, shown inside a panel title.'),
 ('link_', 'Link progress', 30, 'What the radio is doing while it connects.'),
 ('p_',    'Node facts', 26, 'Facts about one node in its focus card.'),
 ('pk_',   'Theme picker', 26, 'Words describing what a theme is like to wear.'),
 ('find_', 'Find', 26, 'Searching the mesh for a node.'),
 ('chan_', 'Channel fallbacks', 26, 'Names for channels the radio did not name.'),
 ('reel_', 'Reel', None, 'The message carousel on your palm.'),
 ('pg_',   'Pager', None, 'Paging through a long list.'),
 ('w_',    'Shared words', None,
  'Fragments reused inside other strings. Changing one changes every sentence it appears in.'),
 ('ago_',  'Time ago', None, 'How long since something happened.'),
 ('dm_',   'Delivery marks', None, 'The mark beside a message you sent.'),
]

def esc(s): return html.escape(s or '')

used, groups = set(), []
for pre, title, bud, ctx in SURF:
    keys = sorted(k for k in EN if k.startswith(pre) and k not in used)
    if not keys: continue
    used.update(keys)
    groups.append((pre, title, bud, ctx, keys))
rest = sorted(k for k in EN if k not in used)
if rest:
    groups.append(('', 'Everything else', None,
                   'Strings that do not belong to one surface.', rest))

def note_for(k, j, bud):
    bits = []
    w = cells(fill(j))
    if bud:
        room = f'{w} of {bud} cells'
        if w > bud: bits.append(f'<b>over the plate — {room}, it will be cut</b>')
        elif w > bud * 0.85: bits.append(f'close to the limit — {room}')
        else: bits.append(room)
    if '%' in EN.get(k, ''):
        bits.append('keeps <code>%1$s</code> / <code>%2$d</code> exactly; order may change')
    if j == EN.get(k, ''):
        bits.append('<b>same as English</b> — intended?')
    return ' · '.join(bits)

rows_html, jump, total = [], [], 0
for gi, (pre, title, bud, ctx, keys) in enumerate(groups):
    total += len(keys)
    jump.append(f"<a href='#g{gi}'>{esc(title)}<span>{len(keys)}</span></a>")
    budline = (f'Room: <b>{bud} cells</b> — a kanji is 2, a Latin letter 1. '
               f'The glasses cut what overruns; they never wrap it.') if bud \
              else 'No fixed width here.'
    body = []
    for k in keys:
        j, e = JA.get(k, ''), EN[k]
        note = note_for(k, j, bud)
        state = 'info' if j == e else 'todo'
        body.append(f'''<article class="row" data-key="{esc(k)}" data-state="{state}" data-g="g{gi}">
  <div class="stripe" aria-hidden="true"></div>
  <div class="body">
    <div class="src"><span class="en">{esc(e)}</span><code class="key">{esc(k)}</code></div>
    <p class="ja" lang="ja">{esc(j)}</p>
    <p class="ja edited" lang="ja" hidden></p>
    {f'<p class="note">{note}</p>' if note else ''}
    <div class="edit" hidden>
      <label for="t{esc(k)}">Your Japanese</label>
      <textarea id="t{esc(k)}" lang="ja" rows="2"
        placeholder="Rewrite the line as it should ship">{esc(j)}</textarea>
      <div class="edit-act">
        <button type="button" data-act="save">Save</button>
        <button type="button" data-act="cancel" class="ghost">Cancel</button>
      </div>
    </div>
  </div>
  <div class="act">
    <span class="pill" aria-hidden="true"></span>
    <button type="button" data-act="ok" aria-pressed="false">Approve</button>
    <button type="button" data-act="open" class="ghost">Rewrite</button>
    <button type="button" data-act="reset" class="ghost quiet">Reset</button>
  </div>
</article>''')
    rows_html.append(f'''<section id="g{gi}">
  <div class="shead"><h2>{esc(title)} {f'<code>{esc(pre)}</code>' if pre else ''}</h2>
    <span class="count"><b data-done="g{gi}">0</b>/{len(keys)}</span></div>
  <p class="stand">{esc(ctx)}</p>
  <p class="budget">{budline}</p>
  <div class="rows">{''.join(body)}</div>
</section>''')

# the pre-wrapped disclaimer, which is lines rather than strings
for k, v in ENA.items():
    ja_lines = JAA.get(k, [])
    n = max(len(v), len(ja_lines))
    body = []
    for i in range(n):
        e = v[i] if i < len(v) else ''
        j = ja_lines[i] if i < len(ja_lines) else ''
        kk = f'{k}[{i}]'
        body.append(f'''<article class="row" data-key="{esc(kk)}" data-state="todo" data-g="gd">
  <div class="stripe" aria-hidden="true"></div>
  <div class="body">
    <div class="src"><span class="en">{esc(e)}</span><code class="key">line {i+1}</code></div>
    <p class="ja" lang="ja">{esc(j)}</p>
    <p class="ja edited" lang="ja" hidden></p>
    <p class="note">one line on the glasses — the break is part of the translation</p>
    <div class="edit" hidden>
      <label for="t{esc(kk)}">Your Japanese</label>
      <textarea id="t{esc(kk)}" lang="ja" rows="2">{esc(j)}</textarea>
      <div class="edit-act">
        <button type="button" data-act="save">Save</button>
        <button type="button" data-act="cancel" class="ghost">Cancel</button>
      </div>
    </div>
  </div>
  <div class="act">
    <span class="pill" aria-hidden="true"></span>
    <button type="button" data-act="ok" aria-pressed="false">Approve</button>
    <button type="button" data-act="open" class="ghost">Rewrite</button>
    <button type="button" data-act="reset" class="ghost quiet">Reset</button>
  </div>
</article>''')
    total += n
    jump.append(f"<a href='#gd'>Region disclaimer<span>{n}</span></a>")
    rows_html.append(f'''<section id="gd">
  <div class="shead"><h2>Region disclaimer <code>{esc(k)}</code></h2>
    <span class="count"><b data-done="gd">0</b>/{n}</span></div>
  <p class="stand">Pre-wrapped lines in the ABOUT panel. English has {len(v)} lines and
  Japanese {len(ja_lines)} — a different count is fine and expected, since kanji carry a
  line in fewer characters. This is the regulatory copy: Japan requires 技適 certification
  on the hardware, not merely a legal frequency, and the wording has to keep saying so.</p>
  <p class="budget">Each line is its own row on the panel. Around 26 cells.</p>
  <div class="rows">{''.join(body)}</div>
</section>''')

sys.stdout.write(open('bin/l10n-form.head.html').read()
                 .replace('{{TOTAL}}', str(total))
                 .replace('{{JUMP}}', ''.join(jump))
                 + ''.join(rows_html)
                 + open('bin/l10n-form.tail.html').read())
