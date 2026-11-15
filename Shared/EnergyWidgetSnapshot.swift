import Foundation

/// Same kW figure the home screen and menu bar draw. One decimal place drops the sign.
func formatPowerValue(_ value: Double, precision: String, showLessPrecision: Bool) -> String {
    let displayedValue = showLessPrecision ? abs(value) : value
    return String(format: precision, displayedValue)
}

/// Latest site figures. The app writes this; the widget reads it. No scene and no SceneKit.
struct EnergyWidgetReading: Codable, Equatable {
    var solarWatts: Double?
    var homeWatts: Double?
    var batteryWatts: Double?
    var gridWatts: Double?
    var siteName: String?
    var updatedAt: Date
    /// Matches the Display setting "Limit data to one decimal place".
    var showLessPrecision: Bool
    var batteryPercent: Double?

    static let empty = EnergyWidgetReading(
        solarWatts: nil,
        homeWatts: nil,
        batteryWatts: nil,
        gridWatts: nil,
        siteName: nil,
        updatedAt: .distantPast,
        showLessPrecision: false,
        batteryPercent: nil
    )

    init(
        solarWatts: Double?,
        homeWatts: Double?,
        batteryWatts: Double?,
        gridWatts: Double?,
        siteName: String?,
        updatedAt: Date,
        showLessPrecision: Bool = false,
        batteryPercent: Double? = nil
    ) {
        self.solarWatts = solarWatts
        self.homeWatts = homeWatts
        self.batteryWatts = batteryWatts
        self.gridWatts = gridWatts
        self.siteName = siteName
        self.updatedAt = updatedAt
        self.showLessPrecision = showLessPrecision
        self.batteryPercent = batteryPercent
    }

    private enum CodingKeys: String, CodingKey {
        case solarWatts, homeWatts, batteryWatts, gridWatts, siteName, updatedAt, showLessPrecision, batteryPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        solarWatts = try container.decodeIfPresent(Double.self, forKey: .solarWatts)
        homeWatts = try container.decodeIfPresent(Double.self, forKey: .homeWatts)
        batteryWatts = try container.decodeIfPresent(Double.self, forKey: .batteryWatts)
        gridWatts = try container.decodeIfPresent(Double.self, forKey: .gridWatts)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        showLessPrecision = try container.decodeIfPresent(Bool.self, forKey: .showLessPrecision) ?? false
        batteryPercent = try container.decodeIfPresent(Double.self, forKey: .batteryPercent)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(solarWatts, forKey: .solarWatts)
        try container.encodeIfPresent(homeWatts, forKey: .homeWatts)
        try container.encodeIfPresent(batteryWatts, forKey: .batteryWatts)
        try container.encodeIfPresent(gridWatts, forKey: .gridWatts)
        try container.encodeIfPresent(siteName, forKey: .siteName)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(showLessPrecision, forKey: .showLessPrecision)
        try container.encodeIfPresent(batteryPercent, forKey: .batteryPercent)
    }
}

/// ▲ charging, ▼ discharging, · idle. Same 40 W band as the home screen and menu bar.
enum BatteryTrend {
    static let wiggleWatts = 40.0

    static func mark(watts: Double?) -> String {
        guard let watts else { return "·" }
        if watts > wiggleWatts { return "▼" }
        if watts < -wiggleWatts { return "▲" }
        return "·"
    }
}

/// Text the widget draws. Built by the timeline entry point, not by the view.
struct EnergyWidgetSnapshot: Equatable {
    var date: Date
    var siteName: String
    var solar: String
    var home: String
    var battery: String
    /// ▲, ▼, or · between the kilowatts and the percentage. Empty when there is no percentage.
    var batteryMark: String
    var batteryPercent: String?
    var grid: String
    var solarWatts: Double?
    var homeWatts: Double?
    var batteryWatts: Double?
    var gridWatts: Double?

    var batteryLine: String {
        guard let batteryPercent, !batteryMark.isEmpty else { return battery }
        return "\(battery) \(batteryMark) \(batteryPercent)"
    }

    var summary: String {
        "\(siteName) Solar \(solar) Home \(home) Battery \(batteryLine) Grid \(grid)"
    }

    /// Kilowatts, using the same precision string as the home screen.
    static func powerText(_ watts: Double?, showLessPrecision: Bool) -> String {
        guard let watts else { return "—" }
        let precision = showLessPrecision ? "%.1f" : "%.3f"
        let figure = formatPowerValue(watts / 1000, precision: precision, showLessPrecision: showLessPrecision)
        return "\(figure) kW"
    }

    /// Small widget always shows one decimal place and drops the sign, whatever the Display setting is.
    static func oneDecimalPowerText(_ watts: Double?) -> String {
        guard let watts else { return "—" }
        return "\(String(format: "%.1f", abs(watts) / 1000)) kW"
    }
}

enum EnergyWidgetTimeline {
    /// Snapshot entry the widget timeline and tests both call.
    static func entry(
        solarWatts: Double?,
        homeWatts: Double?,
        batteryWatts: Double?,
        gridWatts: Double?,
        siteName: String?,
        showLessPrecision: Bool = false,
        batteryPercent: Double? = nil,
        at date: Date = Date()
    ) -> EnergyWidgetSnapshot {
        let name = siteName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let percentText = batteryPercent.map { String(format: "%.0f%%", $0) }
        return EnergyWidgetSnapshot(
            date: date,
            siteName: name.isEmpty ? "Powerwall" : name,
            solar: EnergyWidgetSnapshot.powerText(solarWatts, showLessPrecision: showLessPrecision),
            home: EnergyWidgetSnapshot.powerText(homeWatts, showLessPrecision: showLessPrecision),
            battery: EnergyWidgetSnapshot.powerText(batteryWatts, showLessPrecision: showLessPrecision),
            batteryMark: percentText == nil ? "" : BatteryTrend.mark(watts: batteryWatts),
            batteryPercent: percentText,
            grid: EnergyWidgetSnapshot.powerText(gridWatts, showLessPrecision: showLessPrecision),
            solarWatts: solarWatts,
            homeWatts: homeWatts,
            batteryWatts: batteryWatts,
            gridWatts: gridWatts
        )
    }

    static func entry(for reading: EnergyWidgetReading, at date: Date = Date()) -> EnergyWidgetSnapshot {
        entry(
            solarWatts: reading.solarWatts,
            homeWatts: reading.homeWatts,
            batteryWatts: reading.batteryWatts,
            gridWatts: reading.gridWatts,
            siteName: reading.siteName,
            showLessPrecision: reading.showLessPrecision,
            batteryPercent: reading.batteryPercent,
            at: date
        )
    }
}

enum EnergyWidgetStore {
    static let suiteName = "group.com.sighmon.Powerwall-TV"
    static let key = "energyWidgetSnapshot"

    static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    static func save(_ reading: EnergyWidgetReading, defaults: UserDefaults = EnergyWidgetStore.sharedDefaults()) {
        guard let data = try? JSONEncoder().encode(reading) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(defaults: UserDefaults = EnergyWidgetStore.sharedDefaults()) -> EnergyWidgetReading? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EnergyWidgetReading.self, from: data)
    }
}
