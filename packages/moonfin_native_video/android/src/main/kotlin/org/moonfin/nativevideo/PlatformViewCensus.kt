package org.moonfin.nativevideo

/**
 * The plugin's platform views that are alive right now, by kind. Flutter
 * composes each one with hybrid composition, which is where some TV GPU
 * drivers crash, so the app keeps this next to the record of how its process
 * ended.
 */
object PlatformViewCensus {
    private val counts = mutableMapOf<String, Int>()

    /** Called with [describe]'s answer every time a view joins or leaves. */
    @Volatile
    var listener: ((String) -> Unit)? = null

    /** Counts a view of [kind] until the returned call, which only counts once. */
    fun join(kind: String): () -> Unit {
        change(kind, 1)
        var left = false
        return {
            if (!left) {
                left = true
                change(kind, -1)
            }
        }
    }

    // What the player is decoding, so a native crash in the middle of a
    // film says which formats were being decoded (a TV's decoder that dies
    // on one of them is the usual cause).
    private var video = ""
    private var audio = ""
    private var audioDecoder = ""

    fun describe(): String = synchronized(counts) { describeViews(counts) + describeMedia(video, audio, audioDecoder) }

    /** The video format now decoded, as its MIME type. */
    fun noteVideo(mime: String?) = noteMedia { video = shortCodec(mime) }

    /** The audio format now decoded, as its MIME type. */
    fun noteAudio(mime: String?) = noteMedia { audio = shortCodec(mime) }

    /** The audio decoder now in use (FFmpeg's, or the device's). */
    fun noteAudioDecoder(name: String?) = noteMedia { audioDecoder = name ?: "" }

    private fun noteMedia(change: () -> Unit) {
        val summary = synchronized(counts) {
            change()
            describeViews(counts) + describeMedia(video, audio, audioDecoder)
        }
        listener?.invoke(summary)
    }

    private fun change(kind: String, by: Int) {
        val summary = synchronized(counts) {
            val count = (counts[kind] ?: 0) + by
            if (count > 0) counts[kind] = count else counts.remove(kind)
            if (counts.isEmpty()) {
                video = ""
                audio = ""
                audioDecoder = ""
            }
            describeViews(counts) + describeMedia(video, audio, audioDecoder)
        }
        listener?.invoke(summary)
    }
}

/** "video/hevc" reads "hevc", "audio/vnd.dts.hd" reads "dts.hd". */
internal fun shortCodec(mime: String?): String =
    (mime ?: "").substringAfter('/').removePrefix("vnd.").removePrefix("x-").take(12)

/**
 * " v=hevc a=eac3", with "/ff" when FFmpeg decodes the audio: short, because
 * Android keeps 128 bytes of the whole summary.
 */
internal fun describeMedia(video: String, audio: String, audioDecoder: String): String {
    val parts = mutableListOf<String>()
    if (video.isNotEmpty()) parts.add("v=$video")
    if (audio.isNotEmpty()) {
        val ff = if (audioDecoder.contains("ffmpeg", ignoreCase = true)) "/ff" else ""
        parts.add("a=$audio$ff")
    }
    return if (parts.isEmpty()) "" else " " + parts.joinToString(" ")
}

/** "none", or each kind in name order, with a count when there's more than one. */
internal fun describeViews(counts: Map<String, Int>): String =
    if (counts.isEmpty()) {
        "none"
    } else {
        counts.toSortedMap().entries.joinToString(",") { (kind, count) ->
            if (count == 1) kind else "$kind*$count"
        }
    }
