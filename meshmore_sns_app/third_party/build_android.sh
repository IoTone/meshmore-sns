#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 IoTone, Inc.
#
# Build the two Codec 2 shared objects the voice feature loads, and a host build
# of the same codec so the Dart side has something testable on a desk.
#
# Two libraries, not one. `libcodec2.so` is the pristine upstream build and
# `libcodec2bridge.so` is our MIT shim, linked against it. Under LGPL 2.1 §6(b)
# the library has to stay a distinct, individually replaceable object inside the
# APK, and fusing the two would remove the strongest part of that position.
#
# Only the two modes the feature ships are compiled in: 700C (28 bits per 40 ms,
# the only mode that fits a 20-second note into about a dozen datagrams) and 1300
# (52 bits, and the one mode wired for a bit-error estimate, which matters on a
# lossy mesh). A mode that is not compiled in cannot be opened at all, which is
# a better guarantee than a runtime check.
#
# Usage:
#   third_party/build_android.sh [arm64-v8a|armeabi-v7a]
#
# Run it once per ABI: Flutter's Gradle plugin ships armeabi-v7a, arm64-v8a and
# x86_64, so an ABI with no jniLibs directory is an ABI where the feature cannot
# load. Both shipped ABIs are built and committed; x86_64 is the emulator's and
# is built the same way when a desk needs it.
#
# Outputs:
#   android/app/src/main/jniLibs/<abi>/libcodec2.so
#   android/app/src/main/jniLibs/<abi>/libcodec2bridge.so
#
# The build directories live under $BUILD_ROOT (default: a temp dir) and are not
# committed; the artefacts are, because AGP packages jniLibs as they are and does
# not build them.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
APP="$REPO/meshmore_sns_app/responsive_starter_app"
CODEC2="$HERE/codec2"
BRIDGE="$HERE/codec2_bridge"
ABI="${1:-arm64-v8a}"
BUILD_ROOT="${BUILD_ROOT:-/tmp/mm-codec2-build}"
NDK="${ANDROID_NDK:-$HOME/Android/Sdk/ndk/28.2.13676358}"
API=24
PAGE_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
MODE_DEFS="-DCODEC2_MODE_EN_DEFAULT=0 -DCODEC2_MODE_700C_EN=1 -DCODEC2_MODE_1300_EN=1"

if [ ! -d "$NDK" ]; then
  echo "no NDK at $NDK; set ANDROID_NDK" >&2
  exit 1
fi
TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
TOOLS="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"

echo "== codec2: configure ($ABI, API $API)"
rm -rf "$BUILD_ROOT/codec2-$ABI"
cmake -G Ninja -S "$CODEC2" -B "$BUILD_ROOT/codec2-$ABI" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release \
  -DUNITTEST=OFF -DLPCNET=OFF \
  -DCMAKE_C_FLAGS="$MODE_DEFS -fvisibility=default " \
  -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_FLAGS" >/dev/null

echo "== codec2: build"
cmake --build "$BUILD_ROOT/codec2-$ABI" --target codec2

echo "== bridge: configure ($ABI, API $API)"
rm -rf "$BUILD_ROOT/bridge-$ABI"
cmake -G Ninja -S "$BRIDGE" -B "$BUILD_ROOT/bridge-$ABI" \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCODEC2_LIB="$BUILD_ROOT/codec2-$ABI/src/libcodec2.so" \
  "-DCODEC2_INCLUDE=$CODEC2/src;$BUILD_ROOT/codec2-$ABI" \
  -DCMAKE_SHARED_LINKER_FLAGS="$PAGE_FLAGS" >/dev/null

echo "== bridge: build"
cmake --build "$BUILD_ROOT/bridge-$ABI"

echo "== strip debug info (the app ships a release library; an unstripped copy stays in the build dir)"
DEST="$APP/android/app/src/main/jniLibs/$ABI"
mkdir -p "$DEST"
cp "$BUILD_ROOT/codec2-$ABI/src/libcodec2.so" "$DEST/libcodec2.so"
cp "$BUILD_ROOT/bridge-$ABI/libcodec2bridge.so" "$DEST/libcodec2bridge.so"
"$TOOLS/llvm-strip" --strip-debug "$DEST/libcodec2.so" "$DEST/libcodec2bridge.so"

echo "== 16 KB checks (both halves: LOAD alignment and the RELRO end)"
status=0
for so in "$DEST/libcodec2.so" "$DEST/libcodec2bridge.so"; do
  name="$(basename "$so")"
  bad_load=$("$TOOLS/llvm-readelf" -lW "$so" | awk '$1=="LOAD" && strtonum($NF) < 16384' | wc -l)
  relro_bad=$("$TOOLS/llvm-readelf" -lW "$so" | awk '$1=="GNU_RELRO"{va=strtonum($3); ms=strtonum($6); if (((va+ms)%16384)!=0) print "bad"}' | wc -l)
  if [ "$bad_load" -ne 0 ] || [ "$relro_bad" -ne 0 ]; then
    echo "  $name: FAIL (load-segments-under-16k=$bad_load, relro-misaligned=$relro_bad)" >&2
    status=1
  else
    echo "  $name: ok (every LOAD at or above 16 KB, RELRO end 16 KB aligned)"
  fi
done
[ "$status" -eq 0 ] || exit "$status"

echo "== exported surface"
"$TOOLS/llvm-readelf" --dyn-symbols "$DEST/libcodec2.so" |
  grep -cE "FUNC +GLOBAL +DEFAULT +[0-9]+ codec2_" | sed 's/^/  libcodec2.so exports codec2_* symbols: /'
"$TOOLS/llvm-readelf" --dyn-symbols "$DEST/libcodec2bridge.so" |
  awk '$4=="FUNC" && $5=="GLOBAL" && $7!="UND"{print "  bridge exposes: "$NF}'

echo "== artefact sizes"
ls -l "$DEST"/*.so | awk '{print "  "$5" "$9}'
