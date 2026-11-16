/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 IoTone, Inc.
 *
 * The boundary between Dart and Codec 2.
 *
 * Codec 2 is LGPL 2.1 and this shim is MIT, and they are built as two separate
 * shared objects on purpose: `libcodec2.so` stays pristine upstream code, and
 * this file is the only thing that links to it. That keeps the library a
 * distinct, individually replaceable object inside the APK, which is the
 * strongest part of an LGPL 2.1 §6(b) position, and it means a modification to
 * either side is visible as a diff to one file.
 *
 * Nothing but these functions is exported: the build sets
 * `-fvisibility=hidden` and each one carries an explicit default-visibility
 * attribute, so the symbol table is the API rather than everything the
 * compiler happened to emit.
 *
 * The surface is deliberately C, not JNI. Encode and decode are pure functions
 * over caller-owned buffers with no callbacks and no allocation, so Dart FFI
 * calls them directly on whichever isolate asks, with no platform thread and no
 * message codec in the path.
 */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#include "codec2.h"

#define C2_EXPORT __attribute__((visibility("default")))

/* The mode identifiers come from codec2.h; a caller that passes anything else
 * gets NULL from codec2_create, and this shim passes that through rather than
 * inventing a failure of its own. */
#define C2_BRIDGE_MODE_700C 8
#define C2_BRIDGE_MODE_1300 4

struct c2_bridge {
    struct CODEC2 *codec;
    int mode;
    int samples_per_frame;
    int bytes_per_frame;
    int bits_per_frame;
};

/* One codec for one mode, or NULL when this build does not carry that mode.
 *
 * Modes are compiled in by define (CODEC2_MODE_EN_DEFAULT=0 plus one _EN per
 * mode), so a mode the app does not ship cannot be opened at all — which is a
 * stronger guarantee than checking a runtime table would be.
 */
C2_EXPORT struct c2_bridge *c2_bridge_open(int mode) {
    struct CODEC2 *codec = codec2_create(mode);
    if (codec == NULL) return NULL;
    struct c2_bridge *b = (struct c2_bridge *)calloc(1, sizeof(*b));
    if (b == NULL) {
        codec2_destroy(codec);
        return NULL;
    }
    b->codec = codec;
    b->mode = mode;
    b->samples_per_frame = codec2_samples_per_frame(codec);
    b->bytes_per_frame = codec2_bytes_per_frame(codec);
    b->bits_per_frame = codec2_bits_per_frame(codec);
    return b;
}

C2_EXPORT void c2_bridge_close(struct c2_bridge *b) {
    if (b == NULL) return;
    codec2_destroy(b->codec);
    free(b);
}

C2_EXPORT int c2_bridge_mode(const struct c2_bridge *b) { return b->mode; }
C2_EXPORT int c2_bridge_samples_per_frame(const struct c2_bridge *b) {
    return b->samples_per_frame;
}
C2_EXPORT int c2_bridge_bytes_per_frame(const struct c2_bridge *b) {
    return b->bytes_per_frame;
}
C2_EXPORT int c2_bridge_bits_per_frame(const struct c2_bridge *b) {
    return b->bits_per_frame;
}

/* True when this mode can use a bit-error estimate, which only 1300 is wired
 * for: it soft-mutes above 0.15 rather than inventing speech that was not
 * there. The caller reads this rather than assuming every mode takes one. */
C2_EXPORT int c2_bridge_uses_ber(const struct c2_bridge *b) {
    return b->mode == C2_BRIDGE_MODE_1300 ? 1 : 0;
}

/* Encode one frame. Returns the bytes written, or -1 for a bad pointer.
 *
 * The caller owns both buffers and their sizes: speech is
 * `samples_per_frame` shorts, bytes is `bytes_per_frame` bytes. Note that
 * `bytes_per_frame` rounds up to whole bytes and the frame may use fewer bits,
 * so a caller packing frames back to back should pack bits, not bytes. */
C2_EXPORT int c2_bridge_encode(struct c2_bridge *b, const int16_t *speech,
                               uint8_t *bytes) {
    if (b == NULL || speech == NULL || bytes == NULL) return -1;
    codec2_encode(b->codec, bytes, (short *)speech);
    return b->bytes_per_frame;
}

/* Decode one frame from hard bits. Returns the samples written, or -1. */
C2_EXPORT int c2_bridge_decode(struct c2_bridge *b, const uint8_t *bytes,
                               int16_t *speech) {
    if (b == NULL || speech == NULL || bytes == NULL) return -1;
    codec2_decode(b->codec, (short *)speech, bytes);
    return b->samples_per_frame;
}

/* Decode one frame with a bit-error estimate in [0, 1].
 *
 * For 1300 this is the soft-decision path and the estimate matters; for the
 * other modes Codec 2 ignores it and decodes the same bytes, so a caller that
 * always has an estimate does not need two code paths. */
C2_EXPORT int c2_bridge_decode_ber(struct c2_bridge *b, const uint8_t *bytes,
                                   int16_t *speech, float ber) {
    if (b == NULL || speech == NULL || bytes == NULL) return -1;
    if (ber < 0.0f) ber = 0.0f;
    if (ber > 1.0f) ber = 1.0f;
    codec2_decode_ber(b->codec, (short *)speech, bytes, ber);
    return b->samples_per_frame;
}

/* What the Dart side reports in Diagnostics and in its licence notice. */
C2_EXPORT const char *c2_bridge_version(void) {
    return "codec2 1.2.0 (700C, 1300)";
}
