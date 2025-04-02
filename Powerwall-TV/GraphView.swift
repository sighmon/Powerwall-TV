//
//  GraphView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 26/3/2025.
//


import SwiftUI
import Charts

struct GraphView: View {
    @ObservedObject var viewModel: PowerwallViewModel

    func colorForPoint(_ point: HistoricalDataPoint) -> Color {
        if point.value >= 0 {
            return .blue
        } else if point.from == PowerFrom.solar {
            return .yellow
        } else {
            return .gray
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Battery Power Flow Chart
            Text("Powerwall")
                .font(.title)
            Text("YESTERDAY → TODAY · ENERGY FLOW · kWh")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(.footnote)
            Chart {
                // Define data points with invisible PointMarks to set the chart's scale
                ForEach(viewModel.batteryPowerHistory, id: \.date) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Power (kW)", point.value / 100)
                    )
                    .opacity(0) // Hide the points
                }
            }
            .frame(height: 600)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack {
                        if viewModel.batteryPowerHistory.count >= 2,
                           let firstDate = viewModel.batteryPowerHistory.first?.date,
                           let baselineY = proxy.position(for: (x: firstDate, y: 0))?.y {

                            ForEach(0..<viewModel.batteryPowerHistory.count - 1, id: \.self) { index in
                                let start = viewModel.batteryPowerHistory[index]
                                let end = viewModel.batteryPowerHistory[index + 1]

                                if (start.value >= 0 && end.value < 0) || (start.value < 0 && end.value >= 0) {
                                    let zeroCrossing = interpolateZeroCrossing(start: start, end: end)

                                    // First segment: start to zeroCrossing
                                    if let startPoint = proxy.position(for: (x: start.date, y: start.value / 100)),
                                       let zeroPoint = proxy.position(for: (x: zeroCrossing.date, y: zeroCrossing.value / 100)) {
                                        let color = colorForPoint(start)
                                        let areaPath = Path { p in
                                            p.move(to: startPoint)
                                            p.addLine(to: zeroPoint)
                                            p.addLine(to: CGPoint(x: zeroPoint.x, y: baselineY))
                                            p.addLine(to: CGPoint(x: startPoint.x, y: baselineY))
                                            p.closeSubpath()
                                        }
                                        let gradient = LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: color.opacity(0.3), location: 0),
                                                .init(color: color.opacity(0.1), location: 1)
                                            ]),
                                            startPoint: color == .blue ? .top : .bottom,
                                            endPoint: color == .blue ? .bottom : .top
                                        )
                                        areaPath
                                            .fill(gradient)

                                        let linePath = Path { p in
                                            p.move(to: startPoint)
                                            p.addLine(to: zeroPoint)
                                        }
                                        linePath
                                            .stroke(color, lineWidth: 2)
                                    }

