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

#if os(macOS)
    @Test func menuBarSelectionReadsLegacyAndMultipleValuesInDisplayOrder() {
        #expect(MenuBarLabelSelection.metrics(from: "battery") == [.battery])
        #expect(MenuBarLabelSelection.metrics(from: "battery,solar,site") == [.solar, .site, .battery])
        #expect(MenuBarLabelSelection.metrics(from: "unknown") == [.solar])
    }

    @Test func menuBarSelectionTogglesMetricsAndKeepsAtLeastOne() {
        #expect(MenuBarLabelSelection.toggling(.load, in: "solar") == "solar,load")
        #expect(MenuBarLabelSelection.toggling(.solar, in: "solar,load") == "load")
        #expect(MenuBarLabelSelection.toggling(.solar, in: "solar") == "solar")
    }

    @Test func automaticMenuBarSelectionUsesGreatestAbsoluteEnergyFlow() {
        #expect(
            automaticMenuBarLabelMetric(
                solarWatts: 1_200,
                loadWatts: 3_400,
                siteWatts: 500,
                batteryWatts: -5_900
            ) == .battery
        )
        #expect(
            automaticMenuBarLabelMetric(
                solarWatts: 6_100,
                loadWatts: 3_400,
                siteWatts: -5_900,
                batteryWatts: 200
            ) == .solar
        )
    }
