#!/usr/bin/env bash
# Copyright (c) 2026 IoTone, Inc.
# SPDX-License-Identifier: MIT
#
# Store readiness: 16 KB page sizes (Android requires them from 1 Feb 2027).
#
# Two things have to hold for every native library the APK ships:
#   1. each PT_LOAD segment is aligned to at least 16 KB, so the loader can map
#      the segment at a 16 KB-page address;
#   2. the GNU_RELRO range ends at or before the next PT_LOAD once rounded up to
#      a 16 KB page, so the read-only remap cannot cover writable data.
# And the archive itself must keep every .so stored uncompressed and 16 KB
# aligned: `zipalign -P 16`.
#
# Usage: tool/check_16k.sh [path/to/app.apk]
# Exit status is non-zero if any library or the archive fails.

set -uo pipefail

APK="${1:-build/app/outputs/flutter-apk/app-debug.apk}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
ZIPALIGN="$(ls -d "$ANDROID_HOME"/build-tools/*/zipalign 2>/dev/null | sort -V | tail -1)"

[ -f "$APK" ] || { echo "no APK at $APK — run: flutter build apk --debug"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q -o "$APK" 'lib/*' -d "$WORK" 2>/dev/null || { echo "APK has no lib/"; exit 2; }

python3 - "$WORK" <<'PY'
import glob, subprocess, sys

PAGE = 16 * 1024

def align_up(x):
    return (x + PAGE - 1) // PAGE * PAGE

status = 0
print(f"{'library':46s} {'load_align':>10s} {'relro_end':>10s} {'next_load':>10s}  verdict")
for so in sorted(glob.glob(sys.argv[1] + '/lib/*/*.so')):
    rel = 'lib/' + so.split('/lib/', 1)[1]
    out = subprocess.run(['readelf', '-lW', so], capture_output=True, text=True).stdout
    loads, relro = [], None
    for line in out.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == 'LOAD' and len(parts) >= 8:
            loads.append((int(parts[2], 16), int(parts[5], 16), int(parts[-1], 16)))
        elif parts[0] == 'GNU_RELRO' and len(parts) >= 6:
            relro = (int(parts[2], 16), int(parts[5], 16))
    if not loads:
        print(f"{rel:46s}  no PT_LOAD — verdict fail")
        status = 1
        continue
    min_align = min(l[2] for l in loads)
    if relro is None:
        print(f"{rel:46s} {min_align:10x} {'-':>10s} {'-':>10s}  fail: no GNU_RELRO")
        status = 1
        continue
    end = relro[0] + relro[1]
    nxt = min((l[0] for l in loads if l[0] > end), default=None)
    ok = min_align >= PAGE and (nxt is None or align_up(end) <= nxt)
    if not ok:
        status = 1
    print(
        f"{rel:46s} {min_align:10x} {align_up(end):10x} "
        f"{(f'{nxt:x}' if nxt else '-'):>10s}  {'ok' if ok else 'fail'}"
    )
sys.exit(status)
PY
status=$?

if [ -n "$ZIPALIGN" ]; then
  if "$ZIPALIGN" -c -P 16 4 "$APK" >/dev/null 2>&1; then
    echo "zipalign -P 16: ok"
  else
    echo "zipalign -P 16: FAIL"
    status=1
  fi
else
  echo "zipalign: not found under $ANDROID_HOME/build-tools — archive check skipped"
fi

exit "$status"
