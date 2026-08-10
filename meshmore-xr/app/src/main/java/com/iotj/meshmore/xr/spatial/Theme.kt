// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

/**
 * THE NINE THEMES, as data.
 *
 * Design brief section 7. A theme is a skin — palette, type, symbology
 * treatment, motion, sound — plus one bigger claim, POSTURE (section 7.0),
 * which decides which zones a theme lights up at all.
 *
 * DATA, NOT ARCHITECTURE, and that is the whole reason nine is affordable. The
 * marginal cost of the ninth theme after the first is a palette and a paragraph
 * of guidance, because every surface already takes its ink from a
 * [Horizon.Palette] passed in at construction rather than from a constant it
 * reaches for itself. Nothing here draws anything. Nothing here needs a
 * headset. It is a table, and it is tested as a table.
 *
 * ## The one hack in this file, stated plainly
 *
 * [Skin] retints a live scene by looking a material's colour back up in the
 * palette it came from — which needs each role in a palette to be
 * DISTINGUISHABLE by its value. Three themes collapse roles onto one hex by
 * design: SEELE is cream-on-black and nothing else, RECON is a single amber at
 * four luminances, TERMINAL VOID is one phosphor green. In those palettes the
 * duplicate roles are nudged by ONE unit in a single channel — `#FFB000` for
 * accent and `#FFB002` for text. That difference is 1/255th of one channel of
 * an emissive display; it is below the panel's own dithering noise and far
 * below anything an eye resolves. It buys an exact reverse lookup, which is
 * what lets a theme change apply to a scene already built.
 *
 * The alternative was threading a role enum through some two hundred call
 * sites, which is a large diff to fix a problem three constants fix.
 */
object Theme {

    /** Which rendering strategy the theme bets on — brief section 7, "substrate classes". */
    enum class Substrate {
        /** Ink on an opaque slab. Survives sunlight best, cheapest, most conventional. */
        PANEL,

        /** Emission into the room. Most spectacular, most fragile in bright light. */
        ADDITIVE,

        /** Additive in the open, panel where reading happens. */
        HYBRID,
    }

    /**
     * Which zones the theme lights up (brief section 7.0).
     *
     * Posture never removes information, only routes: anything a FIELD theme
     * shows on the HORIZON is reachable in TABLETOP and TRANSIT, from the
     * GROUND map and the hand menu respectively.
     */
    enum class Posture {
        /** Standing, walking, stopping to look. The general case, seven of the nine. */
        FIELD,

        /** Seated, indoors, stationary, powered. Everything inside about 0.8 m. */
        TABLETOP,

        /** Moving, hands busy, eyes on the world. MICROHUD and palm, nothing else. */
        TRANSIT,
    }

    /**
     * WHAT A NODE ON THE HORIZON ACTUALLY IS.
     *
     * The axis that makes nine themes rather than nine palettes. A node mark is
     * the thing a wearer sees several hundred times a session, so changing it
     * changes the app more than any amount of recolouring — and the brief has
     * always specified it per theme (§7: "one primitive set, nine restylings").
     *
     * Deliberately a small closed set rather than a per-theme drawing routine.
     * Every one of these still has to answer the same questions at 1.5 degrees —
     * is it a node, a repeater or a cluster; is it located; how old is it — and
     * a free-form hook is how a theme quietly stops answering one of them.
     */
    enum class Symbol {
        /** Solid facetted body. A disc for a node, a dish for a repeater. HALO. */
        SOLID,

        /** Hexagonal, bracketed, MAGI-console. NERV. */
        HEX,

        /** A forward chevron — the craft HUD's velocity mark. AG-SYSTEMS. */
        CHEVRON,

        /** A flat monolith seen edge-on: type on a slab, nothing round. SEELE. */
        SLAB,

        /** A hard flat cube. No curvature anywhere. DR POP. */
        BLOCK,

        /** A gapped sweep ring — an instrument mark, single hue. RECON AMBER. */
        RADAR,

