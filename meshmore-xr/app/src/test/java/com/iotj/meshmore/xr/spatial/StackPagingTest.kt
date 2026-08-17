// Copyright (c) 2026 IoTone, Inc.
// SPDX-License-Identifier: MIT
package com.iotj.meshmore.xr.spatial

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Paging arithmetic for the Stack.
 *
 * `Stack` needs a Session, so the windowing is mirrored here — deliberately,
 * the same trade `LinkStepTest` makes: change one side without the other and
 * this fails rather than drifting.
 *
 * The reason paging exists at all is worth stating: six rows is a FIELD
 * constraint, not a protocol one. Six rows plus a header and footer is 35
 * degrees at a metre, already past a 34-degree field, so a seventh row cannot
 * simply be added — and a bay that silently drops its seventh setting looks
 * exactly like a bay that never had it. REDUCE MOTION was that seventh setting,
 * unreachable for no better reason.
 */
class StackPagingTest {

    private val max = 6
    private val perPage = max - 1

    private fun pages(n: Int) = if (n <= max) 1 else (n + perPage - 1) / perPage

    /** The rows visible on [page], MORE included when there is more than one. */
    private fun window(n: Int, page: Int): List<String> {
        val all = (1..n).map { "row$it" }
        if (n <= max) return all
        val p = pages(n)
        val q = ((page % p) + p) % p
        return all.drop(q * perPage).take(perPage) + "MORE"
    }

    @Test fun aShortListDoesNotPageAtAll() {
        for (n in 1..max) {
            assertEquals("$n rows", 1, pages(n))
            assertEquals("$n rows", n, window(n, 0).size)
            assertTrue("$n rows should have no MORE", "MORE" !in window(n, 0))
        }
    }

    /** The moment it overflows, a way forward appears and costs a row. */
    @Test fun theSeventhRowStartsPagingAndCostsOneSlot() {
        assertEquals(2, pages(7))
        val first = window(7, 0)
        assertEquals(max, first.size)
        assertEquals("MORE", first.last())
        assertEquals(listOf("row1", "row2", "row3", "row4", "row5", "MORE"), first)
    }

    /**
     * EVERY ROW IS REACHABLE. This is the §8 parity check for the widget: a
     * paged bay that cannot reach its last item is worse than a truncated one,
     * because it looks like it works.
     */
    @Test fun everyRowIsReachableOnSomePage() {
        for (n in 1..20) {
            val seen = mutableSetOf<String>()
            for (p in 0 until pages(n)) seen += window(n, p).filter { it != "MORE" }
            assertEquals("$n rows: unreachable rows", n, seen.size)
        }
    }

    /**
     * THE LABEL HAS TO AGREE WITH THE WRAP.
     *
     * This file has covered the windowing and the wrap since it was written,
     * and never once looked at the words on the control — which were built
     * inline in the surface, out of reach. So MORE announced `page + 2`: right
     * on every page but the last, where paging wraps back to the first. Two
     * pages of app settings therefore ended on "MORE 3 OF 2", a page that does
     * not exist, in a count that says so in the same breath. Reported from a
     * headset, which is the expensive way to find a string bug.
     */
    @Test fun theMoreControlNeverPromisesAPageThatDoesNotExist() {
        for (n in 1..6) {
            for (p in 0 until n) {
                val label = moreLabel(p, n)
                val shown = Regex("(\\d+) OF (\\d+)").find(label)
                    ?: error("unreadable MORE label '$label'")
                val to = shown.groupValues[1].toInt()
                val of = shown.groupValues[2].toInt()
                assertEquals("the count is the page count", n, of)
                assertTrue("'$label' offers page $to of $n", to in 1..n)
                // And it is the page the wrap actually lands on.
                assertEquals("'$label' does not match where MORE goes", ((p + 1) % n) + 1, to)
            }
        }
    }

    /** The last page sends you home rather than nowhere. */
    @Test fun theLastPageOffersTheFirst() {
        assertEquals("MORE  1 OF 2", moreLabel(1, 2))
        assertEquals("MORE  2 OF 2", moreLabel(0, 2))
        assertEquals("MORE  1 OF 3", moreLabel(2, 3))
        assertEquals("MORE  1 OF 1", moreLabel(0, 1))
    }

    /** The word is the caller's, so the JA bay does not say MORE in English. */
    @Test fun theWordIsTranslatable() {
        assertEquals("つづき  1 OF 2", moreLabel(1, 2, "つづき"))
    }

    /** Paging wraps, so MORE is never a dead end on the last page. */
    @Test fun pagingWrapsBackToTheStart() {
        val n = 8
        val p = pages(n)
        assertEquals(window(n, 0), window(n, p))
        assertEquals(window(n, 0), window(n, p * 3))
    }

    /** A negative page — from any off-by-one upstream — still resolves. */
    @Test fun anOutOfRangePageStillResolves() {
        val n = 9
        assertTrue(window(n, -1).isNotEmpty())
        assertTrue(window(n, 99).isNotEmpty())
    }

    /** No page ever exceeds what the field can hold. */
    @Test fun noPageIsTallerThanTheField() {
        for (n in 1..30) {
            for (p in 0 until pages(n)) {
                assertTrue("$n rows page $p", window(n, p).size <= max)
            }
        }
    }

    /** The APP bay is the case that forced this: seven settings, two pages. */
    @Test fun theAppBayNowFits() {
        val settings = 7
        assertEquals(2, pages(settings))
        val reachable = (0 until pages(settings))
            .flatMap { window(settings, it) }
            .filter { it != "MORE" }
            .toSet()
        assertEquals(settings, reachable.size)
    }
}
