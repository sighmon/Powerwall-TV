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

struct PowerSurgeView<Curve: Shape>: View {
    var color: Color
    var isForward: Bool
    var duration: Double
    var pauseDuration: Double
    var startOffset: Double
    let curve: Curve
    var shouldStart: Bool
#if os(macOS)
    let lineWidth: Double = 5
#else
    let lineWidth: Double = 6
#endif

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
        curve: Curve = PreviewCurve(),
        shouldStart: Bool = false
    ) {
        self.color = color
        self.isForward = isForward
        self.duration = duration
        self.pauseDuration = pauseDuration
        self.startOffset = startOffset
        self.curve = curve
        self.shouldStart = shouldStart
        _startFraction = State(initialValue: isForward ? 0 : 2.0 / 3.0)
        _direction = State(initialValue: isForward)
        _opacity = State(initialValue: 0.0)
    }

    var body: some View {
        ZStack {
            curve
                .stroke(Color.gray, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(0.0)
            curve
                .trim(from: startFraction, to: startFraction + 1.0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(opacity)
        }
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
                opacity = 0.0 // Optional: reset visibility
            }
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
        withAnimation(.linear(duration: duration)) {
            startFraction = targetFraction
            opacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + calculateDelay() + startOffset) {
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
