# MeshmoreXR — Course Correction

**Written 2026-08-02, against `MeshmoreXR-design-brief.md` (rev 2026-08-01) and
the tree at `daf4201`/`9687578`.**

A review of what got built against what was specified. Three findings, in the
order they should be acted on. The last section is the only part that needs a
decision from you rather than work from me.

---

## 1. We stopped finishing P2 and started building P3–P5 instead

The brief is unambiguous about sequencing (§10):

> **P1 and P2 are the whole risk.** If the zone framework and the HORIZON don't
> feel right on real hardware, everything downstream changes — so get to P2
> before building anything else.

P2 is **S1 HORIZON + S2 LINK + S3 NODE FOCUS**. Here is the actual state:

| Phase | Surface | State |
|---|---|---|
| P1 | Zone framework, seven primitives, HALO FIELD | **done** |
| P2 | **S1 HORIZON** | **done**, and good — live mesh, clustering, angular type, lens |
| P2 | **S2 LINK** | **not built** — pairing is adb flags and a bonded radio |
| P2 | **S3 NODE FOCUS** | **not built** — see below |
| P3 | MICROHUD | done (ahead of order) |
| P3 | HAND MENU → shipped as the DOCK | done (ahead of order, and not in the brief) |
| — | §9.6 THE RACK (S9 territory) | done (well ahead of order) |
| — | §9.7 ASL quick actions | done (not in the phase plan at all) |

Of 61 commits since 28 July, roughly a third went into typography, the radio
rack, and the hand classifier. All three are good work. None of them is P2.

**S3 is the one that matters.** Right now, pinching a node does this and only
this (`Horizon.drainSelections` → `pulse`): it emits an expanding ring. No
panel, no callsign, no RSSI, no distance, no last-heard, no spur. Paradigm rule
3 — *one FOCUS at a time* — currently has nothing to focus. The two questions a
mesh operator actually has are "who is that?" and "can I reach them?", and the
app can answer neither by pointing at a node.

The brief's S3 asks for a FOCUS panel at 1.2 m **plus a SPUR painted through the
real world toward the node's true bearing**, and is explicit that the spur, not
the panel, is the real answer. We have every primitive needed to build it: the
node data (`MeshNodes`), the type tiers, the reusable panel path, the billboard
helper, the reach interlock. It is assembly, not invention.

**Recommendation: build S3 NODE FOCUS next, before anything else.** It is the
last load-bearing piece of the phase the brief says carries all the risk, and
it is the difference between a beautiful visualisation and a usable one.

---

## 2. Almost all text is below the brief's own legibility floor

§4.1 sets a hard rule:

> **No text below 1.2° of visual angle**, ever, in any theme, at any distance.
> […] This is roughly 3× what a phone designer's instinct produces, and it is
> the most common reason XR text is unreadable.

I measured every text surface in the app — cap height in metres over its actual
viewing distance:

| Surface | cap (m) | dist (m) | angle | | needs |
|---|---|---|---|---|---|
| Node labels (by range) | 0.0227·r | any | **1.30°** | OK | — |
| HERE marker | 0.036 | 1.57 | **1.31°** | OK | — |
| MICROHUD compass labels | 0.021 | 1.05 | 1.15° | under | 0.0220 (×1.05) |
| HelpCard rows | 0.030 | 1.50 | 1.15° | under | 0.0314 (×1.05) |
| MICROHUD stats line | 0.020 | 1.05 | 1.09° | under | 0.0220 (×1.10) |
| Hands readout (debug) | 0.016 | 0.90 | 1.02° | under | 0.0189 (×1.18) |
| Notice (bearing/nearest) | 0.020 | 1.15 | 1.00° | under | 0.0241 (×1.20) |
| RACK legends | 0.010 | 0.64 | 0.90° | under | 0.0134 (×1.34) |
| **Dock captions** | 0.011 | 0.76 | **0.83°** | under | 0.0160 (×1.45) |

The pattern is exact and worth naming: **the two surfaces that pass are the two
that compute their size angularly.** `CAP_FRACTION = 0.0227` in `MeshNodes` is
1.30° by construction, and `HereMark` inherited the same discipline. Every
surface whose cap height was chosen as a fixed number in metres — picked by eye,
on the device, and it *looked* fine — came out under the floor. Judging type
size by looking at it is precisely what the rule exists to override.

Most of these are a one-constant fix. **The dock is not**, and it is the worst
offender at 69% of the floor — which is my fault twice over, since I sized those
captions and then made them permanent last night without checking them against
§4.1.

**The dock has a real geometry problem at legal size.** Character advance is
about 0.94 × cap height, so an 8-character caption is ~7.5 cap-heights wide. At
1.2° that is **9° of arc per caption**, against a pip pitch of 0.075 m at 0.76 m
= **5.6°**. Captions would overlap by 60%. Moving the dock further away does not
help — both the type and the spacing scale with distance, so the angular
crowding is invariant. Three ways out:

- **(a) Four-character labels.** `COMP LINK RDIO HELP HERE WIDE HAND` ≈ 4.5° —
  fits with margin. Cheapest, but abbreviations are exactly the "guessing game"
  you objected to last night.
- **(b) Two-row stagger**, alternating captions high and low. Doubles the
  budget to 11.2° per row. Keeps full words. My recommendation.
