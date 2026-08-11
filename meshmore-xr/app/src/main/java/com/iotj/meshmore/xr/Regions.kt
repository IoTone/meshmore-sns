// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr

/**
 * LORA REGION PRESETS — ported from Meshmore SNS `lib/meshcore/region_presets.dart`.
 *
 * ## Why this file exists at all
 *
 * XR shipped its own four-entry preset list inside the rack, with invented
 * names, and it had DRIFTED from the SNS table it was informally copied from:
 * `ANZ915` carried SF11 where SNS's Australian preset is SF10, so the two apps
 * from the same project, pointed at the same continent, would not have heard
 * each other. It also carried no transmit power at all — which is survivable in
 * North America, where the preset's 22 dBm is under the FCC ceiling anyway, and
 * is not survivable in Japan, where the legal conducted limit is 13 dBm and a
 * radio left at 22 is simply transmitting illegally.
 *
 * A second copy of a table of legal operating points is a second copy that
 * transmits somewhere it should not. So this is a PORT, not a reinterpretation:
 * the `id`s are byte-identical to the Dart so the two apps agree about what
 * "us_canada" means, the tuples are copied value-for-value, and the geofence
 * boxes are copied in their original order — which is load-bearing, because
 * narrower entries are listed before broader ones and the FIRST match wins.
 *
 * ## What the values are, and are not
 *
 * Community-curated, mirrored from the canonical MeshCore-companion preset
 * table (zjs81/meshcore-open, gotnull/socialmesh, both importing the set the
 * reference Liam Cottle companion uses). They are **not regulatory
 * guarantees** — they are the operating points the community has converged on
 * inside each country's ISM band. The wearer remains responsible for confirming
 * legality where they are, and [DISCLAIMER] is on the ABOUT surface for that
 * reason rather than buried in a store listing.
 *
 * Baked into the binary rather than fetched, for the same reason as SNS: this
 * is an offline-first radio app, the table changes about once a year, and
 * shipping a new build is the right cadence for it.
 *
 * ## What is deliberately different from SNS
 *
 * LABELS ARE SHORTER AND UPPERCASE. A row is 28 characters and the region sits
 * in a 20-character value slot beside the word REGION; "Australia (SA / WA /
 * QLD)" does not fit and would have been silently clipped. `RegionsTest`
 * asserts every label against the slot, so a future entry cannot quietly
 * overflow it.
 *
 * NOTES ARE ASCII AND SHORT. They pass through [spatial.Notice], which is 45
 * characters. The Japanese note in SNS runs to 50 and names 技適 in kanji; here
 * it is `GITEKI`, because the note has to survive a font fallback on a headset
 * whose typeface is not yet chosen. The full text lives in [DISCLAIMER].
 *
 * SELECTING A REGION STAGES, IT DOES NOT SEND. SNS applies a preset to the
 * radio the moment the chip is tapped. On the glasses the whole radio surface
 * is staged-then-committed, because a mis-picked region can move the radio to a
 * frequency where nothing — including this app — can reach it, and that is not
 * recoverable from inside a headset. Picking a region fills the pending column;
 * COMMIT is a separate, guarded pick.
 */
object Regions {

    /**
     * One region's complete operating point.
     *
     * [txDbm] is part of the set, not a suggestion alongside it. The firmware
     * clamps to its own hardware limit regardless, but a preset that omits
     * power leaves the previous region's power in place, which is exactly how a
     * radio ends up at 22 dBm on a 13 dBm band.
     */
    data class Region(
        /** Stable id, IDENTICAL to the SNS Dart. Never translated, never renamed. */
        val id: String,
        /** Uppercase, <= [LABEL_MAX] chars so it fits the row's value slot. */
        val label: String,
        val freqMhz: Double,
        val bandwidthKhz: Double,
        val spreadingFactor: Int,
        val codingRate: Int,
        val txDbm: Int,
        /** One-line regulatory hint, <= [NOTE_MAX] chars. Shown on selection. */
        val note: String? = null,
    ) {
        fun params() = RadioConfig.Params(
            freqMhz = freqMhz,
            bandwidthKhz = bandwidthKhz,
            spreadingFactor = spreadingFactor,
            codingRate = codingRate,
            txDbm = txDbm,
        )
    }

    /** The value slot beside the word REGION on a 28-character row. */
    const val LABEL_MAX = 20

    /** [spatial.Notice] is 45 characters and clamps silently past that. */
    const val NOTE_MAX = 45

