// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * THE CARD THAT RAN OFF THE FIELD.
 *
 * `at()` places a help row starting at a fixed column and extending rightward
 * by its whole measured width. Nothing bounded it, so the copy simply grew
 * until it left the viewport — photographed with "MOVE THE SCENE TO WHERE YOU
 * STA" cut mid-word against the right edge, printed over the theme picker
 * behind it. Ten of the eighteen rows were over.
 *
 * It is the same failure the stack had and the same fix: measure the container,
 * not the sentence. These hold the copy to it, because help text is exactly the
 * kind of thing somebody lengthens later while fixing something else — which is
 * how the longest row on that card got there, in the commit that added the H
 * gesture two hours before this test existed.
 */
class HelpCardTest {

    /** Cell width as a fraction of cap height, shared with the row templates. */
    private val cellEm = ROW_CELL_EM

    /** Where the card is read from. */
    private val readM = 1.5

    @Test fun everyHelpRowFitsTheCardsWidth() {
        HelpCard.ROWS.forEach { r ->
            assertTrue(
                "'${r.does}' is ${r.does.length}, budget is ${HelpCard.HELP_WIDEST}",
                r.does.length <= HelpCard.HELP_WIDEST,
            )
            // The hand column is short by nature, but it is drawn from the same
            // cap and nothing stops it growing either.
            assertTrue("'${r.hand}' is long for a column", r.hand.length <= 8)
        }
    }

    /**
     * ...and the budget itself has to fit the FIELD, or holding the copy to it
     * proves nothing. A 26-character row is 0.60 m of ink read at 1.5 m, which
     * is 22.8 degrees — inside the 34-degree window with room for the hand
     * column and the glyph to its left.
     */
    @Test fun theBudgetIsInsideTheFieldOfView() {
        val w = HelpCard.HELP_WIDEST * cellEm * HelpCard.CAP
        val deg = Math.toDegrees(2.0 * Math.atan(w / 2.0 / readM))
        assertTrue("text alone is %.1f deg".format(deg), deg <= 26.0)
        // And not so mean that the card cannot say anything useful.
        assertTrue("only %.1f deg of text".format(deg), deg >= 18.0)
    }

    /** The gesture rows still name both letters that recentre the scene. */
    @Test fun theRecentreGestureIsDocumentedForBothLetters() {
        val letters = HelpCard.ROWS.mapNotNull { it.letter }.toSet()
        assertTrue("H is the recentre gesture and must be on the card", 'h' in letters)
        assertTrue("R still works and is still documented", 'r' in letters)
    }
}
