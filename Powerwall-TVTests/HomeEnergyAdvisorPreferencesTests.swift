import Foundation
import Testing
@testable import Powerwall_TV

struct HomeEnergyAdvisorPreferencesTests {
    @Test func customPromptAndBlankFallback() throws {
        let name = "HomeEnergyAdvisorPreferencesTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(HomeEnergyAdvisorPreferences.initialPrompt(in: defaults) == HomeEnergyAdvisorPreferences.defaultPrompt)
        defaults.set("  Should I charge before sunrise?\n", forKey: "homeEnergyAdvisor_defaultPrompt")
        #expect(HomeEnergyAdvisorPreferences.initialPrompt(in: defaults) == "Should I charge before sunrise?")
        defaults.set(" \n", forKey: "homeEnergyAdvisor_defaultPrompt")
        #expect(HomeEnergyAdvisorPreferences.initialPrompt(in: defaults) == HomeEnergyAdvisorPreferences.defaultPrompt)
    }
}