#endif

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

    @Test func powerwallRuntimeEstimateFormatsTimeUntilEmptyWhenDischarging() {
        #expect(
            PowerwallRuntimeEstimator.estimateString(
                batteryWatts: 2_000,
                batteryCount: 2,
                batteryPercentage: 50,
                idleThresholdWatts: 40
            ) == "6 hours 45 minutes"
        )
    }

    @Test func powerwallRuntimeEstimateFormatsTimeUntilFullWhenCharging() {
        #expect(
            PowerwallRuntimeEstimator.estimateString(
                batteryWatts: -3_000,
                batteryCount: 1,
                batteryPercentage: 20,
                idleThresholdWatts: 40
            ) == "3 hours 36 minutes"
        )
    }

    @Test func powerwallRuntimeEstimateOmitsZeroHourAndMinuteUnits() {
        #expect(
            PowerwallRuntimeEstimator.estimateString(
                batteryWatts: 4_500,
                batteryCount: 1,
                batteryPercentage: 50,
                idleThresholdWatts: 40
            ) == "1 hours 30 minutes"
        )

        #expect(
            PowerwallRuntimeEstimator.estimateString(
                batteryWatts: 6_750,
                batteryCount: 1,
                batteryPercentage: 50,
                idleThresholdWatts: 40
            ) == "1 hours"
        )

        #expect(
            PowerwallRuntimeEstimator.estimateString(
                batteryWatts: 27_000,
                batteryCount: 1,
                batteryPercentage: 10,
                idleThresholdWatts: 40
            ) == "3 minutes"
        )
    }

    @Test func powerwallRuntimeEstimateFormatsDaysAndDropsMinutes() {
        #expect(
            PowerwallRuntimeEstimator.estimateString(
                batteryWatts: 500,
                batteryCount: 1,
                batteryPercentage: 90,
                idleThresholdWatts: 40
            ) == "1 days"
        )

        #expect(
            PowerwallRuntimeEstimator.estimateString(
                batteryWatts: 400,
                batteryCount: 1,
                batteryPercentage: 90,
                idleThresholdWatts: 40
            ) == "1 days 6 hours"
        )
    }

    @Test func powerwallRuntimeEstimateRequiresBatteryCountPercentageAndPowerFlow() {
        #expect(PowerwallRuntimeEstimator.estimateString(batteryWatts: 2_000, batteryCount: 0, batteryPercentage: 50, idleThresholdWatts: 40) == nil)
        #expect(PowerwallRuntimeEstimator.estimateString(batteryWatts: 2_000, batteryCount: 1, batteryPercentage: nil, idleThresholdWatts: 40) == nil)
        #expect(PowerwallRuntimeEstimator.estimateString(batteryWatts: 20, batteryCount: 1, batteryPercentage: 50, idleThresholdWatts: 40) == nil)
    }

    @Test func powerwallRuntimeEstimateIgnoresFullAndEmptyBatteryPercentages() {
        #expect(PowerwallRuntimeEstimator.estimateString(batteryWatts: 2_000, batteryCount: 1, batteryPercentage: 100, idleThresholdWatts: 40) == nil)
        #expect(PowerwallRuntimeEstimator.estimateString(batteryWatts: -2_000, batteryCount: 1, batteryPercentage: 100, idleThresholdWatts: 40) == nil)
        #expect(PowerwallRuntimeEstimator.estimateString(batteryWatts: 2_000, batteryCount: 1, batteryPercentage: 0, idleThresholdWatts: 40) == nil)
        #expect(PowerwallRuntimeEstimator.estimateString(batteryWatts: -2_000, batteryCount: 1, batteryPercentage: 0, idleThresholdWatts: 40) == nil)
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
        let start = HistoricalDataPoint(date: startDate, value: 100, from: .solar, to: .home, source: .solar)
        let end = HistoricalDataPoint(date: endDate, value: -100, from: .solar, to: .home, source: .solar)

        let crossing = interpolateZeroCrossing(start: start, end: end)
        #expect(crossing.value == 0)
        #expect(crossing.from == .solar)
        #expect(crossing.to == .home)
        #expect(crossing.source == .solar)
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

    @Test func localSiteInfoUsesSiteName() throws {
        let json = """
        {
          "max_system_energy_kWh": 27,
          "max_system_power_kW": 10,
          "site_name": "Queens",
          "timezone": "Australia/Adelaide",
          "net_meter_mode": "battery_ok"
        }
        """
        let decoded = try JSONDecoder().decode(LocalSiteInfo.self, from: Data(json.utf8))
        #expect(decoded.energySiteDisplayName == "Queens")
    }

    @Test func legacyScheduleDecodesWithoutAHomeAndCannotRun() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy",
          "isEnabled": true,
          "startMinutes": 900,
          "endMinutes": 1260,
          "startMode": "timeBasedControl",
          "endMode": "selfPowered"
        }
        """
        let schedule = try JSONDecoder().decode(PowerwallSchedule.self, from: Data(json.utf8))

        #expect(schedule.energySiteId == nil)
        #expect(PowerwallScheduleStore.dueSchedules(from: [schedule]).isEmpty)
        #expect(PowerwallScheduleStore.nextDueDate(from: [schedule]) == nil)
    }

    @Test func targetedScheduleIsEligibleToRun() {
        let schedule = PowerwallSchedule(
            energySiteId: "123456",
            energySiteName: "Queens"
        )
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 22))!
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let due = PowerwallScheduleStore.dueSchedules(
            from: [schedule],
            now: now,
            calendar: calendar,
            userDefaults: defaults
        )

        #expect(due.count == 2)
        #expect(due.allSatisfy { $0.schedule.energySiteId == "123456" })
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

    @Test func wallConnectorVitalsTreatsClosedContactorWithCurrentAsCharging() {
        let vitals = WallConnectorVitals(
            contactorClosed: true,
            vehicleConnected: true,
            session: 1,
            gridVolts: 0,
            gridHertz: 0,
            vehicleCurrentAmps: 16,
            uptime: 10,
            evseState: 2
        )
        #expect(vitals.wallConnectorPower == 0)
        #expect(vitals.fleetWallConnectorState == 1.0)
    }

    @Test func wallConnectorVitalsTreatsConnectedVehicleWithoutCurrentAsPluggedIn() {
        let vitals = WallConnectorVitals(
            contactorClosed: false,
            vehicleConnected: true,
            session: 1,
            gridVolts: 0,
            gridHertz: 0,
            vehicleCurrentAmps: 0,
            uptime: 10,
            evseState: 2
        )
        #expect(vitals.fleetWallConnectorState == 4.0)
    }

    @Test func wallConnectorVitalsTreatsDisconnectedVehicleAsIdle() {
        let vitals = WallConnectorVitals(
            contactorClosed: false,
            vehicleConnected: false,
            session: 1,
            gridVolts: 0,
            gridHertz: 0,
            vehicleCurrentAmps: 0,
            uptime: 10,
            evseState: 0
        )
        #expect(vitals.fleetWallConnectorState == nil)
    }

    @Test func formatPowerValueKeepsNegativeSignWithFullPrecision() {
        #expect(formatPowerValue(-1.234, precision: "%.3f", showLessPrecision: false) == "-1.234")
    }

    @Test func formatPowerValueRemovesNegativeSignWithLessPrecision() {
        #expect(formatPowerValue(-1.234, precision: "%.1f", showLessPrecision: true) == "1.2")
    }

    @Test func clampSceneScaleHonorsBounds() {
        #expect(clampSceneScale(0.5) == 0.8)
        #expect(clampSceneScale(1.0) == 1.0)
        #expect(clampSceneScale(1.5) == 1.2)
    }

    @Test func clampSceneHorizontalOffsetHonorsBounds() {
        #expect(clampSceneHorizontalOffset(-0.5) == -0.2)
        #expect(clampSceneHorizontalOffset(0.0) == 0.0)
        #expect(clampSceneHorizontalOffset(0.5) == 0.2)
    }
}
