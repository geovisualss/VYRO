import SwiftUI

/// Time-remap graph. X = output (timeline) time, Y = source time.
/// Slope of a segment = playback speed. Flat = freeze frame. Steeper = faster.
/// Drag points · double-tap empty space to add · double-tap a point to delete.
struct RemapGraph: View {
    @Binding var points: [RemapPoint]
    let srcDur: Double
    let playhead: Double
    private var xMax: Double { max(srcDur * 2, 0.1) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Canvas { ctx, size in
                    let px = { (x: Double) in CGFloat(x / xMax) * size.width }
                    let py = { (y: Double) in size.height - CGFloat(y / max(srcDur, 0.001)) * size.height }

                    // grid
                    for i in 0...4 {
                        var g = Path()
                        let gy = size.height * CGFloat(i) / 4
                        g.move(to: .init(x: 0, y: gy)); g.addLine(to: .init(x: size.width, y: gy))
                        let gx = size.width * CGFloat(i) / 4 * 1.0
                        g.move(to: .init(x: gx, y: 0)); g.addLine(to: .init(x: gx, y: size.height))
                        ctx.stroke(g, with: .color(.white.opacity(0.07)), lineWidth: 1)
                    }
                    // reference 1x line
                    var ref = Path(); ref.move(to: .init(x: 0, y: py(0))); ref.addLine(to: .init(x: px(srcDur), y: py(srcDur)))
                    ctx.stroke(ref, with: .color(.white.opacity(0.18)), style: .init(lineWidth: 1, dash: [4, 4]))

                    guard points.count >= 2 else { return }
                    // fill
                    var fill = Path(); fill.move(to: .init(x: px(points[0].x), y: py(0)))
                    for p in points { fill.addLine(to: .init(x: px(p.x), y: py(p.y))) }
                    fill.addLine(to: .init(x: px(points.last!.x), y: py(0))); fill.closeSubpath()
                    ctx.fill(fill, with: .linearGradient(
                        Gradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)]),
                        startPoint: .init(x: 0, y: 0), endPoint: .init(x: 0, y: size.height)))

                    // segments colored by speed
                    for i in 1..<points.count {
                        let a = points[i-1], b = points[i]
                        let speed = (b.y - a.y) / max(b.x - a.x, 0.0001)
                        var seg = Path()
                        seg.move(to: .init(x: px(a.x), y: py(a.y))); seg.addLine(to: .init(x: px(b.x), y: py(b.y)))
                        let c: Color = speed < 0.98 ? Theme.slow : (speed > 1.02 ? Theme.accent : .white)
                        ctx.stroke(seg, with: .color(c), style: .init(lineWidth: 3, lineCap: .round))
                        let mid = CGPoint(x: (px(a.x) + px(b.x)) / 2, y: (py(a.y) + py(b.y)) / 2 - 14)
                        ctx.draw(Text(String(format: "%.2fx", speed)).font(.caption2.monospacedDigit())
                            .foregroundColor(c), at: mid)
                    }
                    // playhead
                    let ph = min(playhead, points.last!.x)
                    var pl = Path()
                    pl.move(to: .init(x: px(ph), y: 0)); pl.addLine(to: .init(x: px(ph), y: size.height))
                    ctx.stroke(pl, with: .color(.white.opacity(0.6)), lineWidth: 1)
                    let sy = py(points.sourceTime(at: ph))
                    ctx.fill(Path(ellipseIn: CGRect(x: px(ph) - 4, y: sy - 4, width: 8, height: 8)), with: .color(.white))
                }

                ForEach(points.indices, id: \.self) { i in
                    Circle().fill(i == 0 ? Color.gray : Theme.accent)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle().inset(by: -10))
                        .position(x: CGFloat(points[i].x / xMax) * w,
                                  y: h - CGFloat(points[i].y / max(srcDur, 0.001)) * h)
                        .onTapGesture(count: 2) { if i > 0 && i < points.count - 1 { points.remove(at: i) } }
                        .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("graph"))
                            .onChanged { v in move(i, v.location, w, h) })
                }
            }
            .coordinateSpace(name: "graph")
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { v in
                let x = Double(v.location.x / w) * xMax
                guard let i = points.firstIndex(where: { $0.x > x }), i > 0 else { return }
                points.insert(RemapPoint(x: x, y: points.sourceTime(at: x)), at: i)
            })
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func move(_ i: Int, _ loc: CGPoint, _ w: CGFloat, _ h: CGFloat) {
        guard i > 0, i < points.count else { return }
        var x = Double(loc.x / w) * xMax
        var y = (1 - Double(loc.y / h)) * srcDur
        let prev = points[i - 1], gap = 0.05
        x = max(x, prev.x + gap)
        if i == points.count - 1 { x = min(x, xMax); y = srcDur }
        else { let next = points[i + 1]; x = min(x, next.x - gap); y = min(y, next.y) }
        y = max(y, prev.y)
        points[i] = RemapPoint(x: x, y: y)
    }
}
