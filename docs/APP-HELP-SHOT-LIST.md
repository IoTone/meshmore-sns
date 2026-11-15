# In-app help: the screenshot list, and the two things that block it

Written 2026-11-15 while replacing `assets/docs/app.md` with the per-feature
reference the STATUS backlog asked for ("Real per-feature app docs
(online-help-md) ... with screenshots").

## What shipped

`meshmore_sns_app/responsive_starter_app/assets/docs/app.md` is now the
per-feature reference rather than a 94-line summary: sixteen sections, one per
feature family, each stating what the feature is for, what it does and what it
cannot do. `test/docs/app_help_test.dart` holds three things to it: the contents
list and the headings agree, every family the app ships has a section, and the
page follows the owner's copy rules (no em dash, no semicolon), because a reader
sees this text inside the app.

That is one page, not the multi-page set with pictures the backlog row asked
for. Two things stop the set, and neither is a writing problem.

## Blocker 1: one asset per Docs section

`lib/docs/doc_section.dart:10` is a closed enum, `DocSection.all` (`:69-75`)
maps each member to exactly one asset path, and `pubspec.yaml:216-219` registers
those four files by name rather than registering the directory. So a per-feature
page set needs:

1. `pubspec.yaml` to register the directory (`- assets/docs/`) or each new page.
2. A document model that is more than one asset per section: either a new
   `DocSection` member per page (sixteen more members, and sixteen more rows in
   the Docs hub) or a section that holds an index and a list of pages.
3. A hub that lists the pages of the App section rather than one row.

That is a change to the docs loader and to the app's asset manifest, which is
outside this pass (which owns `assets/docs/**` and nothing else under `lib/`).

## Blocker 2: an image in a document renders as its alt text

`lib/docs/markdown_view.dart:400-408` turns an `img` node into
`TextSpan(text: '🖼 $alt')`. That is deliberate and documented at `:16` ("images
degrade to alt text", so the reader stays offline), but it means a screenshot
placed in a help page would show as a caption and nothing else. Showing the
pictures needs `MarkdownView` to resolve a relative asset path and draw it,
which is the same slice as blocker 1.

## The shot list

Sixteen shots, one per section. Each entry is the screen, the state the screen
must be in, and the caption the page would carry under it. Take them on the
handset with the paired radio in the state named. Every one is a real state of
the app, not a mock.

| # | Section | Screen | State | Caption |
|---|---|---|---|---|
| 1 | Finding and pairing a radio | Settings -> Radio connection | scanner running, one radio listed | "One radio, one phone. Nothing else stands between them." |
| 2 | The six views | any view, strip visible | default theme | "Six views. The strip is the tap path, the swipe is the shortcut." |
| 3 | Channels | Chat, channel chips | three channels, two with unread counts | "A channel is a name and a key. A tag gives you both from the name." |
| 4 | Direct messages | A DM thread | one message sent, one delivered, one unknown | "Five states, and unknown is one of them. It is not a failure." |
| 5 | Nodes, the tree and routes | Node sheet | a contact with an N-hop route | "The route is what the radio advertises, never a guess." |
| 6 | The map | Map, layers sheet open | places, a fence and the quilt on | "One sheet for what is drawn. The choice survives a restart." |
| 7 | Places | Place create sheet | a label typed, type chosen, TTL picker open | "Six an hour, on purpose. A place report is channel time." |
| 8 | Geofences | Geofences screen with a polygon on the map behind | one circle, one polygon | "A circle, or the shape of the thing you are actually walking." |
| 9 | The hyperlocal grid | Radar, auto range | six nodes, one hollow | "Auto range frames the group. A hollow mark has no position to draw." |
| 10 | Tools | Tools hub | all six rows | "One tool at a time, because each of them needs the radio alone." |
| 11 | Safety | SOS screen, idle | destination channel named | "The alarm names the channel it will use, and never creates one." |
| 12 | Notifications | App settings, notification group | three classes listed, one quieted | "One OS channel per class, so a message and an alarm are separate." |
| 13 | Sound, haptics and speech | Profile -> sound | cue volume slider with the stream named | "The slider names the stream, because only one of them is the one you hear." |
| 14 | Themes | Theme picker | the two light grounds visible | "Eleven presets, one set of measured floors." |
| 15 | Settings, storage | App settings, storage block | every store with a number | "A store that cannot measure itself is absent, not shown as a zero." |
| 16 | What this app cannot do | Chat, a blocked key | block confirmation sheet | "A block filters this device. The radio still carries the packet." |

## Taking them

The handset is the motorola edge 2024 (`ZD222W34LJ`) with the paired radio
attached. `adb exec-out screencap -p > shot-NN.png` per state, cropped to the
app's own content, no status bar. Store them under `assets/docs/app/` beside the
pages once blockers 1 and 2 are closed, and name each file after its section
(`02-views.png`).
