//
//  PowerSurgeView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 19/3/2025.
//


import SwiftUI


struct PreviewCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Example cubic curve: from left middle to right middle
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                      control1: CGPoint(x: rect.midX, y: rect.minY),
                      control2: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

struct SolarToGateway: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let endDX = rect.width * 0.25        // 10 / 40
        let control1DX = rect.width * 0.125  // 5 / 40
        let controlY = rect.height * 0.0526  // 10 / 190
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.midX + endDX, y: rect.maxY * 0.35),
                      control1: CGPoint(x: rect.midX + control1DX, y: rect.minY + controlY),
                      control2: CGPoint(x: rect.midX + endDX, y: rect.minY + controlY)
        )
        return path
    }
}

struct ChargerToCar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let moveUp = rect.height * 0.3478      // 40 / 115
        let targetInset = rect.height * 0.3913 // 45 / 115
        let controlInset = rect.height * 0.4348 // 50 / 115
        let dxSmall = rect.width * 0.125       // 5 / 40
        let dxLarge = rect.width * 0.25        // 10 / 40
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - moveUp))
        path.addCurve(
            to: CGPoint(x: rect.midX - dxLarge, y: rect.minY + ((rect.height - targetInset) * 0.35)),
            control1: CGPoint(x: rect.midX - dxSmall, y: rect.maxY - controlInset),
            control2: CGPoint(x: rect.midX - dxLarge, y: rect.maxY - controlInset)
        )
        return path
    }
}

struct GatewayToGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lineStartY = rect.height * 0.1531   // 15 / 98
        let lineEndY = rect.height * 0.3367     // 33 / 98
        let arcCenterX = rect.width * 0.0462    // 6 / 130
        let arcCenterY = rect.height * 0.3980   // 39 / 98
        let arcRadius = min(rect.width, rect.height) * 0.052
        let endXInset = rect.width * 0.0385     // 5 / 130
        let endYInset = rect.height * 0.1020    // 10 / 98
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + lineStartY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + lineEndY))
        path.addArc(
            center: CGPoint(x: rect.minX + arcCenterX, y: rect.minY + arcCenterY),
            radius: arcRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(120),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX - endXInset, y: rect.maxY - endYInset))
        return path
    }
}

struct GatewayToHome: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rise = rect.width * 0.3571 // 25 / 70
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - rise))
        return path
    }
}

struct PowerwallToGateway: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startXOffset = rect.width * 0.125   // 9 / 72
        let startYOffset = rect.height * 0.3333 // 20 / 60
        let endCurveX = rect.width * 0.0278     // 2 / 72
        let endCurveY = rect.height * 0.0667    // 4 / 60
        let controlXOffset = rect.width * 0.1389 // 10 / 72
        let controlYOffset = rect.height * 0.1333 // 8 / 60
        let lineRise = rect.width * 0.3471      // 25 / 72
        path.move(to: CGPoint(x: rect.minX - startXOffset, y: rect.minY + startYOffset))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + endCurveX, y: rect.minY + endCurveY),
            control: CGPoint(x: rect.minX - controlXOffset, y: rect.minY + controlYOffset)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - lineRise))
        return path
    }
}

/// Samples a SwiftUI path so paused surges can sit chevrons along it.
enum PathPolyline {
    static func flatten(_ path: CGPath, steps: Int = 8) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        path.applyWithBlock { element in
            let element = element.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]
                points.append(current)
            case .addLineToPoint:
                current = element.points[0]
                points.append(current)
            case .addQuadCurveToPoint:
                let control = element.points[0]
                let end = element.points[1]
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    points.append(quad(current, control, end, t))
                }
                current = end
            case .addCurveToPoint:
                let control1 = element.points[0]
                let control2 = element.points[1]
                let end = element.points[2]
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    points.append(cubic(current, control1, control2, end, t))
                }
                current = end
            case .closeSubpath:
                break
            default:
                break
            }
        }
        return points
    }

    private static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: a.x * u * u + 2 * b.x * u * t + c.x * t * t,
            y: a.y * u * u + 2 * b.y * u * t + c.y * t * t
        )
    }

    private static func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return CGPoint(
            x: a.x * uu * u + 3 * b.x * uu * t + 3 * c.x * u * tt + d.x * tt * t,
            y: a.y * uu * u + 3 * b.y * uu * t + 3 * c.y * u * tt + d.y * tt * t
        )
    }
}

