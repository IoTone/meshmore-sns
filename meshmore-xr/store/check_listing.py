#!/usr/bin/env python3
"""Assert every listing field is inside Play's limit.

Play counts CHARACTERS, not bytes — a Japanese description well under 4000
characters is far over 4000 bytes, and a byte-based check would reject copy
Play accepts. Counting the wrong unit is the whole reason this exists.
"""
import re, sys, pathlib

LIMITS = {"App name": 30, "Short description": 80, "Full description": 4000}
src = pathlib.Path(__file__).with_name("LISTING.md").read_text(encoding="utf-8")

# Split into sections at every heading, so a section only owns its own fences.
parts = re.split(r"^##+ +(.+?)\s*$", src, flags=re.M)
bad = []
for i in range(1, len(parts), 2):
    name = re.sub(r"\s*\*\(limit \d+\)\*", "", parts[i]).strip()
    limit = next((v for k, v in LIMITS.items() if name.startswith(k)), None)
    if limit is None:
        continue
    for body in re.findall(r"```\n(.*?)```", parts[i + 1], re.S):
        n = len(body.rstrip("\n"))
        ok = n <= limit
        print(f"{'OK  ' if ok else 'OVER'}  {name:34s} {n:5d} / {limit}")
        if not ok:
            bad.append(name)

print("\nFAIL" if bad else "\nall fields within limits")
sys.exit(1 if bad else 0)
