import Foundation
import Testing
@testable import Powerwall_TV

/// Fixtures are made up: no real VIN, token or location. `vehicle_data_cached` never sends
/// `drive_state` or location anyway.
enum VehicleInfoFixtures {
    static let charging = #"""
    {"response": {
      "id": 100021, "vehicle_id": 99999, "vin": "TESTVIN0000000001", "state": "online",
      "charge_state": {
        "battery_level": 80, "battery_range": 249.8, "charge_limit_soc": 90,
        "charging_state": "Charging", "charger_power": 11, "charge_rate": 29.8,
        "charge_energy_added": 18.4, "minutes_to_full_charge": 45, "timestamp": 1790000000000
      },
      "climate_state": {"inside_temp": 21.5, "outside_temp": 17.0, "is_climate_on": false, "timestamp": 1790000060000},
      "gui_settings": {"gui_distance_units": "km/hr", "gui_temperature_units": "C", "gui_tirepressure_units": "Bar"},
      "vehicle_state": {
        "locked": true, "sentry_mode": false, "odometer": 15320.4, "car_version": "2026.38.4 0a1b2c3d4e5f",
        "software_update": {"status": ""},
        "tpms_pressure_fl": 2.9, "tpms_pressure_fr": 2.9, "tpms_pressure_rl": 2.8, "tpms_pressure_rr": 2.9,
        "timestamp": 1790000120000
      }
    }}
    """#

    /// A parked US car with some blocks missing and nulls where Fleet has nothing.
    static let sparse = #"""
    {"response": {
      "state": "asleep",
      "charge_state": {"battery_level": 54, "battery_range": 180.0, "charge_limit_soc": null,
        "charging_state": "Disconnected", "charger_power": 0, "charge_rate": 0, "charge_energy_added": 3.2,
        "minutes_to_full_charge": 0, "timestamp": 1790000000000},
      "gui_settings": {"gui_distance_units": "mi/hr", "gui_temperature_units": "F", "gui_tirepressure_units": "Psi"},
      "vehicle_state": {"locked": false, "sentry_mode": true, "odometer": null, "car_version": null,
        "tpms_pressure_fl": 2.9, "tpms_pressure_fr": null, "tpms_pressure_rl": 2.8, "tpms_pressure_rr": 2.9,
        "software_update": {"status": "available"}}
    }}
    """#
}

struct VehicleInfoTests {
    @Test func parsesTheCachedChargingFixture() throws {
        let info = try VehicleInfo.parse(Data(VehicleInfoFixtures.charging.utf8))
        #expect(info.batteryLevel == 80)
        #expect(info.isCharging)
        #expect(info.chargeLimitPercent == 90)
        #expect(info.tyrePressuresBar == [2.9, 2.9, 2.8, 2.9])
        #expect(info.usesMiles == false && info.usesFahrenheit == false && info.usesPSI == false)
        #expect(info.reportedAt == Date(timeIntervalSince1970: 1_790_000_120))

        let now = Date(timeIntervalSince1970: 1_790_000_120 + 4 * 60)
        let rows = info.rows(now: now)
        #expect(rows.map(\.id) == ["range", "limit", "rate", "added", "temperature", "lock", "tyres", "odometer", "software", "updated"])
        let text = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.text) })
        #expect(text["range"] == "402 km range")
        #expect(text["limit"] == "Charge limit 90%")
        #expect(text["rate"] == "11 kW · +48 km/h")
        #expect(text["added"] == "18.4 kWh added")
        #expect(text["temperature"] == "Inside 22° · Outside 17°")
        #expect(text["lock"] == "Locked")
        #expect(text["tyres"] == "Tyres 2.9 · 2.9 · 2.8 · 2.9 bar")
        #expect(text["odometer"] == "24,656 km")
        #expect(text["software"] == "Software 2026.38.4")
        #expect(text["updated"] == "Updated 4 min ago")
        #expect(rows.first { $0.id == "rate" }?.symbol == "ev.charger")
        // Battery and charging state are on the title lines, not repeated in the panel.
        #expect(!rows.contains { $0.text.contains("% battery") })
    }

    @Test func missingFieldsHideTheirRows() throws {
        let info = try VehicleInfo.parse(Data(VehicleInfoFixtures.sparse.utf8))
        let rows = info.rows(now: Date(timeIntervalSince1970: 1_790_000_000 + 3 * 3600))
        let ids = rows.map(\.id)
        #expect(ids == ["range", "lock", "sentry", "update", "updated"])
        let text = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.text) })
        #expect(text["range"] == "180 mi range")
        #expect(text["lock"] == "Unlocked")
        #expect(rows.first { $0.id == "lock" }?.symbol == "lock.open.fill")
        #expect(text["update"] == "Update available")
        #expect(text["updated"] == "Updated 3 h ago")
        // No charger power while unplugged, no half tyre set, no climate block.
        #expect(info.tyrePressuresBar == nil)
        #expect(info.insideCelsius == nil)
    }

    @Test func unitsFollowTheCarsDisplaySettings() {
        let info = VehicleInfo(insideCelsius: 20, tyrePressuresBar: [2.9, 2.9, 2.9, 2.9], usesFahrenheit: true, usesPSI: true)
        let text = Dictionary(uniqueKeysWithValues: info.rows().map { ($0.id, $0.text) })
        #expect(text["temperature"] == "Inside 68°")
        #expect(text["tyres"] == "Tyres 42 · 42 · 42 · 42 psi")
        #expect(VehicleInfo().rows().isEmpty)
    }

    @Test func statusCodesMapToOutcomes() {
        let ok = Data(VehicleInfoFixtures.charging.utf8)
        if case .fresh(let info) = VehicleInfoFetchOutcome.classify(statusCode: 200, data: ok) {
            #expect(info.batteryLevel == 80)
        } else {
            #expect(Bool(false))
        }
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 200, data: Data("{}".utf8)) == .failed)
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 408, data: Data()) == .asleep)
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 429, data: Data(), retryAfterHeader: "120") == .rateLimited(retryAfter: 120))
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 429, data: Data()) == .rateLimited(retryAfter: nil))
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 404, data: Data()) == .unavailable)
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 412, data: Data()) == .unavailable)
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 401, data: Data()) == .unauthorized)
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 403, data: Data()) == .forbidden)
        #expect(VehicleInfoFetchOutcome.classify(statusCode: 503, data: Data()) == .failed)
    }

    @Test func throttleWaitsBacksOffAndCaps() {
        let policy = VehicleInfoRefreshPolicy()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var state = VehicleInfoRefreshState()
        #expect(policy.shouldFetch(state, now: start))

        let parked = VehicleInfo(chargingState: "Disconnected", reportedAt: start)
        state = policy.record(.fresh(parked), into: state, at: start)
        #expect(!policy.shouldFetch(state, now: start.addingTimeInterval(9 * 60)))
        #expect(policy.shouldFetch(state, now: start.addingTimeInterval(10 * 60)))

        // The car slept and reported nothing new: 20, then 40, then capped at 60 minutes.
        var now = start.addingTimeInterval(10 * 60)
        state = policy.record(.fresh(parked), into: state, at: now)
        #expect(policy.nextAllowedAt(state) == now.addingTimeInterval(20 * 60))
        now = now.addingTimeInterval(20 * 60)
        state = policy.record(.fresh(parked), into: state, at: now)
        #expect(policy.nextAllowedAt(state) == now.addingTimeInterval(40 * 60))
        for _ in 0..<5 {
            now = now.addingTimeInterval(60 * 60)
            state = policy.record(.fresh(parked), into: state, at: now)
        }
        #expect(policy.nextAllowedAt(state) == now.addingTimeInterval(60 * 60))

        // New data while charging resets the backoff to the 5-minute charging interval.
        now = now.addingTimeInterval(60 * 60)
        let charging = VehicleInfo(chargingState: "Charging", reportedAt: now)
        state = policy.record(.fresh(charging), into: state, at: now)
        #expect(state.unchangedStreak == 0)
        #expect(policy.nextAllowedAt(state) == now.addingTimeInterval(5 * 60))
    }

    @Test func asleepRateLimitAndErrorsBlock() {
        let policy = VehicleInfoRefreshPolicy()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let base = VehicleInfoRefreshState()

        let asleep = policy.record(.asleep, into: base, at: now)
        #expect(!policy.shouldFetch(asleep, now: now.addingTimeInterval(29 * 60)))
        #expect(policy.shouldFetch(asleep, now: now.addingTimeInterval(30 * 60)))

        let limited = policy.record(.rateLimited(retryAfter: 3600), into: base, at: now)
        #expect(policy.nextAllowedAt(limited) == now.addingTimeInterval(3600))
        let limitedShort = policy.record(.rateLimited(retryAfter: 5), into: base, at: now)
        #expect(policy.nextAllowedAt(limitedShort) == now.addingTimeInterval(15 * 60))

        #expect(policy.nextAllowedAt(policy.record(.unavailable, into: base, at: now)) == now.addingTimeInterval(6 * 3600))
        #expect(policy.nextAllowedAt(policy.record(.forbidden, into: base, at: now)) == now.addingTimeInterval(24 * 3600))

        var failing = policy.record(.failed, into: base, at: now)
        #expect(policy.nextAllowedAt(failing) == now.addingTimeInterval(10 * 60))
        failing = policy.record(.failed, into: failing, at: now)
        #expect(failing.failureStreak == 2)
        #expect(policy.nextAllowedAt(failing) == now.addingTimeInterval(10 * 60))
        for _ in 0..<6 { failing = policy.record(.unauthorized, into: failing, at: now) }
        #expect(policy.nextAllowedAt(failing) == now.addingTimeInterval(60 * 60))
    }

    @Test func dailyCallLimitStopsFetching() {
        let policy = VehicleInfoRefreshPolicy(chargingInterval: 1, dailyCallLimit: 3)
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        var state = VehicleInfoRefreshState()
        var calls = 0
        for minute in 0..<120 {
            now = Date(timeIntervalSince1970: 1_790_000_000 + Double(minute) * 60)
            guard policy.shouldFetch(state, now: now) else { continue }
            calls += 1
            state = policy.record(.fresh(VehicleInfo(chargingState: "Charging", reportedAt: now)), into: state, at: now)
        }
        #expect(calls == 3)
        #expect(policy.shouldFetch(state, now: Date(timeIntervalSince1970: 1_790_000_000 + 24 * 3600)))
    }

    @Test func demoPanelUsesSampleDataAndMatchesTheTitleLine() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let info = DemoHouseTour.exampleInfo(now: now)
        #expect(info.chargeSnapshot.batteryLevel == DemoHouseTour.exampleCharge.batteryLevel)
        #expect(info.chargingState == DemoHouseTour.exampleCharge.chargingState)
        let rows = info.rows(now: now)
        #expect(rows.count >= 8)
        #expect(rows.last?.text == "Updated 4 min ago")
        #expect(CarShowroom.statLines(displayName: "Vehicle", exteriorColor: nil, snapshot: info.chargeSnapshot)
            .contains("80% battery · Charging"))
    }
}
