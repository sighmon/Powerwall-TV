import Foundation

// MARK: - Fleet `vehicle_data_cached`

/// `GET /api/1/vehicles/{vin}/vehicle_data_cached`. Tesla answers from the last data the car reported,
/// so the call never wakes the car and works while it sleeps. The body only ever has `charge_state`,
/// `climate_state`, `gui_settings` and `vehicle_state`: no `drive_state` or location.
struct VehicleInfoResponse: Decodable {
    let response: VehicleInfoPayload
}

struct VehicleInfoPayload: Decodable {
    struct Charge: Decodable {
        let batteryLevel: Double?
        let batteryRange: Double?
        let chargeLimitSoc: Double?
        let chargingState: String?
        let chargerPower: Double?
        let chargeRate: Double?
        let chargeEnergyAdded: Double?
        let minutesToFullCharge: Double?
        let timestamp: Double?

        enum CodingKeys: String, CodingKey {
            case batteryLevel = "battery_level"
            case batteryRange = "battery_range"
            case chargeLimitSoc = "charge_limit_soc"
            case chargingState = "charging_state"
            case chargerPower = "charger_power"
            case chargeRate = "charge_rate"
            case chargeEnergyAdded = "charge_energy_added"
            case minutesToFullCharge = "minutes_to_full_charge"
            case timestamp
        }
    }

    struct Climate: Decodable {
        let insideTemp: Double?
        let outsideTemp: Double?
        let isClimateOn: Bool?
        let timestamp: Double?

        enum CodingKeys: String, CodingKey {
            case insideTemp = "inside_temp"
            case outsideTemp = "outside_temp"
            case isClimateOn = "is_climate_on"
            case timestamp
        }
    }

    struct GUI: Decodable {
        let distanceUnits: String?
        let temperatureUnits: String?
        let tyrePressureUnits: String?

        enum CodingKeys: String, CodingKey {
            case distanceUnits = "gui_distance_units"
            case temperatureUnits = "gui_temperature_units"
            case tyrePressureUnits = "gui_tirepressure_units"
        }
    }

    struct State: Decodable {
        struct SoftwareUpdate: Decodable {
            let status: String?
        }

        let locked: Bool?
        let sentryMode: Bool?
        let odometer: Double?
        let carVersion: String?
        let softwareUpdate: SoftwareUpdate?
        let tpmsPressureFL: Double?
        let tpmsPressureFR: Double?
        let tpmsPressureRL: Double?
        let tpmsPressureRR: Double?
        let timestamp: Double?

        enum CodingKeys: String, CodingKey {
            case locked
            case sentryMode = "sentry_mode"
            case odometer
            case carVersion = "car_version"
            case softwareUpdate = "software_update"
            case tpmsPressureFL = "tpms_pressure_fl"
            case tpmsPressureFR = "tpms_pressure_fr"
            case tpmsPressureRL = "tpms_pressure_rl"
            case tpmsPressureRR = "tpms_pressure_rr"
            case timestamp
        }
    }

    let state: String?
    let chargeState: Charge?
    let climateState: Climate?
    let guiSettings: GUI?
    let vehicleState: State?

    enum CodingKeys: String, CodingKey {
        case state
        case chargeState = "charge_state"
        case climateState = "climate_state"
        case guiSettings = "gui_settings"
        case vehicleState = "vehicle_state"
    }
}

/// The showroom panel's copy of one car. Fleet units: miles, Celsius, bar. Every field is optional
/// so a missing block or key just hides its row.
struct VehicleInfo: Codable, Equatable {
    var batteryLevel: Double?
    var chargingState: String?
    var minutesToFullCharge: Double?
    var rangeMiles: Double?
    var chargeLimitPercent: Double?
    var chargerPowerKilowatts: Double?
    var chargeRateMilesPerHour: Double?
    var energyAddedKilowattHours: Double?
    var insideCelsius: Double?
    var outsideCelsius: Double?
    var climateOn: Bool?
    var locked: Bool?
    var sentryMode: Bool?
    var odometerMiles: Double?
    var softwareVersion: String?
    var softwareUpdateStatus: String?
    var tyrePressuresBar: [Double]?
    var usesMiles: Bool = false
    var usesFahrenheit: Bool = false
    var usesPSI: Bool = false
    /// Newest block `timestamp`: when the car last reported, not when we asked.
    var reportedAt: Date?

    var isCharging: Bool {
        chargingState?.caseInsensitiveCompare("Charging") == .orderedSame
    }

