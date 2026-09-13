import Foundation
import Testing
@testable import Powerwall_TV

struct AdvisorEstimateSettingsTests {
    @Test func settingsIdentityTracksPeakHourAndSelectedSiteLocation() throws {
        let name = "AdvisorEstimateSettingsTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("Adelaide, Australia", forKey: "exportAdvisor_weatherLocation_123")
        let original = AdvisorEstimateSettings.current(siteID: "123", defaults: defaults)
        #expect(original.morningEndHour == 10)
        #expect(original == .current(siteID: "123", defaults: defaults))
        defaults.set(12, forKey: "exportAdvisor_peakEnd")
        #expect(original != .current(siteID: "123", defaults: defaults))
        defaults.set(10, forKey: "exportAdvisor_peakEnd")
        defaults.set("Melbourne, Australia", forKey: "exportAdvisor_weatherLocation_123")
        #expect(original != .current(siteID: "123", defaults: defaults))
        // A changed setting never mutates the inputs already captured for an in-flight estimate.
        #expect(original.weatherLocation == "Adelaide, Australia")
        defaults.set(" Adelaide, Australia\n", forKey: "exportAdvisor_weatherLocation_123")
        defaults.set("Sydney, Australia", forKey: "exportAdvisor_weatherLocation_456")
        #expect(original == .current(siteID: "123", defaults: defaults))
        #expect(original != .current(siteID: "456", defaults: defaults))
        #expect(original != .current(siteID: "123", morningEndHour: 11, defaults: defaults))
    }
}
