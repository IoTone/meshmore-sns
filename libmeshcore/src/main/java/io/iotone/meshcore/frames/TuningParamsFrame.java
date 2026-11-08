// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package io.iotone.meshcore.frames;

import io.iotone.meshcore.model.TuningParams;

/**
 * {@code RESP_CODE_TUNING_PARAMS} (0x17) — the radio's own airtime limit.
 *
 * @param params the receive-delay base and the airtime factor
 */
public record TuningParamsFrame(TuningParams params) implements MeshcoreInbound {

    @Override
    public String toString() {
        return "TuningParamsFrame(" + params + ")";
    }
}