    init(
        batteryLevel: Double? = nil, chargingState: String? = nil, minutesToFullCharge: Double? = nil,
        rangeMiles: Double? = nil, chargeLimitPercent: Double? = nil, chargerPowerKilowatts: Double? = nil,
        chargeRateMilesPerHour: Double? = nil, energyAddedKilowattHours: Double? = nil,
        insideCelsius: Double? = nil, outsideCelsius: Double? = nil, climateOn: Bool? = nil,
        locked: Bool? = nil, sentryMode: Bool? = nil, odometerMiles: Double? = nil,
        softwareVersion: String? = nil, softwareUpdateStatus: String? = nil, tyrePressuresBar: [Double]? = nil,
        usesMiles: Bool = false, usesFahrenheit: Bool = false, usesPSI: Bool = false, reportedAt: Date? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.chargingState = chargingState
        self.minutesToFullCharge = minutesToFullCharge
        self.rangeMiles = rangeMiles
        self.chargeLimitPercent = chargeLimitPercent
        self.chargerPowerKilowatts = chargerPowerKilowatts
        self.chargeRateMilesPerHour = chargeRateMilesPerHour
        self.energyAddedKilowattHours = energyAddedKilowattHours
        self.insideCelsius = insideCelsius
        self.outsideCelsius = outsideCelsius
        self.climateOn = climateOn
        self.locked = locked
        self.sentryMode = sentryMode
        self.odometerMiles = odometerMiles
        self.softwareVersion = softwareVersion
        self.softwareUpdateStatus = softwareUpdateStatus
        self.tyrePressuresBar = tyrePressuresBar
        self.usesMiles = usesMiles
        self.usesFahrenheit = usesFahrenheit
        self.usesPSI = usesPSI
        self.reportedAt = reportedAt
    }

