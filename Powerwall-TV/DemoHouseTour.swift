import Foundation
import WeatherKit

/// One scripted sky. The sun is fixed so a night scene stays night no matter
/// what the clock says. Live WeatherKit still follows the real sun.
struct DemoWeatherScene: Equatable {
    let title: String
    let sunAltitude: Double
    let sunAzimuth: Double
    let isDaylight: Bool
    let cloudCover: Double
    let condition: WeatherCondition
    let precipitationMillimetresPerHour: Double

    func parameters(heading: Double) -> HouseLightingParameters {
        WeatherLighting(houseHeadingDegrees: heading).parameters(
            sunAltitude: sunAltitude,
            sunAzimuth: sunAzimuth,
            isDaylight: isDaylight,
            cloudCover: cloudCover,
            condition: condition,
            precipitationMillimetresPerHour: precipitationMillimetresPerHour
        )
    }
}

struct DemoVehicle: Equatable {
    let vin: String
    let displayName: String
    let model: VehicleModel
    /// A Fleet `wheel_type` this model ships with, so demo shows real wheel swaps with no Fleet call.
    var wheelType: String? = nil
}

/// Demo mode walks these skies and, for each exported car, every distinct Tesla paint and every
/// wheel that fits that car. The baked generic body stays its file colour and its own wheels.
/// Paint and wheels change together every `colourInterval`. The sky still waits for two 10-second
/// power samples so its five-second fade can finish. A car changes only after its colours and wheels.
enum DemoHouseTour {
    static let powerTicksPerScene = 2
    static let colourInterval: TimeInterval = 2
    /// Sample `vehicle_data` charge state. Demo has no Fleet account, so every parked car uses this.
    static let exampleCharge = VehicleChargeSnapshot(
        batteryLevel: 80,
        chargingState: "Charging",
        minutesToFullCharge: 45
    )

    /// Sample `vehicle_data_cached` panel for every demo car. Made-up numbers, no VIN or location,
    /// and the demo never calls Fleet. It matches `exampleCharge`. No `gui_settings` units, so the panel
    /// uses the device region's: km, °C and psi in Australia.
    static func exampleInfo(now: Date = Date()) -> VehicleInfo {
        VehicleInfo(
            batteryLevel: exampleCharge.batteryLevel,
            chargingState: exampleCharge.chargingState,
            minutesToFullCharge: exampleCharge.minutesToFullCharge,
            rangeMiles: 249.8,
            chargeLimitPercent: 90,
            chargerPowerKilowatts: 11,
            chargeRateMilesPerHour: 29.8,
            energyAddedKilowattHours: 18.4,
            insideCelsius: 21.5,
            outsideCelsius: 17,
            climateOn: false,
            locked: true,
            sentryMode: false,
            odometerMiles: 15_320,
            softwareVersion: "2026.38.4 0a1b2c3d4e5f",
            tyrePressuresBar: [2.9, 2.9, 2.8, 2.9],
            reportedAt: now.addingTimeInterval(-4 * 60)
        )
    }

    static let weather: [DemoWeatherScene] = [
        DemoWeatherScene(title: "Clear", sunAltitude: 52, sunAzimuth: 180, isDaylight: true, cloudCover: 0.05, condition: .clear, precipitationMillimetresPerHour: 0),
        DemoWeatherScene(title: "Partly cloudy", sunAltitude: 46, sunAzimuth: 120, isDaylight: true, cloudCover: 0.15, condition: .partlyCloudy, precipitationMillimetresPerHour: 0),
        DemoWeatherScene(title: "Cloudy", sunAltitude: 38, sunAzimuth: 210, isDaylight: true, cloudCover: 0.85, condition: .cloudy, precipitationMillimetresPerHour: 0),
        DemoWeatherScene(title: "Drizzle", sunAltitude: 32, sunAzimuth: 160, isDaylight: true, cloudCover: 0.72, condition: .drizzle, precipitationMillimetresPerHour: 2),
        DemoWeatherScene(title: "Rain", sunAltitude: 28, sunAzimuth: 190, isDaylight: true, cloudCover: 0.82, condition: .rain, precipitationMillimetresPerHour: 6),
        DemoWeatherScene(title: "Heavy rain", sunAltitude: 24, sunAzimuth: 200, isDaylight: true, cloudCover: 0.95, condition: .heavyRain, precipitationMillimetresPerHour: 12),
        DemoWeatherScene(title: "Flurries", sunAltitude: 30, sunAzimuth: 150, isDaylight: true, cloudCover: 0.55, condition: .flurries, precipitationMillimetresPerHour: 0),
        DemoWeatherScene(title: "Snow", sunAltitude: 22, sunAzimuth: 170, isDaylight: true, cloudCover: 0.8, condition: .snow, precipitationMillimetresPerHour: 0),
        DemoWeatherScene(title: "Blizzard", sunAltitude: 18, sunAzimuth: 190, isDaylight: true, cloudCover: 0.95, condition: .blizzard, precipitationMillimetresPerHour: 0),
        DemoWeatherScene(title: "Sleet", sunAltitude: 20, sunAzimuth: 180, isDaylight: true, cloudCover: 0.8, condition: .sleet, precipitationMillimetresPerHour: 0),
        DemoWeatherScene(title: "Night", sunAltitude: -12, sunAzimuth: 270, isDaylight: false, cloudCover: 0, condition: .clear, precipitationMillimetresPerHour: 0),
        DemoWeatherScene(title: "Rainy night", sunAltitude: -8, sunAzimuth: 200, isDaylight: false, cloudCover: 0.9, condition: .rain, precipitationMillimetresPerHour: 8),
    ]