        /** A soft round body with a faint halo, like something living. BIOLUME. */
        SPORE,

        /**
         * Open geometry only: rings and tubes, no fill. VECTORLINE's whole
         * proposition — Tempest and Battlezone drew light, not surfaces — and
         * on additive optics an unfilled ring is also the cheapest mark that
         * still reads against a bright wall.
         */
        WIRE,

        /**
         * No geometry at all. The node IS its text: `davi1 -71dBm 340m 042`.
         * TERMINAL VOID, and the most literal reading of §1.3 — if black is
         * transparent and only emission reads, then emit letters.
         */
        TEXT,
    }

    /**
     * WHAT A MENU PLATE IS MADE OF.
     *
     * The second axis §7 never specified, and the reason every theme's console
     * behaved identically. Derived from [Symbol] rather than chosen freely, so
     * a theme whose nodes are open geometry has open menus too — RECON's gapped
     * ring and VECTORLINE's wire node next to a solid slab of a button would be
     * two applications in one view.
     *
     * ON ADDITIVE OPTICS THIS IS NOT A STYLE CHOICE. A filled plate emits
     * across its whole area and washes out the room behind it; a frame emits
     * along its edges only and leaves the middle of the control transparent.
     * Which of those a theme wants is the same question as which substrate it
     * bet on.
     */
    enum class Plate {
        /** A dim slab with the label as ink on it. HALO, NERV, AG-SYS, BIOLUME. */
        SOLID,

        /** An outline. Nothing between the wearer and the room. RECON, VECTOR. */
        FRAME,

        /** A flat block with a hard offset block behind it in a second hue. DR POP. */
        OFFSET,

        /** No plate at all — the words, and a prompt. SEELE, TERMINAL VOID. */
        NONE,
    }

    /** How much the theme is allowed to move, before the wearer's reduce-motion setting. */
    enum class Motion {
        /** Nothing idles. Movement means an event happened. */
        STILL,

        /** Considered transitions, no ambient drift. */
        MEASURED,

        /** Ambient life — drift, breathing, growth. Never perfectly still. */
        ALIVE,
    }

    /**
     * One theme.
     *
     * [palette] is what the surfaces consume; everything else here is either
     * consumed by the picker, or is guidance that a future surface honours.
     * Fields that no surface reads YET are kept because the alternative is
     * re-deriving them from prose at the moment they are needed, and the prose
     * is in a different file.
     */
    data class Skin(
        /** Stable id. Persisted, so it must never change once shipped. */
        val key: String,
        /** What the picker says. */
        val name: String,
        /** The one-liner from the brief, shown under the name. */
        val line: String,
        val palette: Horizon.Palette,
        val substrate: Substrate,
        val posture: Posture = Posture.FIELD,
        val motion: Motion = Motion.MEASURED,
        /** What a horizon node is made of. See [Symbol]. */
        val symbol: Symbol = Symbol.SOLID,
        /** What a menu plate is made of. See [Plate]. */
        val plate: Plate = Plate.SOLID,
        /**
         * How many rows of a menu are shown at once, before paging.
         *
         * Only SEELE MONOLITH moves this, and it moves it to ONE. "One item per
         * page" is the treatment §7 names for it, and the reason it is a theme
         * property rather than a preference is that it changes the SHAPE of a
         * menu: a monolith shows you one enormous thing and nothing else, and a
         * list of six would be a different theme wearing this palette.
         *
         * §8 parity survives because paging reaches every row — asserted in
         * StackPagingTest, which is the check that makes this safe to do at all.
         */
        val rowsPerPage: Int = 6,
        /**
         * Row type size, as a multiple of the house standard.
         *
         * Above 1.0 only where there is room for it. SEELE can afford 1.23
         * BECAUSE it shows one row at a time — the two properties are the same
         * decision and would be wrong apart.
         */
        val rowScale: Float = 1f,
        /** Which audio pack fires (brief section 7, per theme). */
        val audio: String,
        /**
         * True when the theme expects an opaque ground slab behind read text.
         *
         * This is the section 1.3 constraint made operational: on additive
         * optics black is transparent, so a PANEL theme must actually paint its
         * `panel` colour as geometry to get the contrast it was designed for,
         * and an ADDITIVE theme must not, or it turns the room into a wall.
         */
        val slab: Boolean = substrate != Substrate.ADDITIVE,
    )

