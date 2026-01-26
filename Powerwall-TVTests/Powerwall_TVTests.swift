//
//  Powerwall_TVTests.swift
//  Powerwall-TVTests
//
//  Created by Simon Loffler on 17/3/2025.
//

import Foundation
import Testing
@testable import Powerwall_TV

struct Powerwall_TVTests {

    @Test func isOffGridReflectsGridStatus() {
        let viewModel = PowerwallViewModel()

        viewModel.gridStatus = GridStatus(status: "SystemIslandedActive")
        #expect(viewModel.isOffGrid() == true)

        viewModel.gridStatus = GridStatus(status: "Inactive")
        #expect(viewModel.isOffGrid() == true)

        viewModel.gridStatus = GridStatus(status: "Active")
        #expect(viewModel.isOffGrid() == false)

        viewModel.gridStatus = nil
        #expect(viewModel.isOffGrid() == false)
    }

    @Test func batteryCountStringHandlesMissingAndZero() {
        let viewModel = PowerwallViewModel()
        #expect(viewModel.batteryCountString() == "")

        viewModel.data = PowerwallData(
            battery: .init(instantPower: 0, count: 0),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0)
        )
        #expect(viewModel.batteryCountString() == "")
    }

    @Test func batteryCountStringFormatsNonZero() {
        let viewModel = PowerwallViewModel()
        viewModel.data = PowerwallData(
            battery: .init(instantPower: 0, count: 2),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0)
        )
        #expect(viewModel.batteryCountString() == " · 2x")
    }

    @Test func currentDateLabelMatchesTodayYesterdayAndOther() {
        let viewModel = PowerwallViewModel()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let midday = calendar.date(byAdding: .hour, value: 12, to: startOfToday) ?? Date()

        viewModel.currentEndDate = midday
        #expect(viewModel.currentDateLabel == "Today")

        let yesterdayMidday = calendar.date(byAdding: .day, value: -1, to: midday) ?? Date().addingTimeInterval(-24 * 3600)
        viewModel.currentEndDate = yesterdayMidday
        #expect(viewModel.currentDateLabel == "Yesterday")

        let fixedDate = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 12)) ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        viewModel.currentEndDate = fixedDate
        #expect(viewModel.currentDateLabel == formatter.string(from: fixedDate))
    }

    @Test func interpolateZeroCrossingFindsMidpoint() {
        let startDate = Date(timeIntervalSince1970: 0)
        let endDate = Date(timeIntervalSince1970: 100)
        let start = HistoricalDataPoint(date: startDate, value: 100, from: .solar, to: .home)
        let end = HistoricalDataPoint(date: endDate, value: -100, from: .solar, to: .home)

        let crossing = interpolateZeroCrossing(start: start, end: end)
        #expect(crossing.value == 0)
        #expect(crossing.from == .solar)
        #expect(crossing.to == .home)
        #expect(abs(crossing.date.timeIntervalSince1970 - 50) < 0.0001)
    }

    @Test func powerwallDataDecodingDefaultsWallConnectorsToEmpty() throws {
        let json = """
        {
          "battery": { "instant_power": 10, "num_meters_aggregated": 2 },
          "load": { "instant_power": 11 },
          "solar": { "instant_power": 12, "energy_exported": 13 },
          "site": { "instant_power": 14 }
        }
        """
        let decoded = try JSONDecoder().decode(PowerwallData.self, from: Data(json.utf8))
        #expect(decoded.wallConnectors.isEmpty)
        #expect(decoded.battery.count == 2)
    }

    @Test func wallConnectorVitalsPowerIsCalculated() {
        let vitals = WallConnectorVitals(
            contactorClosed: true,
            vehicleConnected: true,
            session: 1,
            gridVolts: 230,
            gridHertz: 50,
            vehicleCurrentAmps: 16,
            uptime: 10,
            evseState: 2
        )
        #expect(vitals.wallConnectorPower == 3680)
    }
}