    /// VINs follow the same year and model rules as a live Fleet car.
    static let vehicles: [DemoVehicle] = [
        DemoVehicle(vin: "5YJ000000NF000001", displayName: "Generic", model: .generic),
        DemoVehicle(vin: "5YJ3GDEE5NF000001", displayName: "Model 3", model: .model3, wheelType: "Pinwheel18CapKit"),
        DemoVehicle(vin: "5YJ3GDEE5RF000001", displayName: "Model 3 Highland", model: .model3Highland, wheelType: "Nova19Dark"),
        DemoVehicle(vin: "5YJYGDEE5LF000001", displayName: "Model Y", model: .modelY, wheelType: "Induction20Black"),
        DemoVehicle(vin: "5YJYGDEE5SF000001", displayName: "Model Y Juniper", model: .modelYJuniper, wheelType: "Crossflow19"),
        DemoVehicle(vin: "5YJSA1E25MF000001", displayName: "Model S", model: .modelS, wheelType: "Tempest19SonicSilver"),
        DemoVehicle(vin: "5YJXCAE25MF000001", displayName: "Model X", model: .modelX, wheelType: "Turbine22Dark"),
        DemoVehicle(vin: "7G2C12345RF000001", displayName: "Cybertruck", model: .cybertruck, wheelType: "CTPremium20"),
    ]

    static func weather(at index: Int) -> DemoWeatherScene {
        weather[wrapped(index, count: weather.count)]
    }

    static func vehicle(at index: Int) -> DemoVehicle {
        vehicles[wrapped(index, count: vehicles.count)]
    }

    /// How many demo steps one model stays parked. Generic is a single step. Every other car stays
    /// long enough to show each of its colours and each of its wheels at least once.
    static func steps(for model: VehicleModel) -> Int {
        guard model != .generic else { return 1 }
        return max(TeslaWheel.demoNames(for: model).count, TeslaPaint.catalogue.count, 1)
    }

    /// The baked generic body stays its file colour for one step. Every other car then walks its
    /// paints and its own wheels before the next model. Both advance together, one step at a time.
    static func parkedCar(at index: Int) -> (vehicle: DemoVehicle, appearance: VehicleAppearance) {
        let generic = vehicles.first { $0.model == .generic } ?? vehicles[0]
        let painted = vehicles.filter { $0.model != .generic }
        let total = 1 + painted.reduce(0) { $0 + steps(for: $1.model) }
        let step = wrapped(index, count: total)
        let blank = VehicleAppearance(exteriorColor: nil, paintColorOverride: nil, colorizerRemap: false, carType: nil)
        guard step > 0 else { return (generic, blank) }
        var cursor = step - 1
        for car in painted {
            let span = steps(for: car.model)
            if cursor < span {
                let paints = TeslaPaint.catalogue
                let wheels = TeslaWheel.demoNames(for: car.model)
                let paint = paints[cursor % max(paints.count, 1)]
                return (
                    car,
                    VehicleAppearance(
                        exteriorColor: paint.name,
                        paintColorOverride: paint.demoOverride,
                        colorizerRemap: false,
                        carType: nil,
                        wheelType: wheels.isEmpty ? car.wheelType : wheels[cursor % wheels.count]
                    )
                )
            }
            cursor -= span
        }
        return (generic, blank)
    }

    /// Keeps a title that is already on the request, and adds the sample charge lines when they are missing.
    static func applyingExampleFleetData(to request: CarShowroomRequest) -> CarShowroomRequest {
        var copy = request
        let sample = CarShowroom.statLines(displayName: "Vehicle", exteriorColor: nil, snapshot: exampleCharge)
        for line in sample.dropFirst() {
            let alreadyShown = copy.lines.contains { existing in
                if line.contains("% battery") { return existing.contains("% battery") }
                if line.contains("minutes to full") { return existing.contains("minutes to full") }
                return existing == line
            }
            if !alreadyShown { copy.lines.append(line) }
        }
        return copy
    }

    /// Demo chip text. Generic has no paint name, so it stays the display name alone.
    static func vehicleLabel(displayName: String, exteriorColor: String?) -> String {
        guard let exteriorColor, !exteriorColor.isEmpty else { return displayName }
        return "\(displayName) · \(TeslaPaint.spacedName(exteriorColor))"
    }

    private static func wrapped(_ index: Int, count: Int) -> Int {
        let count = max(count, 1)
        let wrapped = index % count
        return wrapped >= 0 ? wrapped : wrapped + count
    }
}
