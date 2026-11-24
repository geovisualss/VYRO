import SwiftUI
import AVKit
import PhotosUI
import Photos

enum Theme {
    static let bg = Color(red: 0.05, green: 0.05, blue: 0.09)
    static let panel = Color.white.opacity(0.06)
    static let accent = Color(red: 1.0, green: 0.48, blue: 0.22)
    static let slow = Color(red: 0.35, green: 0.7, blue: 1.0)
}

struct ContentView: View {
    @StateObject private var m = EditorModel()
    @State private var pick: PhotosPickerItem?
    @State private var tab = 0

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if m.asset == nil { welcome } else { editor }
        }
        .onChange(of: pick) { item in
            Task {
                if let mv = try? await item?.loadTransferable(type: Movie.self) { await m.load(mv.url) }
            }
        }
    }

    var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "wand.and.rays").font(.system(size: 54)).foregroundColor(Theme.accent)
            Text("VYRO").font(.largeTitle.bold())
            Text("Free video effects, glitches and time remap.").foregroundColor(.secondary)
            PhotosPicker(selection: $pick, matching: .videos) {
                Label("Import video", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 24).padding(.vertical, 14)
                    .background(Theme.accent, in: Capsule()).foregroundColor(.black).font(.headline)
            }
        }
    }

    var editor: some View {
        VStack(spacing: 10) {
            VideoPlayer(player: m.player)
                .frame(maxHeight: 340)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

            HStack(spacing: 12) {
                Button { m.toggle() } label: {
                    Image(systemName: m.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                        .frame(width: 40, height: 40).background(Theme.panel, in: Circle())
                }
                Slider(value: Binding(get: { m.playhead }, set: { m.seek($0) }),
                       in: 0...max(m.outDuration, 0.1)).tint(Theme.accent)
                Text(String(format: "%.1f/%.1fs", m.playhead, m.outDuration))
                    .font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }.padding(.horizontal)

            Group {
                switch tab {
                case 0: effectsTab
                case 1: remapTab
                default: exportTab
                }
            }.frame(maxHeight: .infinity)

            HStack {
                tabButton(0, "sparkles", "Effects")
                tabButton(1, "chart.xyaxis.line", "Time Remap")
                tabButton(2, "square.and.arrow.up", "Export")
            }
            .padding(.vertical, 8).background(Theme.panel)
        }
    }

    func tabButton(_ i: Int, _ icon: String, _ title: String) -> some View {
        Button { tab = i } label: {
            VStack(spacing: 3) { Image(systemName: icon); Text(title).font(.caption2) }
                .frame(maxWidth: .infinity)
                .foregroundColor(tab == i ? Theme.accent : .secondary)
        }
    }

    // MARK: Effects

    var effectsTab: some View {
        VStack(spacing: 8) {
            Menu {
                ForEach(EffectKind.allCases) { k in Button(k.title) { m.addEffect(k) } }
            } label: {
                Label("Add effect at playhead", systemImage: "plus")
                    .frame(maxWidth: .infinity).padding(10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.black).font(.subheadline.bold())
            }.padding(.horizontal)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($m.effects) { $e in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(e.kind.title).font(.headline)
                                Spacer()
                                Button { m.effects.removeAll { $0.id == e.id } } label: {
                                    Image(systemName: "trash").foregroundColor(.red)
                                }
                            }
                            row("Amount", $e.amount, 0...1)
                            row("Start", $e.start, 0...max(m.outDuration, 0.1))
                            row("End", $e.end, 0...max(m.outDuration, 0.1))
                        }
                        .padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if m.effects.isEmpty {
                        Text("No effects yet.").foregroundColor(.secondary).padding(.top, 30)
                    }
                }.padding(.horizontal)
            }
        }
    }

    func row(_ name: String, _ v: Binding<Double>, _ r: ClosedRange<Double>) -> some View {
        HStack {
            Text(name).font(.caption).frame(width: 52, alignment: .leading).foregroundColor(.secondary)
            Slider(value: v, in: r).tint(Theme.accent)
        }
    }

    // MARK: Time remap

    var remapTab: some View {
        VStack(spacing: 8) {
            RemapGraph(points: $m.remap, srcDur: m.srcDuration, playhead: m.playhead)
                .frame(height: 220).padding(.horizontal)
            Text("Y = source time · X = timeline · slope = speed. Drag points, double-tap to add/delete.")
                .font(.caption2).foregroundColor(.secondary).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    chip("Normal") { m.remap = .normal(m.srcDuration) }
                    chip("Slow-mo") { m.remap = .slowMid(m.srcDuration) }
                    chip("Ramp") { m.remap = .ramp(m.srcDuration) }
                    chip("Freeze") { m.remap = .freeze(m.srcDuration) }
                    chip("+ Point at playhead") { m.addRemapPoint(atX: m.playhead) }
                }.padding(.horizontal)
            }
            Spacer()
        }
    }

    func chip(_ t: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Text(t).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.panel, in: Capsule())
        }
    }

    // MARK: Export

    @State private var exporting = false
    @State private var exported: URL?
    @State private var saved = false

    var exportTab: some View {
        VStack(spacing: 14) {
            Button {
                guard let a = m.asset else { return }
                exporting = true; saved = false; exported = nil
                Task {
                    do { exported = try await Builder.export(asset: a, remap: m.remap, effects: m.effects) }
                    catch { m.errorText = error.localizedDescription }
                    exporting = false
                }
            } label: {
                Group { exporting ? AnyView(ProgressView()) : AnyView(Text("Render video")) }
                    .frame(maxWidth: .infinity).padding(14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundColor(.black).font(.headline)
            }.disabled(exporting)

            if let url = exported {
                ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                Button(saved ? "Saved ✓" : "Save to Photos") {
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
                        guard s == .authorized || s == .limited else { return }
                        PHPhotoLibrary.shared().performChanges({
                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                        }) { ok, _ in DispatchQueue.main.async { saved = ok } }
                    }
                }
            }
            if let e = m.errorText { Text(e).foregroundColor(.red).font(.caption) }
            Spacer()
        }.padding()
    }
}