                                    // Second segment: zeroCrossing to end
                                    if let zeroPoint = proxy.position(for: (x: zeroCrossing.date, y: zeroCrossing.value / 100)),
                                       let endPoint = proxy.position(for: (x: end.date, y: end.value / 100)) {
                                        let color = colorForPoint(end) // Updated to use end point
                                        let areaPath = Path { p in
                                            p.move(to: zeroPoint)
                                            p.addLine(to: endPoint)
                                            p.addLine(to: CGPoint(x: endPoint.x, y: baselineY))
                                            p.addLine(to: CGPoint(x: zeroPoint.x, y: baselineY))
                                            p.closeSubpath()
                                        }
                                        let gradient = LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: color.opacity(0.3), location: 0),
                                                .init(color: color.opacity(0.1), location: 1)
                                            ]),
                                            startPoint: color == .blue ? .top : .bottom,
                                            endPoint: color == .blue ? .bottom : .top
                                        )
                                        areaPath
                                            .fill(gradient)

                                        let linePath = Path { p in
                                            p.move(to: zeroPoint)
                                            p.addLine(to: endPoint)
                                        }
                                        linePath
                                            .stroke(color, lineWidth: 2)
                                    }
                                } else {
                                    // No zero crossing, draw the full segment
                                    if let startPoint = proxy.position(for: (x: start.date, y: start.value / 100)),
                                       let endPoint = proxy.position(for: (x: end.date, y: end.value / 100)) {
                                        let color = colorForPoint(start)
                                        let areaPath = Path { p in
                                            p.move(to: startPoint)
                                            p.addLine(to: endPoint)
                                            p.addLine(to: CGPoint(x: endPoint.x, y: baselineY))
                                            p.addLine(to: CGPoint(x: startPoint.x, y: baselineY))
                                            p.closeSubpath()
                                        }
                                        let gradient = LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: color.opacity(0.3), location: 0),
                                                .init(color: color.opacity(0.1), location: 1)
                                            ]),
                                            startPoint: color == .blue ? .top : .bottom,
                                            endPoint: color == .blue ? .bottom : .top
                                        )
                                        areaPath
                                            .fill(gradient)
                                        
                                        let linePath = Path { p in
                                            p.move(to: startPoint)
                                            p.addLine(to: endPoint)
                                        }
                                        linePath
                                            .stroke(color, lineWidth: 2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 40)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine()
                    AxisTick()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.hour())
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }

            // Battery Percentage Chart
            Text("CHARGE LEVEL · %")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(.footnote)
            if (viewModel.data == nil), let errorMessage = viewModel.errorMessage {
                Text("Error: \(errorMessage)")
                    .opacity(0.6)
                    .fontWeight(.bold)
                    .font(.footnote)
            }
            Chart {
                ForEach(viewModel.batteryPercentageHistory, id: \.date) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Percentage (%)", point.value)
                    )
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Percentage (%)", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .green.opacity(0.3), location: 0.0),
                                .init(color: .green.opacity(0.1), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .frame(height: 200)
            .foregroundColor(.green)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100])
            }
        }
        .padding()
        .onAppear {
            if viewModel.loginMode == .fleetAPI {
                viewModel.fetchFleetAPIHistory()
            }
        }
    }
}

// Helper function to interpolate zero crossing
func interpolateZeroCrossing(start: HistoricalDataPoint, end: HistoricalDataPoint) -> HistoricalDataPoint {
    let startTime = start.date.timeIntervalSince1970
    let endTime = end.date.timeIntervalSince1970
    let startValue = start.value / 100 // Convert to kW
    let endValue = end.value / 100

    let ratio = startValue / (startValue - endValue)
    let crossingTime = startTime + ratio * (endTime - startTime)
    let crossingDate = Date(timeIntervalSince1970: crossingTime)

    return HistoricalDataPoint(date: crossingDate, value: 0, from: start.from)
}

// Sample data generation functions
func generateSampleData() -> [HistoricalDataPoint] {
    let now = Date()
    let calendar = Calendar.current
    var dataPoints: [HistoricalDataPoint] = []
    for i in 0..<48 {
        let date = calendar.date(byAdding: .hour, value: -i, to: now)!
        let value = Double.random(in: -1000...1000) // Random power in watts
        let from = ((i % 2) == 0) ? PowerFrom.solar : PowerFrom.grid
        dataPoints.append(HistoricalDataPoint(date: date, value: value, from: from))
    }
    return dataPoints
}

func generateSamplePercentageData() -> [HistoricalDataPoint] {
    let now = Date()
    let calendar = Calendar.current
    var dataPoints: [HistoricalDataPoint] = []
    for i in 0..<48 {
        let date = calendar.date(byAdding: .hour, value: -i, to: now)!
        let value = Double.random(in: 0...100) // Random percentage between 0% and 100%
        dataPoints.append(HistoricalDataPoint(date: date, value: value, from: nil))
    }
    return dataPoints
}

// Mock view model
class MockPowerwallViewModel: PowerwallViewModel {
    override init() {
        super.init()
        self.batteryPowerHistory = generateSampleData()
        self.batteryPercentageHistory = generateSamplePercentageData()
    }
}

// Preview provider
struct GraphView_Previews: PreviewProvider {
    static var previews: some View {
        GraphView(viewModel: MockPowerwallViewModel())
    }
}