    /** What a radio is on when its parameters match no shipped region. */
    const val CUSTOM = "CUSTOM"

    val ALL: List<Region> = listOf(
        // --- North America ---
        Region(
            "us_canada", "USA / CANADA",
            910.525, 62.5, 7, 5, 22,
            "FCC 902-928 ISM · 30dBm MAX",
        ),
        Region(
            "us_arizona", "USA — ARIZONA",
            908.205, 62.5, 10, 5, 20,
            "AZ REGIONAL VARIANT",
        ),
        // --- Japan ---
        // ARIB STD-T108 CH37 (923.2 MHz centre) — a valid 200 kHz unit channel
        // that a 125 kHz signal fits inside, and the same point LoRaWAN AS923-JP
        // and Meshtastic-JP default to. NOT the MeshCore-JP community proposal,
        // which is the entry below. MeshCore ships no canonical JP preset:
        // issues #2079 (JP_STRICT) and #2218 (ARIB-LBT) were both still open
        // mid-2026 and #460 was parked without shipping one.
        //
        // License-free 特定小電力 basis, verified 2026-07:
        //   power  <= 13 dBm conducted against a <= 3 dBi antenna (~16 dBm
        //          EIRP). More antenna gain means less conducted power.
        //   LBT    carrier sense at -80 dBm, 128 us minimum. Enforced by the
        //          device FIRMWARE, not by this app.
        //   duty   CH33-38, which includes CH37, cap transmit at 360 s per
        //          rolling hour. A chatty mesh has to respect that.
        //   技適   legal parameters do NOT make operation legal — the radio
        //          hardware itself must be certified, and most grey-import
        //          LoRa boards are not. See [DISCLAIMER].
        Region(
            "jp_arib_t108", "JAPAN (ARIB T108)",
            923.2, 125.0, 10, 5, 13,
            "CH37 · LBT · 10%/H DUTY · GITEKI HW ONLY",
        ),
        // MeshCore-JP community convention (proposal stage, small user base):
        // 920.8 MHz is ARIB CH25, in the CH24-32 group, which in long-sense LBT
        // mode carries no explicit hourly duty cap unlike CH33-38. SF12 / CR 4/8
        // is their deliberate maximum-range choice. Pick this to interoperate
        // with other MeshCore-JP nodes; it will NOT reach the preset above.
        Region(
            "jp_meshcore", "JAPAN (MESHCORE)",
            920.8, 125.0, 12, 8, 13,
            "CH25 · LBT · GITEKI HW ONLY · MESHCORE-JP",
        ),
        // --- EU / UK ---
        Region(
            "eu_uk_long", "EU / UK LONG",
            869.525, 250.0, 11, 5, 14,
            "ERC 869.4-869.65 · 27dBm MAX",
        ),
        Region("eu_uk_medium", "EU / UK MEDIUM", 869.525, 250.0, 10, 5, 14),
        Region("eu_uk_narrow", "EU / UK NARROW", 869.618, 62.5, 8, 5, 14),
        Region("ch", "SWITZERLAND", 869.618, 62.5, 8, 5, 14),
        Region("cz", "CZECH REPUBLIC", 869.432, 62.5, 7, 5, 14),
        Region("pt_869", "PORTUGAL 869", 869.618, 62.5, 7, 5, 14),
        // --- Australia / NZ ---
        Region("au_default", "AUSTRALIA", 915.8, 250.0, 10, 5, 20),
        Region("au_narrow", "AUSTRALIA NARROW", 916.575, 62.5, 7, 5, 20),
        Region("au_sa_wa_qld", "AUSTRALIA SA/WA/QLD", 923.125, 62.5, 8, 5, 20),
        Region("nz_default", "NEW ZEALAND", 917.375, 250.0, 11, 5, 20),
        // --- SE Asia ---
        Region("vn", "VIETNAM", 920.250, 250.0, 11, 5, 20),
    )

    fun byId(id: String?): Region? = ALL.firstOrNull { it.id == id }

