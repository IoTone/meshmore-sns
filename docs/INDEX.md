# Documentation index

Where to start: for what the app does, read `meshmore-app-spec.md` (the normative requirements) and
`meshmore-feature-register.md` (the single feature list with its state vocabulary). For what is being built next, read
`meshmore-master-plan.md` §9.6 (build order) and the register's open-questions section. For what is known to be broken,
read `docs/MISSING-WORK.md` and the register's §10 residue and §11 pass log.

This index is the only place that lists every document. A document that is not here is not part of the set.

## Authority order

Copied from `meshmore-feature-register.md:7-24`, which is the record for it.

| Order | Document | Authority |
| --- | --- | --- |
| 1 | `meshmore-scope-of-record.md` | Decisions. A ruling here wins over everything below |
| 2 | `meshmore-master-plan.md` | Plan and evidence. §9 supersedes §8, which supersedes §2 and §4 |
| 3 | `meshmore-app-spec.md` | Normative requirements, APP-A to APP-N |
| 4 | the four feature specs at implementation depth | Block, SOS, places, telemetry and coverage |
| 4a | `meshmore-spec-breadth-review.md` | Breadth: what a complete specification needs |
| 5 | `meshmore-feature-audit.md` | What exists, measured against source |
| 6 | `meshmore-sns-spec.md` | History, R1 to R113 |
| 7 | `mesh-research/notes/topics/` | Field evidence, outside this repository |

Two rules the register states and this index repeats: a claim of "shipped" needs the audit, and a claim of "decided"
needs the scope of record.

## The set

Role vocabulary: SPEC OF RECORD, PLAN, AUDIT, STATUS, SUPERSEDED, HISTORICAL, OTHER PRODUCT, VENDORED.

### Entry points and state

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `README.md` | STATUS | What the repository is, and the one measured set of numbers, dated 2026-11-09 | current |
| `docs/INDEX.md` | STATUS | This file. The list of every document and its role | current |
| `meshmore-feature-register.md` | STATUS | The single feature list, the state vocabulary, the merged open-questions register, §10 residue, §11 pass log | current |
| `meshmore-scope-of-record.md` | SPEC OF RECORD | The owner's decisions D1 to D11, with the consequence of each | current |
| `docs/MISSING-WORK.md` | STATUS | Work that is missing or unverified, and the device steps that would close it | current |
| `meshmore_sns_app/STATUS.md` | STATUS | The measured snapshot: test counts, build sizes, device runs, change records from R122 | current, dated 2026-11-12 |
| `meshmore_sns_app/TOOLING.md` | STATUS | The toolchain and the exact verification commands | current |

### Requirements and plans

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `meshmore-app-spec.md` | SPEC OF RECORD | The normative application requirements, APP-A to APP-N, each with a check | current |
| `meshmore-master-plan.md` | PLAN | The build plan, milestones M1 to M7, and the build order in §9.6 | current, status line dated 2026-11-04 |
| `meshmore-execution-plan.md` | HISTORICAL | The supervisor's operating plan of 2026-11-05, and the toolchain facts measured that day | historical |
| `meshmore-feature-plan.md` | SUPERSEDED | The 2026-11-04 analysis trail behind the scope of record | superseded in part by `meshmore-scope-of-record.md` |
| `meshmore-feature-audit.md` | AUDIT | What existed on 2026-11-04, measured against source | historical |
| `meshmore-spec-breadth-review.md` | AUDIT | What a complete specification needs beyond the feature list | historical |
| `meshmore-sns-spec.md` | HISTORICAL | R1 to R113 and the change record | historical |
| `meshmore-sns-UX-spec.md` | SPEC OF RECORD | The UX bindings: spacing contract, accessibility and sensory parity, the U-series plan, the chosen theme direction | current |
| `meshmore-sns-UX-brief.md` | AUDIT | The six design concepts and the research behind them | current as design research |
| `meshmore-publishing.md` | SPEC OF RECORD | The publishing steps, which are verified and which need the publisher | current, verified 2026-11-05 |
| `M6-interop-runbook.md` | PLAN | The on-device interop procedure for M6 | current |