    init(payload: VehicleInfoPayload) {
        let charge = payload.chargeState
        let climate = payload.climateState
        let state = payload.vehicleState
        let gui = payload.guiSettings
        self.init(
            batteryLevel: charge?.batteryLevel,
            chargingState: charge?.chargingState,
            minutesToFullCharge: charge?.minutesToFullCharge,
            rangeMiles: charge?.batteryRange,
            chargeLimitPercent: charge?.chargeLimitSoc,
            chargerPowerKilowatts: charge?.chargerPower,
            chargeRateMilesPerHour: charge?.chargeRate,
            energyAddedKilowattHours: charge?.chargeEnergyAdded,
            insideCelsius: climate?.insideTemp,
            outsideCelsius: climate?.outsideTemp,
            climateOn: climate?.isClimateOn,
            locked: state?.locked,
            sentryMode: state?.sentryMode,
            odometerMiles: state?.odometer,
            softwareVersion: state?.carVersion,
            softwareUpdateStatus: state?.softwareUpdate?.status,
            tyrePressuresBar: Self.tyres(state),
            usesMiles: gui?.distanceUnits.map { $0.lowercased().hasPrefix("mi") } ?? false,
            usesFahrenheit: gui?.temperatureUnits.map { $0.uppercased() == "F" } ?? false,
            usesPSI: gui?.tyrePressureUnits.map { $0.lowercased() == "psi" } ?? false,
            reportedAt: [charge?.timestamp, climate?.timestamp, state?.timestamp]
                .compactMap { $0 }
                .max()
                .map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    static func parse(_ data: Data) throws -> VehicleInfo {
        VehicleInfo(payload: try JSONDecoder().decode(VehicleInfoResponse.self, from: data).response)
    }

    /// All four or none: a half set reads like a flat tyre.
    private static func tyres(_ state: VehicleInfoPayload.State?) -> [Double]? {
        guard let state,
              let fl = state.tpmsPressureFL, let fr = state.tpmsPressureFR,
              let rl = state.tpmsPressureRL, let rr = state.tpmsPressureRR else { return nil }
        let all = [fl, fr, rl, rr]
        return all.allSatisfy({ $0 > 0 }) ? all : nil
    }

    var chargeSnapshot: VehicleChargeSnapshot {
        VehicleChargeSnapshot(batteryLevel: batteryLevel, chargingState: chargingState, minutesToFullCharge: minutesToFullCharge)
    }
}

// MARK: - Panel rows

/// One line on the showroom's left column: an SF Symbol and its text.
struct VehicleInfoRow: Equatable, Identifiable {
    let id: String
    let symbol: String
    let text: String
}

extension VehicleInfo {
    static let kilometresPerMile = 1.609344
    static let psiPerBar = 14.5037738

    /// Rows in reading order. A field Fleet did not send has no row. Battery, charging state and
    /// minutes to full are already on the title lines, so they are not repeated here.
    func rows(now: Date = Date()) -> [VehicleInfoRow] {
        var rows: [VehicleInfoRow] = []
        func add(_ id: String, _ symbol: String, _ text: String) {
            rows.append(VehicleInfoRow(id: id, symbol: symbol, text: text))
        }

        if let rangeMiles, rangeMiles > 0 {
            add("range", "gauge.with.dots.needle.67percent", "\(distance(rangeMiles)) range")
        }
        if let chargeLimitPercent, chargeLimitPercent > 0 {
            add("limit", "flag.checkered", "Charge limit \(Int(chargeLimitPercent.rounded()))%")
        }
        if isCharging, let power = chargerPowerKilowatts, power > 0 {
            var text = "\(Self.number(power, decimals: power < 10 ? 1 : 0)) kW"
            if let rate = chargeRateMilesPerHour, rate > 0 {
                text += " · +\(distance(rate))/h"
            }
            add("rate", "ev.charger", text)
        }
        if let added = energyAddedKilowattHours, added > 0, isCharging || chargingState == "Complete" {
            add("added", "bolt.fill", "\(Self.number(added, decimals: 1)) kWh added")
        }
        var temperatures: [String] = []
        if let insideCelsius { temperatures.append("Inside \(temperature(insideCelsius))") }
        if let outsideCelsius { temperatures.append("Outside \(temperature(outsideCelsius))") }
        if !temperatures.isEmpty {
            add("temperature", "thermometer.medium", temperatures.joined(separator: " · "))
        }
        if climateOn == true {
            add("climate", "fan", "Climate on")
        }
        if let locked {
            add("lock", locked ? "lock.fill" : "lock.open.fill", locked ? "Locked" : "Unlocked")
        }
        if sentryMode == true {
            add("sentry", "record.circle", "Sentry Mode on")
        }
        if let tyrePressuresBar, tyrePressuresBar.count == 4 {
            let values = tyrePressuresBar.map { usesPSI ? Self.number($0 * Self.psiPerBar, decimals: 0) : Self.number($0, decimals: 1) }
            add("tyres", "tirepressure", "Tyres \(values.joined(separator: " · ")) \(usesPSI ? "psi" : "bar")")
        }
        if let odometerMiles, odometerMiles > 0 {
            add("odometer", "road.lanes", distance(odometerMiles))
        }
        if let version = softwareVersion?.split(separator: " ").first.map(String.init), !version.isEmpty {
            add("software", "gearshape", "Software \(version)")
        }
        if let status = softwareUpdateStatus?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty {
            add("update", "arrow.down.circle", "Update \(status.lowercased())")
        }
        if let reportedAt {
            add("updated", "clock", Self.updatedText(reportedAt, now: now))
        }
        return rows
    }

    private func distance(_ miles: Double) -> String {
        let value = usesMiles ? miles : miles * Self.kilometresPerMile
        return "\(Self.number(value, decimals: 0)) \(usesMiles ? "mi" : "km")"
    }

    private func temperature(_ celsius: Double) -> String {
        let value = usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Self.number(value, decimals: 0))°"
    }

    /// Cached data can be hours old, so the panel says how old.
    static func updatedText(_ reportedAt: Date, now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(reportedAt)) / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "Updated \(hours) h ago" }
        return "Updated \(hours / 24) days ago"
    }

    static func number(_ value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_AU")
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - Refresh policy

/// What one `vehicle_data_cached` call came back with.
enum VehicleInfoFetchOutcome: Equatable {
    case fresh(VehicleInfo)
    /// 408: the car is asleep or offline. Cached data should not do this, but back off if it does.
    case asleep
    /// 429. `retryAfter` is the header in seconds when Tesla sends one.
    case rateLimited(retryAfter: TimeInterval?)
    /// 404 no cached data yet, 412 car does not support cached data.
    case unavailable
    /// 401: the shared token refresh runs, then the normal failure backoff.
    case unauthorized
    /// 403: missing vehicle scope. Stop until the next launch or login.
    case forbidden
    /// Network error, 5xx (not billed), or a body that did not decode.
    case failed

    static func classify(statusCode: Int, data: Data, retryAfterHeader: String? = nil) -> VehicleInfoFetchOutcome {
        switch statusCode {
        case 200:
            guard let info = try? VehicleInfo.parse(data) else { return .failed }
            return .fresh(info)
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404, 412: return .unavailable
        case 408: return .asleep
        case 429: return .rateLimited(retryAfter: retryAfterHeader.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) })
        default: return .failed
        }
    }
}

