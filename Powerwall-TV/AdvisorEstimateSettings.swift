import Foundation

/// Capture once per estimate so the usage window and geocoded forecast use the same inputs.
struct AdvisorEstimateSettings: Equatable {
    let morningEndHour: Int
    let weatherLocation: String

    static func current(siteID: String, morningEndHour: Int? = nil, defaults: UserDefaults = .standard) -> Self {
        Self(
            morningEndHour: morningEndHour ?? (defaults.object(forKey: "exportAdvisor_peakEnd") as? Int ?? 10),
            weatherLocation: (defaults.string(forKey: "exportAdvisor_weatherLocation_" + siteID) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
