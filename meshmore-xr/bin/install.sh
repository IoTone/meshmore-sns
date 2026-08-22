#!/usr/bin/env bash
# Copyright (c) 2026 IoTone, Inc.
# SPDX-License-Identifier: MIT
#
# INSTALL AND THEN GRANT EVERYTHING, because an uninstall takes the grants with
# it and a hand-written grant list is a list somebody will get wrong.
#
# It was got wrong on 2026-08-21. Installing the release build meant uninstalling
# the debug one, which revoked every runtime permission; the re-grant covered
# Bluetooth, location and the microphone and missed HAND_TRACKING. The app came
# up looking healthy and logged one line about it:
#
#     [stage] hand tracking refused (SecurityException) — gestures off
#
# Hands, ASL and every gesture were dead, which is most of the app. So this
# reads the permission list OUT OF THE MANIFEST rather than repeating it: a
# permission added to the app is granted by this script the same day, with
# nobody remembering to update anything.
#
# Usage:
#   bin/install.sh                       # debug build to the only device
#   bin/install.sh release               # release build (uninstalls first)
#   bin/install.sh debug emulator-5554   # a named device
set -euo pipefail

cd "$(dirname "$0")/.."

VARIANT="${1:-debug}"
DEVICE="${2:-}"
PKG=com.iotj.meshmore.xr
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
[ -n "$DEVICE" ] && ADB="$ADB -s $DEVICE"

case "$VARIANT" in
  debug)   APK=app/build/outputs/apk/debug/app-debug.apk ;;
  release) APK=app/build/outputs/apk/release/app-release.apk ;;
  *) echo "usage: bin/install.sh [debug|release] [device]" >&2; exit 2 ;;
esac

[ -f "$APK" ] || { echo "no $APK — build it first" >&2; exit 1; }

# THE SIGNATURES DIFFER, so debug over release (or the reverse) cannot be an
# upgrade. Try the cheap path, fall back to the one that loses the app's data.
echo "installing ${VARIANT} build"
if ! $ADB install -r -d "$APK" >/dev/null 2>&1; then
  echo "  signature mismatch — uninstalling first (THIS ERASES THEME, TAGS, HISTORY)"
  $ADB uninstall "$PKG" >/dev/null 2>&1 || true
  $ADB install "$APK" >/dev/null
fi

# Every runtime permission the manifest asks for. Install-time permissions
# (VIBRATE, INTERNET, the OpenXR one) refuse a grant; that is expected and not
# an error, so their failure is swallowed and counted rather than printed.
PERMS=$(sed -n 's/.*<uses-permission android:name="\([^"]*\)".*/\1/p' \
          app/src/main/AndroidManifest.xml | sort -u)

granted=0; skipped=0
for p in $PERMS; do
  if $ADB shell pm grant "$PKG" "$p" >/dev/null 2>&1; then
    granted=$((granted + 1))
  else
    skipped=$((skipped + 1))
  fi
done
echo "granted $granted runtime permission(s), $skipped not grantable (install-time)"

# THE ONE THAT MATTERS MOST, CHECKED BY NAME. Without it the app runs, draws,
# connects to the radio and cannot see your hands — which is not a failure any
# casual look at the screen would catch.
if $ADB shell dumpsys package "$PKG" | grep -q "HAND_TRACKING: granted=true"; then
  echo "hand tracking: granted"
else
  echo "HAND TRACKING IS NOT GRANTED — gestures and ASL will be dead" >&2
  exit 1
fi
