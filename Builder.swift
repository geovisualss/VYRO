import AVFoundation

enum BuildError: Error { case noVideo, exportFailed }

enum Builder {
    static func orientation(_ t: CGAffineTransform) -> CGImagePropertyOrientation {
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 { return .right }
        if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 { return .left }
        if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 { return .down }
        return .up
    }

    /// Turns the remap graph into a composition: each graph segment becomes a clip range
    /// that is time-scaled to its output length (slope = speed). Flat segments become freeze frames.
    static func build(asset: AVAsset, remap: [RemapPoint], effects: [EffectInstance]) async throws
        -> (AVMutableComposition, AVMutableVideoComposition) {

        let comp = AVMutableComposition()
        guard let vSrc = try await asset.loadTracks(withMediaType: .video).first,
              let vDst = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw BuildError.noVideo }
        let aSrc = try await asset.loadTracks(withMediaType: .audio).first
        let aDst = aSrc == nil ? nil :
            comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let total = try await asset.load(.duration).seconds
        let ts: CMTimeScale = 600
        func cm(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: ts) }

        for (p0, p1) in zip(remap, remap.dropFirst()) {
            let outLen = p1.x - p0.x
            guard outLen > 0.001 else { continue }
            var srcLen = p1.y - p0.y
            let freeze = srcLen < 0.02
            var srcStart = p0.y
            if freeze { srcLen = 1.0 / 30; srcStart = min(srcStart, max(0, total - srcLen)) }
            let range = CMTimeRange(start: cm(srcStart), duration: cm(srcLen))
            let at = comp.duration

            try vDst.insertTimeRange(range, of: vSrc, at: at)
            vDst.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: cm(outLen))

            if let aSrc, let aDst {
                if freeze {
                    aDst.insertEmptyTimeRange(CMTimeRange(start: at, duration: cm(outLen)))
                } else {
                    try aDst.insertTimeRange(range, of: aSrc, at: at)
                    aDst.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: cm(outLen))
                }
            }
        }

        let nat = try await vSrc.load(.naturalSize)
        let tf = try await vSrc.load(.preferredTransform)
        let sz = nat.applying(tf)
        let fps = try await vSrc.load(.nominalFrameRate)

        let vc = AVMutableVideoComposition()
        vc.renderSize = CGSize(width: abs(sz.width), height: abs(sz.height))
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(24, min(60, fps.rounded()))))
        vc.customVideoCompositorClass = EffectCompositor.self
        vc.instructions = [EffectInstruction(range: CMTimeRange(start: .zero, duration: comp.duration),
                                             trackID: vDst.trackID, effects: effects,
                                             orientation: orientation(tf))]
        return (comp, vc)
    }

    static func export(asset: AVAsset, remap: [RemapPoint], effects: [EffectInstance]) async throws -> URL {
        let (c, vc) = try await build(asset: asset, remap: remap, effects: effects)
        guard let s = AVAssetExportSession(asset: c, presetName: AVAssetExportPresetHighestQuality)
        else { throw BuildError.exportFailed }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VYRO-\(UUID().uuidString).mov")
        s.outputURL = url; s.outputFileType = .mov; s.videoComposition = vc
        await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
            s.exportAsynchronously { k.resume() }
        }
        guard s.status == .completed else { throw s.error ?? BuildError.exportFailed }
        return url
    }
}
