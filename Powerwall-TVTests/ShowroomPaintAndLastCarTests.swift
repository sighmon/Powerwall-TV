import Foundation
import SceneKit
import Testing
import simd
@testable import Powerwall_TV

/// Serves synthetic `vehicle_data_cached` bodies. VINs follow the demo pattern; no real account data.
private final class CachedDataProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var body = Data()
    @MainActor static var paths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            Self.paths.append(request.url!.path)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private let carA = "5YJYGDEE5LF000001"
private let carB = "5YJ3GDEE5RF000001"
private let carC = "5YJSA1E25MF000001"

private func cachedBody(exterior: String?, timestamp: Int = 1_700_000_000_000) -> Data {
    let config = exterior.map { #","vehicle_config":{"exterior_color":"\#($0)","car_type":"modely"}"# } ?? ""
    return Data(#"{"response":{"state":"online","charge_state":{"battery_level":64,"charging_state":"Stopped","timestamp":\#(timestamp)}\#(config)}}"#.utf8)
}

@MainActor
@Suite(.serialized)
struct ShowroomPaintAndLastCarTests {
    private func appearance(_ exterior: String?, override: String? = nil, carType: String? = nil) -> VehicleAppearance {
        VehicleAppearance(exteriorColor: exterior, paintColorOverride: override, colorizerRemap: false, carType: carType)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "ShowroomLastCarTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: Paint names and codes

    @Test func paintNamesAndOptionCodesResolveToTheAppTable() {
        #expect(TeslaPaint(exteriorColor: "StealthGrey")?.name == "StealthGrey")
        #expect(TeslaPaint(exteriorColor: "Stealth Gray")?.name == "StealthGrey")
        #expect(TeslaPaint(exteriorColor: "pearl_white_multi-coat")?.name == "PearlWhite")
        #expect(TeslaPaint(exteriorColor: "Deep Blue Metallic")?.name == "DeepBlue")
        #expect(TeslaPaint(exteriorColor: "MIDNIGHT CHERRY RED")?.name == "MidnightCherryRed")
        for name in ["Quicksilver", "UltraRed", "GlacierBlue", "DiamondBlack", "LunarSilver", "MarineBlue", "CoastalBlue", "FrostBlue"] {
            #expect(TeslaPaint(exteriorColor: name)?.name == name)
        }
        #expect(TeslaPaint(exteriorColor: "StainlessSteel") == nil)

        #expect(TeslaPaint.exteriorColor(optionCodes: "AD15,MDL3,PN01,W40B") == "StealthGrey")
        #expect(TeslaPaint.exteriorColor(optionCodes: "ppsw") == "PearlWhite")
        #expect(TeslaPaint.exteriorColor(optionCodes: "MDL3,W40B") == nil)
        #expect(TeslaPaint.exteriorColor(productColor: "PR01", optionCodes: nil) == "UltraRed")
        #expect(TeslaPaint.exteriorColor(productColor: "Glacier Blue", optionCodes: "PPSW") == "GlacierBlue")
        #expect(TeslaPaint.exteriorColor(productColor: nil, optionCodes: "PX02") == "DiamondBlack")
        let codes = ["PPSW": "PearlWhite", "PMNG": "MidnightSilver", "PN01": "StealthGrey", "PPSB": "DeepBlue",
                     "PR01": "UltraRed", "PPMR": "RedMulticoat", "PBSB": "SolidBlack", "PN00": "Quicksilver",
                     "PR00": "MidnightCherryRed", "PB01": "GlacierBlue", "PB02": "MarineBlue", "PX02": "DiamondBlack"]
        for (code, name) in codes {
            #expect(TeslaPaint.optionCodes[code] == name)
        }
        #expect(TeslaPaint.optionCodes.values.allSatisfy { TeslaPaint.table[$0] != nil })
        #expect(TeslaPaint.table.keys.allSatisfy { TeslaPaint.demoDisplayHex[$0] != nil })
    }

    @Test func productsCarriesColourAndOptionCodesIntoTheCar() throws {
        let body = Data(#"""
        {"response":[
          {"vin":"5YJYGDEE5LF000001","display_name":"A","color":null,"option_codes":"AD15,MDL3,PB01,W40B"},
          {"vin":"5YJ3GDEE5RF000001","display_name":"B","color":"UltraRed"},
          {"vin":"5YJSA1E25MF000001","display_name":"C"}
        ]}
        """#.utf8)
        let vehicles = try ProductsResponse.vehicles(from: body)
        #expect(vehicles.map(\.paintName) == ["GlacierBlue", "UltraRed", nil])
        let merged = vehicles[0].merging(FleetVehicle(vin: carA, displayName: nil, state: "online"))
        #expect(merged.paintName == "GlacierBlue")
    }

    @Test func cachedVehicleDataCarriesVehicleConfigPaint() throws {
        let info = try VehicleInfo.parse(cachedBody(exterior: "UltraRed"))
        #expect(info.appearance?.exteriorColor == "UltraRed")
        #expect(info.appearance?.carType == "modely")
        #expect(try VehicleInfo.parse(cachedBody(exterior: nil)).appearance == nil)
        // Cached panel copies saved before this field existed still decode.
        let old = try JSONDecoder().decode(VehicleInfo.self, from: Data(#"{"batteryLevel":50}"#.utf8))
        #expect(old.appearance == nil)
    }

    @Test func storedPaintMergesWithoutForgettingFields() {
        let stored = appearance("PearlWhite", carType: "modely")
        let newer = stored.merging(appearance("UltraRed"))
        #expect(newer.exteriorColor == "UltraRed")
        #expect(newer.carType == "modely")
        let wrapped = appearance("PearlWhite", override: "10,20,30,0.5,0.1").merging(appearance(nil, carType: "modely"))
        #expect(wrapped.paintColorOverride == "10,20,30,0.5,0.1")
        #expect(appearance("PearlWhite", override: "10,20,30,0.5,0.1").merging(appearance("DeepBlue")).paintColorOverride == nil)
    }

    // MARK: Paint priority and stepping

    @Test func paintComesFromVehicleConfigThenProductsThenTheFile() {
        let vehicles = [
            FleetVehicle(vin: carA, displayName: "A", state: nil, color: nil, optionCodes: "MDL3,PN01"),
            FleetVehicle(vin: carB, displayName: "B", state: nil, color: nil, optionCodes: "PPSW"),
            FleetVehicle(vin: carC, displayName: "C", state: nil),
        ]
        let appearances = [carA: appearance("UltraRed"), carC: appearance(nil, carType: "models")]
        #expect(CarShowroom.paintSource(vin: carA, appearances: appearances, vehicles: vehicles)?.exteriorColor == "UltraRed")
        #expect(CarShowroom.paintSource(vin: carB, appearances: appearances, vehicles: vehicles)?.exteriorColor == "PearlWhite")
        #expect(CarShowroom.paintSource(vin: carC, appearances: appearances, vehicles: vehicles) == nil)
        #expect(CarShowroom.paintSource(vin: carA.lowercased(), appearances: appearances, vehicles: vehicles)?.exteriorColor == "UltraRed")

        let lineup = CarShowroom.select(
            data: nil, fallbackVIN: "", appearances: appearances, solar: .panels,
            vehicles: vehicles, charges: [:], displayBoost: 4, isDemoMode: false
        ).lineup
        #expect(ShowroomPaint.resolve(for: lineup[0]) == .named(TeslaPaint.table["UltraRed"]!.display))
        #expect(ShowroomPaint.resolve(for: lineup[1]) == .named(TeslaPaint.table["PearlWhite"]!.display))
        #expect(ShowroomPaint.resolve(for: lineup[2]) == .file)
        #expect(lineup[0].lines.first == "A · Ultra Red")
        #expect(lineup[1].lines.first == "B · Pearl White")
        // Catalogue cars keep their own file colours and glows, never an owned car's paint.
        for car in lineup.dropFirst(3) {
            #expect(car.exteriorColor == nil && car.paintColorOverride == nil)
            #expect(ShowroomPaint.resolve(for: car) == .file)
            let glow = ShowroomStage.highlight(for: car)
            #expect(simd_length(glow - ShowroomStage.rgb(ShowroomStage.highlightTable[ShowroomStage.fileHighlightName(for: car.model)]!)) < 0.001)
        }
    }

    @Test func steppingBetweenCarsUsesEachCarsOwnPaintAndGlow() {
        let vehicles = [FleetVehicle(vin: carA, displayName: "A", state: nil), FleetVehicle(vin: carB, displayName: "B", state: nil)]
        let appearances = [carA: appearance("UltraRed"), carB: appearance("DeepBlue")]
        let request = CarShowroom.select(
            data: nil, fallbackVIN: "", appearances: appearances, solar: .panels,
            vehicles: vehicles, charges: [:], displayBoost: 4, isDemoMode: false
        )
        let count = request.lineup.count
        let path = [0, 1, 2, count, 1, 0]
        let glows = path.map { ShowroomStage.highlight(for: CarShowroom.entry(in: request, at: $0)) }
        #expect(simd_length(glows[0] - ShowroomStage.rgb(0xf03042)) < 0.001)
        #expect(simd_length(glows[1] - ShowroomStage.rgb(0x1667ee)) < 0.001)
        #expect(simd_length(glows[3] - glows[0]) < 0.001)
        #expect(simd_length(glows[4] - glows[1]) < 0.001)
        #expect(simd_length(glows[5] - glows[0]) < 0.001)
        #expect(simd_length(glows[0] - glows[1]) > 0.1)
        #expect(CarShowroom.entry(in: request, at: 2).browsesCatalogue)
        // Named paints draw their display colour at boost 1, so white reads white.
        guard case .named(let red) = ShowroomPaint.resolve(for: CarShowroom.entry(in: request, at: 0)) else {
            Issue.record("Car A should be a named paint")
            return
        }
        #expect(red.hex == TeslaPaint.demoDisplayHex["UltraRed"])
    }

    @Test func paintThatArrivesWhileOpenRepaintsTheCarAndItsGlow() {
        let vehicles = [FleetVehicle(vin: carA, displayName: "A", state: nil)]
        let request = CarShowroom.select(
            data: nil, fallbackVIN: "", appearances: [:], solar: .panels,
            vehicles: vehicles, charges: [:], displayBoost: 4, isDemoMode: false
        )
        let before = CarShowroom.entry(in: request, at: 0)
        #expect(ShowroomPaint.resolve(for: before) == .file)
        let after = CarShowroom.repainted(before, appearances: [carA: appearance("UltraRed")], vehicles: vehicles)
        #expect(after.exteriorColor == "UltraRed")
        #expect(after.lines.first == "A · Ultra Red")
        #expect(after != before)
        #expect(simd_length(ShowroomStage.highlight(for: after) - ShowroomStage.rgb(0xf03042)) < 0.001)
        let again = CarShowroom.repainted(after, appearances: [carA: appearance("GlacierBlue")], vehicles: vehicles)
        #expect(again.lines.first == "A · Glacier Blue")
        let catalogue = CarShowroom.entry(in: request, at: 1)
        #expect(CarShowroom.repainted(catalogue, appearances: [carA: appearance("UltraRed")], vehicles: vehicles) == catalogue)
    }

    @Test func cachedVehicleDataStoresPaintPerVINAndRepaints() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CachedDataProtocol.self]
        CachedDataProtocol.paths = []
        CachedDataProtocol.body = cachedBody(exterior: "UltraRed")
        let model = PowerwallViewModel(fleetURLSession: URLSession(configuration: configuration))
        model.ipAddress = "gateway.example"
        model.loginMode = .fleetAPI
        model.accessToken = "test-only"
        model.clearVehicleChargeCache()
        model.clearVehicleAppearanceCache()
        defer {
            model.clearVehicleChargeCache()
            model.clearVehicleAppearanceCache()
        }
        model.refreshVehicleInfoIfDue(vin: carA)
        for _ in 0..<100 where model.vehicleAppearances[carA] == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(CachedDataProtocol.paths == ["/api/1/vehicles/\(carA)/vehicle_data_cached"])
        #expect(model.vehicleAppearances[carA]?.exteriorColor == "UltraRed")
        #expect(model.vehicleAppearances[carA]?.carType == "modely")
        let saved = UserDefaults.standard.data(forKey: "fleetVehicleAppearanceCache")
            .flatMap { try? JSONDecoder().decode([String: VehicleAppearance].self, from: $0) }
        #expect(saved?[carA]?.exteriorColor == "UltraRed")
        let car = CarShowroom.repainted(
            CarShowroom.ownedRequest(vin: carA, appearances: [:], vehicles: [], charges: [:], displayBoost: 4),
            appearances: model.vehicleAppearances,
            vehicles: []
        )
        #expect(ShowroomPaint.resolve(for: car) == .named(TeslaPaint.table["UltraRed"]!.display))
    }

    @Test func showroomSceneDrawsANamedPaintInItsDisplayColour() {
        let car = CarShowroomRequest(
            vin: carA, model: .modelY, exteriorColor: "PearlWhite", paintColorOverride: nil,
            colorizerRemap: false, displayBoost: 4, lines: []
        )
        var paint: SCNMaterial?
        CarShowroom.scene(for: car).rootNode.enumerateHierarchy { node, stop in
            if let found = node.geometry?.materials.first(where: { $0.name == "Paint" }) {
                paint = found
                stop.pointee = true
            }
        }
        guard let colour = paint?.diffuse.contents as? HouseColor else {
            Issue.record("Model Y has no painted Paint material")
            return
        }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #if canImport(AppKit)
        let resolved = colour.usingColorSpace(.sRGB) ?? colour
        #else
        let resolved = colour
        #endif
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // 0xF3F0E8, not the app's 0x181818 albedo lifted to grey.
        #expect(abs(red - 0xF3 / 255) < 0.02)
        #expect(abs(blue - 0xE8 / 255) < 0.02)
    }

    // MARK: Last car shown

    @Test func lastCarIsAVINOrAModelNeverAnIndex() {
        let owned = CarShowroom.ownedRequest(vin: carA.lowercased(), appearances: [:], vehicles: [], charges: [:], displayBoost: 4)
        #expect(ShowroomLastCar.key(for: owned) == "vin:\(carA)")
        #expect(ShowroomLastCar.key(for: CarShowroom.catalogueRequest(index: 0)) == "model:\(CarShowroom.catalogueModels[0].rawValue)")
    }

    @Test func openingStartsOnTheLastCarWhenItIsStillThere() {
        let vehicles = [FleetVehicle(vin: carA, displayName: "A", state: nil), FleetVehicle(vin: carB, displayName: "B", state: nil)]
        func open(_ last: String?, vehicles: [FleetVehicle] = vehicles) -> CarShowroomRequest {
            CarShowroom.select(
                data: nil, fallbackVIN: "", appearances: [:], solar: .panels,
                vehicles: vehicles, charges: [:], displayBoost: 4, isDemoMode: false, lastCar: last
            )
        }
        let byVIN = open("vin:\(carB)")
        #expect(byVIN.startIndex == 1)
        #expect(CarShowroom.entry(in: byVIN, at: byVIN.startIndex).vin == carB)
        let model = CarShowroom.catalogueModels[2]
        let byModel = open("model:\(model.rawValue)")
        #expect(CarShowroom.entry(in: byModel, at: byModel.startIndex).model == model)
        #expect(CarShowroom.entry(in: byModel, at: byModel.startIndex).browsesCatalogue)
        // Gone from the account, or nothing saved: the usual first car.
        #expect(open("vin:\(carB)", vehicles: [vehicles[0]]).startIndex == 0)
        #expect(open(nil).startIndex == 0)
        #expect(open("garbage").startIndex == 0)
    }

    @Test func lastCarSavesLoadsSkipsDemoAndClears() {
        let defaults = freshDefaults()
        let owned = CarShowroom.ownedRequest(vin: carA, appearances: [:], vehicles: [], charges: [:], displayBoost: 4)
        ShowroomLastCar.save(owned, to: defaults, isDemoMode: false)
        #expect(ShowroomLastCar.load(from: defaults, isDemoMode: false) == "vin:\(carA)")
        // Demo neither overwrites nor reads the real saved car.
        ShowroomLastCar.save(CarShowroom.catalogueRequest(index: 3), to: defaults, isDemoMode: true)
        #expect(ShowroomLastCar.load(from: defaults, isDemoMode: false) == "vin:\(carA)")
        #expect(ShowroomLastCar.load(from: defaults, isDemoMode: true) == nil)
        ShowroomLastCar.save(CarShowroom.catalogueRequest(index: 3), to: defaults, isDemoMode: false)
        #expect(ShowroomLastCar.load(from: defaults, isDemoMode: false) == "model:\(CarShowroom.catalogueModels[3].rawValue)")
        ShowroomLastCar.clear(defaults)
        #expect(ShowroomLastCar.load(from: defaults, isDemoMode: false) == nil)
    }
}