### Feature specifications

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `meshmore-sns-block-spec.md` | SPEC OF RECORD | Blocking a key, at implementation depth. The depth template for the others | current |
| `meshmore-sos-spec.md` | SPEC OF RECORD | SOS and check-in: the send schedule, the ACK grammar, the stop rule | current |
| `meshmore-places-spec.md` | SPEC OF RECORD | Places: the token grammar, the id derivation, the type set, the budget | current |
| `meshmore-telemetry-coverage-spec.md` | SPEC OF RECORD | Telemetry and coverage: the cell model, the pacing, session-only storage | current |
| `meshmore-sns-maps-spec.md` | SPEC OF RECORD | Offline maps: the tile store, packs, layers, the budget | current |
| `meshmore-sns-tools-spec.md` | SPEC OF RECORD | The six tools and their screens | current |
| `meshmore-sns-geofence-tracking.md` | SPEC OF RECORD | Geofences: the model, the hysteresis, the cue and notification requirements | current, two requirements unbuilt (see below) |
| `meshmore-sns-meshbook-mbk.md` | PLAN | The Meshbook earmark, design only | current, not built |
| `meshmore-sns-microclimate-wx.md` | PLAN | The microclimate earmark, design only | current, not built |

### Evidence and investigations

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `meshmore-sns-radio-config.md` | AUDIT | What the firmware's radio settings actually are, read from `companion-v1.17.1` | current |
| `meshmore-sns-radio-alerts.md` | AUDIT | Where the radio's buzzer and vibration live, and how to silence them | current |
| `meshmore-sns-protocol-coverage.md` | AUDIT | Which companion opcodes the app uses, and which MeshCore already offers | current |
| `meshmore-sns-ux-coverage.md` | AUDIT | Which protocol capabilities earn a UI surface, and why | current |
| `meshmore-sns-meshcore-interop.md` | AUDIT | MeshCore as a shared transport for lobospeak, ldmux and MeshMore | current |
| `meshmore-sns-private-mesh-investigation.md` | AUDIT | Private mesh, radio parameters, the haptics storm, the transport selector, 2026-10-26 | historical |
| `meshmore-sns-telemetry-research.md` | AUDIT | Device altitude instead of phone GPS, 2026-05-26 | historical |
| `notes/airtime-audit.md` | AUDIT | Every path that occupies the channel, and every path charged as if it did, 2026-11-14 | current |
| `notes/media-audit.md` | AUDIT | Photo and voice, both directions | current |
| `notes/instrument-modes-audit.md` | AUDIT | The grid's instrument views: tree, weather, cells, elevation | current |
| `notes/bottom-edge-audit.md` | AUDIT | The bottom inset, measured on the handset | current |
| `docs/SPEC-SCOPE-AUDIT.md` | AUDIT | Every spec row that asks for something nothing needs, judged keep / cut / covered, plus the 19 statements that are false against the code, 2026-11-15 | current |
| `docs/APP-HELP-SHOT-LIST.md` | PLAN | The screenshots the in-app reference still needs, with the screen, the state and the caption for each | current |

### Withdrawn architecture

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `meshmore-sns-architecture.md` | HISTORICAL | The two-app gateway architecture of 2026-10-24, withdrawn 2026-11-05 (D10.1) | superseded by `meshmore-scope-of-record.md` §12 |
| `meshmore-sns-architecture-audit.md` | HISTORICAL | The audit of that architecture | superseded by `meshmore-scope-of-record.md` §12 |
| `meshmore-sns-gateway-handoff.md` | HISTORICAL | The gateway handoff procedure | superseded by `meshmore-scope-of-record.md` §12 |
| `meshmore-maps-and-directions.md` | HISTORICAL | The 2026-11-04 map and directions design | superseded by `meshmore-places-spec.md` and `meshmore-sns-maps-spec.md` |

