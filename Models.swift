import Foundation

/// One point on the time-remap graph. x = output (timeline) seconds, y = source seconds.
struct RemapPoint: Codable, Equatable {
    var x: Double
    var y: Double
}

extension Array where Element == RemapPoint {
    static func normal(_ d: Double) -> [RemapPoint] { [.init(x: 0, y: 0), .init(x: d, y: d)] }
    static func slowMid(_ d: Double) -> [RemapPoint] {
        [.init(x: 0, y: 0), .init(x: 0.3*d, y: 0.3*d), .init(x: 1.2*d, y: 0.6*d), .init(x: 1.6*d, y: d)]
    }
    static func ramp(_ d: Double) -> [RemapPoint] {
        [.init(x: 0, y: 0), .init(x: 0.6*d, y: 0.15*d), .init(x: 0.85*d, y: d)]
    }
    static func freeze(_ d: Double) -> [RemapPoint] {
        [.init(x: 0, y: 0), .init(x: 0.4*d, y: 0.4*d), .init(x: 0.8*d, y: 0.4*d), .init(x: 1.2*d, y: d)]
    }
    func sourceTime(at x: Double) -> Double {
        guard count >= 2 else { return x }
        for i in 1..<count where x <= self[i].x {
            let a = self[i-1], b = self[i]
            let u = (x - a.x) / Swift.max(b.x - a.x, 0.0001)
            return a.y + (b.y - a.y) * u
        }
        return last?.y ?? 0
    }
}

enum EffectKind: String, CaseIterable, Codable, Identifiable {
    case glow, rgbSplit, zoomBlur, zoomPulse, shake, glitch, vhs, scanlines, grain
    case pixelate, halftone, twirl, bulge, kaleidoscope, mirror
    case hueShift, posterize, vignette, strobe, neonEdges, invert, lightLeak

    var id: String { rawValue }
    var title: String {
        switch self {
        case .glow: return "Glow"
        case .rgbSplit: return "RGB Split"
        case .zoomBlur: return "Zoom Blur"
        case .zoomPulse: return "Zoom Pulse"
        case .shake: return "Shake"
        case .glitch: return "Glitch"
        case .vhs: return "VHS"
        case .scanlines: return "CRT Lines"
        case .grain: return "Film Grain"
        case .pixelate: return "Pixelate"
        case .halftone: return "Halftone"
        case .twirl: return "Twirl"
        case .bulge: return "Bulge"
        case .kaleidoscope: return "Kaleidoscope"
        case .mirror: return "Mirror"
        case .hueShift: return "Hue Cycle"
        case .posterize: return "Posterize"
        case .vignette: return "Vignette"
        case .strobe: return "Strobe"
        case .neonEdges: return "Neon Edges"
        case .invert: return "Invert"
        case .lightLeak: return "Light Leak"
        }
    }
}

struct EffectInstance: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: EffectKind
    var amount: Double = 0.5
    var start: Double
    var end: Double
}
