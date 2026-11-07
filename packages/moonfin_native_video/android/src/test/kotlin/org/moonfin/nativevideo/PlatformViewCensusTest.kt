package org.moonfin.nativevideo

import org.junit.Assert.assertEquals
import org.junit.Test

class PlatformViewCensusTest {

    @Test
    fun `no views reads as none`() {
        assertEquals("none", describeViews(emptyMap()))
    }

    @Test
    fun `kinds come out in name order with a count past one`() {
        assertEquals(
            "media3-main,media3-preview*2",
            describeViews(mapOf("media3-preview" to 2, "media3-main" to 1)),
        )
    }

    @Test
    fun `the formats being decoded read short`() {
        assertEquals("hevc", shortCodec("video/hevc"))
        assertEquals("dts.hd", shortCodec("audio/vnd.dts.hd"))
        assertEquals(" v=hevc a=eac3/ff", describeMedia("hevc", "eac3", "ffmpegLib"))
        assertEquals(" a=ac3", describeMedia("", "ac3", "c2.android.ac3.decoder"))
        assertEquals("", describeMedia("", "", ""))
    }
}
