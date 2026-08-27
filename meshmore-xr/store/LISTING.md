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
あなたのLoRaメッシュを空間に。オフライン優先のMeshCoreクライアント。
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

```
Meshmore XR は、MeshCore の LoRa メッシュを空間に描き出すクライアントです。

ホーム画面はありません。受信したノードは実際の方位と距離に配置され、近い局は
近くに、遠い局は遠くに、コールサイン・距離・ホップ数とともに水平線のリングまで
広がります。一覧をスクロールするのではなく、頭を向けて自分のメッシュを見ます。

オフライン優先
アカウント不要、サーバー不要、インターネット不要。表示されるものはすべて、
Bluetooth で接続した MeshCore 対応無線機から直接読み取っています。

主な機能
• メッシュの可視化 — 距離リング、コールサイン、方位、ホップ数、信号
• メッセージ送信 — 音声入力で下書きが一語ずつ表示されます
• 到達確認 — 直接メッセージには実際の到達状態が付きます
• チャンネル参加 — #タグを入力すると鍵が導出されます
• メッシュ天候 — 公開チャンネルの発言から天候を読み取り、発言者の位置ごとに
  まとめ、どれくらい前の情報かを表示します
• Meshbook — その日のメッシュの様子を、端末内のメッセージだけから集計します
• 9 種類のテーマ（配色・記号・生成音）

プライバシー
本アプリは情報を収集せず、当社へ送信しません。位置情報は方位計算のために端末内
で使われます。メッシュへの位置共有は、利用者が自分で有効にした場合のみ行われます。

必要なもの
• Android XR 端末
• MeshCore 対応無線機（Bluetooth LE 接続）

安全上の注意
運転中や機械の操作中には使用しないでください。方位と距離は他局の送信内容に基づく
ため、誤り・欠落・古い情報の可能性があります。ナビゲーションには使用しないで
ください。

本アプリは MeshCore プロジェクトの非公式クライアントです。
```

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
