---
title: "Support"
description: "Getting help with Meshmore XR."
url: /support/
---

## Before anything else

Most "it doesn't connect" reports are one of three things:

1. **The radio is off or out of Bluetooth range.** The status band counts how
   long the link has been down (`LOST 4M`); the app reconnects on its own when
   the radio returns.
2. **No position fix.** A radio without GPS reports no position, and without
   one the ring cannot place nodes. The band says `NO FIX` and names the
   remedy — the HERE control enables the headset's GPS as a fallback.
3. **Region mismatch.** Your radio must be on a preset that is legal where you
   are, and every node you talk to must share it. SETUP → DEVICE → REGION.

## Japan / 日本のユーザーへ

Presets alone are not legal authority to transmit: the **hardware** must carry
技適 (Giteki) certification. Many imported boards do not. The app repeats this
in its ABOUT screen, in Japanese.

## Contact

Email **privacy@iotone.io** with the app version (shown on the splash and in
SETUP → ABOUT) and, if it is a connection issue, your radio model.
