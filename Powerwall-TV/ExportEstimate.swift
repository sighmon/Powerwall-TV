import Foundation

/// Energy buckets from Fleet calendar_history are Wh, not instantaneous watts.
struct ExportEnergyBucket: Decodable {
    let timestamp: Date
    let consumerEnergy: Double?
    let grid: Double?
    let solar: Double?
    let battery: Double?
    var generator: Double? = nil

    enum CodingKeys: String, CodingKey {
        case timestamp
        case consumerEnergy = "consumer_energy_imported"
        case grid = "consumer_energy_imported_from_grid"
        case solar = "consumer_energy_imported_from_solar"
        case battery = "consumer_energy_imported_from_battery"
        case generator = "consumer_energy_imported_from_generator"
    }

    var homeWh: Double? {
        let value: Double
        if let consumerEnergy { value = consumerEnergy }
        else if let grid, let solar, let battery { value = grid + solar + battery + (generator ?? 0) }
        else { return nil }
        return value.isFinite && value >= 0 ? value : nil
    }
}

enum ExportEstimateError: LocalizedError {
    case incompleteForecast(String)
    case invalidConfiguration, weatherAuthorization, missingWeatherLocation, missingSiteMetadata, incompleteHistory, invalidBattery, service(String, Int)
    var errorDescription: String? {
        switch self {
        case let .incompleteForecast(details):
#if DEBUG
            return "Apple Weather returned an incomplete forecast: " + details
#else
            return "Apple Weather returned an incomplete overnight or tomorrow forecast. Please try again later."
#endif
        case .invalidConfiguration: return "Check the Fleet region and morning peak end hour in Settings."
        case .weatherAuthorization: return "Apple Weather could not authorize this app. Please try again later or contact the app developer to check WeatherKit service activation."
        case .missingWeatherLocation: return "Set the Powerwall site’s suburb and country in Settings → Home Energy Advisor → Weather location. Choose a location in the site’s time zone."
        case .missingSiteMetadata: return "Tesla did not return the site location, time zone, battery count or backup reserve required for this estimate."
        case .incompleteHistory: return "Fleet history does not contain three complete recent usage windows. Try again when more data is available."
        case .invalidBattery: return "Fresh battery capacity, charge and backup reserve are required."
        case let .service(name, code): return "\(name) request failed (HTTP \(code)). Check your credentials and service access."
        }
    }
}

struct ExportUsageWindow {
    let interval: DateInterval
    let historical: [DateInterval]

    init(now: Date, timeZone: TimeZone, morningEndHour: Int, days: Int = 5) throws {
        guard (0...12).contains(morningEndHour), (3...7).contains(days) else {
            throw ExportEstimateError.invalidConfiguration
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Always include tonight and tomorrow's morning peak, even before today's peak ends.
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let end = calendar.date(bySettingHour: morningEndHour, minute: 0, second: 0, of: tomorrow)!
        interval = DateInterval(start: now, end: end)
        // Skip any comparison window that has not finished yet.
        historical = (1...8).compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: now),
                  let pastEnd = calendar.date(byAdding: .day, value: -offset, to: end), pastEnd <= now else { return nil }
            return DateInterval(start: start, end: pastEnd)
        }.prefix(days).map { $0 }
    }

    /// Prorate boundary buckets; reject missing buckets rather than treating gaps as zero use.
    static func consumption(in interval: DateInterval, buckets: [ExportEnergyBucket], cadence: TimeInterval = 300) -> Double? {
        let sorted = buckets.sorted { $0.timestamp < $1.timestamp }
        var cursor = interval.start
        var wh = 0.0
        for bucket in sorted {
            let end = bucket.timestamp.addingTimeInterval(cadence)
            guard end > interval.start, bucket.timestamp < interval.end else { continue }
            guard bucket.timestamp <= cursor, end > cursor, let energy = bucket.homeWh else { return nil }
            let clippedEnd = min(end, interval.end)
            wh += energy * clippedEnd.timeIntervalSince(cursor) / cadence
            cursor = clippedEnd
        }
        guard cursor >= interval.end else { return nil }
        return wh / 1000
    }
}

struct ExportBatteryBudget {
    let capacityKWh: Double
    let availableKWh: Double
    let exportKWh: Double
    var exportPercent: Double { exportKWh / capacityKWh * 100 }

    init(capacityKWh: Double, chargePercent: Double, reservePercent: Double, demandKWh: Double) throws {
        guard [capacityKWh, chargePercent, reservePercent, demandKWh].allSatisfy(\.isFinite),
              capacityKWh > 0, (0...100).contains(chargePercent), (0...100).contains(reservePercent), demandKWh >= 0 else {
            throw ExportEstimateError.invalidBattery
        }
        self.capacityKWh = capacityKWh
        availableKWh = capacityKWh * max(0, chargePercent - reservePercent) / 100
        exportKWh = max(0, availableKWh - demandKWh)
    }
}

/// WeatherKit hourly dates mark interval starts. Require all of tonight and tomorrow,
/// including the current partial hour, before presenting a weather-informed estimate.
enum ExportForecastCoverage {
    static func isComplete(dates: [Date], from start: Date, through end: Date) -> Bool {
        guard end > start else { return false }
        var cursor = start
        for date in dates.sorted() {
            let hourEnd = date.addingTimeInterval(3600)
            guard hourEnd > cursor else { continue }
            guard date <= cursor else { return false }
            cursor = hourEnd
            if cursor >= end { return true }
        }
        return false
    }
}

/// An estimate is reusable only within its original site-local day and usage window.
enum AdvisorEstimateFreshness {
    static func isFresh(generatedAt: Date, end: Date, timeZone: TimeZone, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(generatedAt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return age >= 0 && age < 900 && now < end && calendar.isDate(generatedAt, inSameDayAs: now)
    }
}
