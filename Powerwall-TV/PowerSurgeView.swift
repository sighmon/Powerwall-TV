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
        path.move(to: CGPoint(x: rect.midX + 10, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + 10, y: rect.minY + 30))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + 20, y: rect.minY + 50),
            control: CGPoint(x: rect.midX + 10, y: rect.minY + 45)
        )
        path.addLine(to: CGPoint(x: rect.midX + 200, y: rect.minY + 115))
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
        path.move(to: CGPoint(x: rect.minX - 7, y: rect.minY + 20))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 5, y: rect.minY),
            control: CGPoint(x: rect.minX - 9, y: rect.minY + 8)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 25))
        return path
    }
}

struct PowerSurgeView<Curve: Shape>: View {
    // The color of the moving line
    var color: Color
    // Direction: true for forward (start to end), false for backward (end to start)
    var isForward: Bool
    // Duration of the animation in seconds
    var duration: Double
    // Pause duration between animations in seconds
    var pauseDuration: Double
    // Offset the start by this duration in seconds
    var startOffset: Double
    let curve: Curve

    // State variable to control the starting point of the green line's trim
    @State private var startFraction: CGFloat
    // Local copy of isForward to toggle direction
    @State private var direction: Bool
    @State private var opacity: Double

    init(
        color: Color = .green,
        isForward: Bool = true,
        duration: Double = 1.0,
        pauseDuration: Double = 1.0,
        startOffset: Double = 0.0,
        curve: Curve = PreviewCurve()
    ) {
        self.color = color
        self.isForward = isForward
        self.duration = duration
        self.pauseDuration = pauseDuration
        self.startOffset = startOffset
        self.curve = curve
        _startFraction = State(initialValue: isForward ? 0 : 2.0 / 3.0)
        _direction = State(initialValue: isForward)
        _opacity = State(initialValue: 1.0)
    }

    var body: some View {
        ZStack {
            // Full gray Bezier line (static)
            curve
                .stroke(Color.gray, lineWidth: 6)
                .opacity(0.0)

            // Moving line (animated)
            curve
                .trim(from: startFraction, to: startFraction + 1.0)
                .stroke(color, lineWidth: 6)
                .opacity(opacity)
        }
        .onAppear {
            opacity = 0.0
            DispatchQueue.main.asyncAfter(deadline: .now() + startOffset) {
                opacity = 1.0
                animate()
            }
        }
    }

    // Function to handle the animation loop with pause
    private func animate() {
        // Define the target fraction based on direction
        let targetFraction: CGFloat = direction ? 1.0 : -1.0

        // Move the line
        withAnimation(.linear(duration: duration)) {
            startFraction = targetFraction
            opacity = 1.0
        }

        // After animation completes, pause and then reverse
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + pauseDuration) {
            // Toggle direction for the next cycle
            startFraction = direction ? -1.0 : 1.0
            opacity = 1.0
            // Recursively call animate to loop
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
