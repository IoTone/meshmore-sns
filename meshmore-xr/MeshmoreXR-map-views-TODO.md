# MeshmoreXR — THE MAP VIEWS: a design brief that does not exist yet

**Status: FLAGGED, NOT WRITTEN. Deferred deliberately, 9 August 2026.**

This file exists so the gap is recorded rather than remembered. Nothing here is
a design; it is a list of what has to be designed, and the questions that have
to be answered before any of it can be.

---

## What we have, and what is asked for

Meshmore SNS ships a suite of **hyperlocal map views**. MeshmoreXR has one of
them — **RADAR** — and the brief's §S6 TERRAIN describes the *substrate*
(PMTiles, the scale ladder, floor-scale relief) without ever naming the views
that sit on it.

Ten views, of which one exists:

| View | In XR | Needs a definition carried over from SNS |
|---|---|---|
| **radar** | assumed present | — |
| **globe** | no | world scale; §S6.0 already ports `world-110m.geojson` for this |
| **cells** | no | **see the conflict below** |
| **roads** | no | street network; §S6.0 forbids the OSM tile approach |
| **mesh** | no | the network itself — closest to what HORIZON already draws |
| **fuji** | no | **undefined here** |
| **tree** | no | **undefined here** |
| **sns** | no | **undefined here** |
| **wx** | no | weather, presumably — source and offline story unknown |
| **mbk** | no | **undefined here** |

**Five of the ten are names I cannot define from this repository**, and guessing
at them is exactly the failure this file exists to prevent. `fuji`, `tree`,
`sns`, `mbk` and the precise meaning of `wx` have to come from the SNS
implementation or from the person who named them.

---

## The three questions that block the brief

**1. What is each view actually FOR?**
Not what it draws — what question a wearer opens it to answer. A view that
cannot state that in one sentence is a layer, not a view, and layers belong on
one map rather than in a list of ten.

**2. Which of these are VIEWS and which are LAYERS?**
Ten map modes is a list, and §2.1 rule 2 is explicit that more room means a
bigger world window rather than more UI. It is very likely that some of these
are toggles on a single terrain — roads, mesh and wx all sound like things you
would want *at the same time* — while globe and radar are genuinely different
scales. That distinction changes the whole surface.

**3. What is each one's offline story?**
§S6.0 settled this for the base map and the answer was hard-won: OSM's usage
policy forbids the prefetching the offline requirement needs, so PMTiles it is.
Every view added here has to answer the same question, and `wx` in particular
almost certainly cannot — weather is by definition live data, on a device whose
whole proposition is working where there is no network.

---

## One known conflict, recorded now so it is not discovered later

**`cells` may already have been decided against.** §S6.0 says of SNS's R25
equal-grid view:

> *"R25's equal-grid map does not port, and should not. Equal-area cells exist
> because a phone screen is small and you need comparability between buckets. At
> floor scale you have a real map and real space, so the abstraction has nothing
> to buy. Port the purpose, not the workaround."*

If `cells` is that view, this list and the brief disagree and one of them is
wrong. If `cells` is something else — cell-tower coverage, for instance — then
the name collides with a decision already on the record, which is its own
problem.

---

## What this is not

Not a request to build ten maps. §S6 is a large surface that is not yet built at
all, and the scale ladder has to exist before anything can sit on it. This is a
note that the *view suite* is a design gap nobody has written down, so that when
S6 does get built it is not built for one view and then bent around nine more.