    /**
     * The region whose four LoRa parameters match [p], or null for CUSTOM.
     *
     * Tolerances are SNS's: 1 kHz on frequency and 0.5 kHz on bandwidth, to
     * absorb the rounding in the wire format, which carries frequency as a
     * uint32 of kilohertz and comes back divided by 1000.
     *
     * TRANSMIT POWER IS NOT PART OF THE MATCH, deliberately. Firmware clamps
     * power to what the hardware can do, so a radio told 22 may report 20 and
     * would then match no region at all — and reporting a legal, correctly
     * tuned radio as CUSTOM because its amplifier is smaller than the preset
     * assumed would train people to ignore the word.
     */
    fun match(p: RadioConfig.Params?): Region? {
        if (p == null) return null
        return ALL.firstOrNull {
            kotlin.math.abs(it.freqMhz - p.freqMhz) <= 0.001 &&
                kotlin.math.abs(it.bandwidthKhz - p.bandwidthKhz) <= 0.5 &&
                it.spreadingFactor == p.spreadingFactor &&
                it.codingRate == p.codingRate
        }
    }

    /** [match]'s label, or [CUSTOM]. What the REGION row says. */
    fun labelFor(p: RadioConfig.Params?): String = match(p)?.label ?: CUSTOM

    private data class Box(
        val latMin: Double, val latMax: Double,
        val lonMin: Double, val lonMax: Double,
        val regionId: String,
    )

    /**
     * Coarse country boxes, in SNS's original order.
     *
     * THE ORDER IS THE ALGORITHM. Boxes overlap on purpose — Mexico sits inside
     * the North American box and correctly gets the same 902-928 ISM preset —
     * and the first match wins, so narrower country-specific entries must stay
     * ahead of the broad ones. Reordering this list changes what a radio in
     * Arizona or Switzerland is told to do.
     *
     * This is geofencing, not legal advice. A fix near a national border can
     * land in the neighbour's box, which is why [suggest] only ever proposes:
     * the suggestion arrives as a row you pick, and even picking it only stages.
     */
    private val BOXES = listOf(
        // Narrow regional preset BEFORE the broad US box.
        Box(31.0, 37.0, -115.0, -109.0, "us_arizona"),
        // Continental USA + AK + HI.
        Box(18.0, 72.0, -180.0, -65.0, "us_canada"),
        // Canada — the same 902-928 ISM band as the US.
        Box(41.0, 84.0, -141.0, -52.0, "us_canada"),
        // Japan, Hokkaido down to Yaeyama, Okinawa included.
        Box(24.0, 46.0, 122.0, 146.0, "jp_arib_t108"),
        Box(8.0, 24.0, 102.0, 110.0, "vn"),
        // Australia — broad. West of ~129°E the SA/WA/QLD preset is the better
        // pick, but the default is also legal there, so the broad box is safe.
        Box(-44.0, -10.0, 112.0, 154.0, "au_default"),
        Box(-47.5, -34.0, 165.0, 179.5, "nz_default"),
        // EU country-specific overrides BEFORE the broad EU box.
        Box(36.9, 42.2, -9.6, -6.1, "pt_869"),
        Box(45.8, 47.9, 5.9, 10.6, "ch"),
        Box(48.5, 51.1, 12.0, 18.9, "cz"),
        // Broad EU / UK / EEA.
        Box(34.0, 71.5, -11.0, 32.0, "eu_uk_long"),
    )

    /**
     * The region suggested for a position, or null when it falls outside every
     * shipped box — ocean, polar, or a country with no preset yet. A null is a
     * reason to show the full list, never a reason to guess.
     */
    fun suggest(lat: Double?, lon: Double?): Region? {
        if (lat == null || lon == null) return null
        val b = BOXES.firstOrNull {
            lat >= it.latMin && lat <= it.latMax && lon >= it.lonMin && lon <= it.lonMax
        } ?: return null
        return byId(b.regionId)
    }

    /**
     * The long form, on the ABOUT surface, wrapped to the 28-character row.
     *
     * Same substance as the SNS `deviceRegionDisclaimer`, because the two apps
     * should not tell people different things about the same law — shortened
     * only where a phone paragraph does not fit a row of glass. The Japanese
     * half is not trimmable: 技適 is the part where correct settings on the
     * wrong hardware is still an offence, and it is the part a wearer is least
     * likely to already know.
     */
    val DISCLAIMER = listOf(
        "PRESETS ARE COMMUNITY SET,",
        "NOT LEGAL ADVICE. PICK ONE",
        "LEGAL WHERE YOU ARE, AND",
        "USE IT ON EVERY NODE.",
        "JAPAN: SETTINGS ALONE ARE",
        "NOT ENOUGH. THE HARDWARE",
        "MUST CARRY GITEKI — MOST",
        "IMPORTED BOARDS DO NOT.",
    )

    /** The same warning compressed to one footer, for the region list itself. */
    const val FOOTER = "COMMUNITY SET — NOT LEGAL ADVICE"
}
