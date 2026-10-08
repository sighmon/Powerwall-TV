import Foundation

/// Keep preference keys stable so existing credentials and advisor settings survive the rename.
enum HomeEnergyAdvisorPreferences {
    static let defaultPrompt = "How should I manage my home energy tonight and tomorrow? Consider my battery reserve, expected household usage and the weather, including whether there is spare energy to export."

    static func initialPrompt(in defaults: UserDefaults = .standard) -> String {
        let saved = defaults.string(forKey: "homeEnergyAdvisor_defaultPrompt") ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultPrompt : trimmed
    }
}

enum AdvisorWeatherMood: String {
    case clear, cloudy, rain, night
}
