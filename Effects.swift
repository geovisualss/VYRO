import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// "AE-style" effects reimplemented with Core Image so they run in real time on iOS.
enum EffectLibrary {

    static func apply(_ e: EffectInstance, to img: CIImage, time t: Double) -> CIImage {
        let ext = img.extent
        let a = CGFloat(e.amount)
        let center = CGPoint(x: ext.midX, y: ext.midY)
        let minSide = min(ext.width, ext.height)

        switch e.kind {
        case .glow:
            let f = CIFilter.bloom(); f.inputImage = img
            f.radius = Float(8 + 40 * a); f.intensity = Float(0.6 + 1.6 * a)
            return f.outputImage?.cropped(to: ext) ?? img

        case .rgbSplit:
            return split(img, ext, dist: 6 + 40 * a, angle: CGFloat(t) * 2)

        case .zoomBlur:
            let f = CIFilter.zoomBlur(); f.inputImage = img
            f.center = center; f.amount = Float(5 + 60 * a)
            return f.outputImage?.cropped(to: ext) ?? img

        case .zoomPulse:
            let s = 1 + 0.15 * a * CGFloat(0.5 + 0.5 * sin(t * 8))
            return scaled(img, ext, s, dx: 0, dy: 0)

        case .shake:
            let dx = CGFloat(sin(t * 47) + 0.5 * sin(t * 91)) * 22 * a
            let dy = CGFloat(cos(t * 53) + 0.5 * cos(t * 83)) * 22 * a
            return scaled(img, ext, 1 + 0.08 * a, dx: dx, dy: dy)

        case .glitch:
            return glitch(img, ext, t: t, a: a)

        case .vhs:
            var o = split(img, ext, dist: 3 + 8 * a, angle: 0)
            let cc = CIFilter.colorControls(); cc.inputImage = o
            cc.saturation = Float(1 - 0.3 * a); cc.contrast = Float(1 + 0.15 * a)
            o = cc.outputImage ?? o
            o = scan(o, ext, a)
            // drifting tracking band
            let y = ext.minY + ext.height * CGFloat((t * 0.25).truncatingRemainder(dividingBy: 1))
            let band = o.cropped(to: CGRect(x: ext.minX, y: y, width: ext.width, height: ext.height * 0.03))
                .transformed(by: .init(translationX: 30 * a, y: 0))
            o = band.composited(over: o)
            return add(o, noise(ext, t, 0.25 * a)).cropped(to: ext)

        case .scanlines:
            return scan(img, ext, 0.4 + a)

        case .grain:
            return add(img, noise(ext, t, 0.5 * a)).cropped(to: ext)

        case .pixelate:
            let f = CIFilter.pixellate(); f.inputImage = img
            f.center = center; f.scale = Float(4 + 60 * a)
            return f.outputImage?.cropped(to: ext) ?? img

        case .halftone:
            let f = CIFilter.cmykHalftone(); f.inputImage = img
            f.width = Float(4 + 14 * a); f.sharpness = 0.9
            return f.outputImage?.cropped(to: ext) ?? img

        case .twirl:
            let f = CIFilter.twirlDistortion(); f.inputImage = img
            f.center = center; f.radius = Float(minSide * 0.6)
            f.angle = Float(a * 4 * CGFloat(sin(t * 2)))
            return f.outputImage?.cropped(to: ext) ?? img

        case .bulge:
            let f = CIFilter.bumpDistortion(); f.inputImage = img
            f.center = center; f.radius = Float(minSide * 0.5)
            f.scale = Float(-1 + 2 * a)
            return f.outputImage?.cropped(to: ext) ?? img

        case .kaleidoscope:
            let f = CIFilter.kaleidoscope(); f.inputImage = img
            f.center = center; f.count = Int(3 + 9 * a); f.angle = Float(t * 0.4)
            return f.outputImage?.cropped(to: ext) ?? img

        case .mirror:
            let left = img.cropped(to: CGRect(x: ext.minX, y: ext.minY, width: ext.width / 2, height: ext.height))
            let flip = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: ext.width + 2 * ext.minX, ty: 0)
            return left.transformed(by: flip).composited(over: img).cropped(to: ext)

        case .hueShift:
            let f = CIFilter.hueAdjust(); f.inputImage = img
            f.angle = Float(t * 3 * Double(0.3 + a))
            return f.outputImage?.cropped(to: ext) ?? img

        case .posterize:
            let f = CIFilter.colorPosterize(); f.inputImage = img
            f.levels = Float(max(2, 12 - 10 * a))
            return f.outputImage?.cropped(to: ext) ?? img

        case .vignette:
            let f = CIFilter.vignette(); f.inputImage = img
            f.intensity = Float(2 * a); f.radius = Float(1 + 2 * a)
            return f.outputImage?.cropped(to: ext) ?? img

        case .strobe:
            let f = CIFilter.exposureAdjust(); f.inputImage = img
            f.ev = sin(t * 20) > 0 ? Float(2.5 * a) : 0
            return f.outputImage?.cropped(to: ext) ?? img

        case .neonEdges:
            let f = CIFilter.edges(); f.inputImage = img; f.intensity = Float(2 + 8 * a)
            guard let edges = f.outputImage else { return img }
            let h = CIFilter.hueAdjust(); h.inputImage = edges; h.angle = Float(t)
            return (h.outputImage ?? edges).cropped(to: ext)

        case .invert:
            let f = CIFilter.colorInvert(); f.inputImage = img
            return f.outputImage?.cropped(to: ext) ?? img

        case .lightLeak:
            let g = CIFilter.radialGradient()
            g.center = CGPoint(x: ext.minX + ext.width * CGFloat(0.5 + 0.5 * sin(t * 0.9)),
                               y: ext.minY + ext.height * CGFloat(0.5 + 0.4 * cos(t * 0.7)))
            g.radius0 = 0; g.radius1 = Float(minSide * (0.5 + 0.4 * a))
            g.color0 = CIColor(red: 1, green: 0.45, blue: 0.1, alpha: 0.9 * a + 0.1)
            g.color1 = CIColor(red: 1, green: 0.1, blue: 0.4, alpha: 0)
            guard let grad = g.outputImage else { return img }
            let s = CIFilter.screenBlendMode(); s.inputImage = grad.cropped(to: ext); s.backgroundImage = img
            return s.outputImage?.cropped(to: ext) ?? img
        }
    }

    // MARK: helpers

    static func channel(_ i: CIImage, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
        let m = CIFilter.colorMatrix(); m.inputImage = i
        m.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        m.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        m.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return m.outputImage ?? i
    }

    static func add(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.additionCompositing(); f.inputImage = a; f.backgroundImage = b
        return f.outputImage ?? a
    }

    static func shift(_ i: CIImage, _ dx: CGFloat, _ dy: CGFloat) -> CIImage {
        i.clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }

    static func split(_ img: CIImage, _ ext: CGRect, dist: CGFloat, angle: CGFloat) -> CIImage {
        let dx = cos(angle) * dist, dy = sin(angle) * dist
        let r = shift(channel(img, 1, 0, 0), dx, dy)
        let g = channel(img, 0, 1, 0)
        let b = shift(channel(img, 0, 0, 1), -dx, -dy)
        return add(add(r, g), b).cropped(to: ext)
    }

    static func scaled(_ img: CIImage, _ ext: CGRect, _ s: CGFloat, dx: CGFloat, dy: CGFloat) -> CIImage {
        let t = CGAffineTransform(translationX: ext.midX + dx, y: ext.midY + dy)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -ext.midX, y: -ext.midY)
        return img.clampedToExtent().transformed(by: t).cropped(to: ext)
    }

    static func noise(_ ext: CGRect, _ t: Double, _ s: CGFloat) -> CIImage {
        guard let n = CIFilter.randomGenerator().outputImage else { return CIImage.empty() }
        let off = CGAffineTransform(translationX: CGFloat((t * 1000).truncatingRemainder(dividingBy: 997)),
                                    y: CGFloat((t * 733).truncatingRemainder(dividingBy: 991)))
        let m = CIFilter.colorMatrix(); m.inputImage = n.transformed(by: off)
        m.rVector = CIVector(x: s, y: 0, z: 0, w: 0)
        m.gVector = CIVector(x: s, y: 0, z: 0, w: 0)
        m.bVector = CIVector(x: s, y: 0, z: 0, w: 0)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        m.biasVector = CIVector(x: -s / 2, y: -s / 2, z: -s / 2, w: 1)
        return (m.outputImage ?? n).cropped(to: ext)
    }

    static func scan(_ img: CIImage, _ ext: CGRect, _ a: CGFloat) -> CIImage {
        let s = CIFilter.stripesGenerator()
        s.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: min(0.6, 0.35 * a + 0.05))
        s.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        s.width = Float(max(1.5, ext.height / 300)); s.sharpness = 1; s.center = .zero
        guard let st = s.outputImage else { return img }
        return st.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: ext).composited(over: img)
    }

    static func rnd(_ seed: UInt64, _ i: Int, _ k: Int) -> CGFloat {
        var x = seed &* 6364136223846793005 &+ UInt64(i * 31 + k * 7 + 1) &* 1442695040888963407
        x ^= x >> 33; x = x &* 0xff51afd7ed558ccd; x ^= x >> 33
        return CGFloat(x % 10000) / 10000
    }

    static func glitch(_ img: CIImage, _ ext: CGRect, t: Double, a: CGFloat) -> CIImage {
        let seed = UInt64(max(0, t) * 12)
        var out = img
        for i in 0..<7 {
            let h = ext.height * (0.02 + 0.08 * rnd(seed, i, 0))
            let y = ext.minY + ext.height * rnd(seed, i, 1)
            let dx = (rnd(seed, i, 2) - 0.5) * ext.width * 0.35 * a
            let band = img.cropped(to: CGRect(x: ext.minX, y: y, width: ext.width, height: h))
                .transformed(by: CGAffineTransform(translationX: dx, y: 0))
            out = band.composited(over: out)
        }
        return split(out, ext, dist: 4 + 14 * a, angle: 0)
    }
}
