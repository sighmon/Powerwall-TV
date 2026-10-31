import CoreLocation
import Foundation
import SceneKit
import Testing
import WeatherKit
#if canImport(AppKit)
import AppKit
#endif
@testable import Powerwall_TV

struct GarageSceneTests {
    @Test func vinSelectsTheFleetModelAndRefreshGeneration() {
        #expect(GarageVehicleModel.resolve(vin: "5YJ3GDEE5NF000001") == .model3)
        #expect(GarageVehicleModel.resolve(vin: "5YJ3GDEE5RF000001") == .model3Highland)
        #expect(GarageVehicleModel.resolve(vin: "5YJYGDEE5LF000001") == .modelY)
        #expect(GarageVehicleModel.resolve(vin: "5YJYGDEE5SF000001") == .modelYJuniper)
        #expect(GarageVehicleModel.resolve(vin: "5YJSA1E25MF000001") == .modelS)
        #expect(GarageVehicleModel.resolve(vin: "5YJXCAE25MF000001") == .modelX)
        #expect(GarageVehicleModel.resolve(vin: "7G2C12345RF000001") == .cybertruck)
        #expect(GarageVehicleModel.resolve(vin: "abc123") == .generic)
        #expect(GarageVehicleModel.modelYear(vin: "5YJYGDEE5SF000001") == 2025)
    }

    @Test func carTypeOverridesTheVINWhenFleetHasAlreadyReportedIt() {
        #expect(GarageVehicleModel.resolve(vin: "5YJSA1E25MF000001", carType: "cybertruck") == .cybertruck)
        #expect(GarageVehicleModel.resolve(vin: "5YJYGDEE5SF000001", carType: "model3") == .model3Highland)
        #expect(GarageVehicleModel.resolve(vin: nil, carType: "modely") == .modelY)
        #expect(GarageVehicleModel.resolve(vin: "5YJ3GDEE5NF000001", carType: "lychee") == .model3Highland)
    }

    @Test func garageFollowsTheWallConnectorAndCachedPaint() {
        let modelY = "5YJYGDEE5LF000001"
        let cybertruck = "7G2C12345RF000001"
        let charging = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [.init(vin: modelY, din: nil, wallConnectorState: 1, wallConnectorPower: 7000)]
        )
        let appearance = VehicleAppearance(
            exteriorColor: "PearlWhite",
            paintColorOverride: nil,
            colorizerRemap: false,
            carType: "modely"
        )
        let parked = GaragePresentation.make(
            data: charging,
            fallbackVIN: cybertruck,
            appearances: [modelY: appearance],
            solar: .panels
        )
        #expect(parked.showWallConnector)
        #expect(parked.showVehicle)
        #expect(parked.model == .modelY)
        #expect(parked.exteriorColor == "PearlWhite")

        let localCharger = PowerwallData(
            battery: charging.battery,
            load: charging.load,
            solar: charging.solar,
            site: charging.site,
            wallConnectors: [.init(vin: nil, din: "10.0.0.8", wallConnectorState: 4, wallConnectorPower: 0)]
        )
        let fallback = GaragePresentation.make(
            data: localCharger,
            fallbackVIN: cybertruck,
            appearances: [cybertruck: VehicleAppearance(exteriorColor: "Red", paintColorOverride: "1,2,3,0.2,0.1", colorizerRemap: true, carType: nil)],
            solar: .roof
        )
        #expect(fallback.showVehicle)
        #expect(fallback.model == .cybertruck)
        #expect(fallback.paintColorOverride == "1,2,3,0.2,0.1")
        #expect(fallback.solar == .roof)

