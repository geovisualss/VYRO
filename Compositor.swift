import AVFoundation
import CoreImage

final class EffectInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    let effects: [EffectInstance]
    let orientation: CGImagePropertyOrientation
    var requiredSourceTrackIDs: [NSValue]? { [NSNumber(value: trackID)] }

    init(range: CMTimeRange, trackID: CMPersistentTrackID, effects: [EffectInstance],
         orientation: CGImagePropertyOrientation) {
        self.timeRange = range; self.trackID = trackID
        self.effects = effects; self.orientation = orientation
    }
}

final class EffectCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String: Any]? =
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    var requiredPixelBufferAttributesForRenderContext: [String: Any] =
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    private let ctx = CIContext()
    private let space = CGColorSpaceCreateDeviceRGB()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let inst = request.videoCompositionInstruction as? EffectInstruction,
              let src = request.sourceFrame(byTrackID: inst.trackID),
              let out = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "VYRO", code: 1))
            return
        }
        var img = CIImage(cvPixelBuffer: src).oriented(inst.orientation)
        let t = request.compositionTime.seconds
        for e in inst.effects where t >= e.start && t <= e.end {
            img = EffectLibrary.apply(e, to: img, time: t)
        }
        let size = request.renderContext.size
        ctx.render(img, to: out, bounds: CGRect(origin: .zero, size: size), colorSpace: space)
        request.finish(withComposedVideoFrame: out)
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