### App-local documentation

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `meshmore_sns_app/README.md` | STATUS | The app directory and how it is laid out | current |
| `meshmore_sns_app/responsive_starter_app/README.md` | HISTORICAL | The Flutter template's own readme | historical |
| `meshmore_sns_app/responsive_starter_app/ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md` | HISTORICAL | The template's launch-image note | historical |
| `meshmore_sns_app/responsive_starter_app/assets/docs/app.md` | SPEC OF RECORD | The in-app document about the app, shipped to the reader | current |
| `meshmore_sns_app/responsive_starter_app/assets/docs/devices.md` | SPEC OF RECORD | The in-app device notes, shipped to the reader | current |
| `meshmore_sns_app/responsive_starter_app/assets/docs/firmware.md` | SPEC OF RECORD | The in-app firmware notes, shipped to the reader | current |
| `meshmore_sns_app/responsive_starter_app/assets/docs/protocol.md` | SPEC OF RECORD | The in-app protocol reference, shipped to the reader | current |

### Packages

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `meshmore_sns_app/packages/meshcore/README.md` | SPEC OF RECORD | The Dart protocol package: what it encodes and decodes | current |
| `meshmore_sns_app/packages/meshcore/CHANGELOG.md` | STATUS | The package's change record | current |
| `meshmore_sns_app/packages/meshcore/test/vectors/interop/SCHEMA.md` | SPEC OF RECORD | The interop fixture schema | current |
| `libmeshcore/README.md` | SPEC OF RECORD | The Java protocol port | current |
| `libmeshcore-android/README.md` | SPEC OF RECORD | The Java Android transport layer | current |
| `libmeshcore/src/test/resources/vectors/interop/SCHEMA.md` | SPEC OF RECORD | The Java side of the interop fixture schema | current |

### Other products in this repository

These are not the SNS app. They are listed so that a reader does not mistake them for it.

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `lobospeak-design.md` | OTHER PRODUCT | The lobospeak (1805PK) design | current for that product |
| `lobospeak-mappins-spec.md` | OTHER PRODUCT | The lobospeak map pins and triggers spec | current for that product |
| `meshmore-xr/MeshmoreXR-design-brief.md` | OTHER PRODUCT | The Android XR client's design brief | current for that product |
| `meshmore-xr/MeshmoreXR-console-spec.md` | OTHER PRODUCT | The XR console | current for that product |
| `meshmore-xr/MeshmoreXR-topology-spec.md` | OTHER PRODUCT | The XR lattice | current for that product |
| `meshmore-xr/MeshmoreXR-audio-haptics.md` | OTHER PRODUCT | XR audio and haptics | current for that product |
| `meshmore-xr/MeshmoreXR-typography.md` | OTHER PRODUCT | XR typography | current for that product |
| `meshmore-xr/MeshmoreXR-theme-expression.md` | OTHER PRODUCT | XR theme expression | current for that product |
| `meshmore-xr/MeshmoreXR-i18n-ja.md` | OTHER PRODUCT | XR Japanese and English | current for that product |
| `meshmore-xr/MeshmoreXR-autopen-spec.md` | OTHER PRODUCT | The XR suggested-reply feature | current for that product |
| `meshmore-xr/MeshmoreXR-course-correction.md` | OTHER PRODUCT | The XR course correction | current for that product |
| `meshmore-xr/MeshmoreXR-map-views-TODO.md` | OTHER PRODUCT | XR map views, not designed yet | current for that product |
| `meshmore-xr/MeshmoreXR-node-identity-TODO.md` | OTHER PRODUCT | XR node identity and telemetry permissions | current for that product |
| `meshmore-xr/AiRspace-UI.md` | OTHER PRODUCT | The AiRspace UI | current for that product |
| `meshmore-xr/AiRspace-HUD-and-symbology.md` | OTHER PRODUCT | AiRspace symbology and the HUD | current for that product |
| `meshmore-xr/airspace-ui/README.md` | OTHER PRODUCT | The AiRspace reference implementation | current for that product |
| `meshmore-xr/PRIVACY.md` | OTHER PRODUCT | The XR privacy policy | current for that product |
| `meshmore-xr/RELEASE-SIGNING.md` | OTHER PRODUCT | XR release signing | current for that product |
| `meshmore-xr-www/content/en/_index.md` | OTHER PRODUCT | The XR site's English landing page | current for that site |
| `meshmore-xr-www/content/en/guide.md` | OTHER PRODUCT | The XR site's English guide | current for that site |
| `meshmore-xr-www/content/en/privacy.md` | OTHER PRODUCT | The XR site's English privacy page | current for that site |
| `meshmore-xr-www/content/en/support.md` | OTHER PRODUCT | The XR site's English support page | current for that site |
| `meshmore-xr-www/content/ja/_index.md` | OTHER PRODUCT | The XR site's Japanese landing page | current for that site |
| `meshmore-xr-www/content/ja/guide.md` | OTHER PRODUCT | The XR site's Japanese guide | current for that site |
| `meshmore-xr-www/content/ja/privacy.md` | OTHER PRODUCT | The XR site's Japanese privacy page | current for that site |
| `meshmore-xr-www/content/ja/support.md` | OTHER PRODUCT | The XR site's Japanese support page | current for that site |

