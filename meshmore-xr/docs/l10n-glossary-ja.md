# Japanese glossary — the terms a general reviewer cannot judge

**Why this exists.** The reviewer's own note, and it is a fair one: much of this
app's vocabulary is invented for LoRa mesh radio, amateur radio, or spatial XR.
The words have no everyday Japanese equivalent, so there is no way to say a
translation is good or bad without first knowing what the English word means
*here*. That is a gap in the brief, not in the review.

**And the answer, 2026-08-28: there is no authority to appeal to.** These terms
have no everyday Japanese use, so neither a technical nor a non-technical user
arrives knowing them. Settling them properly would take the makers of the core
technology documenting Japanese terminology, and LoRa adoption in Japan is too
low for that to have happened. **We are not waiting for it.**

That changes the review standard rather than removing it. The question is no
longer "is this the accepted Japanese word", because there is no accepted
Japanese word. It becomes two answerable questions:

1. **Is it consistent** — does one concept read the same way on every screen?
2. **Is it traceable** — can a reader who meets the English term in MeshCore's
   docs, in the firmware, or in someone's node name connect it to what the app
   showed them?

**Question 2 argues for transliteration over translation on protocol terms.**
A Japanese operator will only ever meet `advert`, `flood` and `hop` in English,
because that is the only language they exist in. `アドバート` keeps that thread;
`自己通知` quietly cuts it, and sends someone searching Japanese for a concept
that has no Japanese. This is a recommendation, not a change — `rr_advert` and
`rr_flood` are the reviewer's own wording and are not being overridden a second
time without a decision.

**So this file states the meaning, not the wording.** For each term: what it
denotes in this app, and what the Japanese currently is. The reviewer's job with
this in hand is the one they can actually do — decide whether the Japanese
conveys *that meaning* naturally to a Japanese operator. The English term itself
is not up for review; it is jargon in English too.

Companion to `docs/l10n-review-ja.csv`, which holds per-key status. **The CSV is
the source of truth for Japanese; `values-ja/strings.xml` is built from it.**
Applying the CSV is a step that can be forgotten — it was, for 108 strings
between 2026-08-27 and 08-28 — so check them against each other before trusting
either.

---

## Settled — signed off 2026-08-28

| English | What it means here | Japanese |
|---|---|---|
| BEARING / HEADING / COMPASS | The direction to a node, in degrees from north | `方位` |
| ALL REPEATERS | Every node that forwards other people's packets | `全中継局` |
| FIELD | A spatial layout mode — nodes free-standing in the room | `空間` |
| STALE | Last heard long enough ago that it may no longer be there | `古い` |

`方位` was the one in doubt. It is already this app's word for COMPASS, HEADING
and COMPASS BAND across seven strings, it is the standard navigation term, and
the loanword `ベアリング` would be a false friend — in Japanese that is a *ball*
bearing.

---

## Needs a decision — one concept, several renderings

These are not translation errors. They are consistency errors, and they are
invisible to a reviewer working key by key, because nothing in a single row says
these rows are the same thing.

### ADVERT — four renderings

MeshCore's periodic "I exist" broadcast. It carries a node's identity and,
optionally, its position. It is how a node appears on anyone's mesh at all.

| Key | English | Japanese |
|---|---|---|
| `rr_advert` | SELF ADVERT | `自己通知` |
| `rr_flood` | FLOOD ADVERT | `全体通知` |
| `n_advert_sent` | SELF ADVERT SENT — NEIGHBOURS ONLY | `アドバート送信 — 隣接のみ` |
| `n_flood_sent` | FLOOD ADVERT SENT | `フラッドを送信しました` |

The settings rows translate it (`通知`); the notices transliterate it
(`アドバート`, `フラッド`). A wearer switches on `自己通知`, then sees
`アドバート送信` and has no way to know it is the same action. **Pick one and
apply it to all four.**

### FLOOD — translated in one place, transliterated in four

An advert relayed across the whole mesh rather than only to neighbours. Costs
everyone airtime, which is why it is a deliberate, confirmed action.

`全体通知` in `rr_flood`; `フラッド` in `n_flood_arm`, `n_flood_sent`,
`f_flood_arm`, `tx_flood`.

---

## Done well, and worth not "fixing"

**HEARD is two different words in English and the Japanese already splits them.**
`n_chan_quiet` NOTHING HEARD HERE YET → `まだ受信なし` (nothing *received*, by
radio). `n_tag_none` NOTHING HEARD → `聞き取れず` (nothing *made out*, by
microphone). Correct, and the kind of thing a literal pass would flatten.

---

## The reference list

Terms whose Japanese is settled or in first-pass form, with what each denotes.

### The radio and the mesh

| English | Meaning here | Japanese |
|---|---|---|
| MESH | The LoRa network as a whole | `メッシュ` |
| NODE | One radio on it | `ノード` |
| RADIO | The companion hardware you carry — **the device, not the phenomenon** | `無線機` |
| CONTACT | An entry in the radio's own address book. Finite — 350 slots | `連絡先` |
| HOP | One relay step between nodes | `ホップ` |
| PATH | The route a packet actually took | `経路` |
| DIRECT | Reached without any relay | `直接` |
| DELIVERED | The acknowledgement came back | `到達` |
| ACKED | Same, on the delivery record | `応答あり` |
| TELEMETRY | Sensor readings asked of another radio | `テレメトリ` |

`無線` on its own is radio *as a phenomenon*; `無線機` is the *set*. The
reviewer corrected this across a dozen keys and it should stay corrected.

### Channels and identity

| English | Meaning here | Japanese |
|---|---|---|
| CHANNEL | A shared group. Its key is SHA-256 over the tag's exact bytes | `チャンネル` |
| TAG | The text a channel key is derived from — one wrong character is a different channel | `タグ` |
| KEY | The 32-byte identifier of a node or channel | `鍵` |
| PUBLIC | The channel everyone is on. Never encrypted to a group | `公開` |
| CLAIM / MINE | Marking a node as hardware you own. Gates unattended sending | `自ノード登録` |
| FAVOURITE | A starred node, kept when others are swept | `お気に入り` |
| SOAK | Repeated automated sends, to test whether a link holds | `連続10通` |

### The spatial interface

These are the app's own coinages, not standard XR terms.

| English | Meaning here | Japanese |
|---|---|---|
| PINCH | The select gesture — thumb to forefinger | `ピンチ` |
| HOLD STILL | Gaze and dwell, the alternative to pinching | `半秒静止` |
| DOCK | The row of pips low and to the left that opens surfaces | `ドック` |
| REEL | The wrist menu shown palm-up | `リール` |
| TABLETOP | A layout mode — the mesh stood on a real surface | `卓上` |
| FIELD | A layout mode — nodes free in the room | `空間` |

---

## Still open with the reviewer

- **214 of 339 strings have never been read.** They are the unidiomatic first
  pass. `cm_bearing` — BEARING shipping as `影響`, *influence* — came out of that
  set and suggests what else may be in it.
- **`al_lookalike` has no English key.** The reviewer returned Japanese for it
  and there is no such string in `values/strings.xml`. Either a rename or a
  string that needs adding on the English side first — worth asking which.
- **`ago_day` / `ago_hr` / `ago_min`** came back as `%1$d１日前`, with a
  full-width `1` after the format argument, which renders as "3 1日前". Read as
  an IME slip; the existing `%1$d日前` was kept. Confirm.
