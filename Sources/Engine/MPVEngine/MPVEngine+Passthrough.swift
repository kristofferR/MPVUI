import Foundation

extension MPVEngine {

    /// mpv's `audio-spdif` with a passthrough sink. TrueHD and DTS-HD go to the sink only at rate 1, because it
    /// renders at the synchronizer's normal rate, and not after it failed on them.
    var spdifCodecs: String {
        let base = configuration.audio.mpvOptions["audio-spdif"] ?? ""
        let rate = desiredProperties["speed"].flatMap(Double.init) ?? configuration.playbackRate
        guard passthroughSinkBridge != nil, rate == 1 else { return base }
        let sinkCodecs = [MPVPassthroughAudioCodec.trueHD, .dtsHD]
            .filter { !passthroughFallbackCodecs.contains($0) }
            .map(\.spdifName)
        return ([base] + sinkCodecs).filter { !$0.isEmpty }.joined(separator: ",")
    }

    /// Decodes `codec` to PCM after the passthrough sink failed on it, until the next track or file loads. Ignores
    /// a fallback from an output mpv has since closed.
    func fallBackToPCM(_ codec: MPVPassthroughAudioCodec, session: Int) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard passthroughSinkBridge?.isOpen(session) == true, passthroughFallbackCodecs.insert(codec).inserted else {
            return
        }
        applySpdifCodecs(reloadingAudio: true)
    }

    /// Offers TrueHD and DTS-HD to the passthrough sink again, before a track or file loads.
    func resetPassthroughFallback() {
        dispatchPrecondition(condition: .onQueue(queue))
        passthroughFallbackCodecs.removeAll()
        applySpdifCodecs(reloadingAudio: false)
    }

    /// Updates `audio-spdif` for the passthrough sink. When it changed during TrueHD or DTS playback, reselects the
    /// audio track, so mpv rebuilds the decoder and output as for a track switch.
    func applySpdifCodecs(reloadingAudio: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard passthroughSinkBridge != nil, handle != nil else { return }
        let codecs = spdifCodecs
        guard getString("audio-spdif") != codecs else { return }
        _ = setPropertyImmediately("audio-spdif", to: codecs)
        guard reloadingAudio,
              ["truehd", "dts"].contains(getString("current-tracks/audio/codec")),
              let track = getInt64("current-tracks/audio/id")
        else { return }
        _ = setPropertyImmediately("aid", to: "no")
        _ = setPropertyImmediately("aid", to: String(track))
    }
}
