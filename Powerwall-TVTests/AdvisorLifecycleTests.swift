import Foundation
import Testing
@testable import Powerwall_TV

@MainActor
struct AdvisorLifecycleTests {
    private func context() throws -> ExportAdvisorContext {
        let url = URL(string: "https://example.com/attribution")!
        let attribution = ExportAdvisorContext.Attribution(legalPageURL: url, combinedMarkDarkURL: url, combinedMarkLightURL: url)
        return ExportAdvisorContext(generatedAt: Date(), siteID: "123", settings: .current(siteID: "123"), prompt: "test", budget: try ExportBatteryBudget(capacityKWh: 27, chargePercent: 80, reservePercent: 20, demandKWh: 5), averageUsageKWh: 5, sampleCount: 5, end: Date().addingTimeInterval(3600), timeZone: TimeZone(secondsFromGMT: 0)!, weatherLocationName: "Test", weatherMood: .clear, weatherSymbol: "sun.max", weatherSummary: "Clear", attribution: attribution)
    }

    @Test func cancellingBeforeInitialAnswerClearsContextForRetry() throws {
        let advisor = ExportAdvisor()
        advisor.context = try context()
        advisor.busy = true
        advisor.cancel()
        #expect(advisor.context == nil)
        #expect(advisor.messages.isEmpty)
        #expect(!advisor.busy)
        #expect(!advisor.hasInitialAnswer)
    }

    @Test func completedAnswerSurvivesClosingButNotInvalidation() throws {
        let advisor = ExportAdvisor()
        advisor.context = try context()
        advisor.messages = ["Question", "Answer"]
        advisor.cancel()
        #expect(advisor.context != nil)
        #expect(advisor.hasInitialAnswer)
        advisor.invalidate()
        #expect(advisor.context == nil)
        #expect(advisor.messages.isEmpty)
        #expect(!advisor.hasInitialAnswer)
    }

    @Test func localModeRejectsFollowUpsEvenWithRetainedFleetSite() throws {
        let advisor = ExportAdvisor()
        advisor.context = try context()
        advisor.messages = ["Question", "Answer"]
        let model = PowerwallViewModel()
        model.loginMode = .local
        model.energySiteId = "123"
        advisor.followUp("Can I export more?", viewModel: model)
        #expect(advisor.context == nil)
        #expect(advisor.messages.isEmpty)
        #expect(advisor.error?.contains("Fleet API") == true)
        #expect(!advisor.busy)
    }
}
