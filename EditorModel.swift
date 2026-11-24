import SwiftUI
import AVFoundation
import PhotosUI

struct Movie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in SentTransferredFile(m.url) } importing: { r in
            let ext = r.file.pathExtension.isEmpty ? "mov" : r.file.pathExtension
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: r.file, to: dst)
            return Movie(url: dst)
        }
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var asset: AVURLAsset?
    @Published var srcDuration: Double = 0
    @Published var outDuration: Double = 0
    @Published var playhead: Double = 0
    @Published var isPlaying = false
    @Published var errorText: String?
    let player = AVPlayer()

    @Published var remap: [RemapPoint] = [] { didSet { scheduleRebuild() } }
    @Published var effects: [EffectInstance] = [] { didSet { scheduleRebuild() } }
    private var task: Task<Void, Never>?

    init() {
        player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            guard let self else { return }
            self.playhead = t.seconds
            self.isPlaying = self.player.rate > 0
        }
    }

    func load(_ url: URL) async {
        let a = AVURLAsset(url: url)
        guard let d = try? await a.load(.duration).seconds else { return }
        asset = a; srcDuration = d; effects = []
        remap = .normal(d)
    }

    func scheduleRebuild() {
        guard let asset else { return }
        let r = remap, fx = effects, was = playhead
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            do {
                let (c, vc) = try await Builder.build(asset: asset, remap: r, effects: fx)
                if Task.isCancelled { return }
                let item = AVPlayerItem(asset: c)
                item.videoComposition = vc
                item.audioTimePitchAlgorithm = .spectral
                outDuration = c.duration.seconds
                player.replaceCurrentItem(with: item)
                await player.seek(to: CMTime(seconds: min(was, outDuration), preferredTimescale: 600),
                                  toleranceBefore: .zero, toleranceAfter: .zero)
            } catch { errorText = error.localizedDescription }
        }
    }

    func seek(_ s: Double) {
        player.seek(to: CMTime(seconds: s, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        playhead = s
    }
    func toggle() { player.rate > 0 ? player.pause() : player.play() }

    func addEffect(_ k: EffectKind) {
        let s = min(playhead, max(0, outDuration - 0.5))
        effects.append(EffectInstance(kind: k, amount: 0.5, start: s, end: min(outDuration, s + 2)))
    }

    /// Adds a point to the remap graph at the current playhead (on the existing curve).
    func addRemapPoint(atX x: Double) {
        guard x > 0.1, x < (remap.last?.x ?? 0) - 0.1 else { return }
        guard let i = remap.firstIndex(where: { $0.x > x }) else { return }
        remap.insert(RemapPoint(x: x, y: remap.sourceTime(at: x)), at: i)
    }
}
