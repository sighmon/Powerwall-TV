//
//  PowerSurgeView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 19/3/2025.
//


import SwiftUI

enum FlowDirection {
    case forward
    case backward
}

// The view that shows an animated pulse flowing along the bezier curve.
struct PowerSurgeView<Curve: Shape>: View {
    let color: Color
    let direction: FlowDirection
    let lineWidth: CGFloat = 10
    let duration: CGFloat
    let curve: Curve

    // Starting pulse length, this will animate to 1
    @State private var pulseLength: CGFloat = 0
    // Starting pulse position
    @State private var pulsePosition: CGFloat = 0.0

    // A computed property to get the gradient used for the pulse stroke.
    private var gradient: LinearGradient {
        // For a forward flow, the gradient fades from full (leading) to transparent (trailing)
        // For a backward flow, we reverse that.
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: color.opacity(0.0), location: 0),
                .init(color: color.opacity(1.0), location: 1)
            ]),
            startPoint: direction == .forward ? .leading : .trailing,
            endPoint: direction == .forward ? .trailing : .leading
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // The static background curve (for reference)
                curve
                    .stroke(Color.gray.opacity(0.3), lineWidth: lineWidth)

                // The animated pulse overlay.
                Group {
                    if pulsePosition + pulseLength <= 1 {
                        // The pulse segment fits entirely within [0, 1]
                        curve
                            .trim(from: pulsePosition, to: pulsePosition + pulseLength)
                            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    } else {
                        // The pulse wraps around; split into two segments.
                        curve
                            .trim(from: pulsePosition, to: 1)
                            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        curve
                            .trim(from: 0, to: (pulsePosition + pulseLength) - 1)
                            .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
            }
            // Ensure the view uses the available geometry.
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear {
                // Start the animation.
                animatePulse()
            }
        }
    }
    // Recursive animation function that animates the pulse, waits for a pause, then repeats.
    private func animatePulse() {
        // Animate the pulse from 0 to 1 over 2 seconds.
        withAnimation(Animation.linear(duration: duration)) {
            pulseLength = 1
        }
        // After the animation finishes (2 seconds) plus a pause (e.g. 1 second), reset and animate again.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + duration) {
            pulseLength = 0
            animatePulse()
        }
    }
}

// A test curve for previewing
struct TestCurve: Shape {
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

// Example preview
struct PulseCurveView_Previews: PreviewProvider {
    static var previews: some View {
        PowerSurgeView(
            color: .green,
            direction: .forward,
            duration: 1,
            curve: TestCurve()
        )
            .frame(width: 1000, height: 1000)
            .padding()
    }
}
