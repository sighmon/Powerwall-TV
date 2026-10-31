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
        let showVehicle = showWallConnector && (
            connectors.reduce(0.0) { $0 + ($1.wallConnectorPower ?? 0) } > 10
                || connectors.contains { $0.wallConnectorState == 1.0 }
                || connectors.contains(where: \.isVehicleConnected)
        )
        let vin = connectedVIN(wallConnectors: connectors, fallbackVIN: fallbackVIN)
        let appearance = vin.flatMap { appearances[$0] }
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

    /// Same choice the flat backgrounds used: a live charging or plugged-in VIN, then the last VIN
    /// that was charging. Local Wall Connector vitals have no VIN, so the fallback still matters.
    static func connectedVIN(wallConnectors: [WallConnector], fallbackVIN: String) -> String? {
        if let liveVIN = wallConnectors.first(where: { wallConnector in
            let chargingOrConnected = (wallConnector.wallConnectorPower ?? 0) > 10
                || wallConnector.wallConnectorState == 1.0
                || wallConnector.wallConnectorState == 4.0
            let normalizedVIN = wallConnector.vin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return chargingOrConnected && !normalizedVIN.isEmpty
        })?.vin?.trimmingCharacters(in: .whitespacesAndNewlines), !liveVIN.isEmpty {
            return liveVIN
        }

        let normalizedFallbackVIN = fallbackVIN.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedFallbackVIN.isEmpty ? nil : normalizedFallbackVIN
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
