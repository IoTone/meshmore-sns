# MeshmoreXR — Play Store listing copy

Paste-ready. Character counts are checked by `store/check_listing.py`; every
field below is inside Play's limit.

---

## App name  *(limit 30)*

```
Meshmore XR
```

## Short description  *(limit 80)*

```
Your LoRa mesh, standing around you. Offline-first MeshCore client for XR.
```

### Short description — Japanese  *(limit 80)*

```
あなたのLoRaメッシュを空間に。XR向けオフライン優先MeshCoreクライアント。
```

---

## Full description  *(limit 4000)*

```
Meshmore XR turns a MeshCore LoRa radio into a network you can see standing
around you.

There is no home screen. Every node your radio has heard is placed at its true
bearing and range — nearer nodes nearer, further nodes further, out to a
horizon ring with callsigns, distances and hop counts. You turn your head to
look at your mesh instead of scrolling a list of it.

OFFLINE FIRST, AND MEANT IT
No accounts. No servers. No internet. Everything you see is read straight off
the mesh through a MeshCore companion radio paired over Bluetooth. The app
works with the network down because it never needed the network.

WHAT YOU CAN DO
• See the mesh — range rings, callsigns, bearings, hop counts, signal
• Message anyone — dictate a message and watch the draft fill word by word
• Know it arrived — every direct message carries a real delivery state, not a
  hopeful "sent". Delivered when the acknowledgement lands, or NO ANSWER
• Join channels — type a #tag; the key is derived from the exact characters
• Mesh weather — most radios ship with telemetry switched off, so the app reads
  the weather people actually mention on the public channel and groups it by
  where the sender is standing, with how long ago it was said
• Meshbook — what kind of day this mesh had: how busy, who carried it, what it
  was about, and when the band is awake. Computed from messages already on the
  device, so it costs no airtime and works with the radio off
• Nine visual themes, each with its own palette, symbols and generated sound

BUILT FOR OPTICAL SEE-THROUGH
Surfaces are drawn in light on a display where black is simply absence. Type is
sized by angle rather than by pixels, so it stays legible at any distance, and
every gesture has a gaze-and-dwell equivalent — nothing here requires working
hand tracking.

PRIVACY
The app collects nothing and sends nothing to us. There is no analytics, no
account and no server. A location fix is used on-device to compute bearings;
your position is broadcast to the mesh only if you switch that on yourself,
and that is a separate setting on purpose.

REQUIREMENTS
• An Android XR device
• A MeshCore companion radio, paired over Bluetooth LE

SAFETY
Do not use while driving or operating machinery. Range and bearing are computed
from adverts other radios chose to send, and can be wrong, absent or stale — do
not navigate by them.

Meshmore XR is an independent client for the MeshCore project and is not
affiliated with it.
```

---

## Full description — Japanese  *(limit 4000)*

> Parity with the English copy is deliberate — see the table in
> "Locales, and what each one owes" below. Any edit here must keep both in step.
> **Not yet native-reviewed.** The sections marked new on 08-27 have not been
> through the reviewer who has the string form.

```
Meshmore XR は、MeshCore の LoRa メッシュを空間に描き出すクライアントです。

ホーム画面はありません。受信したノードは実際の方位と距離に配置され、近い局は
近くに、遠い局は遠くに、コールサイン・距離・ホップ数とともに水平線のリングまで
広がります。一覧をスクロールするのではなく、頭を向けて自分のメッシュを見ます。

オフライン優先、徹底して
アカウント不要、サーバー不要、インターネット不要。表示されるものはすべて、
Bluetooth で接続した MeshCore 対応無線機から直接読み取っています。ネットワークが
止まっていても動作します。もともと必要としていないからです。

主な機能
• メッシュの可視化 — 距離リング、コールサイン、方位、ホップ数、信号
• メッセージ送信 — 音声入力で下書きが一語ずつ表示され、そのまま送信できます
• 到達確認 — 直接メッセージには実際の到達状態が付きます。「送信しました」では
  なく、確認応答が届けば配達済み、届かなければ NO ANSWER と表示されます
• チャンネル参加 — #タグを入力すると、その文字列そのものから鍵が導出されます
• メッシュ天候 — 多くの無線機はテレメトリが無効のまま出荷されるため、本アプリは
  公開チャンネルで実際に語られた天候を読み取り、発言者の位置ごとにまとめ、
  どれくらい前の情報かを表示します
• Meshbook — その日のメッシュの様子（通信量、中心となった局、話題、電波が活発な
  時間帯）を、端末内のメッセージだけから集計します。電波を消費せず、無線機の
  電源が入っていなくても動作します
• 9 種類のテーマ（配色・記号・生成音）

光学シースルーのための設計
表示面は光で描かれます。この方式では黒は「何も出さない」ことを意味します。
文字の大きさはピクセルではなく視野角で決まるため、どの距離でも読めます。
すべての操作には視線と長押しによる代替手段があり、ハンドトラッキングが
動作しなくても使えます。

プライバシー
本アプリは情報を収集せず、当社へ送信しません。アナリティクス、アカウント、
サーバーのいずれもありません。位置情報は方位計算のために端末内で使われます。
メッシュへの位置共有は、利用者が自分で有効にした場合のみ行われ、これは意図的に
別の設定になっています。

必要なもの
• Android XR 端末
• MeshCore 対応無線機（Bluetooth LE 接続）

安全上の注意
運転中や機械の操作中には使用しないでください。方位と距離は他局の送信内容に基づく
ため、誤り・欠落・古い情報の可能性があります。ナビゲーションには使用しないで
ください。

本アプリは MeshCore プロジェクトの非公式クライアントであり、同プロジェクトとは
関係ありません。
```

