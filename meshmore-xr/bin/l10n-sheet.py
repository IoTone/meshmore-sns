#!/usr/bin/env python3
# Copyright (c) 2026 IoTone, Inc.
# SPDX-License-Identifier: MIT
"""
THE JAPANESE REVIEW SHEET, GENERATED — never typed.

A reviewer needs three things this repository already knows and a hand-written
document would immediately get wrong: every string that can appear, the surface
it appears ON, and how much room it has there. So the sheet is generated from
values/strings.xml and values-ja/strings.xml, and regenerating it is how it
stays true after the next commit.

Widths use the app's own rule (TypeTier.displayCells): emoji 3 cells, CJK 2,
everything else 1, with placeholders filled by a plausible worst case. The
budgets come from the templates each surface sizes itself from — see Rows.kt,
Notice.WIDEST_JA, Crown.WIDEST and Dock.CAPTION_WIDEST_JA.

    python3 bin/l10n-sheet.py            # writes docs/l10n-review-ja.csv
    python3 bin/l10n-sheet.py --json     # the same data, for the HTML sheet
"""
import re, xml.etree.ElementTree as ET, html, json, collections

def cells(t):
    n=0
    for ch in t:
        cp=ord(ch)
        if 0x1F300<=cp<=0x1FAFF or 0x2600<=cp<=0x27BF: n+=3
        elif (0x1100<=cp<=0x115F or 0x2E80<=cp<=0x303E or 0x3041<=cp<=0x33FF
              or 0x3400<=cp<=0x4DBF or 0x4E00<=cp<=0x9FFF or 0xAC00<=cp<=0xD7A3
              or 0xF900<=cp<=0xFAFF or 0xFE30<=cp<=0xFE6F or 0xFF00<=cp<=0xFF60
              or 0xFFE0<=cp<=0xFFE6): n+=2
        else: n+=1
    return n

def fill(t):
    t = re.sub(r'%\d+\$s','名前', t)
    return re.sub(r'%\d+\$d','99', t)

def load(p):
    r=ET.parse(p).getroot()
    d={}
    for e in r.iter('string'):
        d[e.get('name')] = ''.join(e.itertext())
    a={}
    for e in r.iter('string-array'):
        a[e.get('name')] = [''.join(i.itertext()) for i in e.iter('item')]
    return d,a

en,ena = load('app/src/main/res/values/strings.xml')
ja,jaa = load('app/src/main/res/values-ja/strings.xml')

# Surfaces: prefix -> (title, where it appears, cell budget, what it must do)
SURF = [
 ('n_',   'Notice band',      30, 'One head-locked line across the view. Appears for a few seconds after an action and then goes. It is the app talking back.'),
 ('a_',   'Hand menu verbs',  12, 'The floating menu at your hand. Each is a VERB you pinch. Very tight — twelve cells is about six kanji.'),
 ('d_',   'Dock captions',    10, 'Labels under the row of pips near your wrist. Read at a glance while walking.'),
 ('t_',   'Bay titles',       28, 'The heading of a settings panel.'),
 ('f_',   'Bay footers',      30, 'The line under a panel. Usually says what a pinch will do, or warns.'),
 ('r_',   'Setting rows',     26, 'A row in a settings panel: name on the left, state on the right.'),
 ('rr_',  'Radio rows',       26, 'Rows in the RADIO panel — frequency, bandwidth, region.'),
 ('c_',   'Channel rows',     26, 'Rows for making, joining and deleting channels.'),
 ('telem_','Telemetry perms', 26, 'Who may ask this radio about itself. A privacy control.'),
 ('wx_',  'Mesh weather',     26, 'The weather panel and the census explaining who could not be asked.'),
 ('tx_',  'Message delivery', 26, 'The panel showing what became of messages you sent.'),
 ('ab_',  'About & safety',   26, 'Version, firmware, and the safety copy.'),
 ('al_',  'Alerts log',       None,'A scrolling log of notable events. Wider than a row.'),
 ('ls_',  'Link state',       12, 'The connection state, shown inside the APP title.'),
 ('link_','Link progress',    30, 'What the radio is doing while it connects.'),
 ('w_',   'Shared words',     None,'Fragments reused inside other strings.'),
 ('ago_', 'Time ago',         None,'How long since something happened.'),
 ('dm_',  'Delivery marks',   None,'The mark beside a message you sent.'),
 ('p_',   'Node facts',       26, 'Facts about one node, in its focus card.'),
 ('pk_',  'Theme picker',     26, 'Words describing a theme.'),
 ('find_','Find',             26, 'Searching the mesh.'),
 ('chan_','Channel names',    26, 'Fallback names for channels.'),
 ('reel_','Reel',             None,'The message carousel on your palm.'),
 ('pg_',  'Pager',            None,'Paging through a long list.'),
]
used=set()
groups=[]
for pre,title,bud,ctx in SURF:
    keys=sorted(k for k in en if k.startswith(pre) and k not in used)
    if not keys: continue
    used.update(keys)
    rows=[]
    for k in keys:
        j=ja.get(k,'')
        w=cells(fill(j))
        rows.append(dict(key=k, en=en[k], ja=j, w=w,
                         tight=(bud is not None and w > bud*0.85),
                         over=(bud is not None and w > bud)))
    groups.append(dict(pre=pre, title=title, bud=bud, ctx=ctx, rows=rows))
rest=sorted(k for k in en if k not in used)
if rest:
    groups.append(dict(pre='', title='Everything else', bud=None,
        ctx='Strings that do not belong to one surface.',
        rows=[dict(key=k, en=en[k], ja=ja.get(k,''), w=cells(fill(ja.get(k,''))), tight=False, over=False) for k in rest]))
import sys, csv, os
data = dict(groups=groups, arrays={k: {'en': ena[k], 'ja': jaa.get(k, [])} for k in ena})
if '--json' in sys.argv:
    json.dump(data, open('/tmp/review.json', 'w'), ensure_ascii=False)
else:
    os.makedirs('docs', exist_ok=True)
    out = 'docs/l10n-review-ja.csv'
    with open(out, 'w', newline='', encoding='utf-8-sig') as fh:
        w = csv.writer(fh)
        w.writerow(['surface', 'key', 'english', 'japanese', 'cells', 'budget',
                    'flag', 'your change', 'notes'])
        for g in groups:
            for r in g['rows']:
                w.writerow([g['title'], r['key'], r['en'], r['ja'], r['w'],
                            g['bud'] or '', 'OVER' if r['over'] else ('tight' if r['tight'] else ''),
                            '', ''])
        for k, v in data['arrays'].items():
            n = max(len(v['en']), len(v['ja']))
            for i in range(n):
                w.writerow(['Region disclaimer', f'{k}[{i}]',
                            v['en'][i] if i < len(v['en']) else '',
                            v['ja'][i] if i < len(v['ja']) else '',
                            '', '', '', '', 'one line on the glasses'])
    print(f"wrote {out}")
print(f"{sum(len(g['rows']) for g in groups)} strings in {len(groups)} surfaces")
