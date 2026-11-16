> **Historical. This is the 2026-11-04 review of what the specification set was missing, and the gaps it closed then.**
> The record for the requirements is `meshmore-app-spec.md`, and for the list `meshmore-feature-register.md`. See `docs/INDEX.md` for the role of every document.

# Specification breadth review

Written 2026-11-04. This is not a feature list and not an audit of the app's screens. It asks one question: **if
someone had to build every change in this set from these documents alone, what would they find missing?** The answer is
organised as a checklist of the concerns a complete specification needs, each marked with where it is covered, and the
gaps that were filled in this pass.

Read with `meshmore-feature-register.md` (the list) and `meshmore-app-spec.md` (the requirements). This document
explains the *shape* of the set, not its contents.

## 1. The checklist

Status: **covered** (a requirement exists and has a check) · **partial** (a decision exists, the requirement does not)
· **added** (was missing, written in this pass) · **out** (deliberately not specified, with the reason).

| Concern | Status | Where |
| --- | --- | --- |
| Transport and link lifecycle | covered | APP-A1–A3 |
| Capability probing and refusal | covered | APP-A4, APP-N7 |
| Frame decode and unknown types | covered | APP-A5 |
| Command surface (what is exposed, what is refused) | covered | APP-A6, APP-A7 |
| Channel key derivation and tag normalization | **added** | APP-A8 |
| Inbound pipeline and block filter | covered | APP-B1–B4, APP-F1–F3 |
| Send lifecycle, correlation, terminal states | covered | APP-C1–C4 |
| Composer budget and drafts | covered | APP-D1–D3, APP-E7 |
| Storage encryption, bounds, backup | covered | APP-E1–E3 |
| Identity replacement, multi-radio | covered | APP-E4, APP-E5 |
| Message search | **added** | APP-E6 |
| Places: grammar, id, TTL, precision, confirmations | covered | APP-G1–G6, places spec |
| Field operations: SOS, check-in, coverage | covered | APP-H1–H6, SOS and coverage specs |
| Media: format, pacing, FEC, path requirement | covered | APP-I1–I3 |
| Notifications: channels, mentions, permission flow | covered | APP-J1–J3, APP-N8 |
| Accessibility and localisation | covered | APP-K1–K3 |
| Diagnostics and redaction | covered | APP-L1–L2 |
| Gateway coupling | covered | APP-M1–M6 |
| **Schema versioning and migration** | **added** | APP-N1 |
| **Error catalogue** | **added** | APP-N2 |
| **Time model (three clocks)** | **added** | APP-N3 |
| **Degraded modes** | **added** | APP-N4 |
| **Export container format** | **added** | APP-N5 |
| **Performance budgets** | **added** | APP-N6 |
| **Interop matrix** | **added** | APP-N7 |
| Data retention and eviction | covered | D8.6, APP-E2 |
| Threat model | partial | `meshmore-sns-architecture.md` §7 covers the gateway; the app-level model is scattered |
| Message ordering and duplicate suppression across reconnect | partial | the offline queue and seen table are documented in the corpus; no app requirement |
| Contact lifecycle (remove, re-add, rename, key change) | partial | APP-B3 and the block spec cover identity; rename and re-add are not specified |
| Onboarding and first run | partial | a screen exists; no requirement |
| Theme, dark mode, text density | out | presentation, not behaviour; the UX spec owns it |
| Feature flags and kill switches | out | there is no cloud, so a remote kill switch cannot exist; a local flag is a build-time decision |
| Firmware changes | out | this set specifies the app; firmware work is a separate track |
| Legal and export compliance | out of this document | tracked as a register row with a deadline, not a requirement |
| Store listing and data-safety declaration | out of this document | the wording is a release task; the facts it must state are in D8.18 and APP-E3 |

## 2. What the breadth review found wrong

Six inconsistencies, all corrected in place. They are listed because the pattern matters more than the individual
fixes: every one came from a document asserting something the code did not say.

1. **The `#emergency` key was described as a hardcoded constant.** It is `SHA-256("#emergency")[0:16]` — keymind
   hardcodes those bytes, wadamesh-tak derives them from the name, and the app already computes them. The correction
   changed the decision: the channel is public *by construction*, and the app offers a one-tap add rather than
   creating it silently (D8.23).
2. **The SOS schedule did not add up.** "12 sends at 60 s (12 minutes) plus a beacon every 5 minutes for 60 minutes"
   ends at 72 minutes. Corrected to 12 sends at 0–660 s and 10 beacons at 720–3420 s, hard stop 3600 s (D8.4).
3. **The place id carried a time bucket** in the item model while the TTL rules said renewal keeps the id. The two
   cannot both hold; the time bucket was removed (D8.2).
4. **Self telemetry was said to contend for the request slot.** It is answered synchronously; only the peer form
   reserves the slot (D8.26).
5. **Two requirements used a different label style** (`**APP-E6. Title.**`), which silently broke every mechanical
   check that counted requirements. Normalised, and the same mistake was caught again in the new group N.
6. **The channel tag field derives different keys for `emergency` and `#emergency`** while the weak-tag check on the
   same screen strips the `#`. That is a live defect, not a documentation error, and it is now APP-A8.

## 3. What is deliberately not specified

- **Firmware behaviour.** The app cannot change it, and every firmware claim here is a constraint, not a requirement.
- **The XR client.** It is a separate product with its own policy; the boundary is in the scope of record §8.
- **Visual design.** The UX spec and brief own it. This set specifies behaviour and copy, not layout.
- **Anything that needs a measurement to be true.** The three measurement protocols in the plan's §9.14 are the
  boundary: where a number depends on one, the requirement says it is a default, not a finding.

## 4. What is still genuinely open

Three judgement calls, not findings: whether the app creates `#emergency` itself (decided: offers, never silently),
whether unkeyed places get a "keyed only" filter (not built), and whether a key-bound refutation should shorten a TTL
for everyone (decided no). Plus the three measurements, which have protocols and no results.

**The honest summary of breadth:** the feature surface is specified to a testable level, and the cross-cutting
concerns that features silently depend on — migration, errors, time, degraded modes, export format, performance,
interop, notification permission — were the real gap. They are now requirements rather than assumptions.
