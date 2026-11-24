import Foundation

/// Which car mesh to park, from Fleet `vehicle_config.car_type` when we have it,
/// otherwise from the VIN. Paint stays on `VehicleAppearance` and is only refreshed
/// from a `vehicle_data` response the app was already going to make.
enum GarageVehicleModel {
    static func resolve(vin: String?, carType: String?) -> VehicleModel {
        let normalizedType = normalize(carType)
        let year = modelYear(vin: vin)
        if normalizedType.contains("cybertruck") {
            return .cybertruck
        }
        if normalizedType.contains("highland") || normalizedType == "lychee" {
            return .model3Highland
        }
        if normalizedType.contains("juniper") {
            return .modelYJuniper
        }
        if normalizedType.contains("model3") || normalizedType == "m3" {
            return (year ?? 0) >= 2024 ? .model3Highland : .model3
        }
        if normalizedType.contains("modely") || normalizedType == "my" {
            return (year ?? 0) >= 2025 ? .modelYJuniper : .modelY
        }
        if normalizedType.contains("modelx") || normalizedType == "mx" {
            return .modelX
        }
        if normalizedType.contains("models") || normalizedType == "ms" {
            return .modelS
        }
        return resolve(vin: vin)
    }

    static func resolve(vin: String?) -> VehicleModel {
        guard let vin = normalizedVIN(vin) else { return .generic }
        let modelCharacter = vin[vin.index(vin.startIndex, offsetBy: 3)]
        let year = modelYear(vin: vin) ?? 0
        switch modelCharacter {
        case "C":
            return .cybertruck
        case "3":
            return year >= 2024 ? .model3Highland : .model3
        case "Y":
            return year >= 2025 ? .modelYJuniper : .modelY
        case "S":
            return .modelS
        case "X":
            return .modelX
        default:
            return .generic
        }
    }

    static func modelYear(vin: String?) -> Int? {
        guard let vin = normalizedVIN(vin) else { return nil }
        let code = vin[vin.index(vin.startIndex, offsetBy: 9)]
        if let year = yearCodes[code] { return year }
        if let digit = code.wholeNumberValue, digit > 0 { return 2000 + digit }
        return nil
    }

    private static func normalizedVIN(_ vin: String?) -> String? {
        guard let vin else { return nil }
        let normalized = vin.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 17, normalized.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return normalized
    }