- **(c) Widen the pitch to 9.5°** — the dock then spans 57° of a 61° FOV. Not
  viable.

This is decision **D1** below.

---

## 3. Three stated non-negotiables are unmet, and the gap is widening

§8.2 lists these as *non-negotiable*, not aspirational:

1. **"No information by position alone. A node behind you must be reachable
   without turning around. Every HORIZON element has an equivalent entry in a
   FOCUS list view."** — There is no list view. Bearing is the *only* access
   path to a node. The lens/magnify work made spatial access better, which is
   good, but it made the app *more* position-dependent, not less.

2. **"Gaze-and-dwell as a full alternative to pinch, for users who cannot
   reliably pinch and for when hand tracking is denied or degraded."** — Not
   built. Every control in the app — dock pips, node selection, rack, radial
   menu — is pinch-only. If hand tracking is denied, the app has no inputs at
   all. Note this is also a *robustness* issue, not only an access one: we have
   already spent two debugging sessions on hand tracking dropping out.

3. **Seated / limited-mobility mode** (360° → 120° forward arc with explicit
   bearing labels). Not built.

None of these blocks a demo. All three get more expensive with every surface
added on top of a pinch-only, bearing-only foundation — which is the argument
for deciding *now* whether they are still commitments. If they are, the list
view falls naturally out of S3 (it is the same data and the same panel), and
that is a good reason to build them together.

---

## 4. The brief has drifted behind the code

Small, but it is how a spec stops being trustworthy:

- **§9.7's gesture table lists only right-A and left-A.** The code now also has
  **B on both hands** (back out one level while magnified), added last night.
  The table needs the row.
- **§9.7.1 item 3 says "the classifier knows A and H."** It knows A, B and H.
- **`Letter.H` is classified but bound to nothing.** Dead capability, and two
  fingers up is a common enough shape that it is a live false-positive source
  with no upside. Either bind it or stop classifying it.
- **The DOCK is not in the brief at all.** It is the app's primary navigation
  surface and it arrived as an unplanned answer to "settings must be summoned".
  The brief specifies a HAND MENU (§5, "HAND SURFACES") for that role. Either
  the dock replaces it and §5 should say so, or they are different things and
  the relationship needs writing down.
- **§9.7.1 item 1, the first-run tutorial, is still owed** and is now the only
  part of the ASL work not done. Every gesture is undiscoverable until it exists
  — the help card helps, but only for someone who already found the HELP pip.

---

## 5. Recommended plan for the next session

Assuming the demo is Monday, split it:

**Before the demo — small, low-risk, high-visible-payoff (≈1 hour):**

1. Raise the five near-floor surfaces to ≥1.2°: MICROHUD ×1.05/×1.10,
   HelpCard ×1.05, Notice ×1.20, Hands readout ×1.18. Pure constants, no layout
   consequence at those ratios. The HUD and the Notice are both things a viewer
   will be asked to read.
2. Turn the diagnostics panel **off** by default. It was explicitly temporary
   and it is the least paradigm-consistent thing on screen — a scrolling list,
   which §2 exists to eliminate.
3. Decide **D1** and fix the dock captions to legal size.

**Do not** start S3 before the demo. It is a new surface and new surfaces fail
in front of people.

**After the demo, in order:**

4. **S3 NODE FOCUS** — panel + spur. Closes P2.
5. **The FOCUS list view** — falls out of S3's data, and discharges
   non-negotiable §8.2(1).
6. **Gaze-and-dwell** as a parallel input path — discharges §8.2(2) and removes
   the hand-tracking single point of failure.
7. **S2 LINK** — the last P2 piece. Lower urgency because a bonded radio makes
   it invisible day to day, but it is the whole first-run experience for anyone
   who is not you.
8. Reconcile the brief: dock vs HAND MENU, the B gesture, unbind or bind H.

---

## 6. Decisions I need from you

- **D1 — Dock caption legibility.** Four-character labels (a), two-row stagger
  (b, my recommendation), or knowingly accept 0.83° and write the exception into
  §4.1 with a reason? The rule currently says "ever … at any distance", so an
  exception has to be deliberate rather than an oversight.
- **D2 — Are the §8.2 non-negotiables still non-negotiable?** If yes, items 5
  and 6 above are not optional and should be scheduled, not deferred. If they
  have become "later", the brief should say so honestly rather than carry a
  commitment we are steadily building away from.
- **D3 — Does the DOCK replace the HAND MENU, or coexist with it?** This
  determines whether §5's HAND SURFACES section gets rewritten or gets a
  sibling.
- **D4 — `Letter.H`: bind it or drop it?** It costs false positives for nothing
  at present.

---

## What is genuinely in good shape

Worth saying, because the above is all deficits. The rendering foundation is
strong and was hard-won: the three-tier type system with real font fallback, the
angular sizing discipline, the primitive set, the panel sizing rule (finally
correct after three attempts), the hand classifier settled on hardware rather
than derived, the audio and focus cues, and a deploy/capture loop that makes
"measure, don't reason" cheap. The horizon itself — live mesh, clustering,
lensing into a cluster and back — is the paradigm working, on real hardware,
which is exactly what P1/P2 were supposed to prove. None of section 1 above is
an argument that the work was wrong; it is an argument that it is time to go
back and close the phase.