---

## Locales, and what each one owes

**Default language: `en-US`.** Everything else is a translation of it, and Play
falls back to it for any field a translation leaves empty.

| Field | en-US | ja-JP | Falls back? |
|---|---|---|---|
| App name (30) | `Meshmore XR` | `Meshmore XR` — **same on purpose**, it is a product name, not a phrase | yes |
| Short description (80) | ✅ | ✅ | yes |
| Full description (4000) | ✅ | ✅ | yes |
| App icon | ✅ | — | **yes**, one icon serves every locale |
| Feature graphic | ✅ | — | **yes** |
| Screenshots | ✅ ×8 | — | **yes** — and two of the eight are already Japanese UI, so the default set reads honestly in both stores |
| Promo video | one YouTube URL | — | **yes**, and Play takes one video per listing regardless of locale |

So adding Japanese costs exactly **three text fields** and no new artwork. That
is worth knowing before §2.3 is decided: the argument against shipping Japanese
at beta is review quality, never effort.

### Parity, section by section

The Japanese copy was abridged when first written — it was missing a section and
had four bullets flattened to one clause each. Corrected 2026-08-27.

| Section | en-US | ja-JP |
|---|---|---|
| Opening | ✅ | ✅ |
| No home screen | ✅ | ✅ |
| Offline first | ✅ | ✅ *(was missing "works with the network down")* |
| See the mesh | ✅ | ✅ |
| Message anyone | ✅ | ✅ |
| Know it arrived | ✅ | ✅ *(was missing DELIVERED vs NO ANSWER)* |
| Join channels | ✅ | ✅ *(was missing "the exact characters")* |
| Mesh weather | ✅ | ✅ *(was missing "telemetry ships off")* |
| Meshbook | ✅ | ✅ *(was missing costs-no-airtime, works-radio-off)* |
| Nine themes | ✅ | ✅ |
| Built for optical see-through | ✅ | ✅ **— was absent entirely** |
| Privacy | ✅ | ✅ *(was missing "no analytics, no account, no server")* |
| Requirements | ✅ | ✅ |
| Safety | ✅ | ✅ |
| Not affiliated | ✅ | ✅ |

**The see-through section was the one that mattered.** It is the paragraph that
explains why the app looks the way it does, and a Japanese shopper was getting a
listing that described a 3D app with no reason for any of its choices.

---

## Prepared answers for the Console forms

### Data safety

| Question | Answer |
|---|---|
| Does your app collect or share user data? | **No** |
| Data encrypted in transit | N/A — no data leaves the device to us |
| Users can request deletion | N/A — nothing is collected |
| Location | Used **on device only**, to compute bearings. Broadcast over LoRa only when the user enables position sharing. Not collected by the developer |
| Microphone | Used **on device** for dictation via the platform speech recogniser. Not recorded, stored or transmitted by us |
| Messages | Sent peer-to-peer over LoRa radio. Never routed through a server we operate |

### Content rating questionnaire

- Category: **Communication**
- User-generated content / user-to-user communication: **Yes** — messages are
  peer-to-peer over LoRa radio; there is no server, no moderation surface and
  no directory. Say so plainly rather than claiming moderation that cannot
  exist on a radio protocol.
- Violence, sexual content, profanity, gambling, drugs: **No**
- Shares user location: **Only if the user enables it**, and to the LoRa mesh
  rather than to the developer

### Ads

**No ads.** No advertising SDK is present.

### Target audience

Adults. Not directed at children.
