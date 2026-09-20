import Foundation
import Testing
@testable import Powerwall_TV

@MainActor
struct DemoEnergyDataTests {
    @Test func demoRefreshSkipsLoginAndClearsStaleConnectionErrors() {
        let model = PowerwallViewModel()
        model.ipAddress = "192.168.1.1"
        model.errorMessage = "Login failed: connection unavailable"
        model.ipAddress = "demo"
        #expect(model.errorMessage == nil)
        for mode in [LoginMode.local, .fleetAPI] {
            model.loginMode = mode
            model.password = ""
            model.accessToken = ""
            model.errorMessage = "Old connection error"
            model.fetchData()
            #expect(model.errorMessage == nil)
            var completed = false
            model.login { authenticated in
                completed = true
                #expect(!authenticated)
            }
            #expect(completed)
            #expect(model.errorMessage == nil)
        }
    }

    @Test func historyBalancesEnergyAndNavigatesWithoutCredentials() {
        let model = PowerwallViewModel()
        model.ipAddress = "demo"
        model.loginMode = .local
        model.energySiteId = nil
        model.accessToken = ""
        model.fetchFleetAPIHistory()
        #expect(model.batteryPowerHistory.count == 288)
        #expect(model.batteryPercentageHistory.allSatisfy { (20...100).contains($0.value) })
        #expect(model.solarPowerHistory.contains { $0.value > 0 })
        #expect(model.gridPowerHistory.contains { $0.value < 0 })
        for index in model.homePowerHistory.indices {
            let supply = model.solarPowerHistory[index].value + model.batteryPowerHistory[index].value + model.gridPowerHistory[index].value
            #expect(abs(supply - model.homePowerHistory[index].value) < 0.000001)
        }
        let original = model.homePowerHistory.first!.date
        model.goToPreviousDay()
        #expect(model.homePowerHistory.first!.date < original)
        model.goToNextDay()
        #expect(model.currentDateLabel == "Today")
    }

    @Test func advisorWorksOfflineAndDoesNotReuseDemoForLiveConnection() {
        let model = PowerwallViewModel()
        model.ipAddress = "demo"
        model.loginMode = .local
        model.energySiteId = nil
        model.accessToken = ""
        let advisor = ExportAdvisor()
        advisor.start(viewModel: model, hour: 10)
        #expect(advisor.context?.isDemo == true)
        #expect(advisor.context?.attribution == nil)
        #expect(advisor.hasInitialAnswer)
        #expect(!advisor.busy)
        #expect(advisor.error == nil)
        #expect(abs((advisor.context?.budget.exportPercent ?? 0) - 36) < 0.000001)
        advisor.followUp("What about the weather?", viewModel: model)
        #expect(advisor.messages.count == 4)
        #expect(advisor.messages.last?.contains("sample forecast") == true)
        advisor.cancel()
        advisor.start(viewModel: model, hour: 8)
        #expect(advisor.messages.count == 2)
        #expect(advisor.context?.settings.morningEndHour == 8)
        model.ipAddress = "192.168.1.1"
        advisor.followUp("Can I export?", viewModel: model)
        #expect(advisor.context == nil)
        #expect(!advisor.hasInitialAnswer)
    }
}