/// One paused chevron. `tip` points along the energy flow.
struct FlowChevronMark: Equatable {
    var tip: CGPoint
    var tail: CGPoint
}

enum FlowChevron {
    static func marks(along polyline: [CGPoint], spacing: CGFloat, length: CGFloat, pointingForward: Bool) -> [FlowChevronMark] {
        guard polyline.count >= 2, spacing > 0, length > 0 else { return [] }
        var cumulative: [CGFloat] = [0]
        for index in 1..<polyline.count {
            let previous = polyline[index - 1]
            let point = polyline[index]
            cumulative.append(cumulative[index - 1] + hypot(point.x - previous.x, point.y - previous.y))
        }
        let total = cumulative[cumulative.count - 1]
        guard total > length * 0.8 else { return [] }
        var stations: [CGFloat] = []
        if total < spacing * 1.4 {
            stations = [total * 0.5]
        } else {
            var distance = spacing * 0.5
            while distance <= total - length * 0.45 {
                stations.append(distance)
                distance += spacing
            }
        }
        return stations.compactMap { station in
            guard let sample = sample(polyline, cumulative: cumulative, at: station) else { return nil }
            let tangent = pointingForward ? sample.tangent : CGVector(dx: -sample.tangent.dx, dy: -sample.tangent.dy)
            return FlowChevronMark(
                tip: CGPoint(x: sample.point.x + tangent.dx * length * 0.62, y: sample.point.y + tangent.dy * length * 0.62),
                tail: CGPoint(x: sample.point.x - tangent.dx * length * 0.38, y: sample.point.y - tangent.dy * length * 0.38)
            )
        }
    }

    static func path(marks: [FlowChevronMark], spread: CGFloat) -> Path {
        var path = Path()
        for mark in marks {
            let delta = CGVector(dx: mark.tip.x - mark.tail.x, dy: mark.tip.y - mark.tail.y)
            let span = hypot(delta.dx, delta.dy)
            guard span > 0.5 else { continue }
            let forward = CGVector(dx: delta.dx / span, dy: delta.dy / span)
            let lateral = CGVector(dx: -forward.dy, dy: forward.dx)
            let left = CGPoint(x: mark.tail.x + lateral.dx * spread, y: mark.tail.y + lateral.dy * spread)
            let right = CGPoint(x: mark.tail.x - lateral.dx * spread, y: mark.tail.y - lateral.dy * spread)
            let soften = span * 0.28
            let leftControl = CGPoint(
                x: mark.tip.x - forward.dx * soften + lateral.dx * spread * 0.72,
                y: mark.tip.y - forward.dy * soften + lateral.dy * spread * 0.72
            )
            let rightControl = CGPoint(
                x: mark.tip.x - forward.dx * soften - lateral.dx * spread * 0.72,
                y: mark.tip.y - forward.dy * soften - lateral.dy * spread * 0.72
            )
            path.move(to: left)
            path.addQuadCurve(to: mark.tip, control: leftControl)
            path.addQuadCurve(to: right, control: rightControl)
        }
        return path
    }

    private static func sample(_ polyline: [CGPoint], cumulative: [CGFloat], at station: CGFloat) -> (point: CGPoint, tangent: CGVector)? {
        for index in 1..<polyline.count {
            let end = cumulative[index]
            guard end + 0.001 >= station || index == polyline.count - 1 else { continue }
            let start = cumulative[index - 1]
            let span = end - start
            guard span > 0.001 else { continue }
            let t = min(max((station - start) / span, 0), 1)
            let from = polyline[index - 1]
            let to = polyline[index]
            let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            let tangent = CGVector(dx: (to.x - from.x) / span, dy: (to.y - from.y) / span)
            return (point, tangent)
        }
        return nil
    }
}

/// Chevrons following `curve`. `pointingForward` aims them from the path start toward its end.
struct FlowChevronShape<Curve: Shape>: Shape {
    var curve: Curve
    var pointingForward: Bool
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let polyline = PathPolyline.flatten(curve.path(in: rect).cgPath)
        let spacing = max(lineWidth * 2.2, 8)
        let length = max(lineWidth * 1.7, 6)
        let spread = max(lineWidth * 1.5, 5)
        let marks = FlowChevron.marks(along: polyline, spacing: spacing, length: length, pointingForward: pointingForward)
        return FlowChevron.path(marks: marks, spread: spread)
    }
}

/// One frame of the flat-home pulse while it is animating.
private struct FlatHomePulse: Equatable {
    var trimStart: CGFloat
    var opacity: Double
}