    /**
     * HALO FIELD, the default (brief section 7.11).
     *
     * First in the list, and the recommendation is not a matter of taste: it is
     * the only one that is simultaneously lowest-effort, most legible and most
     * accessible, and it exercises every zone and every primitive without any
     * exotic rendering.
     */
    val HALO = Skin(
        key = "halo",
        name = "HALO FIELD",
        line = "The mesh as a calm horizon. The one you can wear for eight hours.",
        palette = Horizon.Palette(
            accent = 0x35E0F0, alt = 0x7CFF6B, warn = 0xFFB020, text = 0xDDE7EF,
            ground = 0x070B10, panel = 0x101722, alert = 0xFF3B6B,
        ),
        substrate = Substrate.HYBRID,
        motion = Motion.STILL,
        audio = "sonar",
    )

    val NERV = Skin(
        key = "nerv",
        name = "NERV SPATIAL",
        line = "The command deck, wrapped around you. MAGI as a 360 degree ring.",
        palette = Horizon.Palette(
            accent = 0xFF7A00, alt = 0x9CFF00, warn = 0xFFC400, text = 0xE6ECF5,
            ground = 0x0A0E1A, panel = 0x121826, alert = 0xE01B24,
        ),
        substrate = Substrate.PANEL,
        symbol = Symbol.HEX,
        audio = "mission",
    )

    val AGSYS = Skin(
        key = "aghud",
        name = "AG-SYSTEMS",
        line = "Wipeout's craft HUD at 900 km/h. Velocity chevrons, race livery.",
        palette = Horizon.Palette(
            accent = 0x22D3EE, alt = 0xFF2D78, warn = 0xFFD23F, text = 0xDDF6FF,
            ground = 0x05060B, panel = 0x10131F, alert = 0xFF2D78,
        ),
        substrate = Substrate.HYBRID,
        motion = Motion.ALIVE,
        symbol = Symbol.CHEVRON,
        audio = "velocity",
    )

    /**
     * SEELE MONOLITH — the high-contrast alternate.
     *
     * Ships regardless of which theme wins the default, because it is the one
     * that works at noon in July. Accent and text are the same cream by design;
     * see the note at the top of this file for the nudge.
     */
    val SEELE = Skin(
        key = "seele",
        name = "SEELE MONOLITH",
        line = "Type is the entire UI. Cream numerals a foot tall, near-zero chrome.",
        palette = Horizon.Palette(
            // accent EDE6D6 / text EDE6D7 and alt 9A958A / warn 9A958B: one unit apart.
            accent = 0xEDE6D6, alt = 0x9A958A, warn = 0x9A958B, text = 0xEDE6D7,
            ground = 0x000000, panel = 0x0E0E0C, alert = 0xC8102E,
        ),
        substrate = Substrate.PANEL,
        motion = Motion.STILL,
        rowsPerPage = 1,
        rowScale = 1.23f,
        plate = Plate.NONE,
        symbol = Symbol.SLAB,
        audio = "tribunal",
    )

    val DRPOP = Skin(
        key = "drpop",
        name = "DR POP",
        line = "Flat colour blocks, fabricated sub-brands, katakana as graphic.",
        palette = Horizon.Palette(
            accent = 0xFF2E88, alt = 0xD7FF00, warn = 0x00E5FF, text = 0xF2F0E6,
            ground = 0x101014, panel = 0x1C1C24, alert = 0xFF2E88,
        ),
        substrate = Substrate.PANEL,
        plate = Plate.OFFSET,
        symbol = Symbol.BLOCK,
        audio = "purephase",
    )