    private static func normalize(_ value: String?) -> String {
        (value ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// VIN model-year codes from 2010. I, O, Q, U and Z are skipped.
    private static let yearCodes: [Character: Int] = {
        let letters = Array("ABCDEFGHJKLMNPRSTVWXY")
        return Dictionary(uniqueKeysWithValues: letters.enumerated().map { (2010 + $0.offset, $0.element) }.map { ($1, $0) })
    }()
}

struct VehicleAppearance: Codable, Equatable {
    var exteriorColor: String?
    var paintColorOverride: String?
    var colorizerRemap: Bool
    var carType: String?

    var hasUsefulData: Bool {
        !trimmed(exteriorColor).isEmpty || !trimmed(paintColorOverride).isEmpty || !trimmed(carType).isEmpty
    }

    /// True when this copy says which paint the car has.
    var hasPaint: Bool {
        !trimmed(exteriorColor).isEmpty || !trimmed(paintColorOverride).isEmpty
    }

    /// Newer fields win. A blank newer field keeps this one.
    func merging(_ newer: VehicleAppearance) -> VehicleAppearance {
        func pick(_ new: String?, _ old: String?) -> String? {
            let value = new?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? old : new
        }
        // A new exterior colour with no override means the override no longer applies.
        let newExterior = trimmed(newer.exteriorColor)
        let newOverride = trimmed(newer.paintColorOverride)
        let override = !newOverride.isEmpty ? newer.paintColorOverride
            : (!newExterior.isEmpty ? nil : paintColorOverride)
        return VehicleAppearance(
            exteriorColor: pick(newer.exteriorColor, exteriorColor),
            paintColorOverride: override,
            colorizerRemap: newer.hasPaint ? newer.colorizerRemap : colorizerRemap,
            carType: pick(newer.carType, carType)
        )
    }

    private func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum GarageSolar: Equatable {
    case panels
    case roof
    case hidden

    /// Missing site metadata keeps the panels shown on the previous background art.
    static func resolve(hasSolar: Bool?, solarType: String?) -> GarageSolar {
        if hasSolar == false { return .hidden }
        if (solarType ?? "").lowercased().contains("roof") { return .roof }
        return .panels
    }

    var sceneOption: SolarOption {
        switch self {
        case .panels: return .panels
        case .roof: return .solarRoof
        case .hidden: return .none
        }
    }
}

struct GaragePresentation: Equatable {
    var showWallConnector: Bool
    var showVehicle: Bool
    var model: VehicleModel
    var exteriorColor: String?
    var paintColorOverride: String?
    var colorizerRemap: Bool
    var solar: GarageSolar

    static func make(
        data: PowerwallData?,
        fallbackVIN: String,
        appearances: [String: VehicleAppearance],
        solar: GarageSolar
    ) -> GaragePresentation {
        let connectors = data?.wallConnectors ?? []
        let showWallConnector = !connectors.isEmpty
        let connectorPower = connectors.reduce(0.0) { $0 + ($1.wallConnectorPower ?? 0) }
        // The cable animates for charging and for vehicle-to-home. Either one parks a car.
        let showVehicle = showWallConnector && (
            abs(connectorPower) > 10
                || connectors.contains { $0.wallConnectorState == 1.0 }
                || connectors.contains(where: \.isVehicleConnected)
        )
        let vin = connectedVIN(wallConnectors: connectors, fallbackVIN: fallbackVIN)
        let appearance = appearance(for: vin, in: appearances)
        let model = showVehicle
            ? GarageVehicleModel.resolve(vin: vin, carType: appearance?.carType)
            : .generic
        let paintOverride = appearance?.paintColorOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let exterior = appearance?.exteriorColor?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GaragePresentation(
            showWallConnector: showWallConnector,
            showVehicle: showVehicle,
            model: model,
            exteriorColor: exterior?.isEmpty == false ? exterior : nil,
            paintColorOverride: paintOverride?.isEmpty == false ? paintOverride : nil,
            colorizerRemap: appearance?.colorizerRemap ?? false,
            solar: solar
        )
    }

    /// The car the garage should show. A connector that is charging (state 1) wins, in list order,
    /// which is the same VIN the kW readout uses. A connector moving energy without that state,
    /// including vehicle-to-home, is next. A car that is only plugged in is used when nothing is
    /// charging. Local Wall Connector vitals have no VIN, so the last charging VIN is the fallback.
    static func connectedVIN(wallConnectors: [WallConnector], fallbackVIN: String) -> String? {
        if let liveVIN = rankedVIN(wallConnectors: wallConnectors, includePlugged: true) {
            return liveVIN
        }
        let normalizedFallbackVIN = fallbackVIN.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedFallbackVIN.isEmpty ? nil : normalizedFallbackVIN
    }

    /// VIN to remember after this sample. Plugged-in-only connectors do not replace the last car
    /// that was actually charging.
    static func chargingVIN(wallConnectors: [WallConnector]) -> String? {
        rankedVIN(wallConnectors: wallConnectors, includePlugged: false)
    }

    private static func appearance(for vin: String?, in appearances: [String: VehicleAppearance]) -> VehicleAppearance? {
        guard let vin, !vin.isEmpty else { return nil }
        if let exact = appearances[vin] { return exact }
        return appearances.first { $0.key.caseInsensitiveCompare(vin) == .orderedSame }?.value
    }

    /// Lower priority wins. State 1 keeps list order so it stays aligned with the readout.
    /// Energy without that state keeps the larger flow, then the earlier connector.
    private static func rankedVIN(wallConnectors: [WallConnector], includePlugged: Bool) -> String? {
        var bestPriority = Int.max
        var bestMagnitude = -1.0
        var bestVIN: String?
        for wallConnector in wallConnectors {
            let vin = wallConnector.vin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !vin.isEmpty else { continue }
            let magnitude = abs(wallConnector.wallConnectorPower ?? 0)
            let state = wallConnector.wallConnectorState
            let priority: Int
            if state == 1 {
                priority = 0
            } else if magnitude > 10 {
                priority = 1
            } else if includePlugged && state == 4 {
                priority = 2
            } else {
                continue
            }
            let betterPriority = priority < bestPriority
            let strongerFlow = priority == 1 && bestPriority == 1 && magnitude > bestMagnitude
            guard betterPriority || strongerFlow else { continue }
            bestPriority = priority
            bestMagnitude = magnitude
            bestVIN = vin
        }
        return bestVIN
    }
}

enum HouseHeading {
    static func label(_ degrees: Double) -> String {
        let names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let wrapped = ((degrees.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((wrapped / 45).rounded()) % names.count
        return "\(names[index]) (\(Int(wrapped.rounded()) % 360)°)"
    }
}
