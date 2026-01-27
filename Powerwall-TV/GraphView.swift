//
//  GraphView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 26/3/2025.
//


import SwiftUI
import Charts

var valuetoKw: Double = 84

struct GraphView: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @FocusState private var isGraphFocused: Bool
    @State private var selectedGraph: GraphType = .battery

#if os(macOS)
    private let maxChartHeight = (NSScreen.main?.visibleFrame.height ?? 600) / 2
#else
    private let maxChartHeight: CGFloat = 600
#endif

    private enum GraphType: Int, CaseIterable {
        case battery
        case solar
        case home
        case grid

        var title: String {
            switch self {
            case .battery:
                return "Powerwall"
            case .solar:
                return "Solar"
            case .home:
                return "Home"
            case .grid:
                return "Grid"
            }
        }

        var subtitle: String {
            switch self {
            case .battery:
                return "ENERGY FLOW"
            case .solar:
                return "SOLAR POWER"
            case .home:
                return "HOME POWER"
            case .grid:
                return "GRID POWER"
            }
        }

        var color: Color {
            switch self {
            case .battery:
                return .blue
            case .solar:
                return .yellow
            case .home:
                return .orange
            case .grid:
                return .gray
            }
        }
    }

    private var powerHistory: [HistoricalDataPoint] {
        switch selectedGraph {
        case .battery:
            return viewModel.batteryPowerHistory
        case .solar:
            return viewModel.solarPowerHistory
        case .home:
            return viewModel.homePowerHistory
        case .grid:
            return viewModel.gridPowerHistory
        }
    }

    private func colorForPoint(_ point: HistoricalDataPoint, graph: GraphType) -> Color {
        switch graph {
        case .battery:
            if point.value >= 0 {
                if point.to == PowerTo.grid {
                    return .gray
                }
                return .blue
            } else if point.from == PowerFrom.solar {
                return .yellow
            } else {
                return .gray
            }
        case .solar:
            return graph.color
        case .home:
            switch point.source {
            case .battery:
                return .green
            case .solar:
                return .yellow
            case .grid:
                return .gray
            case .none:
                return .gray
            }
        case .grid:
            if point.value >= 0 {
                return .gray
            }
            switch point.source {
            case .solar:
                return .yellow
            case .battery:
                return .green
            case .grid, .none:
                return .gray
            }
        }
    }

    private func cycleGraph(_ delta: Int) {
        let graphs = GraphType.allCases
        guard let index = graphs.firstIndex(of: selectedGraph) else { return }
        let next = (index + delta + graphs.count) % graphs.count
        selectedGraph = graphs[next]
    }

    var body: some View {
        VStack(spacing: 20) {
            // Battery Power Flow Chart
            Text(selectedGraph.title)
                .font(.title)
            Text("\(viewModel.currentDateLabel) · \(selectedGraph.subtitle) · kWh")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(.footnote)
            Chart {
                // Define data points with invisible PointMarks to set the chart's scale
                ForEach(powerHistory, id: \.date) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Power (kW)", point.value / valuetoKw)
                    )
                    .opacity(0) // Hide the points
                }
            }
            .frame(height: maxChartHeight)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack {
                        if powerHistory.count >= 2,
                           let firstDate = powerHistory.first?.date,
                           let baselineY = proxy.position(for: (x: firstDate, y: 0))?.y {

                            ForEach(0..<powerHistory.count - 1, id: \.self) { index in
                                let start = powerHistory[index]
                                let end = powerHistory[index + 1]

                                if (start.value >= 0 && end.value < 0) || (start.value < 0 && end.value >= 0) {
                                    let zeroCrossing = interpolateZeroCrossing(start: start, end: end)

                                    // First segment: start to zeroCrossing
                                    if let startPoint = proxy.position(for: (x: start.date, y: start.value / valuetoKw)),
                                       let zeroPoint = proxy.position(for: (x: zeroCrossing.date, y: zeroCrossing.value / 100)) {
                                        let color = colorForPoint(start, graph: selectedGraph)
                                        let isPositive = start.value >= 0
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
                                            startPoint: isPositive ? .top : .bottom,
                                            endPoint: isPositive ? .bottom : .top
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
                                       let endPoint = proxy.position(for: (x: end.date, y: end.value / valuetoKw)) {
                                        let color = colorForPoint(end, graph: selectedGraph)
                                        let isPositive = end.value >= 0
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
                                            startPoint: isPositive ? .top : .bottom,
                                            endPoint: isPositive ? .bottom : .top
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
                                    if let startPoint = proxy.position(for: (x: start.date, y: start.value / valuetoKw)),
                                       let endPoint = proxy.position(for: (x: end.date, y: end.value / valuetoKw)) {
                                        let color = colorForPoint(start, graph: selectedGraph)
                                        let isPositive = start.value >= 0
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
                                            startPoint: isPositive ? .top : .bottom,
                                            endPoint: isPositive ? .bottom : .top
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
#if os(macOS)
                    .padding(.leading, 22)
#else
                    .padding(.leading, 40)
#endif
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
            .frame(height: maxChartHeight / 3)
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
            isGraphFocused = true
        }
        .focusable() // Still needed to make it focusable
        .focused($isGraphFocused) // Bind focus state
        .onMoveCommand { direction in
            if direction == .left {
                viewModel.goToPreviousDay()
            }
            if direction == .right {
                viewModel.goToNextDay()
            }
            if direction == .up {
                cycleGraph(-1)
            }
            if direction == .down {
                cycleGraph(1)
            }
        }
#if os(macOS)
        .frame(minWidth: 1000)
        .onKeyPress(.upArrow, phases: .down) { _ in
            cycleGraph(-1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            cycleGraph(1)
            return .handled
        }
#endif
    }
}

// Helper function to interpolate zero crossing
func interpolateZeroCrossing(start: HistoricalDataPoint, end: HistoricalDataPoint) -> HistoricalDataPoint {
    let startTime = start.date.timeIntervalSince1970
    let endTime = end.date.timeIntervalSince1970
    let startValue = start.value / valuetoKw // Convert to kW
    let endValue = end.value / valuetoKw

    let ratio = startValue / (startValue - endValue)
    let crossingTime = startTime + ratio * (endTime - startTime)
    let crossingDate = Date(timeIntervalSince1970: crossingTime)

    return HistoricalDataPoint(date: crossingDate, value: 0, from: start.from, to: start.to, source: start.source)
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
        let to = ((i % 2) == 0) ? PowerTo.grid : PowerTo.home
        dataPoints.append(HistoricalDataPoint(date: date, value: value, from: from, to: to, source: nil))
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
        dataPoints.append(HistoricalDataPoint(date: date, value: value, from: nil, to: nil, source: nil))
    }
    return dataPoints
}

// Mock view model
class MockPowerwallViewModel: PowerwallViewModel {
    override init() {
        super.init()
        self.batteryPowerHistory = generateSampleData()
        self.batteryPercentageHistory = generateSamplePercentageData()
        self.solarPowerHistory = generateSampleData()
        self.homePowerHistory = generateSampleData()
        self.gridPowerHistory = generateSampleData()
    }
}

// Preview provider
struct GraphView_Previews: PreviewProvider {
    static var previews: some View {
        GraphView(viewModel: MockPowerwallViewModel())
    }
}
