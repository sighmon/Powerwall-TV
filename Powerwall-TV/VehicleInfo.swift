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
    /// The car's own `gui_settings` strings ("km/hr", "C", "Bar"...). Nil when the car did not send them;
    /// `VehicleDisplayUnits` then falls back to the device region.
    var guiDistanceUnits: String?
    var guiTemperatureUnits: String?
    var guiTyrePressureUnits: String?
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
        guiDistanceUnits: String? = nil, guiTemperatureUnits: String? = nil, guiTyrePressureUnits: String? = nil,
        reportedAt: Date? = nil
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
        self.guiDistanceUnits = guiDistanceUnits
        self.guiTemperatureUnits = guiTemperatureUnits
        self.guiTyrePressureUnits = guiTyrePressureUnits
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
            guiDistanceUnits: gui?.distanceUnits,
            guiTemperatureUnits: gui?.temperatureUnits,
            guiTyrePressureUnits: gui?.tyrePressureUnits,
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

/// Distance, temperature and tyre pressure units for the panel. The car's `gui_settings` win, so the
/// panel matches the car's screen. A unit the car did not send comes from the device region.
struct VehicleDisplayUnits: Equatable {
    var distance: UnitLength
    var temperature: UnitTemperature
    var pressure: UnitPressure

    /// Regions where tyres are usually read in psi, and in kPa. Everywhere else uses bar, as most of Europe does.
    static let psiRegions: Set<String> = ["US", "GB", "AU", "NZ", "PR", "LR", "MM"]
    static let kilopascalRegions: Set<String> = ["CA", "JP"]

    /// `temperaturePreference` is the system's own `AppleTemperatureUnit` ("Celsius" or "Fahrenheit")
    /// when the person has set one in Settings. `pressureSetting` is the app's own tyre unit setting,
    /// which beats the car and the region unless it is Automatic.
    static func resolve(
        guiDistance: String?,
        guiTemperature: String?,
        guiPressure: String?,
        locale: Locale,
        temperaturePreference: String? = UserDefaults.standard.string(forKey: "AppleTemperatureUnit"),
        pressureSetting: TyrePressureSetting = .automatic
    ) -> VehicleDisplayUnits {
        VehicleDisplayUnits(
            distance: distanceUnit(gui: guiDistance) ?? localeDistance(locale),
            temperature: temperatureUnit(gui: guiTemperature)
                ?? temperatureUnit(gui: temperaturePreference)
                ?? localeTemperature(locale),
            pressure: pressureSetting.unit ?? pressureUnit(gui: guiPressure) ?? localePressure(locale)
        )
    }

    /// "km/hr" or "mi/hr".
    static func distanceUnit(gui: String?) -> UnitLength? {
        guard let value = gui?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return nil }
        if value.hasPrefix("mi") { return .miles }
        if value.hasPrefix("km") { return .kilometers }
        return nil
    }

    /// "C" or "F", or the system's "Celsius" or "Fahrenheit".
    static func temperatureUnit(gui: String?) -> UnitTemperature? {
        guard let value = gui?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return nil }
        if value.hasPrefix("f") { return .fahrenheit }
        if value.hasPrefix("c") { return .celsius }
        return nil
    }

    /// "Psi", "Bar" or "kPa".
    static func pressureUnit(gui: String?) -> UnitPressure? {
        switch gui?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "psi": return .poundsForcePerSquareInch
        case "bar": return .bars
        case "kpa": return .kilopascals
        default: return nil
        }
    }

    static func localeDistance(_ locale: Locale) -> UnitLength {
        switch locale.measurementSystem {
        case .us, .uk: return .miles
        default: return .kilometers
        }
    }

    static func localeTemperature(_ locale: Locale) -> UnitTemperature {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }

    static func localePressure(_ locale: Locale) -> UnitPressure {
        let region = locale.region?.identifier ?? ""
        if psiRegions.contains(region) || locale.measurementSystem == .us { return .poundsForcePerSquareInch }
        if kilopascalRegions.contains(region) { return .kilopascals }
        return .bars
    }

    /// Tesla-style symbols. `MeasurementFormatter` would pick its own spacing per locale ("22 °C"),
    /// and the tyre row shows one unit after four numbers, so the symbol is written here.
    var distanceSymbol: String { distance == .miles ? "mi" : "km" }
    var temperatureSymbol: String { temperature == .fahrenheit ? "°F" : "°C" }
    var pressureSymbol: String {
        switch pressure {
        case .poundsForcePerSquareInch: return "psi"
        case .kilopascals: return "kPa"
        default: return "bar"
        }
    }
    var pressureDecimals: Int { pressure == .bars ? 1 : 0 }
}

/// Settings → Display → Tyre pressure, and the showroom details tap. Stored in `UserDefaults` under `storageKey`.
enum TyrePressureSetting: String, CaseIterable, Identifiable {
    case automatic
    case psi
    case bar
    case kilopascals = "kPa"