### Research

| Document | Role | What it is the record for | Status |
| --- | --- | --- | --- |
| `AndroidXR_Glasses_Dev_StarterGuide.md` | AUDIT | Android XR glasses development, as researched | historical |
| `AndroidXR_Glasses_UX_Best_Practices.md` | AUDIT | Android XR glasses UX practice, as researched | historical |
| `UX-XR-best-practices.md` | AUDIT | XR, TUI and web UX practice, as researched | historical |

### Vendored

`meshmore_sns_app/third_party/codec2/*.md` are the upstream Codec 2 readmes, vendored unpatched with the library. They
are not project documentation and are not maintained here.

## Known contradictions between documents and code

Verified on 2026-11-14 against the tree at `6feb9a69`. Each row is a document claim and what the code does.

| Document | Claim | Code | What the code does |
| --- | --- | --- | --- |
| `meshmore-sns-geofence-tracking.md:110-111` | A crossing plays `geofenceEnter` or `geofenceExit` | `lib/main.dart:346` | Plays `CueKind.alert`, the same cue as a protocol error |
| `meshmore-sns-geofence-tracking.md:113-116` | A crossing raises an OS notification so it can fire while backgrounded | `lib/notifications/` has no geofence reference | No notification is posted for a fence |
| `meshmore-places-spec.md` (no channel field) | A place report is a channel message | `lib/places/place.dart` has no channel member | The destination channel is not recorded, so the app cannot say where a place came from |
| `meshmore-telemetry-coverage-spec.md:201-204` | Coverage is session-only for this phase, because persisting positions is a privacy commitment | `lib/meshcore/coverage_store.dart:34` (`mm.coverage.v1`), `meshcore_controller.dart:1039,1102` | Coverage cells are written to plain preferences and loaded at startup. The app's own terms text is accurate about it (`termsLocalBody`: "Coverage cells ... are kept too ... they are not encrypted"), so the spec and the register's "Places at rest" row are the stale side, not the code |

Corrected in this pass, so no longer contradictions:

| Document | Was | Now |
| --- | --- | --- |
| `meshmore-sns-UX-spec.md:407` | U5 marked not done | Marked done, with the four files that prove it |
| `meshmore-sns-UX-spec.md:409` | U7 marked not done | Marked done, with the setting and the floor sweep |
| `meshmore-sns-UX-spec.md:417` | U15 marked not done | Marked done, with the prefs class and the channel screen |
| `meshmore-master-plan.md:9` | "planned, not started" read as current | A dated correction sits under the line, pointing at the register for state |
| The R1 to R113 spec | Read as requirements | A historical header now says the record for requirements is `meshmore-app-spec.md` |

The register's §11 records the six stale rows corrected on 2026-11-14 and the work that pass landed.

## How to keep this file true

A new document is added to the table in the same commit that adds the file. A document that stops being the record gets
a superseded header and its status column changes here. A contradiction found between a document and the code is a row
in the table above until one of the two is fixed.
