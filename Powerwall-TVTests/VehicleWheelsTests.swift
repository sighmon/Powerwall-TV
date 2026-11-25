import Foundation
import SceneKit
import Testing
import simd
@testable import Powerwall_TV

/// Serves one synthetic `vehicle_data` body. VINs follow the demo pattern; no real account data.
private final class WheelDataProtocol: URLProtocol, @unchecked Sendable {
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

private let carY = "5YJYGDEE5LF000001"
private let car3 = "5YJ3GDEE5NF000001"

@MainActor
@Suite(.serialized)
struct VehicleWheelsTests {
    private func owned(_ model: VehicleModel, vin: String, wheelType: String?) -> CarShowroomRequest {
        CarShowroomRequest(
            vin: vin, model: model, exteriorColor: nil, paintColorOverride: nil, colorizerRemap: false,
            displayBoost: 4, lines: ["Vehicle"], wheelType: wheelType
        )
    }

    private func vehicle(in scene: SCNScene) throws -> SCNNode {
        try #require(scene.rootNode.childNode(withName: "Vehicle", recursively: false))
    }

    private func lowestWheelPoint(under node: SCNNode) -> Float {
        var lowest = Float.greatestFiniteMagnitude
        node.enumerateHierarchy { child, _ in
            guard child.name?.hasPrefix(VehicleWheels.mountPrefix) == true else { return }
            child.enumerateHierarchy { mesh, _ in
                guard let box = mesh.geometry?.boundingBox else { return }
                for x in [box.min.x, box.max.x] {
                    for y in [box.min.y, box.max.y] {
                        for z in [box.min.z, box.max.z] {
                            lowest = min(lowest, mesh.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: node).y)
                        }
                    }
                }
            }
        }
        return lowest
    }

    // MARK: Fleet data