    static let storageKey = "showroom_tyrePressureUnit"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .psi: return "psi"
        case .bar: return "bar"
        case .kilopascals: return "kPa"
        }
    }

    /// Nil for Automatic: the car's unit, then the region's.
    var unit: UnitPressure? {
        switch self {
        case .automatic: return nil
        case .psi: return .poundsForcePerSquareInch
        case .bar: return .bars
        case .kilopascals: return .kilopascals
        }
    }

    init(stored: String?) {
        self = stored.flatMap(TyrePressureSetting.init(rawValue:)) ?? .automatic
    }

    /// The details tap: from whatever is on screen now, psi → bar → kPa → psi. Never back to Automatic;
    /// Settings has that.
    static func next(after shown: UnitPressure) -> TyrePressureSetting {
        switch shown {
        case .poundsForcePerSquareInch: return .bar
        case .bars: return .kilopascals
        default: return .psi
        }
    }
}

extension VehicleInfo {
    func displayUnits(
        locale: Locale,
        temperaturePreference: String?,
        pressureSetting: TyrePressureSetting = .automatic
    ) -> VehicleDisplayUnits {
        VehicleDisplayUnits.resolve(
            guiDistance: guiDistanceUnits,
            guiTemperature: guiTemperatureUnits,
            guiPressure: guiTyrePressureUnits,
            locale: locale,
            temperaturePreference: temperaturePreference,
            pressureSetting: pressureSetting
        )
    }

    /// The setting the details tap should store next, or nil when there is no tyre row to change.
    func nextPressureSetting(
        locale: Locale = .current,
        temperaturePreference: String? = UserDefaults.standard.string(forKey: "AppleTemperatureUnit"),
        current: TyrePressureSetting
    ) -> TyrePressureSetting? {
        guard tyrePressuresBar?.count == 4 else { return nil }
        let shown = displayUnits(locale: locale, temperaturePreference: temperaturePreference, pressureSetting: current).pressure
        return TyrePressureSetting.next(after: shown)
    }

    /// Rows in reading order. A field Fleet did not send has no row. Battery, charging state and
    /// minutes to full are already on the title lines, so they are not repeated here.
    func rows(
        now: Date = Date(),
        locale: Locale = .current,
        temperaturePreference: String? = UserDefaults.standard.string(forKey: "AppleTemperatureUnit"),
        pressureSetting: TyrePressureSetting = .automatic
    ) -> [VehicleInfoRow] {
        let units = displayUnits(locale: locale, temperaturePreference: temperaturePreference, pressureSetting: pressureSetting)
        var rows: [VehicleInfoRow] = []
        func add(_ id: String, _ symbol: String, _ text: String) {
            rows.append(VehicleInfoRow(id: id, symbol: symbol, text: text))
        }
        func number(_ value: Double, decimals: Int) -> String {
            Self.number(value, decimals: decimals, locale: locale)
        }
        /// Fleet sends miles.
        func distance(_ miles: Double) -> String {
            let value = Measurement(value: miles, unit: UnitLength.miles).converted(to: units.distance).value
            return "\(number(value, decimals: 0)) \(units.distanceSymbol)"
        }
        /// Fleet sends Celsius.
        func temperature(_ celsius: Double) -> String {
            let value = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: units.temperature).value
            return "\(number(value, decimals: 0))\(units.temperatureSymbol)"
        }

        if let rangeMiles, rangeMiles > 0 {
            add("range", "gauge.with.dots.needle.67percent", "\(distance(rangeMiles)) range")
        }
        if let chargeLimitPercent, chargeLimitPercent > 0 {
            add("limit", "flag.checkered", "Charge limit \(Int(chargeLimitPercent.rounded()))%")
        }
        if isCharging, let power = chargerPowerKilowatts, power > 0 {
            var text = "\(number(power, decimals: power < 10 ? 1 : 0)) kW"
            if let rate = chargeRateMilesPerHour, rate > 0 {
                text += " · +\(distance(rate))/h"
            }
            add("rate", "ev.charger", text)
        }
        if let added = energyAddedKilowattHours, added > 0, isCharging || chargingState == "Complete" {
            add("added", "bolt.fill", "\(number(added, decimals: 1)) kWh added")
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
            // Fleet sends bar.
            let values = tyrePressuresBar.map { bar in
                number(Measurement(value: bar, unit: UnitPressure.bars).converted(to: units.pressure).value, decimals: units.pressureDecimals)
            }
            add("tyres", "tirepressure", "Tyres \(values.joined(separator: " · ")) \(units.pressureSymbol)")
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

    /// Cached data can be hours old, so the panel says how old.
    static func updatedText(_ reportedAt: Date, now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(reportedAt)) / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "Updated \(hours) h ago" }
        return "Updated \(hours / 24) days ago"
    }

    static func number(_ value: Double, decimals: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
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