/// Per-car throttle state. Saved with the cached info so a relaunch does not reset the budget.
struct VehicleInfoRefreshState: Codable, Equatable {
    var lastAttemptAt: Date?
    var lastReportedAt: Date?
    /// Calls in a row where the car had not reported anything new. Each one doubles the wait.
    var unchangedStreak = 0
    var failureStreak = 0
    var blockedUntil: Date?
    var wasCharging = false
    var dayStart: Date?
    var callsToday = 0
}

/// Pure timing rules for `vehicle_data_cached`, so the call budget is testable.
/// The caller only asks while the showroom is on screen; nothing polls in the background.
struct VehicleInfoRefreshPolicy {
    /// Showroom open, car parked.
    var idleInterval: TimeInterval = 10 * 60
    /// Showroom open and charging: range and kWh added move, so a quicker look is worth it.
    var chargingInterval: TimeInterval = 5 * 60
    /// Upper bound for the unchanged and failure backoffs.
    var maximumInterval: TimeInterval = 60 * 60
    var asleepInterval: TimeInterval = 30 * 60
    var rateLimitedInterval: TimeInterval = 15 * 60
    var unavailableInterval: TimeInterval = 6 * 60 * 60
    var failureInterval: TimeInterval = 5 * 60
    var forbiddenInterval: TimeInterval = 24 * 60 * 60
    /// Hard ceiling per car per rolling day: 100 Data calls is $0.20 at Tesla's 500 per $1.
    var dailyCallLimit = 100
    /// Older cached info is not shown at all.
    var displayLifetime: TimeInterval = 24 * 60 * 60

    func nextAllowedAt(_ state: VehicleInfoRefreshState) -> Date? {
        guard let last = state.lastAttemptAt else { return state.blockedUntil }
        let base = state.wasCharging ? chargingInterval : idleInterval
        let backoff = min(maximumInterval, base * pow(2, Double(min(state.unchangedStreak, 8))))
        var next = last.addingTimeInterval(backoff)
        if let blockedUntil = state.blockedUntil, blockedUntil > next { next = blockedUntil }
        return next
    }

    func shouldFetch(_ state: VehicleInfoRefreshState, now: Date) -> Bool {
        if let dayStart = state.dayStart, now.timeIntervalSince(dayStart) < 24 * 60 * 60, state.callsToday >= dailyCallLimit {
            return false
        }
        guard let next = nextAllowedAt(state) else { return true }
        return now >= next
    }

    /// Counts the call and sets the next wait for this outcome.
    func record(_ outcome: VehicleInfoFetchOutcome, into state: VehicleInfoRefreshState, at now: Date) -> VehicleInfoRefreshState {
        var state = state
        state.lastAttemptAt = now
        state.blockedUntil = nil
        if let dayStart = state.dayStart, now.timeIntervalSince(dayStart) < 24 * 60 * 60 {
            state.callsToday += 1
        } else {
            state.dayStart = now
            state.callsToday = 1
        }
        switch outcome {
        case .fresh(let info):
            state.failureStreak = 0
            state.wasCharging = info.isCharging
            if let reported = info.reportedAt, let previous = state.lastReportedAt, reported <= previous {
                state.unchangedStreak += 1
            } else {
                state.unchangedStreak = 0
            }
            state.lastReportedAt = info.reportedAt ?? state.lastReportedAt
        case .asleep:
            state.wasCharging = false
            state.blockedUntil = now.addingTimeInterval(asleepInterval)
        case .rateLimited(let retryAfter):
            state.blockedUntil = now.addingTimeInterval(max(retryAfter ?? 0, rateLimitedInterval))
        case .unavailable:
            state.blockedUntil = now.addingTimeInterval(unavailableInterval)
        case .forbidden:
            state.blockedUntil = now.addingTimeInterval(forbiddenInterval)
        case .unauthorized, .failed:
            state.failureStreak += 1
            let wait = min(maximumInterval, failureInterval * pow(2, Double(min(state.failureStreak - 1, 8))))
            state.blockedUntil = now.addingTimeInterval(wait)
        }
        return state
    }
}

/// What `UserDefaults` keeps per VIN between launches.
struct CachedVehicleInfo: Codable, Equatable {
    var info: VehicleInfo?
    var fetchedAt: Date?
    var refresh: VehicleInfoRefreshState
}

extension VehicleInfoFetchOutcome {
    /// Log text without the payload.
    var debugName: String {
        switch self {
        case .fresh: return "fresh"
        case .asleep: return "asleep"
        case .rateLimited: return "rateLimited"
        case .unavailable: return "unavailable"
        case .unauthorized: return "unauthorized"
        case .forbidden: return "forbidden"
        case .failed: return "failed"
        }
    }
}