struct PowerSurgeView<Curve: Shape>: View {
    var color: Color
    var isForward: Bool
    var duration: Double
    var pauseDuration: Double
    var startOffset: Double
    var lineWidth: CGFloat
    let curve: Curve
    var shouldStart: Bool
    /// Stopped. Draws chevrons in `color` along the cable and does not schedule another pulse.
    var paused: Bool = false

    @State private var startFraction: CGFloat
    @State private var direction: Bool
    @State private var opacity: Double
    @State private var isAnimating = false

    private var gradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: color.opacity(0.5), location: 0),
                .init(color: color.opacity(1.0), location: 1)
            ]),
            startPoint: direction ? .leading : .trailing,
            endPoint: direction ? .trailing : .leading
        )
    }

    init(
        color: Color = .green,
        isForward: Bool = true,
        duration: Double = 2.0,
        pauseDuration: Double = 1.0,
        startOffset: Double = 0.0,
        lineWidth: CGFloat? = nil,
        curve: Curve = PreviewCurve(),
        shouldStart: Bool = false,
        paused: Bool = false
    ) {
        self.color = color
        self.isForward = isForward
        self.duration = duration
        self.pauseDuration = pauseDuration
        self.startOffset = startOffset
        self.lineWidth = lineWidth ?? Self.defaultLineWidth
        self.curve = curve
        self.shouldStart = shouldStart
        self.paused = paused
        _startFraction = State(initialValue: isForward ? 0 : 2.0 / 3.0)
        _direction = State(initialValue: isForward)
        _opacity = State(initialValue: 0.0)
    }

    var body: some View {
        Group {
            if paused {
                FlowChevronShape(curve: curve, pointingForward: isForward, lineWidth: lineWidth)
                    .stroke(color, style: StrokeStyle(lineWidth: max(lineWidth * 0.32, 1.5), lineCap: .round, lineJoin: .round))
            } else {
                surgeShape(FlatHomePulse(trimStart: startFraction, opacity: opacity))
                    .onAppear {
                        if shouldStart {
                            startAnimation()
                        }
                    }
                    .onChange(of: shouldStart) { newValue in
                        if newValue {
                            if !isAnimating {
                                startAnimation()
                            }
                        } else {
                            isAnimating = false
                            opacity = 0.0
                        }
                    }
            }
        }
        .onChange(of: paused) { isPaused in
            if isPaused {
                isAnimating = false
            }
        }
    }

    private func surgeShape(_ frame: FlatHomePulse) -> some View {
        ZStack {
            curve
                .stroke(Color.gray, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(0.0)
            curve
                .trim(from: frame.trimStart, to: frame.trimStart + 1.0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(frame.opacity)
        }
    }

    private func startAnimation() {
        isAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + calculateDelay() + startOffset) {
            if isAnimating {
                opacity = 1.0
                startFraction = direction ? -1.0 : 1.0
                animate()
            }
        }
    }

    private func animate() {
        let targetFraction: CGFloat = direction ? 1.0 : -1.0
        let nextCycleDelay = calculateDelay() + startOffset
        withAnimation(.linear(duration: duration)) {
            startFraction = targetFraction
            opacity = 1.0
        }

        // Prevent a lingering round-cap point at the end of the path during pause time.
        DispatchQueue.main.asyncAfter(deadline: .now() + (duration * 0.97)) {
            guard isAnimating else { return }
            opacity = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + nextCycleDelay) {
            guard isAnimating else { return }
            startFraction = direction ? -1.0 : 1.0
            opacity = 1.0
            animate()
        }
    }

    private func calculateDelay() -> Double {
        // Get the current system uptime
        let currentUptime = ProcessInfo.processInfo.systemUptime
        // Calculate the total cycle time
        let cycleTime = duration + pauseDuration
        // Time elapsed since the last theoretical start
        let timeSinceLastStart = currentUptime.truncatingRemainder(dividingBy: cycleTime)
        // Delay until the next start time
        let delay = cycleTime - timeSinceLastStart
        return delay
    }

    private static var defaultLineWidth: CGFloat {
#if os(macOS)
        return 5.0
#else
        return 6.0
#endif
    }
}

// Example preview
struct PowerSurgeView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PowerSurgeView(startOffset: 1)
                .frame(width: 1000, height: 500)
            PowerSurgeView(color: .blue, isForward: false)
                .frame(width: 1000, height: 500)
        }
    }
}
