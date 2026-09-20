import Foundation

/// Offline fixtures shared by every platform. Power samples use the same five-minute Wh
/// buckets as Fleet history; the advisor is explicitly illustrative, never live advice.
enum DemoEnergyData {
    struct History {
        var battery: [HistoricalDataPoint] = []
        var charge: [HistoricalDataPoint] = []
        var solar: [HistoricalDataPoint] = []
        var home: [HistoricalDataPoint] = []
        var grid: [HistoricalDataPoint] = []
    }

    static func history(endingAt end: Date, calendar: Calendar = .current) -> History {
        var result = History()
        var storedWh = 18_000.0
        let capacityWh = 27_000.0
        let start = end.addingTimeInterval(-24 * 3600)
        for index in 0..<288 {
            let date = start.addingTimeInterval(Double(index) * 300)
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let hour = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            let solarW = max(0, sin((hour - 6) / 12 * .pi)) * 6200
            let breakfast = 1800 * exp(-pow((hour - 7.5) / 1.2, 2))
            let dinner = 2600 * exp(-pow((hour - 19) / 1.8, 2))
            let homeW = 550 + breakfast + dinner + 120 * (1 + sin(hour * 2))
            let solarWh = solarW / 12
            let homeWh = homeW / 12
            let surplus = solarWh - homeWh
            let batteryWh: Double
            if surplus > 0 {
                batteryWh = -min(surplus, 5000 / 12, capacityWh - storedWh)
            } else {
                batteryWh = min(-surplus, 5000 / 12, max(0, storedWh - capacityWh * 0.2))
            }
            storedWh -= batteryWh
            let gridWh = homeWh - solarWh - batteryWh
            result.battery.append(.init(date: date, value: batteryWh, from: .solar, to: .home, source: .battery))
            result.charge.append(.init(date: date, value: storedWh / capacityWh * 100, from: nil, to: nil, source: nil))
            result.solar.append(.init(date: date, value: solarWh, from: .solar, to: .home, source: .solar))
            result.home.append(.init(date: date, value: homeWh, from: nil, to: .home, source: solarWh >= homeWh ? .solar : (batteryWh > 0 ? .battery : .grid)))
            result.grid.append(.init(date: date, value: gridWh, from: .grid, to: .home, source: gridWh < 0 ? .solar : .grid))
        }
        return result
    }

    static func advisorContext(morningEndHour: Int, now: Date = Date()) throws -> ExportAdvisorContext {
        let zone = TimeZone.current
        let window = try ExportUsageWindow(now: now, timeZone: zone, morningEndHour: morningEndHour)
        return ExportAdvisorContext(
            generatedAt: now, siteID: "demo", settings: .init(morningEndHour: morningEndHour, weatherLocation: ""),
            prompt: "Demo sample", budget: try ExportBatteryBudget(capacityKWh: 27, chargePercent: 80, reservePercent: 20, demandKWh: 6.48),
            averageUsageKWh: 5.4, sampleCount: 5, end: window.interval.end, timeZone: zone,
            weatherLocationName: "Demo home · Sample forecast", weatherMood: .clear, weatherSymbol: "cloud.sun.fill",
            weatherSummary: "Mostly sunny tomorrow · 18–26°C · 10% chance of rain",
            attribution: nil, isDemo: true)
    }

    static let advice = "In this sample, your battery is at 80%, with 60% above a 20% backup reserve; expected household use is 20%, or 24% with a safety margin, leaving 36% as potential export. Tomorrow’s sample forecast is mostly sunny, so solar could replenish the battery — these are demonstration figures, not a live recommendation."

    static func followUp(_ question: String) -> String {
        let question = question.lowercased()
        if question.contains("weather") || question.contains("solar") || question.contains("rain") {
            return "The sample forecast shows mostly sunny skies and a 10% chance of rain tomorrow. In a live estimate, a cloudier outlook could be a reason to retain more charge; this demo uses fixed sample weather."
        }
        if question.contains("reserve") || question.contains("backup") {
            return "This example keeps a 20% backup reserve and allows another 24% for household use including a safety margin. From an 80% charge, that leaves 36% as sample export potential."
        }
        return "Demo replies use a fixed example rather than a live AI service: 80% charge minus 20% reserve and 24% budgeted use leaves 36% potential export (9.7 kWh of a 27 kWh battery). Ask about the sample weather or backup reserve to explore the example."
    }
}