    /**
     * RECON AMBER — night operations, and the TRANSIT posture.
     *
     * One hue at four luminance steps, so information is carried by brightness
     * and form and never by colour, which makes it the most colour-blind-safe
     * of the nine without trying. Accent, warn and text are one amber; see the
     * nudge note at the top of this file.
     */
    val RECON = Skin(
        key = "recon",
        name = "RECON AMBER",
        line = "Single-hue night operations. Works at 3 a.m. without ruining your eyes.",
        palette = Horizon.Palette(
            // accent FFB000 / warn FFB001 / text FFB002: within one unit of each other.
            accent = 0xFFB000, alt = 0x6E4E00, warn = 0xFFB001, text = 0xFFB002,
            ground = 0x000000, panel = 0x0A0A07, alert = 0xB3231F,
        ),
        substrate = Substrate.HYBRID,
        posture = Posture.TRANSIT,
        motion = Motion.STILL,
        plate = Plate.FRAME,
        symbol = Symbol.RADAR,
        audio = "codec",
    )

    val VECTOR = Skin(
        key = "vector",
        name = "VECTORLINE",
        line = "Tempest, Rez, Battlezone. Glowing vector geometry in your actual room.",
        palette = Horizon.Palette(
            accent = 0x00FFC8, alt = 0xB14BFF, warn = 0xFFE066, text = 0xDFFFF6,
            ground = 0x000000, panel = 0x05070A, alert = 0xFF3D00,
        ),
        substrate = Substrate.ADDITIVE,
        motion = Motion.MEASURED,
        plate = Plate.FRAME,
        symbol = Symbol.WIRE,
        audio = "arcade",
    )

    /** BIOLUME — the mesh as a living organism, and the TABLETOP posture. */
    val BIOLUME = Skin(
        key = "biolume",
        name = "BIOLUME",
        line = "Drifting spores, mycelial threads, soft breathing light.",
        palette = Horizon.Palette(
            accent = 0x5FFFC2, alt = 0x9B6BFF, warn = 0xFFD08A, text = 0xD8FFF0,
            ground = 0x04100E, panel = 0x0B1F1A, alert = 0xFF6B5F,
        ),
        substrate = Substrate.ADDITIVE,
        posture = Posture.TABLETOP,
        motion = Motion.ALIVE,
        symbol = Symbol.SPORE,
        audio = "bloom",
    )

    /**
     * TERMINAL VOID — phosphor text in space.
     *
     * Accent and text are one green by design; see the nudge note at the top of
     * this file.
     */
    val VOID = Skin(
        key = "void",
        name = "TERMINAL VOID",
        line = "Phosphor text floating in space. No panels, no chrome, no graphics.",
        palette = Horizon.Palette(
            // accent 33FF66 / text 33FF67: one unit apart.
            accent = 0x33FF66, alt = 0x0A3D17, warn = 0xB8FF33, text = 0x33FF67,
            ground = 0x000000, panel = 0x020402, alert = 0xFF4444,
        ),
        substrate = Substrate.ADDITIVE,
        motion = Motion.STILL,
        plate = Plate.NONE,
        symbol = Symbol.TEXT,
        audio = "teletype",
    )

    /** Picker order. HALO first because it is the default and the reference. */
    val ALL: List<Skin> = listOf(HALO, SEELE, RECON, AGSYS, NERV, DRPOP, VECTOR, BIOLUME, VOID)

    val DEFAULT: Skin = HALO

    /** A persisted key back to a theme, tolerating a key from a build that had others. */
    fun byKey(key: String?): Skin = ALL.firstOrNull { it.key == key } ?: DEFAULT

    /** Position in [ALL], for a picker that needs to know where it is. */
    fun indexOf(skin: Skin): Int = ALL.indexOf(skin).coerceAtLeast(0)

    /** The next theme in the ring, for a control that steps rather than picks. */
    fun next(skin: Skin): Skin = ALL[(indexOf(skin) + 1) % ALL.size]
}