        let idle = PowerwallData(
            battery: charging.battery,
            load: charging.load,
            solar: charging.solar,
            site: charging.site,
            wallConnectors: [.init(vin: modelY, din: nil, wallConnectorState: nil, wallConnectorPower: 0)]
        )
        let empty = GaragePresentation.make(data: idle, fallbackVIN: modelY, appearances: [:], solar: .hidden)
        #expect(empty.showWallConnector)
        #expect(!empty.showVehicle)
        #expect(empty.solar == .hidden)
        #expect(GaragePresentation.make(data: nil, fallbackVIN: "", appearances: [:], solar: .panels).showWallConnector == false)
    }

    @Test func paintOverrideBeatsExteriorColorAndUnknownColorsFallBack() {
        let pearl = TeslaPaint.resolve(exteriorColor: "pearl white", paintColorOverride: nil)
        #expect(pearl.name == "PearlWhite")
        let override = TeslaPaint.resolve(exteriorColor: "PearlWhite", paintColorOverride: "255,0,0,0.4,0.2")
        #expect(override.name == "Override")
        #expect(override.metallic == 0.4)
        #expect(TeslaPaint.resolve(exteriorColor: "NotAColor", paintColorOverride: "nope").name == "Fallback")

        let remapped = TeslaPaint.resolve(exteriorColor: nil, paintColorOverride: "255,0,0,0.4,0.2", colorizerRemap: true)
        var plain: CGFloat = 0
        var dark: CGFloat = 0
        override.colour(displayBoost: 1).getRed(&plain, green: nil, blue: nil, alpha: nil)
        remapped.colour(displayBoost: 1).getRed(&dark, green: nil, blue: nil, alpha: nil)
        #expect(dark < plain)
    }

    @Test func weatherLightingDimsAtNightAndStartsRain() {
        let lighting = WeatherLighting(houseHeadingDegrees: 180)
        let night = lighting.parameters(
            sunAltitude: -10,
            sunAzimuth: 20,
            isDaylight: false,
            cloudCover: 0,
            condition: .clear,
            precipitationMillimetresPerHour: 0
        )
        #expect(night.theme == 0)
        #expect(night.rainIntensity == 0)

        let storm = lighting.parameters(
            sunAltitude: 40,
            sunAzimuth: 180,
            isDaylight: true,
            cloudCover: 0.9,
            condition: .heavyRain,
            precipitationMillimetresPerHour: 10
        )
        #expect(storm.rainIntensity >= 0.8)
        #expect(storm.theme < 0.7)
    }

    @Test func solarPositionStaysOnTheCompassAndIsHigherInSummer() {
        let adelaide = CLLocationCoordinate2D(latitude: -34.9, longitude: 138.6)
        let summer = SolarPosition.compute(date: Date(timeIntervalSince1970: 1_766_286_000), coordinate: adelaide)
        let winter = SolarPosition.compute(date: Date(timeIntervalSince1970: 1_750_500_000), coordinate: adelaide)
        #expect((-90...90).contains(summer.altitude))
        #expect((0..<360).contains(summer.azimuth))
        #expect(summer.altitude > winter.altitude)
    }

    @Test func siteInfoDecodesSolarInstallationAndVehicleConfig() throws {
        let site = try JSONDecoder().decode(SiteInfo.self, from: Data(#"""
        {"site_name":"Home","battery_count":2,"components":{"solar":true,"solar_type":"pv_roof"}}
        """#.utf8))
        #expect(GarageSolar.resolve(hasSolar: site.components?.solar, solarType: site.components?.solarType) == .roof)
        #expect(GarageSolar.resolve(hasSolar: false, solarType: "pv_panel") == .hidden)
        #expect(GarageSolar.resolve(hasSolar: nil, solarType: nil) == .panels)

        let vehicle = try JSONDecoder().decode(VehicleDataResponse.self, from: Data(#"""
        {"response":{"charge_state":{"battery_level":80,"charging_state":"Charging"},"vehicle_config":{"car_type":"modely","exterior_color":"StealthGrey","paint_color_override":null},"vehicle_state":{"colorizer_paint_remap_enabled":false}}}
        """#.utf8))
        #expect(vehicle.response.chargeState?.batteryLevel == 80)
        #expect(vehicle.response.vehicleConfig?.exteriorColor == "StealthGrey")
        #expect(vehicle.response.vehicleConfig?.carType == "modely")
        #expect(vehicle.response.vehicleState?.colorizerPaintRemapEnabled == false)
    }

    @Test func powerFlowFollowsGaragePresence() {
        let listed = PowerwallData(
            battery: .init(instantPower: -500, count: 1),
            load: .init(instantPower: 800),
            solar: .init(instantPower: 3000, energyExported: 0),
            site: .init(instantPower: -1000),
            wallConnectors: [.init(vin: nil, din: "1", wallConnectorState: 0, wallConnectorPower: 0)]
        )
        let idle = GaragePresentation.make(data: listed, fallbackVIN: "", appearances: [:], solar: .panels)
        let flow = PowerFlowSnapshot(data: listed, presentation: idle, batteryCount: 1)
        #expect(idle.showVehicle == false)
        #expect(flow.hasVehicle == false)
        #expect(flow.hasSolar == true)
        #expect(flow.solarW == 3000)
        #expect(flow.batteryW == -500)

        let hidden = GaragePresentation.make(data: listed, fallbackVIN: "", appearances: [:], solar: .hidden)
        let dark = PowerFlowSnapshot(data: listed, presentation: hidden, batteryCount: 0)
        #expect(dark.hasSolar == false)
        #expect(dark.solarW == 0)
        #expect(dark.hasBattery == false)
        #expect(dark.batteryW == 0)

        let panels = PowerFlowAnimator(solarTerminateAt: 2.2)
        let roof = PowerFlowAnimator(solarTerminateAt: 1000)
        let panelEnd = panels.ribbons.first { $0.name == "Solar_1A" }?.midU.last ?? 0
        let roofEnd = roof.ribbons.first { $0.name == "Solar_1A" }?.midU.last ?? 0
        #expect(panelEnd <= 2.2)
        #expect(roofEnd > panelEnd)
    }

    @Test func pipesKeepTheRouteAndStayOffThePowerwall() {
        let points = [
            PowerFlowPathPoint(u: 0, position: SIMD3(0.02, 0.5, 0.2), side: SIMD3(-0.01, 0, 0.016), shade: 1, alpha: 1),
            PowerFlowPathPoint(u: 0.2, position: SIMD3(0.02, 0.3, 0.2), side: SIMD3(-0.01, 0, 0.016), shade: 1, alpha: 1),
            PowerFlowPathPoint(u: 0.4, position: SIMD3(0.02, 0.1, 0.2), side: SIMD3(-0.01, 0, 0.016), shade: 1, alpha: 1),
        ]
        let gateway = PowerFlowClearance(lower: SIMD3(-0.02, 0.22, 0.12), upper: SIMD3(0.08, 0.4, 0.3))
        let ribbon = PowerFlowRibbon(
            name: "wall",
            points: points,
            terminateAt: 1000,
            step: 0.2,
            camera: SIMD3(4, 2, 6),
            clearances: [gateway]
        )
        let corners = ribbon?.corners ?? []
        #expect(!corners.isEmpty)
        #expect(corners.allSatisfy { $0.x >= 0.019 && $0.x <= 0.032 })
        #expect(corners.allSatisfy { !gateway.contains($0) })
        let width = (corners.map(\.z).max() ?? 0) - (corners.map(\.z).min() ?? 0)
        #expect(width > 0.02)

        let face = PowerwallLevelFace.nearest(
            minBound: SIMD3(0.004, 0.01, 0.81),
            maxBound: SIMD3(0.044, 0.34, 1.03),
            camera: SIMD3(4.5, 4.0, 6.5)
        )
        #expect(face?.normal == SIMD3<Float>(0, 0, 1))
        #expect(abs(face?.side.x ?? 0) > abs(face?.side.z ?? 0))

        let restored = PowerFlowRibbon(
            name: "Powerwall_2A",
            points: PowerFlowLayout.paths["Powerwall_2A"] ?? [],
            terminateAt: 1000,
            step: 0.1,
            camera: SIMD3(7.55, 5.7, 9.75)
        )
        let restoredCorners = restored?.corners ?? []
        let terminal = restoredCorners.filter { abs($0.y - 0.27) < 0.04 && abs($0.z - 0.9429) < 0.04 }
        #expect(!terminal.isEmpty)
        #expect(terminal.allSatisfy { abs($0.x - 0.0178) < 0.03 })

        let meter = PowerFlowClearance(
            lower: SIMD3(0.002, 0.23, 0.15),
            upper: SIMD3(0.040, 0.47, 0.25),
            inset: 0
        )
        let solar = PowerFlowRibbon(
            name: "Solar_1A",
            points: PowerFlowLayout.paths["Solar_1A"] ?? [],
            terminateAt: 1000,
            step: 0.1,
            camera: SIMD3(7.55, 5.7, 9.75),
            clearances: [meter]
        )
        let grid = PowerFlowRibbon(
            name: "Grid_1A",
            points: PowerFlowLayout.paths["Grid_1A"] ?? [],
            terminateAt: 1000,
            step: 0.1,
            camera: SIMD3(7.55, 5.7, 9.75),
            clearances: [meter]
        )
        let solarY = solar?.corners.map(\.y).min() ?? -1
        let gridY = grid?.corners.map(\.y).max() ?? -1
        #expect(abs(solarY - 0.47) < 0.004)
        #expect(abs(gridY - 0.23) < 0.004)
    }

    @Test func sceneStaysCentredWithoutTurning() {
        let size = CGSize(width: 1280, height: 720)
        let projected = HouseCameraFraming.project(HouseCameraFraming.subject, viewport: size)
        #expect(abs(projected.x - size.width * 0.50) < 6)
        #expect(abs(projected.y - size.height * 0.50) < 6)
        let straight = simd_normalize(HouseCameraFraming.subject - HouseCameraFraming.position)
        let aimed = simd_normalize(HouseCameraFraming.target(viewport: size) - HouseCameraFraming.eye(viewport: size))
        #expect(abs(simd_dot(straight, aimed) - 1) < 0.0001)
    }

    #if os(macOS)
    @Test func calloutProjectionMatchesSceneKit() {
        let size = CGSize(width: 1280, height: 720)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        let eye = HouseCameraFraming.eye(viewport: size)
        let target = HouseCameraFraming.target(viewport: size)
        camera.position = SCNVector3(eye.x, eye.y, eye.z)
        camera.look(at: SCNVector3(target.x, target.y, target.z))
        let scene = SCNScene()
        scene.rootNode.addChildNode(camera)
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        view.scene = scene
        view.pointOfView = camera
        let world = SIMD3<Float>(0.05, 0.17, 0.92)
        let got = HouseCameraFraming.project(world, viewport: size)
        let hit = view.projectPoint(SCNVector3(world.x, world.y, world.z))
        #expect(abs(got.x - CGFloat(hit.x)) < 3)
        #expect(abs(got.y - (size.height - CGFloat(hit.y))) < 3)
    }

    @Test func gradedHouseStaysAsDarkAsTheReference() throws {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let lighting = HouseLighting(root: house)
        lighting.apply(HouseLightingParameters(), animated: false)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        camera.position = SCNVector3(7.55, 5.7, 9.75)
        camera.look(at: SCNVector3(-1.6, 0.6, 0))
        scene.rootNode.addChildNode(camera)
        scene.background.contents = NSColor(red: 22.0 / 255, green: 23.0 / 255, blue: 24.0 / 255, alpha: 1)
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        view.scene = scene
        view.pointOfView = camera
        view.antialiasingMode = .multisampling4X
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            throw NSError(domain: "GarageSceneTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "snapshot has no bitmap"])
        }
        if let png = rep.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/house-graded.png"))
        }
        // home.png walls sit near 50/255. The ungraded atlas rendered near 151.
        var wall: CGFloat = 0
        var wallCount = 0
        var bright = 0
        let step = 16
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let luminance = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                if luminance > 0.75 { bright += 1 }
                // Skip the flat background and the near-white Powerwall.
                if luminance > 0.08, luminance < 0.45 {
                    wall += luminance
                    wallCount += 1
                }
            }
        }
        let meanWall = wallCount > 0 ? wall / CGFloat(wallCount) : 1
        #expect(wallCount > 40)
        #expect(meanWall < 0.32)
        #expect(bright > 0)
    }
    #endif

    @Test func headingLabelUsesCompassNames() {
        #expect(HouseHeading.label(180) == "south (180°)")
        #expect(HouseHeading.label(0) == "north (0°)")
    }
}
