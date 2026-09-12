import Foundation
import Testing
@testable import Powerwall_TV

struct ExportEstimateTests {
    @Test func includesGeneratorEnergyInFleetHomeConsumption() throws {
        let json = Data(#"{"timestamp":"2026-09-11T00:00:00Z","consumer_energy_imported_from_grid":10,"consumer_energy_imported_from_solar":20,"consumer_energy_imported_from_battery":30,"consumer_energy_imported_from_generator":40}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bucket = try decoder.decode(ExportEnergyBucket.self, from: json)
        #expect(bucket.homeWh == 100)
    }

    @Test func decodesFleetInstallationTimeZoneWithoutCoordinates() throws {
        let json = Data(#"{"response":{"installation_time_zone":"Australia/Adelaide","battery_count":2,"backup_reserve_percent":20,"nameplate_energy":27000}}"#.utf8)
        let site = try JSONDecoder().decode(ExportAdvisorService.SitePayload.self, from: json).response
        #expect(site.timeZoneIdentifier == "Australia/Adelaide")
        #expect(site.latitude == nil)
        #expect(site.battery_count == 2)
    }

    @Test func requiresForecastForWholeOvernightAndTomorrow() {
        let hour = Date(timeIntervalSince1970: 0)
        let dates = (0..<30).map { hour.addingTimeInterval(Double($0) * 3600) }
        let start = hour.addingTimeInterval(1800)
        let end = hour.addingTimeInterval(30 * 3600)
        #expect(ExportForecastCoverage.isComplete(dates: dates, from: start, through: end))
        #expect(!ExportForecastCoverage.isComplete(dates: Array(dates.dropFirst()), from: start, through: end))
        #expect(!ExportForecastCoverage.isComplete(dates: Array(dates.dropLast()), from: start, through: end))
        #expect(!ExportForecastCoverage.isComplete(dates: dates.enumerated().filter { $0.offset != 8 }.map(\.element), from: start, through: end))
    }

    @Test func keychainCanSaveReplaceAndRemoveOnlyTemporaryKey() {
        let key = "export-advisor-test-" + UUID().uuidString
        defer { KeychainWrapper.standard.set("", forKey: key) }
        #expect(KeychainWrapper.standard.set("first", forKey: key))
        #expect(KeychainWrapper.standard.string(forKey: key) == "first")
        #expect(KeychainWrapper.standard.set("replacement", forKey: key))
        #expect(KeychainWrapper.standard.string(forKey: key) == "replacement")
        #expect(KeychainWrapper.standard.set("", forKey: key))
        #expect(KeychainWrapper.standard.string(forKey: key) == nil)
    }

    @Test func capacityAndReserveScaleAcrossPowerwalls() throws {
        let result = try ExportBatteryBudget(capacityKWh: 27, chargePercent: 80, reservePercent: 20, demandKWh: 6)
        #expect(abs(result.exportKWh - 10.2) < 0.0001)
        #expect(abs(result.exportPercent - 37.7777778) < 0.0001)
        let depleted = try ExportBatteryBudget(capacityKWh: 27, chargePercent: 10, reservePercent: 20, demandKWh: 6)
        #expect(depleted.exportKWh == 0)
    }

    @Test func rejectsInvalidBatteryData() {
        #expect(throws: ExportEstimateError.self) {
            try ExportBatteryBudget(capacityKWh: .nan, chargePercent: 80, reservePercent: 20, demandKWh: 6)
        }
    }

    @Test func energyBucketsAreSummedAndProratedWithoutMultiplyingByHours() {
        let start = Date(timeIntervalSince1970: 0)
        let buckets = (0..<12).map { index in
            ExportEnergyBucket(timestamp: start.addingTimeInterval(Double(index) * 300), consumerEnergy: 100, grid: nil, solar: nil, battery: nil)
        }
        let full = ExportUsageWindow.consumption(in: DateInterval(start: start, duration: 3600), buckets: buckets)
        #expect(full == 1.2)
        let partial = ExportUsageWindow.consumption(in: DateInterval(start: start.addingTimeInterval(150), duration: 300), buckets: buckets)
        #expect(partial == 0.1)
        #expect(ExportUsageWindow.consumption(in: DateInterval(start: start, duration: 3600), buckets: Array(buckets.dropFirst())) == nil)
    }

    @Test func missingEnergyDoesNotBecomeZero() {
        let start = Date(timeIntervalSince1970: 0)
        let bucket = ExportEnergyBucket(timestamp: start, consumerEnergy: nil, grid: 10, solar: nil, battery: 5)
        #expect(ExportUsageWindow.consumption(in: DateInterval(start: start, duration: 300), buckets: [bucket]) == nil)
    }

    @Test func historicalWindowsHaveFinishedAndPreserveSiteClockAcrossDST() throws {
        let zone = TimeZone(identifier: "Australia/Adelaide")!
        let now = ISO8601DateFormatter().date(from: "2026-10-04T08:30:00Z")!
        let window = try ExportUsageWindow(now: now, timeZone: zone, morningEndHour: 10)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(window.historical.count == 5)
        #expect(calendar.component(.hour, from: window.interval.end) == 10)
        for past in window.historical {
            #expect(past.end <= now)
            #expect(calendar.component(.hour, from: past.start) == calendar.component(.hour, from: now))
            #expect(calendar.component(.hour, from: past.end) == 10)
        }
    }
}
