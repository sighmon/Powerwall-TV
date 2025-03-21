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
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.midX + 10, y: rect.maxY * 0.35),
                      control1: CGPoint(x: rect.midX + 5, y: rect.minY + 10),
                      control2: CGPoint(x: rect.midX + 10, y: rect.minY + 10)
        )
        return path
    }
}

struct GatewayToGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 35))
        path.addArc(
            center: CGPoint(x: rect.minX + 6, y: rect.minY + 39),
            radius: 5.1,
            startAngle: .degrees(180),
            endAngle: .degrees(120),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX - 5, y: rect.maxY - 10))
        return path
    }
}

struct GatewayToHome: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 25))
        return path
    }
}

struct PowerwallToGateway: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - 9, y: rect.minY + 20))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 2, y: rect.minY + 4),
            control: CGPoint(x: rect.minX - 10, y: rect.minY + 8)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 25))
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

    @State private var startFraction: CGFloat
    @State private var direction: Bool
    @State private var opacity: Double

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
        duration: Double = 1.0,
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
                .stroke(Color.gray, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .opacity(0.0)
            curve
                .trim(from: startFraction, to: startFraction + 1.0)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .opacity(opacity)
        }
        .onAppear {
            if shouldStart {
                DispatchQueue.main.asyncAfter(deadline: .now() + startOffset) {
                    opacity = 1.0
                    startFraction = direction ? -1.0 : 1.0
                    animate()
                }
            }
        }
    }

    private func animate() {
        let targetFraction: CGFloat = direction ? 1.0 : -1.0
        withAnimation(.linear(duration: duration)) {
            startFraction = targetFraction
            opacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + pauseDuration) {
            startFraction = direction ? -1.0 : 1.0
            opacity = 1.0
            animate()
        }
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
