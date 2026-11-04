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
}

/// Demo mode walks these skies and cars. The power sample still refreshes
/// every 10 seconds; each scene stays up for two of those samples so the
/// five-second weather fade can finish.
enum DemoHouseTour {
    static let powerTicksPerScene = 2

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
        DemoVehicle(vin: "5YJ3GDEE5NF000001", displayName: "Model 3", model: .model3),
        DemoVehicle(vin: "5YJ3GDEE5RF000001", displayName: "Model 3 Highland", model: .model3Highland),
        DemoVehicle(vin: "5YJYGDEE5LF000001", displayName: "Model Y", model: .modelY),
        DemoVehicle(vin: "5YJYGDEE5SF000001", displayName: "Model Y Juniper", model: .modelYJuniper),
        DemoVehicle(vin: "5YJSA1E25MF000001", displayName: "Model S", model: .modelS),
        DemoVehicle(vin: "5YJXCAE25MF000001", displayName: "Model X", model: .modelX),
        DemoVehicle(vin: "7G2C12345RF000001", displayName: "Cybertruck", model: .cybertruck),
    ]

    static func weather(at index: Int) -> DemoWeatherScene {
        weather[wrapped(index, count: weather.count)]
    }

    static func vehicle(at index: Int) -> DemoVehicle {
        vehicles[wrapped(index, count: vehicles.count)]
    }

    private static func wrapped(_ index: Int, count: Int) -> Int {
        let count = max(count, 1)
        let wrapped = index % count
        return wrapped >= 0 ? wrapped : wrapped + count
    }
}