    @Test func wheelTypeDecodesFromVehicleConfig() throws {
        let body = Data(#"{"response":{"vehicle_config":{"exterior_color":"PearlWhite","car_type":"modely","wheel_type":"Gemini19"}}}"#.utf8)
        let config = try JSONDecoder().decode(VehicleDataResponse.self, from: body).response.vehicleConfig
        #expect(config?.wheelType == "Gemini19")
        #expect(VehicleAppearance(vehicleConfig: config, colorizerRemap: false).wheelType == "Gemini19")

        let none = try JSONDecoder().decode(VehicleDataResponse.self, from: Data(#"{"response":{"vehicle_config":{"car_type":"modely"}}}"#.utf8))
        // Read and empty is "", so the car is not asked again just for wheels.
        #expect(VehicleAppearance(vehicleConfig: none.response.vehicleConfig, colorizerRemap: false).wheelType == "")
        #expect(VehicleAppearance(vehicleConfig: nil, colorizerRemap: false).wheelType == nil)

        let cached = try VehicleInfo.parse(Data(#"{"response":{"state":"online","vehicle_config":{"car_type":"model3","wheel_type":"Pinwheel18CapKit"}}}"#.utf8))
        #expect(cached.appearance?.wheelType == "Pinwheel18CapKit")
    }

    @Test func savedWheelsMigrateMergeAndSurviveReload() throws {
        // A cache written before wheels has no key: it decodes as not known yet.
        let old = try JSONDecoder().decode(VehicleAppearance.self, from: Data(#"{"exteriorColor":"Red","colorizerRemap":false}"#.utf8))
        #expect(old.wheelType == nil)
        #expect(!old.wheelsKnown)
        let named = old.merging(VehicleAppearance(exteriorColor: nil, paintColorOverride: nil, colorizerRemap: false, carType: nil, wheelType: "Gemini19"))
        #expect(named.wheelType == "Gemini19")
        #expect(named.exteriorColor == "Red")
        let blank = VehicleAppearance(exteriorColor: nil, paintColorOverride: nil, colorizerRemap: false, carType: nil, wheelType: "")
        #expect(named.merging(blank).wheelType == "Gemini19")
        #expect(old.merging(blank).wheelType == "")
        #expect(blank.hasUsefulData)
        let reloaded = try JSONDecoder().decode(VehicleAppearance.self, from: JSONEncoder().encode(named))
        #expect(reloaded == named)
    }

    @Test func policyBackfillsWheelsOnceForACarSavedBeforeThem() {
        let policy = VehiclePaintFetchPolicy()
        let now = Date()
        #expect(policy.shouldFetch(hasPaint: true, wheelsKnown: false, inFlight: false, blockedUntil: nil, now: now))
        #expect(!policy.shouldFetch(hasPaint: true, wheelsKnown: true, inFlight: false, blockedUntil: nil, now: now))
        #expect(!policy.shouldFetch(hasPaint: true, wheelsKnown: false, inFlight: true, blockedUntil: nil, now: now))
        #expect(!policy.shouldFetch(hasPaint: true, wheelsKnown: false, inFlight: false, blockedUntil: now.addingTimeInterval(60), now: now))
    }

    @Test func oldCacheEntryIsAskedOnceThenSavedEvenWithNoWheelType() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WheelDataProtocol.self]
        WheelDataProtocol.paths = []
        WheelDataProtocol.body = Data(#"{"response":{"vehicle_config":{"exterior_color":"StealthGrey","car_type":"modely","wheel_type":"Induction20Black"}}}"#.utf8)
        let model = PowerwallViewModel(fleetURLSession: URLSession(configuration: configuration))
        model.ipAddress = "gateway.example"
        model.loginMode = .fleetAPI
        model.accessToken = "test-only"
        model.clearVehicleAppearanceCache()
        defer { model.clearVehicleAppearanceCache() }
        // Paint saved by an earlier build, no wheels.
        model.rememberVehicleAppearance(
            VehicleAppearance(exteriorColor: "StealthGrey", paintColorOverride: nil, colorizerRemap: false, carType: "modely"),
            for: carY
        )
        #expect(model.vehicleAppearances[carY]?.wheelsKnown == false)
        model.fetchVehiclePaintIfNeeded(vin: carY)
        for _ in 0..<100 where model.vehicleAppearances[carY]?.wheelType == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(WheelDataProtocol.paths == ["/api/1/vehicles/\(carY)/vehicle_data"])
        #expect(model.vehicleAppearances[carY]?.wheelType == "Induction20Black")
        #expect(model.vehicleAppearances[carY]?.exteriorColor == "StealthGrey")
        model.fetchVehiclePaintIfNeeded(vin: carY)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(WheelDataProtocol.paths.count == 1)

        // A reply with no wheel_type still settles it.
        WheelDataProtocol.body = Data(#"{"response":{"vehicle_config":{"exterior_color":"PearlWhite","car_type":"model3"}}}"#.utf8)
        model.rememberVehicleAppearance(
            VehicleAppearance(exteriorColor: "PearlWhite", paintColorOverride: nil, colorizerRemap: false, carType: "model3"),
            for: car3
        )
        model.fetchVehiclePaintIfNeeded(vin: car3)
        for _ in 0..<100 where model.vehicleAppearances[car3]?.wheelType == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(model.vehicleAppearances[car3]?.wheelType == "")
        model.fetchVehiclePaintIfNeeded(vin: car3)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(WheelDataProtocol.paths.count == 2)

        // Demo never calls.
        model.clearVehicleAppearanceCache()
        model.ipAddress = "demo"
        model.fetchVehiclePaintIfNeeded(vin: carY)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(WheelDataProtocol.paths.count == 2)
    }

    @Test func resetForgetsSavedWheels() {
        let model = PowerwallViewModel()
        model.rememberVehicleAppearance(
            VehicleAppearance(exteriorColor: nil, paintColorOverride: nil, colorizerRemap: false, carType: nil, wheelType: "Gemini19"),
            for: carY
        )
        #expect(model.vehicleAppearances[carY]?.wheelType == "Gemini19")
        model.clearVehicleAppearanceCache()
        #expect(model.vehicleAppearances.isEmpty)
        #expect(UserDefaults.standard.data(forKey: "fleetVehicleAppearanceCache") == nil)
    }

    // MARK: Mapping

    @Test func fleetNamesMapWithoutCaseToTheAppsWheels() {
        func asset(_ type: String?, _ model: VehicleModel, capsOn: Bool = true) -> String? {
            WheelChoice.resolve(wheelType: type, model: model, capsOn: capsOn)?.asset
        }
        #expect(asset("Gemini19", .modelY) == "Wheel_Gemini")
        #expect(asset("GEMINI19", .modelY) == "Wheel_Gemini")
        #expect(asset("gemini_19", .modelY) == "Wheel_Gemini")
        // Caps or covers off: Tesla's CapKit names and a caps-off flag.
        #expect(asset("Pinwheel18CapKit", .model3) == "Wheel_Pinwheel_No_Cap")
        #expect(asset("Pinwheel18", .model3) == "Wheel_Pinwheel")
        #expect(asset("Gemini19", .modelY, capsOn: false) == "Wheel_Gemini_No_Caps")
        #expect(asset("Glider18CapKit", .model3Highland) == "Wheel_Glider_No_Caps")
        // Finishes.
        #expect(asset("Induction20Black", .modelY) == "Wheel_Induction")
        #expect(asset("Nova19Dark", .model3Highland) == "Wheel_D33_Dark_Nova_19")
        #expect(asset("Tempest19SonicSilver", .modelS) == "Wheel_Tempest_Sonic_Silver")
        #expect(asset("Turbine22Dark", .modelX) == "Wheel_Turbine_Onyx_Black")
        #expect(asset("CTPremium20", .cybertruck) == "Wheel_Cybertruck_Premium")
        // Unknown, blank and missing fall back to the model's standard wheel.
        for (type, model) in [("UNKNOWN", VehicleModel.modelY), ("", .modelY), ("NotAWheel", .modelS)] {
            let choice = WheelChoice.resolve(wheelType: type, model: model)
            #expect(choice?.source == .standard)
            #expect(choice?.wheel == TeslaWheel.standard(for: model))
        }
        #expect(WheelChoice.resolve(wheelType: nil, model: .model3)?.asset == "Wheel_Pinwheel")
        // Cybertruck wheels only fit the Cybertruck.
        #expect(asset("Gemini19", .cybertruck) == "Wheel_Cybertruck_Standard")
        #expect(asset("CTPremium20", .model3) == "Wheel_Pinwheel")
        #expect(WheelChoice.resolve(wheelType: "Gemini19", model: .generic) == nil)
        for model in VehicleModel.allCases where model != .generic {
            #expect(TeslaWheel.standard(for: model) != nil)
        }
    }

    @Test func everyWheelAndCarFileIsInTheApp() {
        var missing: [String] = []
        for wheel in TeslaWheel.allCases {
            for asset in wheel.assets where HouseLighting.resourceURL(name: asset, ext: "usdz") == nil {
                missing.append(asset)
            }
        }
        #expect(missing.isEmpty, "missing \(missing)")
        for model in CarShowroom.catalogueModels {
            guard let url = HouseLighting.resourceURL(name: model.rawValue, ext: "usdz"),
                  let scene = try? SCNScene(url: url, options: nil) else {
                Issue.record("\(model.rawValue).usdz did not load")
                continue
            }
            for name in VehicleWheels.anchorNames {
                #expect(scene.rootNode.childNode(withName: name, recursively: true) != nil, "\(model.rawValue) \(name)")
            }
            // Baked wheels are gone; only mounted ones draw.
            #expect(scene.rootNode.childNode(withName: "Wheels", recursively: true) == nil)
        }
    }

    // MARK: Mounting

    @Test func showroomCarAndItsMirrorWearTheCarsWheels() throws {
        for model in CarShowroom.catalogueModels {
            let request = owned(model, vin: carY, wheelType: nil)
            let scene = CarShowroom.scene(for: request)
            let car = try vehicle(in: scene)
            let expected = try #require(WheelChoice.resolve(for: request)).asset
            #expect(VehicleWheels.mountedAssets(on: car) == Array(repeating: expected, count: 4), "\(model.rawValue)")
            let mirror = try #require(scene.rootNode.childNode(withName: ShowroomStage.mirrorName, recursively: false))
            #expect(VehicleWheels.mountedAssets(on: mirror).count == 4)
            // The tyre sits on the floor: no floating, no sinking.
            let lowest = lowestWheelPoint(under: car)
            #expect(lowest > -0.02 && lowest < 0.01, "\(model.rawValue) tyre bottom \(lowest)")
        }
        let capsOff = CarShowroom.scene(for: owned(.model3, vin: car3, wheelType: "Pinwheel18CapKit"))
        #expect(VehicleWheels.mountedAssets(on: try vehicle(in: capsOff)).first == "Wheel_Pinwheel_No_Cap")
    }

    @Test func catalogueCarsKeepTheStandardWheels() throws {
        for index in CarShowroom.catalogueModels.indices {
            var request = CarShowroom.catalogueRequest(index: index)
            request.wheelType = "Induction20Black"
            let scene = CarShowroom.scene(for: request)
            let expected = TeslaWheel.standard(for: request.model)?.asset
            #expect(VehicleWheels.mountedAssets(on: try vehicle(in: scene)).first == expected)
        }
    }

    @Test func savedWheelTypeSwapsTheShowroomWheels() throws {
        let start = CarShowroom.ownedRequest(vin: carY, appearances: [:], vehicles: [], charges: [:], displayBoost: 4)
        #expect(start.wheelType == nil)
        let saved = [carY: VehicleAppearance(exteriorColor: nil, paintColorOverride: nil, colorizerRemap: false, carType: "modely", wheelType: "Induction20Black")]
        // No paint known: the wheels still follow.
        let swapped = CarShowroom.repainted(start, appearances: saved, vehicles: [])
        #expect(swapped.wheelType == "Induction20Black")
        #expect(swapped != start)
        let scene = CarShowroom.scene(for: swapped)
        #expect(VehicleWheels.mountedAssets(on: try vehicle(in: scene)).first == "Wheel_Induction")
    }

    @Test func remountingReplacesTheWheels() throws {
        let scene = CarShowroom.scene(for: owned(.modelY, vin: carY, wheelType: "Gemini19"))
        let car = try vehicle(in: scene)
        let induction = WheelChoice.resolve(wheelType: "Induction20Black", model: .modelY)
        #expect(VehicleWheels.mount(induction, on: car, look: .showroom) == 4)
        #expect(VehicleWheels.mountedAssets(on: car) == Array(repeating: "Wheel_Induction", count: 4))
        VehicleWheels.mount(nil, on: car, look: .showroom)
        #expect(VehicleWheels.mountedAssets(on: car).isEmpty)
    }

    @Test func garageCarWearsItsWheelsInTheCarsLightAndOutOfTheReflection() throws {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let lighting = HouseLighting(root: house)
        lighting.setVehicleModel(.modelY)
        lighting.showVehicle(true)
        let parked = try #require(house.childNode(withName: "VehicleModel_ModelY", recursively: true))
        #expect(VehicleWheels.mountedAssets(on: parked) == Array(repeating: "Wheel_Gemini", count: 4))
        lighting.setVehicleWheels(WheelChoice.resolve(wheelType: "Induction20Black", model: .modelY))
        #expect(VehicleWheels.mountedAssets(on: parked) == Array(repeating: "Wheel_Induction", count: 4))
        var wheelMeshes = 0
        parked.enumerateHierarchy { node, _ in
            #expect(node.categoryBitMask == HouseCarLighting.lightBit)
            #expect(node.categoryBitMask & HouseGroundPlate.reflectionBit == 0)
            guard node.geometry != nil, Self.isWheel(node) else { return }
            wheelMeshes += 1
            // No environment in the home: metal would draw black.
            for material in node.geometry?.materials ?? [] {
                #expect((material.metalness.contents as? NSNumber)?.doubleValue ?? 0 == 0)
            }
        }
        #expect(wheelMeshes >= 4)
    }

    private static func isWheel(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let next = current {
            if next.name?.hasPrefix(VehicleWheels.mountPrefix) == true { return true }
            current = next.parent
        }
        return false
    }

    // MARK: Demo and logging

    @Test func demoCarsWearRealWheelsWithoutAFleetCall() {
        for car in DemoHouseTour.vehicles where car.model != .generic {
            let choice = WheelChoice.resolve(wheelType: car.wheelType, model: car.model)
            #expect(choice?.source == .fleet, "\(car.model.rawValue)")
        }
        let parked = DemoHouseTour.parkedCar(at: 1)
        #expect(parked.appearance.wheelType == TeslaWheel.demoNames(for: parked.vehicle.model).first)
    }

    @Test func paintLogShowsTheWheelTypeAndTheFileWithTheVINCut() {
        let saved = [carY: VehicleAppearance(exteriorColor: nil, paintColorOverride: nil, colorizerRemap: false, carType: "modely", wheelType: "Induction20Black")]
        let car = CarShowroom.repainted(
            CarShowroom.ownedRequest(vin: carY, appearances: saved, vehicles: [], charges: [:], displayBoost: 4),
            appearances: saved,
            vehicles: []
        )
        let report = CarShowroom.paintReport(for: car, appearances: saved, vehicles: [])
        #expect(!report.contains(carY))
        #expect(report.contains("…" + carY.suffix(4)))
        #expect(report.contains("wheel_type=\"Induction20Black\""))
        #expect(report.contains("Wheel_Induction.usdz (fleet)"))
    }
}
