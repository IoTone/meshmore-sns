# SPDX-License-Identifier: MIT
# Copyright (c) 2026 IoTone, Inc.
#
# The bridge is its own CMake project so it never adds a compile definition to
# Codec 2: `libcodec2.so` is built by its own CMakeLists with its own mode
# defines, and this project only links against the artefact it produced. That
# separation is the licence position (LGPL 2.1 §6(b)) and it is also why
# `CODEC2_LIB` and `CODEC2_INCLUDE` are inputs rather than a subdirectory.
#
# Invoke with:
#   cmake -G Ninja \
#     -DCMAKE_TOOLCHAIN_FILE=<ndk>/build/cmake/android.toolchain.cmake \
#     -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
#     -DCODEC2_LIB=<build>/src/libcodec2.so \
#     -DCODEC2_INCLUDE=<codec2>/src:<codec2-build> \
#     -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384" \
#     <repo>/meshmore_sns_app/third_party/codec2_bridge

cmake_minimum_required(VERSION 3.13)
project(codec2_bridge LANGUAGES C)

if(NOT CODEC2_LIB)
  message(FATAL_ERROR "CODEC2_LIB must point at the built libcodec2.so")
endif()
if(NOT CODEC2_INCLUDE)
  message(FATAL_ERROR "CODEC2_INCLUDE must list the Codec 2 include directories")
endif()

add_library(codec2 SHARED IMPORTED)
set_target_properties(codec2 PROPERTIES IMPORTED_LOCATION "${CODEC2_LIB}")

add_library(codec2bridge SHARED codec2_bridge.c)

target_include_directories(codec2bridge PRIVATE ${CODEC2_INCLUDE})
target_link_libraries(codec2bridge PRIVATE codec2)

# The only symbols this object exports are the ones marked C2_EXPORT: everything
# else stays hidden, so the symbol table is the API rather than whatever the
# compiler emitted.
target_compile_options(codec2bridge PRIVATE -fvisibility=hidden -Wall -Wextra)

# Android 15+ requires 16 KB page support on 64-bit devices, and Play's check is
# on the ELF, not on the Gradle config. NDK r28 aligns LOAD by default; passing
# the flags anyway keeps the artefact correct on r27 and on any future toolchain
# whose default changes again. `common-page-size` is what fixes the RELRO end,
# which is the half that fails silently after the LOAD check passes.
if(ANDROID)
  target_link_options(codec2bridge PRIVATE
    -Wl,-z,max-page-size=16384
    -Wl,-z,common-page-size=16384)
endif()
