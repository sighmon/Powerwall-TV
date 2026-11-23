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

        let exporting = PowerwallData(
            battery: charging.battery,
            load: charging.load,
            solar: charging.solar,
            site: charging.site,
            wallConnectors: [.init(vin: nil, din: "1", wallConnectorState: nil, wallConnectorPower: -4000)]
        )
        #expect(GaragePresentation.make(data: exporting, fallbackVIN: "", appearances: [:], solar: .panels).showVehicle)
        #expect(empty.solar == .hidden)
        #expect(GaragePresentation.make(data: nil, fallbackVIN: "", appearances: [:], solar: .panels).showWallConnector == false)
    }

    @Test func chargingCarBeatsAnEarlierPluggedInCar() {
        let model3 = "5YJ3GDEE5NF000001"
        let modelY = "5YJYGDEE5LF000001"
        let both = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [
                .init(vin: model3, din: "stall-a", wallConnectorState: 4, wallConnectorPower: 0),
                .init(vin: modelY, din: "stall-b", wallConnectorState: 1, wallConnectorPower: 7000)
            ]
        )
        let parked = GaragePresentation.make(
            data: both,
            fallbackVIN: model3,
            appearances: [
                model3: VehicleAppearance(exteriorColor: nil, paintColorOverride: nil, colorizerRemap: false, carType: "model3"),
                modelY.lowercased(): VehicleAppearance(exteriorColor: "PearlWhite", paintColorOverride: nil, colorizerRemap: false, carType: "modely")
            ],
            solar: .panels
        )
        #expect(parked.model == .modelY)
        #expect(parked.exteriorColor == "PearlWhite")
        #expect(GaragePresentation.connectedVIN(wallConnectors: both.wallConnectors, fallbackVIN: model3) == modelY)
        #expect(GaragePresentation.chargingVIN(wallConnectors: both.wallConnectors) == modelY)

        let twoCharging = [
            WallConnector(vin: model3, din: "stall-a", wallConnectorState: 1, wallConnectorPower: 1000),
            WallConnector(vin: modelY, din: "stall-b", wallConnectorState: 1, wallConnectorPower: 11000)
        ]
        #expect(GaragePresentation.connectedVIN(wallConnectors: twoCharging, fallbackVIN: "") == model3)

        let exporting = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [.init(vin: modelY, din: "1", wallConnectorState: nil, wallConnectorPower: -4000)]
        )
        let sendingHome = GaragePresentation.make(data: exporting, fallbackVIN: model3, appearances: [:], solar: .panels)
        #expect(sendingHome.showVehicle)
        #expect(sendingHome.model == .modelY)
        #expect(GaragePresentation.chargingVIN(wallConnectors: exporting.wallConnectors) == modelY)

        let onlyPlugged = [WallConnector(vin: model3, din: "stall-a", wallConnectorState: 4, wallConnectorPower: 0)]
        #expect(GaragePresentation.connectedVIN(wallConnectors: onlyPlugged, fallbackVIN: modelY) == model3)
        #expect(GaragePresentation.chargingVIN(wallConnectors: onlyPlugged) == nil)
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

    @Test func demoTourCyclesEveryWeatherAndEveryCar() {
        #expect(DemoHouseTour.vehicles.map(\.model) == VehicleModel.allCases)
        #expect(DemoHouseTour.powerTicksPerScene >= 2)
        #expect(DemoHouseTour.colourInterval == 2)
        for vehicle in DemoHouseTour.vehicles {
            #expect(GarageVehicleModel.resolve(vin: vehicle.vin) == vehicle.model)
            let parked = PowerwallData(
                battery: .init(instantPower: 256, count: 1),
                load: .init(instantPower: 2304),
                solar: .init(instantPower: 2048, energyExported: 0),
                site: .init(instantPower: 1024),
                wallConnectors: [.init(vin: vehicle.vin, din: "def456", wallConnectorState: 1, wallConnectorPower: 512)]
            )
            let presentation = GaragePresentation.make(data: parked, fallbackVIN: "", appearances: [:], solar: .panels)
            #expect(presentation.showVehicle)
            #expect(presentation.model == vehicle.model)
        }
        #expect(DemoHouseTour.vehicle(at: DemoHouseTour.vehicles.count).model == .generic)
        #expect(DemoHouseTour.vehicle(at: -1).model == .cybertruck)

        let heading = 180.0
        func sky(_ title: String) -> HouseLightingParameters {
            DemoHouseTour.weather.first { $0.title == title }!.parameters(heading: heading)
        }
        let clear = sky("Clear")
        #expect(clear.cloudCover < 0.2)
        #expect(clear.rainIntensity == 0)
        #expect(clear.snowIntensity == 0)
        #expect(clear.theme > 0.5)

        let partly = sky("Partly cloudy")
        #expect(partly.cloudCover >= 0.42)
        #expect(partly.cloudCover < 0.6)
        #expect(partly.ambientScale > 0.95)
        #expect(partly.rainIntensity == 0)

        let cloudy = sky("Cloudy")
        #expect(cloudy.cloudCover >= 0.88)
        #expect(cloudy.rainIntensity == 0)
        #expect(cloudy.snowIntensity == 0)
        #expect(cloudy.theme > 0.05)

        let drizzle = sky("Drizzle")
        #expect(drizzle.rainIntensity > 0)
        #expect(drizzle.rainIntensity <= 0.35)
        #expect(drizzle.snowIntensity == 0)

        let rain = sky("Rain")
        #expect(rain.rainIntensity > 0.4)
        #expect(rain.rainIntensity < 0.8)
        #expect(rain.snowIntensity == 0)

        let heavy = sky("Heavy rain")
        #expect(heavy.rainIntensity >= 0.8)
        #expect(heavy.snowIntensity == 0)
        #expect(heavy.cloudCover >= 0.9)
        #expect(heavy.theme > 0.05)

        #expect(sky("Flurries").snowIntensity == 0.25)
        #expect(sky("Flurries").rainIntensity == 0)
        #expect(sky("Snow").snowIntensity == 0.5)
        #expect(sky("Blizzard").snowIntensity == 1)
        #expect(sky("Blizzard").cloudCover >= 0.9)
        #expect(sky("Sleet").rainIntensity == 0.3)
        #expect(sky("Sleet").snowIntensity == 0.3)

        let night = sky("Night")
        #expect(night.theme == 0)
        #expect(night.rainIntensity == 0)
        #expect(night.snowIntensity == 0)
        #expect(night.sunAltitude < 0)

        let rainyNight = sky("Rainy night")
        #expect(rainyNight.theme == 0)
        #expect(rainyNight.rainIntensity > 0.4)
        #expect(rainyNight.snowIntensity == 0)

        let signatures = DemoHouseTour.weather.map { scene -> String in
            let parameters = scene.parameters(heading: heading)
            let day = parameters.theme > 0.05 ? "day" : "night"
            return "\(day)-\(parameters.rainIntensity)-\(parameters.snowIntensity)-\(parameters.cloudCover)"
        }
        #expect(Set(signatures).count == DemoHouseTour.weather.count)
        #expect(DemoHouseTour.weather(at: DemoHouseTour.weather.count).title == "Clear")
        #expect(DemoHouseTour.weather(at: -1).title == "Rainy night")
    }

    @Test func demoTourCyclesEveryColourOnEachCar() {
        let paints = TeslaPaint.catalogue
        #expect(paints.map(\.name) == TeslaPaint.catalogueNames)
        #expect(paints.count > 10)
        let looks = Set(paints.map { "\($0.hex)|\($0.metallic)|\($0.roughness)" })
        #expect(looks.count == paints.count)
        for paint in paints {
            let parsed = TeslaPaint(paintColorOverride: paint.fleetOverride)
            #expect(parsed?.hex == paint.hex)
            #expect(parsed.map { abs($0.metallic - paint.metallic) < 0.001 } == true)
        }

        let first = DemoHouseTour.parkedCar(at: 0)
        #expect(first.vehicle.model == .generic)
        #expect(first.appearance.exteriorColor == nil)
        #expect(first.appearance.paintColorOverride == nil)

        let model3 = DemoHouseTour.parkedCar(at: 1)
        #expect(model3.vehicle.model == .model3)
        #expect(model3.appearance.exteriorColor == paints[0].name)

        let endOfModel3 = DemoHouseTour.parkedCar(at: paints.count)
        #expect(endOfModel3.vehicle.model == .model3)
        #expect(endOfModel3.appearance.exteriorColor == paints.last?.name)

        let highland = DemoHouseTour.parkedCar(at: paints.count + 1)
        #expect(highland.vehicle.model == .model3Highland)
        #expect(highland.appearance.exteriorColor == paints[0].name)

        let previous = DemoHouseTour.parkedCar(at: -1)
        #expect(previous.vehicle.model == .cybertruck)
        #expect(previous.appearance.exteriorColor == paints.last?.name)

        let paintedCars = DemoHouseTour.vehicles.filter { $0.model != .generic }
        let truck = DemoHouseTour.parkedCar(at: 1 + (paintedCars.count - 1) * paints.count)
        #expect(truck.vehicle.model == .cybertruck)
        let data = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [.init(vin: truck.vehicle.vin, din: "def456", wallConnectorState: 1, wallConnectorPower: 512)]
        )
        let parked = GaragePresentation.make(
            data: data,
            fallbackVIN: "",
            appearances: [truck.vehicle.vin: truck.appearance],
            solar: .panels
        )
        #expect(parked.showVehicle)
        #expect(parked.model == .cybertruck)
        #expect(parked.paintColorOverride == truck.appearance.paintColorOverride)
        #expect(parked.exteriorColor == truck.appearance.exteriorColor)

        let white = TeslaPaint.table["White"]!
        let pearl = TeslaPaint.table["PearlWhite"]!
        let black = TeslaPaint.table["SolidBlack"]!
        let silver = TeslaPaint.table["SilverMetallic"]!
        #expect((TeslaPaint(paintColorOverride: white.demoOverride)?.hex ?? 0) > 0xE0E0E0)
        #expect(TeslaPaint(paintColorOverride: white.demoOverride)?.hex != TeslaPaint(paintColorOverride: pearl.demoOverride)?.hex)
        #expect(TeslaPaint(paintColorOverride: white.demoOverride)?.hex != TeslaPaint(paintColorOverride: silver.demoOverride)?.hex)
        #expect((TeslaPaint(paintColorOverride: black.demoOverride)?.hex ?? 0xFFFFFF) < 0x303030)
        #expect(TeslaPaint.catalogueNames.allSatisfy { TeslaPaint.demoDisplayHex[$0] != nil })
        #expect(DemoHouseTour.vehicleLabel(displayName: "Model 3", exteriorColor: "PearlWhite") == "Model 3 · Pearl White")
        #expect(DemoHouseTour.vehicleLabel(displayName: "VEHICLE", exteriorColor: "White") == "VEHICLE · White")
        #expect(DemoHouseTour.vehicleLabel(displayName: "Generic", exteriorColor: nil) == "Generic")
        #expect(TeslaPaint.spacedName("MidnightCherryRed") == "Midnight Cherry Red")
    }

    @Test @MainActor func demoSkyStaysPutWhenTheClockAdvances() {
        let controller = HouseSceneController()
        controller.prepareIfNeeded()
        let rain = DemoHouseTour.weather.first { $0.title == "Rain" }!
        controller.applyDemoSky(rain, heading: 180, fadeIn: false)
        #expect(controller.rainIntensity > 0.4)
        controller.advanceSkyClock()
        #expect(controller.rainIntensity > 0.4)
        controller.applyDemoSky(rain, heading: 180, fadeIn: true)
        #expect(controller.rainIntensity > 0.4)
        controller.clearWeather(heading: 180)
        #expect(controller.rainIntensity == 0)
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
        #expect(storm.cloudCover >= 0.9)
        #expect(night.cloudCover == 0)

        let partly = lighting.parameters(
            sunAltitude: 40,
            sunAzimuth: 90,
            isDaylight: true,
            cloudCover: 0.1,
            condition: .partlyCloudy,
            precipitationMillimetresPerHour: 0
        )
        #expect(partly.cloudCover >= 0.42)
        // The visible deck can thicken without dimming the house beyond the measured cover.
        #expect(partly.ambientScale > 0.95)
    }

    @Test func sunArcsAcrossTheVisibleSkyAndCloudsVeilIt() {
        let view = CGSize(width: 1280, height: 720)
        let eye = HouseCameraFraming.eye(viewport: view)
        let target = HouseCameraFraming.target(viewport: view)
        func place(altitude: Float, azimuth: Float, cloud: Float) -> HouseSky.Placement {
            HouseSky.placement(
                altitude: altitude, azimuth: azimuth, heading: 180, cloudCover: cloud,
                eye: eye, target: target, viewport: view
            )
        }
        let morning = place(altitude: 22, azimuth: 90, cloud: 0)
        let noon = place(altitude: 58, azimuth: 180, cloud: 0)
        let evening = place(altitude: 22, azimuth: 270, cloud: 0)
        let night = place(altitude: -10, azimuth: 270, cloud: 0)
        let veiled = place(altitude: 58, azimuth: 180, cloud: 0.9)
        #expect(morning.screenX < -0.5)
        #expect(evening.screenX > 0.5)
        #expect(abs(noon.screenX) < 0.05)
        #expect(noon.screenY > morning.screenY + 0.15)
        #expect(night.sunOpacity == 0)
        #expect(noon.sunOpacity > veiled.sunOpacity * 4)

        #expect(HouseSky.wispOpacity(threshold: 0.34, cloudCover: 0, cirrus: true) == 0)
        #expect(HouseSky.wispOpacity(threshold: 0.9, cloudCover: 0.4, cirrus: false) == 0)
        let fullCirrus = HouseSky.wispOpacity(threshold: 0.34, cloudCover: 1, cirrus: true)
        #expect(fullCirrus > 0.30 && fullCirrus < 0.38)
        let fullPuff = HouseSky.wispOpacity(threshold: 0.55, cloudCover: 1, cirrus: false)
        #expect(fullPuff > 0.40 && fullPuff < 0.48)
        #expect(HouseSky.wisps.allSatisfy { abs($0.y - 1) < 0.001 })
        let dawn = HouseSky.skyWash(altitude: 4)
        let noonWash = HouseSky.skyWash(altitude: 58)
        let nightWash = HouseSky.skyWash(altitude: -10)
        #expect(nightWash.amount == 0)
        #expect(noonWash.amount > 0.95)
        #expect(dawn.top.z > dawn.top.x)
        #expect(dawn.top.x > dawn.top.y)
        #expect(dawn.bottom.x > dawn.bottom.z)
        #expect(dawn.bottom.z > dawn.bottom.y)
        #expect(noonWash.top.z > noonWash.top.x)
        let lowSun = place(altitude: 4, azimuth: 90, cloud: 0)
        #expect(lowSun.sunColor.x > lowSun.sunColor.z)
        #expect(lowSun.sunColor.z > lowSun.sunColor.y)
        let thin = HouseSky.wisps.filter { $0.cirrus && HouseSky.wispOpacity(threshold: $0.threshold, cloudCover: 0.5, cirrus: true) > 0 }
        let thick = HouseSky.wisps.filter { !$0.cirrus && HouseSky.wispOpacity(threshold: $0.threshold, cloudCover: 0.5, cirrus: false) > 0.2 }
        #expect(!thin.isEmpty)
        #expect(thick.isEmpty)
        #expect(HouseSky.wisps.allSatisfy { $0.height >= 2.6 && $0.width > $0.height })

        let edge = HouseSkyArt.cloudThickness(0.16)
        let mid = HouseSkyArt.cloudThickness(0.55)
        let core = HouseSkyArt.cloudThickness(1.8)
        #expect(abs(edge - 0.16) < 0.001)
        #expect(core > mid)
        #expect(core < 0.5)
        #expect((core - mid) < (mid - edge))
    }

    @Test func precipitationIsSoftAndRound() {
        #expect(HouseSkyArt.precipitationFade(0) == 1)
        #expect(HouseSkyArt.precipitationFade(1) == 0)
        #expect(HouseSkyArt.precipitationFade(1.3) == 0)
        let near = HouseSkyArt.precipitationFade(0.15)
        let shoulder = HouseSkyArt.precipitationFade(0.5)
        #expect(near > 0.9)
        #expect(shoulder > 0.15)
        #expect(shoulder < 0.55)

        let sprite = HouseSkyArt.precipitation
        #expect(sprite.width == sprite.height)
        #expect(spriteAlpha(sprite, x: 0, y: 0) == 0)
        #expect(spriteAlpha(sprite, x: sprite.width - 1, y: 0) == 0)
        let centre = sprite.width / 2
        #expect(spriteAlpha(sprite, x: centre, y: centre) > 240)
        // Even sizes have no single centre pixel. Mirror across the far edge.
        let eastX = centre + sprite.width / 5
        let westX = sprite.width - 1 - eastX
        let east = spriteAlpha(sprite, x: eastX, y: centre)
        let west = spriteAlpha(sprite, x: westX, y: centre)
        let north = spriteAlpha(sprite, x: centre, y: westX)
        let south = spriteAlpha(sprite, x: centre, y: eastX)
        #expect(east == west)
        #expect(north == south)
        #expect(east == north)
        #expect(east > 20)
        #expect(east < 180)

        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        _ = HouseLighting(root: house)
        for name in ["Rain", "Snow"] {
            guard let system = house.childNode(withName: name, recursively: true)?.particleSystems?.first else {
                #expect(Bool(false))
                continue
            }
            #expect(system.stretchFactor == 0)
            #expect(system.particleImage != nil)
        }
    }

    private func spriteAlpha(_ image: CGImage, x: Int, y: Int) -> Int {
        guard let data = image.dataProvider?.data as Data? else { return -1 }
        let index = (y * image.bytesPerRow) + x * 4 + 3
        guard data.indices.contains(index) else { return -1 }
        return Int(data[index])
    }

    @Test func loadedWeatherFadesInFromTheClockSky() {
        var clock = HouseLightingParameters()
        clock.cloudCover = 0.2
        clock.rainIntensity = 0
        var forecast = clock
        forecast.cloudCover = 0.8
        forecast.rainIntensity = 0.6
        let halfway = clock.interpolated(toward: forecast, fraction: Float(HouseWeatherFade.ease(0.5)))
        #expect(abs(halfway.cloudCover - 0.5) < 0.001)
        #expect(abs(halfway.rainIntensity - 0.3) < 0.001)
        #expect(HouseWeatherFade.ease(0) == 0)
        #expect(HouseWeatherFade.ease(1) == 1)
        let refresh = 1.0 / 120.0
        #expect(HouseWeatherFade.stepInterval(attention: .focused, pauseWhenUnfocused: false, displayRefresh: refresh) == refresh)
        #expect(HouseWeatherFade.stepInterval(attention: .visibleUnfocused, pauseWhenUnfocused: false, displayRefresh: refresh) == refresh)
        #expect(HouseWeatherFade.stepInterval(attention: .visibleUnfocused, pauseWhenUnfocused: true, displayRefresh: refresh).isInfinite)
        #expect(HouseWeatherFade.stepInterval(attention: .hidden, pauseWhenUnfocused: false, displayRefresh: refresh).isInfinite)

        let view = HouseCameraControlView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let idle = PowerFlowSnapshot()
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: idle, interacting: false, revealingWeather: true)
        #expect(view.rendersContinuously == true)
        #expect(view.isPlaying == true)
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: idle, revealingWeather: false)
        #expect(view.rendersContinuously == false)
        #expect(view.isPlaying == false)
    }

    @Test func clockSunRisesOnTheLeftAndSetsOnTheRight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func sun(_ hour: Int, _ minute: Int) -> (altitude: Double, azimuth: Double) {
            let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: hour, minute: minute))!
            return HouseSky.clockSun(at: date, heading: 180, calendar: calendar)
        }
        let morning = sun(8, 0)
        let noon = sun(12, 0)
        let evening = sun(16, 0)
        let night = sun(2, 0)
        #expect(morning.azimuth < noon.azimuth)
        #expect(noon.azimuth < evening.azimuth)
        #expect(noon.altitude > morning.altitude)
        #expect(night.altitude < 0)
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

    @Test func groundPlateMirrorsTheHouseAndLeavesTheSkyOut() {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        _ = HouseLighting(root: house)
        let plate = house.childNode(withName: HouseGroundPlate.name, recursively: false)
        let floor = plate?.geometry as? SCNFloor
        #expect(floor != nil)
        #expect((floor?.reflectivity ?? 0) > 0.05)
        #expect((floor?.reflectivity ?? 1) < 0.5)
        #expect(abs((floor?.reflectionFalloffStart ?? 1) - 0.08) < 0.001)
        #expect(abs((floor?.reflectionFalloffEnd ?? 0) - 0.32) < 0.001)
        #if os(macOS)
        #expect(abs((floor?.reflectionResolutionScaleFactor ?? 0) - 1) < 0.01)
        #expect(plate?.filters?.isEmpty != false)
        #endif
        let bit = HouseGroundPlate.reflectionBit
        func tally(prefix: String) -> (on: Int, off: Int) {
            var on = 0
            var off = 0
            house.enumerateHierarchy { child, _ in
                guard child.name?.hasPrefix(prefix) == true else { return }
                if child.categoryBitMask & bit != 0 { on += 1 } else { off += 1 }
            }
            return (on, off)
        }
        #expect((plate?.categoryBitMask ?? bit) & bit == 0)
        #expect(tally(prefix: "HouseSky").on == 0)
        #expect(tally(prefix: "Home").on > 0)
        #expect(tally(prefix: "Home").off == 0)
        #expect(tally(prefix: "GarageDoor").on > 0)
        #expect(tally(prefix: "GarageDoor").off == 0)
        #expect(tally(prefix: "Powerwall").on > 0)
        #expect(tally(prefix: "Powerwall").off == 0)
        #expect(tally(prefix: "Windows").on > 0)
        #expect(tally(prefix: "Windows").off == 0)
        #expect(tally(prefix: "Solar").off > 0)
        #expect(tally(prefix: "Solar").on == 0)
        #expect(tally(prefix: "Meter").off > 0)
        #expect(tally(prefix: "Meter").on == 0)
        let gateway = house.childNode(withName: "Meter3_0", recursively: true)
        let connector = house.childNode(withName: "WC_Faceplate_0", recursively: true)
        #expect(gateway?.geometry?.materials.isEmpty == false)
        #expect(gateway?.geometry?.materials.allSatisfy {
            $0.shaderModifiers?[.fragment]?.contains("discard_fragment") == true
        } == true)
        #expect(connector?.geometry?.materials.allSatisfy { $0.shaderModifiers?[.fragment] == nil } == true)
        #expect(gateway?.geometry?.materials.first !== connector?.geometry?.materials.first)
        #expect(tally(prefix: "WallConnector").on == 0)
        #expect(house.childNode(withName: "GroundReflection", recursively: true)?.isHidden == true)
    }

    @Test func houseShadowCardIsBackWithTeslasBlackAndAlpha() throws {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        _ = HouseLighting(root: house)
        let card = try #require(house.childNode(withName: HouseGroundShadow.nodeName, recursively: true))
        #expect(card.isHidden == false)
        var meshes = 0
        card.enumerateHierarchy { node, _ in
            #expect(node.renderingOrder == HouseGroundShadow.renderingOrder)
            #expect(node.categoryBitMask & HouseGroundPlate.reflectionBit == 0)
            guard let material = node.geometry?.materials.first else { return }
            meshes += 1
            #expect(material.name == "HouseGroundShadow")
            #expect(material.lightingModel == .constant)
            #expect(material.blendMode == .alpha)
            #expect(material.writesToDepthBuffer == false)
        }
        #expect(meshes > 0)
        // Drawn over the plate and the sky wash, under the house shell.
        let shell = try #require(house.childNode(withName: "Home", recursively: true))
        #expect(shell.renderingOrder > HouseGroundShadow.renderingOrder)
        // The car's garage shadow stays hidden: its texture does not match Tesla's.
        #expect(house.childNode(withName: "GarageVehicleShadow", recursively: true)?.isHidden == true)
    }

    @Test func bakedHouseShadowIsBlackWithASoftAlpha() throws {
        let url = try #require(HouseLighting.resourceURL(name: HouseGroundShadow.texture, ext: "png"))
        #if canImport(AppKit)
        let image = try #require(NSImage(contentsOf: url))
        let rep = try #require(image.representations.first as? NSBitmapImageRep)
        var maxAlpha: CGFloat = 0
        var clear = 0
        var samples = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 16) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 16) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                samples += 1
                maxAlpha = max(maxAlpha, colour.alphaComponent)
                if colour.alphaComponent < 0.03 { clear += 1 }
                if colour.alphaComponent > 0.5 {
                    #expect(colour.redComponent < 0.02 && colour.greenComponent < 0.02 && colour.blueComponent < 0.02)
                }
            }
        }
        #expect(maxAlpha > 0.95)
        // Most of the 8 m card is clear; the shade is around the footprint.
        #expect(Double(clear) / Double(max(samples, 1)) > 0.3)
        #else
        #expect(FileManager.default.fileExists(atPath: url.path))
        #endif
    }

    @Test func parkedCarGetsTheStudioLightsAndTheHouseKeepsItsOwn() throws {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let lighting = HouseLighting(root: house)
        lighting.setVehicleModel(.modelY)
        lighting.showVehicle(true)

        for role in HouseCarLighting.Role.allCases {
            let light = try #require(house.childNode(withName: role.rawValue, recursively: true)?.light)
            #expect(light.type == (role == .fill ? .ambient : .directional))
            #expect(light.categoryBitMask == HouseCarLighting.lightBit)
            #expect(light.intensity > 0)
        }
        for name in ["HouseFill", "HouseSun"] {
            let light = try #require(house.childNode(withName: name, recursively: true)?.light)
            #expect(light.categoryBitMask & HouseCarLighting.lightBit == 0)
        }
        // A light probe ignores category bits and gave the car and the solar panels black
        // highlights (cf3d74f). No probe and no scene-wide environment in the home view.
        house.enumerateHierarchy { node, _ in
            #expect(node.light?.type != .probe)
        }
        #expect(scene.lightingEnvironment.contents == nil)

        let vehicle = try #require(house.childNode(withName: "Vehicle", recursively: true))
        var carMeshes = 0
        vehicle.enumerateHierarchy { node, _ in
            #expect(node.categoryBitMask == HouseCarLighting.lightBit)
            if node.geometry != nil { carMeshes += 1 }
        }
        #expect(carMeshes > 0)
        for name in ["Home", "Windows", "SolarPanels", "SolarRoof", "Powerwall"] {
            guard let node = house.childNode(withName: name, recursively: true) else { continue }
            node.enumerateHierarchy { child, _ in
                #expect(child.categoryBitMask & HouseCarLighting.lightBit == 0)
                #expect(child.categoryBitMask & 1 == 1)
            }
        }
    }

    @Test func carStudioDimsAtNightAndUnderCloud() {
        typealias L = HouseCarLighting
        let fill = L.intensity(.fill, theme: 1, ambientScale: 1)
        #expect(abs(fill - L.fillLumens * L.dayStrength) < 0.001)
        #expect(abs(L.intensity(.key, theme: 1, ambientScale: 1) - L.keyLumens * L.dayStrength) < 0.001)
        #expect(abs(L.intensity(.rim, theme: 1, ambientScale: 1) - L.rimLumens * L.dayStrength) < 0.001)
        #expect(abs(L.intensity(.fill, theme: 0, ambientScale: 1) - fill * L.nightFraction) < 0.001)
        #expect(L.intensity(.key, theme: 1, ambientScale: 0.75) < L.intensity(.key, theme: 1, ambientScale: 1))
        #expect(L.intensity(.fill, theme: 2, ambientScale: 1) == fill)
        #expect(abs(L.intensity(.sun, theme: 1, ambientScale: 1) - 1000 * L.sunFraction) < 0.001)
        #expect(abs(L.intensity(.sun, theme: 0, ambientScale: 1) - 350 * L.sunFraction) < 0.001)
    }

    @Test func solarStaysOutOfTheFloorMirror() throws {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let lighting = HouseLighting(root: house)
        let floor = try #require(house.childNode(withName: HouseGroundPlate.name, recursively: true)?.geometry as? SCNFloor)
        #expect(floor.reflectionCategoryBitMask == HouseGroundPlate.reflectionBit)
        for option in [SolarOption.panels, .solarRoof] {
            lighting.setSolar(option)
            for name in HouseGroundPlate.discardedFromMirror {
                let solar = try #require(house.childNode(withName: name, recursively: true))
                var meshes = 0
                solar.enumerateHierarchy { node, _ in
                    #expect(node.categoryBitMask & HouseGroundPlate.reflectionBit == 0)
                    guard let geometry = node.geometry else { return }
                    meshes += 1
                    for material in geometry.materials {
                        #expect(material.shaderModifiers?[.fragment] == HouseGroundPlate.reflectedFragment)
                    }
                }
                #expect(meshes > 0)
            }
        }
        // The house shell and the Powerwall still show in the mirror.
        for name in ["Home", "Powerwall"] {
            let node = try #require(house.childNode(withName: name, recursively: true))
            #expect(node.categoryBitMask & HouseGroundPlate.reflectionBit != 0)
            #expect(node.childNodes.filter { $0.geometry != nil }.allSatisfy { $0.categoryBitMask & HouseGroundPlate.reflectionBit != 0 })
        }
    }

    @Test func powerwallKeepsASingleRibbon() {
        let bothWays = PowerFlowSnapshot(solarW: 1000, batteryW: -3000, gridW: 2500, homeW: 500)
        let charging = PowerFlowRemapper.remap(PowerFlowSolver.wires(for: bothWays))
        #expect(charging.keys.filter { $0.hasPrefix("Powerwall") } == ["Powerwall_1A"])

        let withCar = PowerFlowSnapshot(
            solarW: 2000, batteryW: 2000, gridW: 0, homeW: 4000, vehicleW: 3000, hasVehicle: true
        )
        let states = PowerFlowRemapper.remap(PowerFlowSolver.wires(for: withCar))
        #expect(states.keys.filter { $0.hasPrefix("Powerwall") } == ["Powerwall_1A"])
        #expect(states["Vehicle_1A"] != nil)
    }

    @Test func chargerRibbonUsesTheLeadingSupplyColour() {
        func cable(_ snapshot: PowerFlowSnapshot) -> PowerFlowColor? {
            PowerFlowRemapper.remap(PowerFlowSolver.wires(for: snapshot))["Vehicle_1A"]?.flowColor
        }
        let solar = PowerFlowStyle.defaultWireColors[.solar]
        let battery = PowerFlowStyle.defaultWireColors[.battery]
        let grid = PowerFlowStyle.defaultWireColors[.grid]
        #expect(cable(.init(solarW: 4000, batteryW: 500, gridW: 100, homeW: 1000, vehicleW: 2000, hasVehicle: true)) == solar)
        #expect(cable(.init(solarW: 100, batteryW: 3000, gridW: 200, homeW: 1000, vehicleW: 2000, hasVehicle: true)) == battery)
        #expect(cable(.init(solarW: 0, batteryW: 2000, gridW: 5000, homeW: 1000, vehicleW: 2000, hasVehicle: true)) == grid)
        // Idle Powerwall (0 W) still yields solar, matching the flat surge: solar + 40 W beats the battery.
        #expect(cable(.init(solarW: 0, batteryW: 0, gridW: 5000, homeW: 1000, vehicleW: 2000, hasVehicle: true)) == solar)
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

    @Test func solarRibbonDrawsOverTheRoofOnTheSamePath() {
        let house = SCNNode()
        _ = PowerFlowSceneKitRenderer(house: house)
        let solar = house.childNode(withName: "PowerFlowWire_Solar_1A", recursively: true)
        let grid = house.childNode(withName: "PowerFlowWire_Grid_1A", recursively: true)
        #expect(solar != nil)
        #expect(solar?.renderingOrder == 15)
        #expect(solar?.geometry?.materials.allSatisfy { $0.readsFromDepthBuffer == false } == true)
        #expect(grid?.renderingOrder == 10)
        #expect(grid?.geometry?.materials.first?.readsFromDepthBuffer == true)
        #expect(grid?.geometry?.materials.allSatisfy {
            $0.shaderModifiers?[.fragment]?.contains("discard_fragment") == true
        } == true)
        #expect(solar?.geometry?.materials.allSatisfy { $0.shaderModifiers?[.fragment] == nil } == true)
        let bit = HouseGroundPlate.reflectionBit
        #expect((solar?.categoryBitMask ?? bit) & bit == 0)
        #expect((grid?.categoryBitMask ?? bit) & bit == 0)
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
        #expect(abs((face?.up.y ?? 0) * 2 - 0.33) < 0.001)

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

        let gridCorners = grid?.corners ?? []
        let exit = gridCorners.filter { $0.y > 0.20 && $0.y < 0.24 && $0.x < 0.08 }
        let drop = gridCorners.filter { $0.y > 0.12 && $0.y < 0.18 && $0.x < 0.08 }
        #expect(!exit.isEmpty)
        #expect(!drop.isEmpty)
        if let exitMin = exit.map(\.x).min(), let exitMax = exit.map(\.x).max(),
           let dropMin = drop.map(\.x).min(), let dropMax = drop.map(\.x).max() {
            let exitX = (exitMin + exitMax) / 2
            let dropX = (dropMin + dropMax) / 2
            #expect(abs(exitX - dropX) < 0.004)
            #expect(exitMax < 0.035)
        }
    }

    @Test func idleFlowTrackSitsJustAboveTheHouseGrey() {
        // Home and Powerwall samples use shade 0.5, then brightness. That is the grey on screen.
        let gain = 0.5 * PowerFlowAnimator().brightness
        #expect(abs(PowerFlowStyle.baseColor.r * gain - 60.0 / 255) < 0.004)
        #expect(abs(PowerFlowStyle.baseColor.b * gain - 63.0 / 255) < 0.004)
    }

    @Test func offGridMarkSitsHalfwayAlongTheGridLine() {
        let points = PowerFlowLayout.paths["Grid_1A"] ?? []
        let mid = PowerFlowLayout.point(along: "Grid_1A", fraction: 0.5) ?? .zero
        var travelled: Float = 0
        var lengths: [Float] = [0]
        for index in 1..<points.count {
            travelled += simd_length(points[index].position - points[index - 1].position)
            lengths.append(travelled)
        }
        var cursor: Float = 0
        var along: Float = 0
        for index in 1..<points.count {
            let span = points[index].position - points[index - 1].position
            let length = simd_length(span)
            let delta = mid - points[index - 1].position
            let t = length > 1e-5 ? simd_dot(delta, span) / (length * length) : 0
            if t >= -0.01 && t <= 1.01 {
                along = lengths[index - 1] + length * min(max(t, 0), 1)
                cursor = simd_length(mid - (points[index - 1].position + span * min(max(t, 0), 1)))
                break
            }
        }
        #expect(cursor < 0.01)
        #expect(abs(along - travelled * 0.5) < 0.02)
        #expect(mid.y < 0.05)
        #expect(mid.x > points[0].position.x && mid.x < points[points.count - 1].position.x)
    }

    @Test func chargerCableStaysOnItsCentreline() {
        let plug = SIMD3<Float>(-1.6734, 0.3460, 1.0465)
        let ribbon = PowerFlowRibbon(
            name: "Vehicle_1A",
            points: PowerFlowLayout.paths["Vehicle_1A"] ?? [],
            terminateAt: 1000,
            step: 0.1,
            camera: SIMD3(7.55, 5.7, 9.75),
            plug: plug
        )
        let corners = ribbon?.corners ?? []
        var centres: [SIMD3<Float>] = []
        let quads = corners.count / 8
        for quad in 0..<quads {
            let base = quad * 8
            centres.append((corners[base] + corners[base + 1]) * 0.5)
        }
        if quads > 0 {
            let base = (quads - 1) * 8
            centres.append((corners[base + 4] + corners[base + 5]) * 0.5)
        }
        #expect(centres.count > 10)
        let start = centres.first ?? .zero
        let end = centres.last ?? .zero
        #expect(simd_length(start - plug) < 0.02)
        #expect(end.x > start.x + 0.2)
        #expect(end.z > 1.20)
        #expect(centres.contains { $0.y < 0.14 })
        // Only the opening descent. The cable rises again at the car, and that end is not under the plug.
        var lead: [SIMD3<Float>] = []
        for centre in centres {
            if let previous = lead.last, centre.y >= previous.y - 0.0005 { break }
            if centre.y <= plug.y - 0.12 { break }
            lead.append(centre)
        }
        #expect(lead.count >= 3)
        #expect((lead.first?.y ?? 0) - (lead.last?.y ?? 0) > 0.08)
        #expect(lead.allSatisfy { abs($0.x - plug.x) < 0.012 && abs($0.z - plug.z) < 0.012 })
        // The front wall is about z 1.17…1.21, and the pier left of the door is x < −1.57.
        let pastTheWall = centres.filter { $0.z > 1.17 && $0.y < 0.8 }
        #expect(pastTheWall.count > 4)
        #expect(pastTheWall.allSatisfy { $0.x > -1.50 })
        let bow = centres.map(\.z).max() ?? 0
        #expect(bow < 1.50)
        #expect(bow < end.z + 0.08)
        #expect(abs(end.x - (-1.18)) < 0.04)
        #expect(abs(end.y - 0.36) < 0.05)
        if let scene = ResidentialClassicScene.load() {
            let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
            if let measured = PowerFlowObstacles.wallConnectorPlug(house: house) {
                #expect(simd_length(measured - plug) < 0.01)
            }
        }
        for index in 1..<(centres.count - 1) {
            let previous = centres[index - 1]
            let next = centres[index + 1]
            let span = next - previous
            let length = simd_length(span)
            let along = length > 1e-5 ? simd_dot(centres[index] - previous, span) / (length * length) : 0
            let closest = previous + span * min(max(along, 0), 1)
            #expect(simd_length(centres[index] - closest) < 0.012)
        }
    }

    @Test func zoomedLabelsMoveAboveAndBelowTheHouse() {
        let size = CGSize(width: 1280, height: 720)
        let restingPose = HouseScenePose.identity
        let resting = HouseCameraFraming.modelVerticalSpan(viewport: size, eye: restingPose.eye, aim: restingPose.target)
        var closer = restingPose
        closer.distanceScale = 0.5
        let zoomed = HouseCameraFraming.modelVerticalSpan(viewport: size, eye: closer.eye, aim: closer.target)
        #expect(zoomed.bottom - zoomed.top > resting.bottom - resting.top + 40)
        #expect(zoomed.top < resting.top)

        let inside = (zoomed.top + zoomed.bottom) * 0.5
        let above = HouseCameraFraming.clearedLabelCenter(
            windowY: inside,
            halfHeight: 18,
            spanTop: zoomed.top,
            spanBottom: zoomed.bottom,
            above: true,
            screenMin: 0,
            screenMax: size.height
        )
        let below = HouseCameraFraming.clearedLabelCenter(
            windowY: inside,
            halfHeight: 18,
            spanTop: zoomed.top,
            spanBottom: zoomed.bottom,
            above: false,
            screenMin: 0,
            screenMax: size.height
        )
        #expect(above + 18 <= zoomed.top + 0.5 || above <= 18)
        #expect(below - 18 >= zoomed.bottom - 0.5 || below >= size.height - 18)
        #expect(above < inside)
        #expect(below > inside)

        let stayed = HouseCameraFraming.clearedLabelCenter(
            windowY: 80,
            halfHeight: 18,
            spanTop: 200,
            spanBottom: 500,
            above: true,
            screenMin: 0,
            screenMax: size.height
        )
        #expect(abs(stayed - 80) < 0.5)

        let open = HouseCameraFraming.leaderSegment(innerY: 30, outerY: 10, calloutY: 90, length: 40, modelTop: nil, modelBottom: nil)
        #expect(open?.end == 70)
        let throughTheHouse = HouseCameraFraming.leaderSegment(innerY: 40, outerY: 16, calloutY: 400, length: 240, modelTop: nil, modelBottom: nil)
        #expect(throughTheHouse?.end == 280)
        let stopped = HouseCameraFraming.leaderSegment(innerY: 40, outerY: 16, calloutY: 400, length: 240, modelTop: 120, modelBottom: 500)
        #expect(stopped?.start == 40)
        #expect(stopped?.end == 110)
        let rising = HouseCameraFraming.leaderSegment(innerY: 640, outerY: 680, calloutY: 200, length: 300, modelTop: 120, modelBottom: 500)
        #expect(rising?.start == 640)
        #expect(rising?.end == 510)
        let buried = HouseCameraFraming.leaderSegment(innerY: 160, outerY: 120, calloutY: 420, length: 180, modelTop: 100, modelBottom: 500)
        #expect(buried != nil)
        #expect((buried?.end ?? 999) < 100)
        #expect((buried?.start ?? 0) < (buried?.end ?? 0))
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

    @Test func savedPoseKeepsTheCentredCameraUntilItChanges() {
        let size = CGSize(width: 1280, height: 720)
        let preferred = HouseScenePose.preferred
        #expect(preferred.yawDegrees == 6)
        #expect(preferred.pitchDegrees == -5)
        #expect(preferred.distanceScale == 0.70)
        #expect(preferred.panRight == 0.5)
        #expect(preferred.panUp == 0)
        #expect(preferred.panForward == 0)
        let clamped = preferred.clamped()
        #expect(abs(clamped.yawDegrees - 6) < 0.001)
        #expect(abs(clamped.pitchDegrees + 5) < 0.001)
        #expect(abs(clamped.distanceScale - 0.70) < 0.001)
        #expect(abs(clamped.panRight - 0.5) < 0.001)

        let identity = HouseScenePose.identity
        #expect(simd_length(identity.eye - HouseCameraFraming.position) < 0.0001)
        #expect(simd_length(identity.target - HouseCameraFraming.subject) < 0.0001)
        #expect(simd_length(identity.eye - HouseCameraFraming.eye(viewport: size)) < 0.0001)

        let world = SIMD3<Float>(0.05, 0.17, 0.92)
        let centred = HouseCameraFraming.project(world, viewport: size)
        let posed = HouseCameraFraming.project(world, viewport: size, eye: identity.eye, aim: identity.target)
        #expect(abs(centred.x - posed.x) < 0.01)
        #expect(abs(centred.y - posed.y) < 0.01)

        var turned = identity
        turned.yawDegrees = 25
        let yawed = turned.clamped()
        #expect(simd_length(yawed.target - identity.target) < 0.0001)
        #expect(simd_length(yawed.eye - identity.eye) > 1)
        let marker = HouseCameraFraming.subject + SIMD3<Float>(1.2, 0.4, 0)
        let before = HouseCameraFraming.project(marker, viewport: size, eye: identity.eye, aim: identity.target)
        let after = HouseCameraFraming.project(marker, viewport: size, eye: yawed.eye, aim: yawed.target)
        #expect(hypot(after.x - before.x, after.y - before.y) > 20)

        let panned = identity.panned(by: SIMD3<Float>(0.4, -0.2, 0.1)).clamped()
        let shift = panned.target - identity.target
        #expect(simd_length(shift - SIMD3<Float>(0.4, -0.2, 0.1)) < 0.001)
        #expect(simd_length((panned.eye - identity.eye) - shift) < 0.001)

        var closer = identity
        closer.distanceScale = 0.5
        let closerLength = simd_length(closer.eye - closer.target)
        let identityLength = simd_length(identity.eye - identity.target)
        #expect(abs(closerLength / identityLength - 0.5) < 0.001)
        #expect(simd_dot(simd_normalize(closer.eye - closer.target), simd_normalize(identity.eye - identity.target)) > 0.999)

        var low = identity
        low.pitchDegrees = -80
        let floor = low.clamped()
        let offset = floor.eye - floor.target
        let pitch = asin(offset.y / simd_length(offset)) * 180 / .pi
        #expect(abs(pitch - 8) < 0.05)

        let draggedRight = identity.panned(by: -HouseScenePose.basis.right).clamped()
        let anchor = SIMD3<Float>(0.2, 0.8, 0.4)
        let parked = HouseCameraFraming.project(anchor, viewport: size, eye: identity.eye, aim: identity.target)
        let followed = HouseCameraFraming.project(anchor, viewport: size, eye: draggedRight.eye, aim: draggedRight.target)
        #expect(followed.x > parked.x + 20)

        let upright = yawed.levelTransform
        let cameraRight = SIMD3<Float>(upright.columns.0.x, upright.columns.0.y, upright.columns.0.z)
        #expect(abs(cameraRight.y) < 0.001)
        let foot = HouseCameraFraming.project(yawed.target, viewport: size, eye: yawed.eye, aim: yawed.target)
        let head = HouseCameraFraming.project(yawed.target + SIMD3<Float>(0, 1, 0), viewport: size, eye: yawed.eye, aim: yawed.target)
        #expect(abs(head.x - foot.x) < 1.5)
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

    @Test func turnedCameraStaysLevelInSceneKit() {
        let size = CGSize(width: 1280, height: 720)
        var pose = HouseScenePose.identity
        pose.yawDegrees = -20
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        camera.simdTransform = pose.levelTransform
        let scene = SCNScene()
        scene.rootNode.addChildNode(camera)
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        view.scene = scene
        view.pointOfView = camera
        func screen(_ world: SIMD3<Float>) -> CGPoint {
            let hit = view.projectPoint(SCNVector3(world.x, world.y, world.z))
            return CGPoint(x: CGFloat(hit.x), y: size.height - CGFloat(hit.y))
        }
        let foot = screen(pose.target)
        let head = screen(pose.target + SIMD3<Float>(0, 1, 0))
        #expect(abs(head.x - foot.x) < 2)
        let predicted = HouseCameraFraming.project(pose.target + SIMD3<Float>(0, 1, 0), viewport: size, eye: pose.eye, aim: pose.target)
        #expect(abs(predicted.x - head.x) < 3)
        #expect(abs(predicted.y - head.y) < 3)
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
        let frame = CGSize(width: 1280, height: 720)
        let doorTop = HouseCameraFraming.project(SIMD3(-0.9, 0.70, 1.20), viewport: frame)
        let doorBottom = HouseCameraFraming.project(SIMD3(-0.9, 0.02, 1.20), viewport: frame)
        var doorLuma: [CGFloat] = []
        let yStart = Int(min(doorTop.y, doorBottom.y))
        let yEnd = Int(max(doorTop.y, doorBottom.y))
        if yEnd > yStart {
            for y in yStart...yEnd {
                let t = CGFloat(y - yStart) / CGFloat(yEnd - yStart)
                let x = Int(doorTop.x + (doorBottom.x - doorTop.x) * t)
                guard x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh,
                      let color = rep.colorAt(x: x, y: y) else { continue }
                doorLuma.append((color.redComponent + color.greenComponent + color.blueComponent) / 3)
            }
        }
        let doorMean = doorLuma.isEmpty ? 0 : doorLuma.reduce(0, +) / CGFloat(doorLuma.count)
        var ribs = 0
        if doorLuma.count > 4 {
            for i in 2..<(doorLuma.count - 2) {
                let sample = doorLuma[i]
                let brighterThanNeighbours = sample > doorLuma[i - 2] + 0.025 && sample >= doorLuma[i + 2]
                let falling = doorLuma[i - 1] <= sample && sample > doorLuma[i + 1]
                if brighterThanNeighbours && falling { ribs += 1 }
            }
        }
        // A shut door is a grey ribbed panel. Four bright shelves over a black opening is not.
        #expect(doorMean > 0.08)
        #expect(doorMean < 0.22)
        #expect(ribs >= 10)
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

    @Test func litSolarAndWindowsStayRectangular() {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        func subdivision(prefix: String) -> Int {
            var level = -1
            house.enumerateHierarchy { child, _ in
                guard child.name?.hasPrefix(prefix) == true, let geometry = child.geometry else { return }
                level = max(level, geometry.subdivisionLevel)
            }
            return level
        }
        // The USD scheme is "none", so current SceneKit imports the Powerwall at 0.
        // Older SceneKit tessellated it. Either way, lighting must leave that level alone.
        let powerwall = subdivision(prefix: "Powerwall")
        _ = HouseLighting(root: house)
        #expect(subdivision(prefix: "SolarPanel") == 0)
        #expect(subdivision(prefix: "SolarRoof") == 0)
        #expect(subdivision(prefix: "Windows") == 0)
        #expect(subdivision(prefix: "Home") == 0)
        #expect(subdivision(prefix: "GarageDoor") == 0)
        #expect(subdivision(prefix: "Powerwall") == powerwall)
        #expect(powerwall >= 0)
    }

    @Test func carSitsInTheMiddleOfTheGarageDoor() {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let lighting = HouseLighting(root: house)
        guard let door = house.childNode(withName: "GarageDoor", recursively: true),
              let vehicle = house.childNode(withName: "Vehicle", recursively: true) else { return }
        // The vehicle node's own box stays empty. Measure the child meshes.
        func centreX(_ node: SCNNode) -> Float {
            var minX = Float.greatestFiniteMagnitude
            var maxX = -Float.greatestFiniteMagnitude
            func consider(_ owner: SCNNode) {
                guard let geometry = owner.geometry else { return }
                let box = geometry.boundingBox
                for x in [box.min.x, box.max.x] {
                    for y in [box.min.y, box.max.y] {
                        for z in [box.min.z, box.max.z] {
                            let world = owner.simdWorldTransform * SIMD4<Float>(Float(x), Float(y), Float(z), 1)
                            minX = min(minX, world.x)
                            maxX = max(maxX, world.x)
                        }
                    }
                }
            }
            consider(node)
            node.enumerateChildNodes { child, _ in consider(child) }
            return (minX + maxX) * 0.5
        }
        #expect(abs(centreX(vehicle) - centreX(door)) < 0.02)
        lighting.setVehicleModel(.modelY)
        guard let parked = vehicle.childNode(withName: "VehicleModel_ModelY", recursively: false) else { return }
        let parkedMid = parked.simdWorldTransform * SIMD4<Float>(-0, 0, 0, 1)
        #expect(abs(parkedMid.x - centreX(door)) < 0.02)
    }

    @Test func garageDoorSlatsStayOverlappedAndShut() {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        _ = HouseLighting(root: house)
        guard let door = house.childNode(withName: "GarageDoor_0", recursively: true),
              let source = door.geometry?.sources(for: .vertex).first else { return }
        #expect(door.geometry?.subdivisionLevel == 0)
        var lowZ: Float = -.greatestFiniteMagnitude
        var highZ: Float = .greatestFiniteMagnitude
        source.data.withUnsafeBytes { raw in
            for index in 0..<source.vectorCount {
                let base = source.dataOffset + index * source.dataStride
                let y = raw.load(fromByteOffset: base + 4, as: Float.self)
                let z = raw.load(fromByteOffset: base + 8, as: Float.self)
                if y < 0.02 { lowZ = max(lowZ, z) }
                if y > 0.02, y < 0.05 { highZ = min(highZ, z) }
            }
        }
        // The bottom edge of a slat sits toward the street and covers the slat below.
        #expect(lowZ > highZ)
    }

    @Test func idleHouseViewDoesNotRenderEveryFrame() {
        let view = HouseCameraControlView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let idle = PowerFlowSnapshot()
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: idle, interacting: false)
        #expect(view.rendersContinuously == false)
        #expect(view.isPlaying == false)

        // Exactly the solver threshold is not "above" it, so the house stays still.
        let atThreshold = PowerFlowSnapshot(solarW: 10, homeW: 10)
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: atThreshold, interacting: false)
        #expect(view.rendersContinuously == false)
        #expect(view.isPlaying == false)
    }

    @Test func interiorLightsStayOffUntilTheHomeDrawsMoreThan200Watts() {
        #expect(HouseLighting.interiorLightsOn(homeW: 200, vehicleW: 0) == false)
        #expect(HouseLighting.interiorLightsOn(homeW: 201, vehicleW: 0) == true)
        #expect(HouseLighting.interiorLightsOn(homeW: 2500, vehicleW: 2300) == false)
        #expect(HouseLighting.interiorLightsOn(homeW: 2500, vehicleW: 2200) == true)
    }

    @Test func idlePausePaintsTheRibbonBaseColour() {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let camera = HouseScenePose.identity.eye
        let driver = HousePowerFlowDriver()
        driver.attach(house: house, cameraPosition: camera)
        let view = HouseCameraControlView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.scene = scene
        view.delegate = driver

        let flowing = PowerFlowSnapshot(solarW: 11, homeW: 11)
        driver.update(flowing)
        driver.renderer(view, updateAtTime: 0)
        guard let material = house.childNode(withName: "PowerFlowWire_Solar_1A", recursively: true)?.geometry?.materials.first else {
            #expect(Bool(false))
            return
        }

        let animator = PowerFlowAnimator(
            solarTerminateAt: 2.2,
            camera: camera,
            clearances: PowerFlowObstacles.clearances(house: house),
            connectorPlug: PowerFlowObstacles.wallConnectorPlug(house: house)
        )
        guard let solar = animator.ribbons.first(where: { $0.name == "Solar_1A" }) else {
            #expect(Bool(false))
            return
        }
        animator.update(flowing)
        let pulse = animator.colors(for: solar, at: 0)?.first
        #expect(pulse != nil)
        #expect(ribbonColor(material, matches: pulse))

        let idle = PowerFlowSnapshot()
        let idleDirection = PowerFlowRemapper.remap(PowerFlowSolver.wires(for: idle))["Solar_1A"]?.direction
        #expect(idleDirection == .idle)
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: idle, interacting: false)
        #expect(view.rendersContinuously == false)
        #expect(view.isPlaying == false)
        animator.update(idle)
        let settled = animator.colors(for: solar, at: 0)?.first
        #expect(settled != nil)
        #expect(ribbonColor(material, matches: settled))
        if let pulse, let settled {
            let gap = abs(pulse.r - settled.r) + abs(pulse.g - settled.g) + abs(pulse.b - settled.b)
            #expect(gap > 0.05)
        }
    }

    /// Live order: the view pauses before the house attaches, then `applyPowerFlow`
    /// stores the snapshot. A later solar-roof change rebuilds the ribbons while
    /// the view is still paused. Both have to show the idle base colour.
    @Test @MainActor func pausedViewPaintsIdleRibbonsAfterTheRendererIsInstalled() {
        let controller = HouseSceneController()
        let view = HouseCameraControlView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.scene = controller.scene
        view.delegate = controller.powerFlow
        let idle = PowerFlowSnapshot()
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: idle, interacting: false)
        #expect(view.rendersContinuously == false)
        #expect(view.isPlaying == false)

        controller.prepareIfNeeded()
        controller.applyPowerFlow(idle, solar: .panels)
        let camera = SIMD3<Float>(
            Float(controller.camera.position.x),
            Float(controller.camera.position.y),
            Float(controller.camera.position.z)
        )
        expectIdleSolarRibbon(in: controller.scene, camera: camera, solarTerminateAt: 2.2, view: view)

        controller.applyPowerFlow(idle, solar: .roof)
        expectIdleSolarRibbon(in: controller.scene, camera: camera, solarTerminateAt: 1000, view: view)
    }

    @Test func movingHouseViewKeepsRendering() {
        let view = HouseCameraControlView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let idle = PowerFlowSnapshot()
        view.applyPlayback(rainIntensity: 0.4, snowIntensity: 0, snapshot: idle, interacting: false)
        #expect(view.rendersContinuously == true)
        #expect(view.isPlaying == true)

        view.applyPlayback(rainIntensity: 0, snowIntensity: 0.4, snapshot: idle, interacting: false)
        #expect(view.rendersContinuously == true)
        #expect(view.isPlaying == true)

        let flowing = PowerFlowSnapshot(solarW: 11, homeW: 11)
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: flowing, interacting: false)
        let ribbonIsFlowing = PowerFlowSolver.wires(for: flowing).contains { $0.isFlowing }
        #expect(ribbonIsFlowing)
        #expect(view.rendersContinuously == true)
        #expect(view.isPlaying == true)

        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: idle, interacting: true)
        #expect(view.rendersContinuously == true)
        #expect(view.isPlaying == true)

        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: idle, interacting: false)
        #expect(view.rendersContinuously == false)
        #expect(view.isPlaying == false)
    }

    @Test func hiddenCloudsDoNotDriftAndOrbitLeavesThemAlone() {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let lighting = HouseLighting(root: house)
        // followSky parks the sky rig on the house's parent so it can face the camera.
        func driftingClouds() -> Int {
            var count = 0
            scene.rootNode.enumerateHierarchy { node, _ in
                if node.name?.hasPrefix("HouseCloud") == true, node.action(forKey: "cloudDrift") != nil {
                    count += 1
                }
            }
            return count
        }
        #expect(driftingClouds() == 0)

        var covered = HouseLightingParameters()
        covered.cloudCover = 1
        lighting.apply(covered, animated: false)
        let drifting = driftingClouds()
        #expect(drifting == HouseSky.wisps.count)
        var cloudMaterials = 0
        scene.rootNode.enumerateHierarchy { node, _ in
            guard node.name?.hasPrefix("HouseCloud") == true else { return }
            cloudMaterials += node.geometry?.materials.count ?? 0
            #expect(node.geometry?.materials.allSatisfy { $0.readsFromDepthBuffer == false } == true)
        }
        #expect(cloudMaterials == HouseSky.wisps.count)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.simdTransform = HouseScenePose.identity.levelTransform
        let size = CGSize(width: 1280, height: 720)
        lighting.updateWeatherCoverage(camera: camera, viewport: size)
        lighting.updateWeatherCoverage(camera: camera, viewport: size)
        #expect(driftingClouds() == drifting)
    }

    @Test func pausedWeatherStopsCloudDriftAndPrecipitation() {
        guard let scene = ResidentialClassicScene.load() else { return }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let lighting = HouseLighting(root: house)
        var storm = HouseLightingParameters()
        storm.cloudCover = 1
        storm.rainIntensity = 0.8
        storm.snowIntensity = 0.4
        lighting.apply(storm, animated: false)
        let rain = scene.rootNode.childNode(withName: "Rain", recursively: true)?.particleSystems?.first
        let snow = scene.rootNode.childNode(withName: "Snow", recursively: true)?.particleSystems?.first
        #expect((rain?.birthRate ?? 0) > 0)
        #expect((snow?.birthRate ?? 0) > 0)

        func pausedClouds() -> Int {
            var count = 0
            scene.rootNode.enumerateHierarchy { node, _ in
                if node.name?.hasPrefix("HouseCloud") == true, node.isPaused, node.action(forKey: "cloudDrift") != nil {
                    count += 1
                }
            }
            return count
        }

        lighting.setWeatherMotionPaused(true)
        #expect(rain?.birthRate == 0)
        #expect(snow?.birthRate == 0)
        #expect(rain?.speedFactor == 0)
        #expect(snow?.speedFactor == 0)
        #expect(pausedClouds() == HouseSky.wisps.count)
        lighting.apply(storm, animated: false)
        #expect(rain?.birthRate == 0)
        #expect(pausedClouds() == HouseSky.wisps.count)

        lighting.setWeatherMotionPaused(false)
        #expect((rain?.birthRate ?? 0) > 0)
        #expect((snow?.birthRate ?? 0) > 0)
        #expect(rain?.speedFactor == 1)
        #expect(snow?.speedFactor == 1)
        #expect(pausedClouds() == 0)
    }

    @Test func cabinCapsCloseAnUpperOpeningAndLeaveTheUndersideOpen() {
        let upper = HouseMeshSeam.cabinCaps(for: openCabinBox(missingTop: true))
        #expect((upper?.elements.first?.primitiveCount ?? 0) >= 2)
        #expect(HouseMeshSeam.cabinCaps(for: openCabinBox(missingTop: false)) == nil)
    }

    private func openCabinBox(missingTop: Bool) -> SCNGeometry {
        let vertices = [
            SCNVector3(0, 0, 0), SCNVector3(2, 0, 0), SCNVector3(2, 0, 4), SCNVector3(0, 0, 4),
            SCNVector3(0, 1, 0), SCNVector3(2, 1, 0), SCNVector3(2, 1, 4), SCNVector3(0, 1, 4),
        ]
        var indices: [UInt32] = []
        func quad(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) {
            indices.append(contentsOf: [a, b, c, a, c, d])
        }
        quad(0, 1, 5, 4)
        quad(1, 2, 6, 5)
        quad(2, 3, 7, 6)
        quad(3, 0, 4, 7)
        if missingTop {
            quad(0, 1, 2, 3)
        } else {
            quad(4, 5, 6, 7)
        }
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [source], elements: [element])
    }

    private func expectIdleSolarRibbon(in scene: SCNScene, camera: SIMD3<Float>, solarTerminateAt: Float, view: HouseCameraControlView) {
        let idle = PowerFlowSnapshot()
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        let node = house.childNode(withName: "PowerFlowWire_Solar_1A", recursively: true)
        #expect(node?.isHidden == false)
        let direction = PowerFlowRemapper.remap(PowerFlowSolver.wires(for: idle))["Solar_1A"]?.direction
        #expect(direction == .idle)
        let animator = PowerFlowAnimator(
            solarTerminateAt: solarTerminateAt,
            camera: camera,
            clearances: PowerFlowObstacles.clearances(house: house),
            connectorPlug: PowerFlowObstacles.wallConnectorPlug(house: house)
        )
        animator.update(idle)
        let settled = animator.ribbons.first { $0.name == "Solar_1A" }.flatMap { animator.colors(for: $0, at: 0)?.first }
        #expect(settled != nil)
        if let material = node?.geometry?.materials.first {
            #expect(ribbonColor(material, matches: settled))
        } else {
            #expect(Bool(false))
        }
        #expect(view.rendersContinuously == false)
        #expect(view.isPlaying == false)
    }

    @Test func pausedWindowDoesNotAdvanceTheSkyEveryTick() {
        #expect(HouseSkyCadence.advancesSun(paused: true, step: 1) == false)
        #expect(HouseSkyCadence.advancesSun(paused: true, step: 44) == false)
        #expect(HouseSkyCadence.advancesSun(paused: false, step: 1) == true)
        #expect(HouseSkyCadence.advancesSun(paused: false, step: 44) == true)
        #expect(HouseSkyCadence.advancesSun(paused: false, step: 0) == false)
        #expect(HouseSkyCadence.advancesSun(paused: false, step: 45) == false)
    }

    @Test @MainActor func houseSceneViewDoesNotReloadTheHouseOnEachUpdate() {
        let model = PowerwallViewModel()
        let before = ResidentialClassicScene.loadCount
        for _ in 0..<4 {
            _ = HouseSceneView(viewModel: model)
        }
        #expect(ResidentialClassicScene.loadCount == before)
    }

    @Test func pauseAnimationWhenUnfocusedStaysOffUntilTheUserTurnsItOn() {
        let suite = "pause-unfocused-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(PauseAnimationWhenUnfocused.stored(in: defaults) == false)
        defaults.set(true, forKey: PauseAnimationWhenUnfocused.key)
        #expect(PauseAnimationWhenUnfocused.stored(in: defaults) == true)
        defaults.set(false, forKey: PauseAnimationWhenUnfocused.key)
        #expect(PauseAnimationWhenUnfocused.stored(in: defaults) == false)
    }

    @Test func focusedFlowUsesTheDisplayRefresh() {
        let flowing = PowerFlowSnapshot(solarW: 11, homeW: 11)
        let full = PresentationRefresh.decision(interacting: false, rainIntensity: 0, snowIntensity: 0, snapshot: flowing)
        #expect(full.animationsPaused == false)
        #expect(full.preferredFramesPerSecond == 0)
        #expect(full.rendersContinuously == true)
        #expect(full.usesDisplayRefresh == true)
        #expect(full.isPlaying == true)

        let idle = PresentationRefresh.decision(interacting: false, rainIntensity: 0, snowIntensity: 0, snapshot: PowerFlowSnapshot())
        #expect(idle.animationsPaused == false)
        #expect(idle.isPlaying == false)
        #expect(idle.rendersContinuously == false)

        let view = HouseCameraControlView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: flowing, interacting: false)
        #expect(view.rendersContinuously == true)
        #expect(view.isPlaying == true)
        #expect(view.preferredFramesPerSecond == 0)
        #expect(view.antialiasingMode == .multisampling4X)
    }

    @Test func offscreenAndUnfocusedPauseUseSolidFlows() {
        let flowing = PowerFlowSnapshot(solarW: 11, homeW: 11)
        let hidden = PresentationRefresh.decision(
            interacting: true,
            rainIntensity: 0.4,
            snowIntensity: 0.4,
            snapshot: flowing,
            revealingWeather: true,
            attention: .hidden,
            pauseWhenUnfocused: false
        )
        #expect(hidden.animationsPaused)
        #expect(hidden.isPlaying == false)
        #expect(hidden.rendersContinuously == false)
        #expect(hidden.usesDisplayRefresh == false)

        let unfocusedStill = PresentationRefresh.decision(
            interacting: false,
            rainIntensity: 0,
            snowIntensity: 0,
            snapshot: flowing,
            attention: .visibleUnfocused,
            pauseWhenUnfocused: true
        )
        #expect(unfocusedStill.animationsPaused)
        #expect(unfocusedStill.isPlaying == false)
        #expect(unfocusedStill.rendersContinuously == false)

        let unfocusedAnimating = PresentationRefresh.decision(
            interacting: false,
            rainIntensity: 0,
            snowIntensity: 0,
            snapshot: flowing,
            attention: .visibleUnfocused,
            pauseWhenUnfocused: false
        )
        #expect(unfocusedAnimating.animationsPaused == false)
        #expect(unfocusedAnimating.usesDisplayRefresh == true)
        #expect(unfocusedAnimating.isPlaying == true)

        #expect(AppAttention.macWindow(isVisible: true, isMiniaturized: false, occlusionVisible: true, appHidden: false, appActive: true) == .focused)
        #expect(AppAttention.macWindow(isVisible: true, isMiniaturized: false, occlusionVisible: true, appHidden: false, appActive: false) == .visibleUnfocused)
        #expect(AppAttention.macWindow(isVisible: true, isMiniaturized: true, occlusionVisible: true, appHidden: false, appActive: true) == .hidden)
        #expect(AppAttention.macWindow(isVisible: false, isMiniaturized: false, occlusionVisible: false, appHidden: false, appActive: true) == .hidden)
        #expect(AppAttention.macWindow(isVisible: true, isMiniaturized: false, occlusionVisible: false, appHidden: false, appActive: true) == .hidden)
        #expect(AppAttention.macWindow(isVisible: true, isMiniaturized: false, occlusionVisible: true, appHidden: true, appActive: false) == .hidden)

        let view = HouseCameraControlView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        view.applyPlayback(rainIntensity: 0.4, snowIntensity: 0, snapshot: flowing, interacting: true, revealingWeather: true, attention: .hidden)
        #expect(view.isPlaying == false)
        #expect(view.rendersContinuously == false)
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: flowing, interacting: false, attention: .visibleUnfocused, pauseWhenUnfocused: true)
        #expect(view.isPlaying == false)
        #expect(view.rendersContinuously == false)
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: flowing, interacting: false, attention: .visibleUnfocused, pauseWhenUnfocused: false)
        #expect(view.rendersContinuously == true)
        #expect(view.isPlaying == true)
        view.applyPlayback(rainIntensity: 0, snowIntensity: 0, snapshot: flowing, interacting: false, attention: .focused)
        #expect(view.rendersContinuously == true)
        #expect(view.isPlaying == true)
    }

    @Test func pausedPowerFlowIsASolidLine() {
        let animator = PowerFlowAnimator()
        animator.update(PowerFlowSnapshot(solarW: 1500, homeW: 1500))
        guard let ribbon = animator.ribbons.first(where: { $0.name == "Solar_1A" }),
              let state = animator.states[ribbon.name],
              ribbon.quadCount > 1 else {
            #expect(Bool(false))
            return
        }
        let solidEarly = animator.colors(for: ribbon, at: 0, solid: true)
        let solidLater = animator.colors(for: ribbon, at: 1.3, solid: true)
        #expect(solidEarly == solidLater)
        let expected = (0..<ribbon.quadCount).map { index -> PowerFlowColor in
            var color = PowerFlowShader.color(
                u: ribbon.midU[index],
                shade: ribbon.shade[index] * animator.brightness,
                alpha: ribbon.alpha[index],
                state: state,
                time: 0,
                params: animator.params,
                solid: true
            )
            color.r = min(color.r, 1)
            color.g = min(color.g, 1)
            color.b = min(color.b, 1)
            return color
        }
        #expect(solidEarly == expected)
        #expect(state.direction == .flowIn || state.direction == .flowOut)
        let pulse = animator.colors(for: ribbon, at: 0, solid: false)
        #expect(pulse != solidEarly)
    }

    @Test func widgetSnapshotShowsTheFixtureWatts() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = EnergyWidgetTimeline.entry(
            solarWatts: 4321,
            homeWatts: 1500,
            batteryWatts: -800,
            gridWatts: 250,
            siteName: "Cabin",
            at: date
        )
        #expect(entry.date == date)
        #expect(entry.solar == "4.321 kW")
        #expect(entry.home == "1.500 kW")
        #expect(entry.battery == "-0.800 kW")
        #expect(entry.batteryMark.isEmpty)
        #expect(entry.grid == "0.250 kW")
        #expect(entry.siteName == "Cabin")
        #expect(entry.summary.contains("4.321"))
        #expect(entry.summary.contains("1.500"))
        #expect(entry.summary.contains("-0.800"))
        #expect(entry.summary.contains("0.250"))
        let coarse = EnergyWidgetTimeline.entry(
            solarWatts: 4321,
            homeWatts: 1500,
            batteryWatts: -800,
            gridWatts: 250,
            siteName: "Cabin",
            showLessPrecision: true,
            at: date
        )
        #expect(coarse.solar == "4.3 kW")
        #expect(coarse.home == "1.5 kW")
        #expect(coarse.battery == "0.8 kW")
        #expect(coarse.grid == "0.2 kW")

        let charging = EnergyWidgetTimeline.entry(
            solarWatts: 4321,
            homeWatts: 1500,
            batteryWatts: -800,
            gridWatts: 250,
            siteName: "Cabin",
            batteryPercent: 80.4,
            at: date
        )
        #expect(charging.batteryMark == "▲")
        #expect(charging.batteryPercent == "80%")
        #expect(charging.batteryLine == "-0.800 kW ▲ 80%")
        let discharging = EnergyWidgetTimeline.entry(
            solarWatts: 0,
            homeWatts: 0,
            batteryWatts: 100,
            gridWatts: 0,
            siteName: "Cabin",
            batteryPercent: 40,
            at: date
        )
        #expect(discharging.batteryMark == "▼")
        #expect(discharging.batteryLine == "0.100 kW ▼ 40%")
        let idle = EnergyWidgetTimeline.entry(
            solarWatts: 0,
            homeWatts: 0,
            batteryWatts: 10,
            gridWatts: 0,
            siteName: "Cabin",
            batteryPercent: 55.2,
            at: date
        )
        #expect(idle.batteryMark == "·")
        #expect(idle.batteryLine == "0.010 kW · 55%")
        #expect(EnergyWidgetSnapshot.oneDecimalPowerText(4321) == "4.3 kW")
        #expect(EnergyWidgetSnapshot.oneDecimalPowerText(-800) == "0.8 kW")
        #expect(EnergyWidgetSnapshot.oneDecimalPowerText(250) == "0.2 kW")
        #expect(EnergyWidgetSnapshot.oneDecimalPowerText(nil) == "—")
        #expect(entry.solarWatts == 4321)

        let suite = "widget-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let reading = EnergyWidgetReading(
            solarWatts: 4321,
            homeWatts: 1500,
            batteryWatts: -800,
            gridWatts: 250,
            siteName: "Cabin",
            updatedAt: date
        )
        EnergyWidgetStore.save(reading, defaults: defaults)
        let loaded = EnergyWidgetStore.load(defaults: defaults)
        let stored = EnergyWidgetTimeline.entry(for: loaded ?? .empty, at: date)
        #expect(stored.solar == entry.solar)
        #expect(stored.home == entry.home)
        #expect(stored.battery == entry.battery)
        #expect(stored.grid == entry.grid)
    }

    @Test func widgetSourcesDoNotLoadTheHouseScene() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let folders = [
            root.appendingPathComponent("PowerwallEnergyWidget"),
            root.appendingPathComponent("Shared"),
        ]
        var sources: [URL] = []
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            sources.append(contentsOf: files.filter { $0.pathExtension == "swift" })
        }
        #expect(sources.count >= 2)
        for file in sources {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("import SceneKit"))
            #expect(!text.contains("HouseSceneView"))
            #expect(!text.contains("ResidentialClassic"))
        }
    }

    @Test func flatHomeLetterboxStillCountsAsOverlappingTheControls() {
        // 850×1022 is taller than 16:9. The fitted image is 1280×720 and leaves
        // the corner buttons and the top summary in the bands around it.
        let scene = CGRect(x: -215, y: 151, width: 1280, height: 720)
        let buttons = CGRect(x: 16, y: 966, width: 160, height: 40)
        let summary = CGRect(x: 24, y: 24, width: 220, height: 80)
        #expect(!OverlayAutoHide.frameIntersects(buttons, scene))
        #expect(!OverlayAutoHide.frameIntersects(summary, scene))
        #expect(OverlayAutoHide.controlsOverlap(showsHouseScene: false, controlsFrame: buttons, sceneFrame: scene))
        #expect(OverlayAutoHide.summaryOverlaps(
            showsHouseScene: false,
            summaryIsInline: false,
            summaryFrame: summary,
            sceneFrame: scene
        ))
        #expect(OverlayAutoHide.summaryOverlaps(
            showsHouseScene: false,
            summaryIsInline: true,
            summaryFrame: .zero,
            sceneFrame: scene
        ))
        #expect(OverlayAutoHide.controlsOverlap(showsHouseScene: true, controlsFrame: .zero, sceneFrame: scene))
        #expect(!OverlayAutoHide.controlsOverlap(showsHouseScene: false, controlsFrame: .zero, sceneFrame: scene))
        #expect(!OverlayAutoHide.summaryOverlaps(
            showsHouseScene: true,
            summaryIsInline: false,
            summaryFrame: summary,
            sceneFrame: scene
        ))
        #expect(!OverlayAutoHide.summaryOverlaps(
            showsHouseScene: true,
            summaryIsInline: true,
            summaryFrame: summary,
            sceneFrame: scene
        ))
    }

    @Test func showroomOpensTheConnectedCarOnTheHomeGlass() {
        let model3 = "5YJ3GDEE5NF000001"
        let modelY = "5YJYGDEE5LF000001"
        let pluggedThenCharging = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [
                .init(vin: model3, din: "stall-a", wallConnectorState: 4, wallConnectorPower: 0),
                .init(vin: modelY, din: "stall-b", wallConnectorState: 1, wallConnectorPower: 2000)
            ]
        )
        let idle = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [.init(vin: modelY, din: "1", wallConnectorState: 0, wallConnectorPower: 0)]
        )
        let paint = DemoHouseTour.parkedCar(at: 1)
        let colourName = TeslaPaint.spacedName(paint.appearance.exteriorColor ?? "")
        let full = VehicleChargeSnapshot(batteryLevel: 80, chargingState: "Charging", minutesToFullCharge: 45)
        let opened = CarShowroom.request(
            data: pluggedThenCharging,
            fallbackVIN: "7G2C12345RF000001",
            appearances: [modelY.lowercased(): paint.appearance],
            solar: .panels,
            vehicles: [FleetVehicle(vin: modelY.lowercased(), displayName: "Daydream", state: "online")],
            charges: [modelY.lowercased(): full],
            displayBoost: 1
        )
        #expect(opened?.vin == GaragePresentation.connectedVIN(wallConnectors: pluggedThenCharging.wallConnectors, fallbackVIN: "7G2C12345RF000001"))
        #expect(GaragePresentation.make(data: idle, fallbackVIN: "", appearances: [:], solar: .panels).showVehicle == false)
        #expect(CarShowroom.request(
            data: idle,
            fallbackVIN: "",
            appearances: [:],
            solar: .panels,
            vehicles: [],
            charges: [:],
            displayBoost: 4
        ) == nil)

        let shown = opened?.lines.joined(separator: "\n") ?? ""
        #expect(shown.contains("80"))
        #expect(shown.contains("Charging"))
        #expect(shown.contains("45"))
        #expect(shown.contains("Daydream"))
        #expect(shown.contains(colourName))
        let generic = DemoHouseTour.parkedCar(at: 0)
        let genericLines = CarShowroom.statLines(
            displayName: generic.vehicle.displayName,
            exteriorColor: generic.appearance.exteriorColor,
            snapshot: full
        )
        // Generic has no colour suffix on its title. The battery line still uses the dot.
        #expect(genericLines.first?.contains("·") == false)
        #expect(genericLines == [generic.vehicle.displayName, "80% battery · Charging", "45 minutes to full charge"])
        #expect(CarShowroom.statLines(
            displayName: "Daydream",
            exteriorColor: nil,
            snapshot: VehicleChargeSnapshot(batteryLevel: 64, chargingState: nil, minutesToFullCharge: nil)
        ) == ["Daydream", "64% battery"])
        #expect(CarShowroom.statLines(
            displayName: "Daydream",
            exteriorColor: nil,
            snapshot: VehicleChargeSnapshot(batteryLevel: nil, chargingState: " Stopped ", minutesToFullCharge: nil)
        ) == ["Daydream", "Stopped"])
        let withoutMinutes = CarShowroom.statLines(
            displayName: "Daydream",
            exteriorColor: paint.appearance.exteriorColor,
            snapshot: VehicleChargeSnapshot(batteryLevel: 80, chargingState: "Charging", minutesToFullCharge: nil)
        )
        #expect(!withoutMinutes.joined(separator: "\n").lowercased().contains("minute"))
        guard let opened else {
            #expect(Bool(false))
            return
        }

        let scene = CarShowroom.scene(for: opened)
        let floorNode = scene.rootNode.childNode(withName: ShowroomStage.floorName, recursively: false)
        let showroomFloor = floorNode?.geometry as? SCNPlane
        #expect(showroomFloor != nil)
        #expect(scene.rootNode.childNode(withName: HouseGroundPlate.name, recursively: false) == nil)
        #expect(abs((showroomFloor?.width ?? 0) - ShowroomStage.floorSize) < 0.001)
        #expect(showroomFloor?.materials.first?.lightingModel == .constant)
        // No SCNFloor reflection and no shader modifier: both failed on an older macOS.
        #expect(showroomFloor?.materials.first?.shaderModifiers == nil)
        #expect(abs(ShowroomStage.floorOpacity(atDistance: 0) - 0.9) < 0.001)
        #expect(abs(ShowroomStage.floorOpacity(atDistance: 4.9) - 0.9) < 0.001)
        #expect(ShowroomStage.floorOpacity(atDistance: 15) < 0.001)
        #expect((floorNode?.categoryBitMask ?? 0) & HouseGroundPlate.reflectionBit == 0)
        let mirror = scene.rootNode.childNode(withName: ShowroomStage.mirrorName, recursively: false)
        #expect(mirror != nil)
        #expect(abs((mirror?.simdScale.y ?? 1) + 1) < 0.001)
        #expect((mirror?.renderingOrder ?? 0) < (floorNode?.renderingOrder ?? 0))
        #expect(scene.lightingEnvironment.contents != nil)
        #expect(abs(scene.lightingEnvironment.intensity - ShowroomStage.environmentIntensity) < 0.001)
        var lights = 0
        scene.rootNode.enumerateHierarchy { node, _ in
            if node.light != nil { lights += 1 }
        }
        #expect(lights == 0)
        let glow = scene.rootNode.childNode(withName: ShowroomStage.glowName, recursively: false)
        #expect(glow != nil)
        #expect((glow?.categoryBitMask ?? 0) & HouseGroundPlate.reflectionBit == 0)
        #expect((glow?.renderingOrder ?? 0) < (floorNode?.renderingOrder ?? 0))
        let shadow = scene.rootNode.childNode(withName: ShowroomStage.groundShadowName, recursively: false)
        #expect(shadow != nil)
        #expect((shadow?.renderingOrder ?? -100) > (floorNode?.renderingOrder ?? 0))
        #expect((shadow?.categoryBitMask ?? 0) & HouseGroundPlate.reflectionBit == 0)
        var vehicle: SCNNode?
        var shell = false
        scene.rootNode.enumerateHierarchy { node, _ in
            if node.name == "Vehicle" { vehicle = node }
            let name = node.name ?? ""
            if name.hasPrefix("Home") || name.hasPrefix("GarageDoor") { shell = true }
        }
        #expect(vehicle != nil)
        if let vehicle, let mirror {
            var carMaterials: [SCNMaterial] = []
            vehicle.enumerateHierarchy { node, _ in carMaterials += node.geometry?.materials ?? [] }
            var mirrorMaterials: [SCNMaterial] = []
            mirror.enumerateHierarchy { node, _ in mirrorMaterials += node.geometry?.materials ?? [] }
            // Shared, so a paint change reaches the reflection too.
            #expect(carMaterials.count == mirrorMaterials.count)
            #expect(zip(carMaterials, mirrorMaterials).allSatisfy { $0 === $1 })
            var renderedAfterTheFloor = false
            mirror.enumerateHierarchy { node, _ in
                if node.renderingOrder >= (floorNode?.renderingOrder ?? 0) { renderedAfterTheFloor = true }
            }
            #expect(!renderedAfterTheFloor)
        }
        var meshes = 0
        vehicle?.enumerateHierarchy { node, _ in
            if node.geometry != nil { meshes += 1 }
        }
        #expect(meshes > 0)
        #expect(shell == false)
    }

    @Test func showroomStageUsesTheTeslaAppValues() {
        #expect(abs(CarShowroomOrbit.verticalFieldOfViewDegrees - 30) < 0.001)
        let offset = CarShowroomOrbit.restingOffset
        let elevation = asin(offset.y / simd_length(offset)) * 180 / .pi
        #expect(abs(elevation - 25) < 0.5)
        let yaw = atan2(offset.x, offset.z) * 180 / .pi
        #expect(abs(yaw - -138) < 0.5)
        #expect(abs(ShowroomStage.backgroundRGB.x - 22 / 255) < 0.001)
        #expect(abs(ShowroomStage.backgroundRGB.z - 24 / 255) < 0.001)
        #expect(HouseLighting.resourceURL(name: ShowroomStage.environmentName, ext: "png") != nil)
        for model in VehicleModel.allCases {
            let shadow = ShowroomStage.groundShadow(for: model)
            #expect(HouseLighting.resourceURL(name: shadow.texture, ext: "png") != nil)
            #expect(shadow.width > 4 && shadow.length > 6)
        }
    }

    @Test func showroomGlowFollowsThePaintLikeTheTeslaFloor() {
        func request(_ model: VehicleModel, colour: String?, override: String? = nil, catalogue: Bool = false) -> CarShowroomRequest {
            CarShowroomRequest(
                vin: nil, model: model, exteriorColor: colour, paintColorOverride: override,
                colorizerRemap: false, displayBoost: 1, lines: [], browsesCatalogue: catalogue
            )
        }
        let white = ShowroomStage.highlight(for: request(.modelY, colour: "PearlWhite"))
        #expect(simd_length(white - ShowroomStage.rgb(0xdadada)) < 0.001)
        let red = ShowroomStage.highlight(for: request(.model3, colour: "Ultra Red", override: TeslaPaint.table["UltraRed"]?.demoOverride))
        #expect(simd_length(red - ShowroomStage.rgb(0xf03042)) < 0.001)
        let truck = ShowroomStage.highlight(for: request(.cybertruck, colour: nil))
        #expect(simd_length(truck - ShowroomStage.rgb(0xc1c1c1)) < 0.001)
        let catalogue = ShowroomStage.highlight(for: request(.model3Highland, colour: nil, catalogue: true))
        #expect(simd_length(catalogue - ShowroomStage.rgb(0x1667ee)) < 0.001)
        // Not in the table: value is lifted to 0.7 and the hue is kept.
        let green = ShowroomStage.highlight(forPaint: SIMD3(0.2, 0.6, 0.3))
        #expect(abs(max(green.x, green.y, green.z) - 0.7) < 0.01)
        #expect(green.y > green.x && green.y > green.z)
        // Near-black paint becomes a soft grey rather than vanishing.
        let black = ShowroomStage.highlight(forPaint: SIMD3(0.02, 0.02, 0.02))
        #expect(black.x > 0.35 && black.x < 0.6)
    }

    @Test func showroomGlowSitsBehindTheCarAndFadesWhenLookingDown() {
        let centre = CarShowroom.stageCentre
        let resting = CarShowroomOrbit()
        let eye = resting.eye(around: centre)
        let forward = simd_normalize(resting.target(around: centre) - eye)
        guard let placement = ShowroomStage.glowPlacement(eye: eye, forward: forward, centre: centre) else {
            Issue.record("No glow placement at the resting camera")
            return
        }
        let origin = SIMD3(placement.transform.columns.3.x, placement.transform.columns.3.y, placement.transform.columns.3.z)
        let glowCentre = SIMD3(centre.x, ShowroomStage.glowCentreHeight, centre.z)
        #expect(abs(simd_length(origin - glowCentre) - ShowroomStage.glowDistance) < 0.01)
        #expect(simd_length(origin - eye) > simd_length(glowCentre - eye))
        let normal = SIMD3(placement.transform.columns.2.x, placement.transform.columns.2.y, placement.transform.columns.2.z)
        #expect(simd_dot(simd_normalize(eye - origin), normal) > 0.999)
        #expect(abs(placement.opacity - ShowroomStage.glowOpacity) < 0.001)

        var overhead = resting
        overhead.pitchDegrees = CarShowroomOrbit.pitchRange.upperBound
        let highEye = overhead.eye(around: centre)
        let highForward = simd_normalize(overhead.target(around: centre) - highEye)
        let high = ShowroomStage.glowPlacement(eye: highEye, forward: highForward, centre: centre)
        #expect((high?.opacity ?? 1) < 0.01)
    }

    @Test func showroomOrbitStartsOnTheRestingCameraAndStaysOnTheCar() {
        let centre = CarShowroom.stageCentre
        let resting = CarShowroomOrbit()
        let target = resting.target(around: centre)
        let eye = resting.eye(around: centre)
        let expected = target + CarShowroomOrbit.restingOffset
        #expect(simd_length(eye - expected) < 0.001)

        var closer = resting
        closer.distanceScale = 0.5
        let near = closer.eye(around: centre)
        #expect(simd_length(near - target) < simd_length(eye - target) - 0.5)

        var spun = resting
        spun.yawDegrees = 90
        let side = spun.eye(around: centre) - target
        let restingOffset = eye - target
        #expect(abs(simd_length(side) - simd_length(restingOffset)) < 0.01)
        #expect(abs(side.x - restingOffset.z) < 0.02)
        #expect(abs(side.z + restingOffset.x) < 0.02)
        #expect(abs(side.y - restingOffset.y) < 0.02)

        var raised = resting
        raised.pitchDegrees = 20
        #expect(raised.eye(around: centre).y > eye.y)

        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let nose = SIMD3<Float>(0, 0, -1)
        #expect(simd_dot(nose, right) < -0.2)
        #expect(simd_dot(eye - target, nose) > 1)
    }

    @Test func showroomStartZoomFitsTheCarToTheWindow() {
        let centre = CarShowroom.stageCentre
        let target = CarShowroomOrbit().target(around: centre)
        let corners = [
            target + SIMD3<Float>(-1.2, -0.5, -2.4),
            target + SIMD3<Float>(1.2, -0.5, -2.4),
            target + SIMD3<Float>(-1.2, 0.9, -2.4),
            target + SIMD3<Float>(1.2, 0.9, -2.4),
            target + SIMD3<Float>(-1.2, -0.5, 2.4),
            target + SIMD3<Float>(1.2, -0.5, 2.4),
            target + SIMD3<Float>(-1.2, 0.9, 2.4),
            target + SIMD3<Float>(1.2, 0.9, 2.4),
        ]
        let wide = CarShowroomOrbit.distanceScale(
            fitting: corners, around: centre, yawDegrees: 0, pitchDegrees: 0, aspect: 16 / 9
        )
        let narrow = CarShowroomOrbit.distanceScale(
            fitting: corners, around: centre, yawDegrees: 0, pitchDegrees: 0, aspect: 9 / 16
        )
        #expect(narrow > wide)
        #expect(showroomFill(of: corners, around: centre, scale: wide, aspect: 16 / 9) <= CarShowroomOrbit.fitFill + 0.02)
        #expect(showroomFill(of: corners, around: centre, scale: narrow, aspect: 9 / 16) <= CarShowroomOrbit.fitFill + 0.02)

        guard let index = CarShowroom.catalogueModels.firstIndex(of: .cybertruck) else {
            Issue.record("Cybertruck is missing from the catalogue")
            return
        }
        let truck = CarShowroom.fitPoints(in: CarShowroom.scene(for: CarShowroom.catalogueRequest(index: index)))
        #expect(truck.count > 8)
        let fitted = CarShowroomOrbit.distanceScale(
            fitting: truck, around: centre, yawDegrees: 0, pitchDegrees: 0, aspect: 16 / 9
        )
        #expect(showroomFill(of: truck, around: centre, scale: fitted, aspect: 16 / 9) <= CarShowroomOrbit.fitFill + 0.02)
    }

    @Test func showroomCarSitsOnTheHorizontalCentre() {
        let centre = CarShowroom.stageCentre
        let target = CarShowroomOrbit().target(around: centre)
        let box = [
            SIMD3<Float>(-1.2, -0.4, -2.2),
            SIMD3<Float>(1.2, -0.4, -2.2),
            SIMD3<Float>(-1.2, 0.8, -2.2),
            SIMD3<Float>(1.2, 0.8, -2.2),
            SIMD3<Float>(-1.2, -0.4, 2.2),
            SIMD3<Float>(1.2, -0.4, 2.2),
            SIMD3<Float>(-1.2, 0.8, 2.2),
            SIMD3<Float>(1.2, 0.8, 2.2),
        ].map { target + $0 }
        let leaning = showroomHorizontalCentre(of: box, around: centre, scale: 1, bias: .zero, aspect: 16 / 9)
        #expect(abs(leaning) > 0.05)
        let bias = CarShowroomOrbit.centreBias(
            fitting: box, around: centre, yawDegrees: 0, pitchDegrees: 0, distanceScale: 1
        )
        #expect(abs(showroomHorizontalCentre(of: box, around: centre, scale: 1, bias: bias, aspect: 16 / 9)) < 0.02)
        #expect(abs(showroomHorizontalCentre(of: box, around: centre, scale: 1, bias: bias, aspect: 9 / 16)) < 0.02)

        for model in [VehicleModel.model3, .modelS, .cybertruck] {
            guard let index = CarShowroom.catalogueModels.firstIndex(of: model) else {
                Issue.record("\(model.rawValue) is missing from the catalogue")
                continue
            }
            let points = CarShowroom.fitPoints(in: CarShowroom.scene(for: CarShowroom.catalogueRequest(index: index)))
            #expect(points.count > 8)
            for yaw in [Float(0), Float(75)] {
                let shift = CarShowroomOrbit.centreBias(
                    fitting: points, around: centre, yawDegrees: yaw, pitchDegrees: -8, distanceScale: 1.4
                )
                let mid = showroomHorizontalCentre(
                    of: points, around: centre, yaw: yaw, pitch: -8, scale: 1.4, bias: shift, aspect: 16 / 9
                )
                #expect(abs(mid) < 0.02)
                let fitted = CarShowroomOrbit.distanceScale(
                    fitting: points, around: centre, yawDegrees: yaw, pitchDegrees: -8, aspect: 16 / 9
                )
                let fittedShift = CarShowroomOrbit.centreBias(
                    fitting: points, around: centre, yawDegrees: yaw, pitchDegrees: -8, distanceScale: fitted
                )
                let fittedMid = showroomHorizontalCentre(
                    of: points, around: centre, yaw: yaw, pitch: -8, scale: fitted, bias: fittedShift, aspect: 16 / 9
                )
                #expect(abs(fittedMid) < 0.02)
                let fill = showroomFill(
                    of: points, around: centre, yaw: yaw, pitch: -8, scale: fitted, bias: fittedShift, aspect: 16 / 9
                )
                #expect(fill <= CarShowroomOrbit.fitFill + 0.02)
            }
        }
    }

    /// Screen-space midpoint of the points. Zero is the horizontal centre of the window.
    private func showroomHorizontalCentre(
        of points: [SIMD3<Float>],
        around centre: SIMD3<Float>,
        yaw: Float = 0,
        pitch: Float = 0,
        scale: Float,
        bias: SIMD3<Float>,
        aspect: Float
    ) -> Float {
        var pose = CarShowroomOrbit()
        pose.yawDegrees = yaw
        pose.pitchDegrees = pitch
        pose.distanceScale = scale
        pose.centreBias = bias
        let eye = pose.eye(around: centre)
        let target = pose.target(around: centre)
        let forward = simd_normalize(target - eye)
        var right = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        right = simd_normalize(right)
        let tanX = tan(CarShowroomOrbit.verticalFieldOfViewDegrees * .pi / 180 / 2) * aspect
        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        for point in points {
            let depth = simd_dot(point - eye, forward)
            guard depth > 0.001 else { return 10 }
            let x = simd_dot(point - eye, right) / (depth * tanX)
            minX = min(minX, x)
            maxX = max(maxX, x)
        }
        return (minX + maxX) / 2
    }

    /// Largest fraction of the vertical or horizontal frame used by these points.
    private func showroomFill(
        of points: [SIMD3<Float>],
        around centre: SIMD3<Float>,
        yaw: Float = 0,
        pitch: Float = 0,
        scale: Float,
        bias: SIMD3<Float> = .zero,
        aspect: Float
    ) -> Float {
        var pose = CarShowroomOrbit()
        pose.yawDegrees = yaw
        pose.pitchDegrees = pitch
        pose.distanceScale = scale
        pose.centreBias = bias
        let eye = pose.eye(around: centre)
        let target = pose.target(around: centre)
        let forward = simd_normalize(target - eye)
        var right = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(right, forward))
        let tanY = tan(CarShowroomOrbit.verticalFieldOfViewDegrees * .pi / 180 / 2)
        let tanX = tanY * aspect
        var used: Float = 0
        for point in points {
            let depth = simd_dot(point - eye, forward)
            guard depth > 0.001 else { return 10 }
            used = max(used, abs(simd_dot(point - eye, right)) / (depth * tanX))
            used = max(used, abs(simd_dot(point - eye, up)) / (depth * tanY))
        }
        return used
    }

    @Test func showroomPanFollowsThePointerAndStaysNearTheCar() {
        let centre = CarShowroom.stageCentre
        var pose = CarShowroomOrbit()
        let before = pose.target(around: centre)
        let eye = pose.eye(around: centre)
        let forward = simd_normalize(before - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_normalize(simd_cross(right, forward))
        pose.pan(screenX: 180, screenY: 0, viewHeight: 900, around: centre)
        let moved = pose.target(around: centre) - before
        #expect(simd_dot(moved, right) < -0.15)
        #expect(abs(simd_dot(moved, up)) < 0.02)
        #expect(abs(simd_dot(moved, forward)) < 0.05)
        let offset = pose.eye(around: centre) - pose.target(around: centre)
        #expect(simd_length(offset - (eye - before)) < 0.001)

        var limited = CarShowroomOrbit()
        limited.pan(by: SIMD3(2, 0, 0))
        limited.pan(by: SIMD3(2, -8, 4))
        #expect(abs(limited.pan.x - 3) < 0.001)
        #expect(abs(limited.pan.y + 3) < 0.001)
        #expect(abs(limited.pan.z - 3) < 0.001)
    }

    @Test func showroomLampsUseTheTeslaAppMaterials() {
        guard let index = CarShowroom.catalogueModels.firstIndex(of: .model3) else {
            Issue.record("Model 3 is missing from the catalogue")
            return
        }
        let scene = CarShowroom.scene(for: CarShowroom.catalogueRequest(index: index))
        #expect(material(named: "Lights", in: scene) == nil)
        guard let housing = material(named: VehicleLamps.housingName, in: scene),
              let lens = material(named: VehicleLamps.glassName, in: scene) else {
            Issue.record("Model 3 has no lamp housing or lamp glass")
            return
        }
        #expect(housing.lightingModel == .physicallyBased)
        #expect(housing.diffuse.contents != nil)
        // The atlas shows at a readable albedo, not the app's ~0.1 that turned every lamp black.
        // Black stays only where the atlas is black (trim); the charge port is its own Trim mesh.
        #expect(abs(housing.diffuse.intensity - VehicleLamps.displayAlbedo) < 0.001)
        #expect(housing.diffuse.intensity >= 0.5)
        // Never black: no metal (no lighting environment in the home view), no occlusion map,
        // and a faint emission of the same atlas. That glow is a floor, not the lamps switching on.
        #expect((housing.metalness.contents as? NSNumber)?.doubleValue == 0)
        #expect(housing.ambientOcclusion.contents == nil)
        #expect(housing.emission.contents != nil)
        #expect(abs(housing.emission.intensity - VehicleLamps.emissionFloor) < 0.001)
        #expect(VehicleLamps.emissionFloor > 0 && VehicleLamps.emissionFloor <= 0.35)
        #expect(VehicleLamps.displayAlbedo >= 1)
        #expect(housing.transparency == 1)
        #expect(housing.writesToDepthBuffer)
        let lensGlow = rgb(lens.emission.contents)
        #expect(lensGlow.red + lensGlow.green + lensGlow.blue < 0.01)
        #expect(rgb(lens.multiply.contents).red > 0.99)
        // The lens node draws after the car.
        var lensOrder = Int.min
        scene.rootNode.enumerateChildNodes { node, _ in
            if node.geometry?.materials.contains(where: { $0 === lens }) == true,
               !(node.parent?.name ?? "").contains(ShowroomStage.mirrorName) {
                lensOrder = max(lensOrder, node.renderingOrder)
            }
        }
        #expect(lensOrder >= VehicleLamps.lensRenderingOrder)
        #expect(rgb(lens.transparent.contents).red > 0.99)
        // Tesla's Glass_Lights smoke, drawn as one see-through layer.
        // Near-clear glossy glass, not Tesla's near-black smoke at 0.51.
        #expect(abs(lens.transparency - VehicleLamps.lensOpacity) < 0.001)
        #expect(lens.transparency <= 0.3)
        // Opacity = transparent alpha (1) × transparency, so the lens is mostly see-through.
        #expect(lens.lightingModel == .blinn)
        #expect(abs(rgb(lens.diffuse.contents).red - Double(VehicleLamps.lensTint)) < 0.01)
        #expect(lens.colorBufferWriteMask == .all)
        #expect(lens.blendMode == .alpha)
        #expect(lens.transparencyMode == .aOne)
        #expect(!lens.isDoubleSided)
        #expect(lens.cullMode == .back)
        #expect(!lens.writesToDepthBuffer)

        var housingHasTextureCoordinates = false
        scene.rootNode.enumerateChildNodes { node, stop in
            guard let geometry = node.geometry,
                  geometry.materials.contains(where: { $0.name == VehicleLamps.housingName }) else { return }
            housingHasTextureCoordinates = !geometry.sources(for: .texcoord).isEmpty
            stop.pointee = true
        }
        #expect(housingHasTextureCoordinates)

        for model in VehicleModel.allCases where model != .generic {
            #expect(VehicleLamps.housing(for: model) != nil)
            #expect(VehicleLamps.lens(for: model) != nil)
            if let texture = VehicleLamps.housing(for: model)?.texture {
                #expect(HouseLighting.resourceURL(name: "\(texture)_Lamps_BC", ext: "png") != nil)
                #expect(HouseLighting.resourceURL(name: "\(texture)_Lamps_MRA", ext: "png") != nil)
            }
        }
        #expect(VehicleLamps.housing(for: .modelYJuniper)?.texture == nil)

        let generic = CarShowroom.scene(for: CarShowroomRequest(
            vin: nil,
            model: .generic,
            exteriorColor: nil,
            paintColorOverride: nil,
            colorizerRemap: false,
            displayBoost: 1,
            lines: []
        ))
        #expect(material(named: "Lights", in: generic) == nil)
        #expect(material(named: VehicleLamps.housingName, in: generic) == nil)
    }

    @Test func lampDebugSettingParsesHideLens() {
        let key = "debugLamps"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.set("hideLens", forKey: key)
        #expect(VehicleLamps.debugHideLens)
        #expect(VehicleLamps.debugLogging)
        UserDefaults.standard.set("YES", forKey: key)
        #expect(!VehicleLamps.debugHideLens)
        #expect(VehicleLamps.debugLogging)
    }

    @Test func lampMaterialsMatchTheNamesSceneKitMightGive() {
        #expect(VehicleLamps.role(material: "Lamps", node: nil) == .housing)
        #expect(VehicleLamps.role(material: "/ModelY/Materials/Lamps", node: nil) == .housing)
        #expect(VehicleLamps.role(material: "Lamps_1", node: nil) == .housing)
        #expect(VehicleLamps.role(material: "LampGlass", node: nil) == .lens)
        #expect(VehicleLamps.role(material: nil, node: "LampGlass") == .lens)
        #expect(VehicleLamps.role(material: "material", node: "Lamps") == .housing)
        #expect(VehicleLamps.role(material: "Glass", node: "Glass") == nil)
        #expect(VehicleLamps.role(material: "Paint", node: nil) == nil)
    }

    @Test func housingWithoutTextureCoordinatesFallsBackToGreyNotBlack() {
        let plain = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        let source = plain.sources(for: .vertex)
        let element = plain.elements[0]
        let bare = SCNGeometry(sources: source, elements: [element])
        let material = SCNMaterial()
        material.name = VehicleLamps.housingName
        bare.materials = [material]
        let lines = VehicleLamps.dress(bare, nodeName: "Lamps", model: .modelY)
        #expect(lines.count == 1)
        #expect(lines.first?.contains("no texture coordinates") == true)
        #expect(rgb(material.diffuse.contents).red > 0.3)
        #expect((material.metalness.contents as? NSNumber)?.doubleValue == 0)
    }

    @Test func usdzWiresTheLampAtlasSoSceneKitKeepsTheUVs() throws {
        for model in VehicleModel.allCases {
            guard let texture = VehicleLamps.housing(for: model)?.texture,
                  let url = HouseLighting.resourceURL(name: model.rawValue, ext: "usdz") else { continue }
            let data = try Data(contentsOf: url)
            // The packaged atlas sits next to the layer in the usdz (a zip), named by the tool.
            let name = Data("0/\(texture)_Lamps_BC.png".utf8)
            #expect(data.range(of: name) != nil, "\(model.rawValue).usdz has no packaged lamp atlas")
        }
    }

    @Test func everyCarsLampsAreSeeThroughInTheShowroomAndTheGarage() throws {
        for model in VehicleModel.allCases where model != .generic {
            let scene = CarShowroom.scene(for: CarShowroomRequest(
                vin: nil, model: model, exteriorColor: nil, paintColorOverride: nil,
                colorizerRemap: false, displayBoost: 1, lines: []
            ))
            guard let lens = material(named: VehicleLamps.glassName, in: scene),
                  let housing = material(named: VehicleLamps.housingName, in: scene) else {
                Issue.record("\(model.rawValue) has no lamp glass or housing")
                continue
            }
            #expect(!lens.isDoubleSided)
            #expect(lens.transparency <= 0.3)
            // The floor mirror culls the flipped lens from the other side and leaves the car's alone.
            if let mirror = scene.rootNode.childNode(withName: ShowroomStage.mirrorName, recursively: true) {
                mirror.enumerateHierarchy { node, _ in
                    node.geometry?.materials.filter { $0.name == VehicleLamps.glassName }.forEach {
                        #expect(!$0.isDoubleSided)
                        #expect($0.cullMode == .front)
                        #expect($0 !== lens)
                    }
                }
            }
            if VehicleLamps.housing(for: model)?.texture != nil {
                #expect(abs(housing.diffuse.intensity - VehicleLamps.displayAlbedo) < 0.001)
            }
        }

        // The home view's garage dresses the parked car the same way, after its shell repair
        // has made every material double-sided.
        guard let houseScene = ResidentialClassicScene.load() else { return }
        let house = houseScene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? houseScene.rootNode
        let lighting = HouseLighting(root: house)
        lighting.setVehicleModel(.modelY)
        lighting.showVehicle(true)
        let vehicle = try #require(house.childNode(withName: "Vehicle", recursively: true))
        var lenses = 0
        var housings = 0
        vehicle.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { material in
                if material.name == VehicleLamps.glassName {
                    lenses += 1
                    #expect(!material.isDoubleSided)
                    #expect(material.transparency <= 0.3)
                }
                if material.name == VehicleLamps.housingName {
                    housings += 1
                    #expect(abs(material.diffuse.intensity - VehicleLamps.displayAlbedo) < 0.001)
                }
            }
        }
        #expect(lenses > 0)
        #expect(housings > 0)
    }

    @Test func juniperKeepsItsBPillarsAndGlassRoof() {
        let scene = CarShowroom.scene(for: CarShowroomRequest(
            vin: nil,
            model: .modelYJuniper,
            exteriorColor: nil,
            paintColorOverride: nil,
            colorizerRemap: false,
            displayBoost: 1,
            lines: []
        ))
        #expect(material(named: "Pillar", in: scene) != nil)
        // The roof glass sits on top of the car. It used to come through as Trim.
        var glassTop: Float = -.infinity
        var trimTop: Float = -.infinity
        scene.rootNode.childNode(withName: "Vehicle", recursively: false)?.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry, let name = geometry.materials.first?.name else { return }
            let top = Float(geometry.boundingBox.max.y)
            if name == "Glass" { glassTop = max(glassTop, top) }
            if name == "Trim" { trimTop = max(trimTop, top) }
        }
        #expect(glassTop >= trimTop)
    }

    @Test func showroomColourStepsWrapTheCatalogue() {
        let last = TeslaPaint.catalogue.count - 1
        #expect(CarShowroom.colourIndex(after: nil, delta: 1) == 0)
        #expect(CarShowroom.colourIndex(after: nil, delta: -1) == last)
        #expect(CarShowroom.colourIndex(after: 0, delta: -1) == last)
        #expect(CarShowroom.colourIndex(after: last, delta: 1) == 0)
    }

    @Test func cybertruckShowroomKeepsTheGlassRoofAndCanTakeAColour() {
        guard let index = CarShowroom.catalogueModels.firstIndex(of: .cybertruck) else {
            Issue.record("Cybertruck is missing from the catalogue")
            return
        }
        var request = CarShowroom.catalogueRequest(index: index)
        let scene = CarShowroom.scene(for: request)
        let glass = material(named: "Glass", in: scene)
        let paint = material(named: "Paint", in: scene)
        #expect(abs((glass?.transparency ?? 0) - VehicleGlass.transparency) < 0.001)
        #expect(glass?.isDoubleSided == true)
        #expect((glassNode(in: scene)?.geometry?.boundingBox.max.y ?? 0) > 1.7)
        let fileMetal = number(paint?.metalness.contents) ?? -1

        request.paintColorOverride = TeslaPaint.catalogue[0].demoOverride
        request.displayBoost = 1
        let coloured = CarShowroom.scene(for: request)
        let colouredMetal = number(material(named: "Paint", in: coloured)?.metalness.contents) ?? -1
        #expect(abs(fileMetal - 0.35) < 0.001)
        #expect(abs(colouredMetal - Double(TeslaPaint.catalogue[0].metallic)) < 0.001)
        #expect(abs((material(named: "Glass", in: coloured)?.transparency ?? 0) - VehicleGlass.transparency) < 0.001)
    }

    private func glassNode(in scene: SCNScene) -> SCNNode? {
        var found: SCNNode?
        scene.rootNode.enumerateChildNodes { node, stop in
            guard node.geometry?.materials.contains(where: { $0.name == "Glass" }) == true else { return }
            found = node
            stop.pointee = true
        }
        return found
    }

    private func material(named name: String, in scene: SCNScene) -> SCNMaterial? {
        var found: SCNMaterial?
        scene.rootNode.enumerateChildNodes { node, stop in
            guard let material = node.geometry?.materials.first(where: { $0.name == name }) else { return }
            found = material
            stop.pointee = true
        }
        return found
    }

    private func rgb(_ value: Any?) -> (red: Double, green: Double, blue: Double) {
        #if canImport(AppKit)
        if let color = (value as? NSColor)?.usingColorSpace(.deviceRGB) {
            return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
        }
        #elseif canImport(UIKit)
        if let color = value as? UIColor {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                return (Double(red), Double(green), Double(blue))
            }
        }
        #endif
        return (0, 0, 0)
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let number = value as? Double { return number }
        if let number = value as? CGFloat { return Double(number) }
        return nil
    }

    @Test func showroomTransitionZoomsTheHomeAwayThenFadesBackAtRest() {
        let home = CarShowroomTransition()
        #expect(home.homeOpacity == 1)
        #expect(home.homeScale == 1)
        #expect(home.showroomOpacity == 0)

        let leaving = CarShowroomTransition.homeDeparted
        #expect(leaving.homeOpacity == 0)
        #expect(leaving.homeScale == CarShowroomTransition.zoom)
        #expect(leaving.showroomOpacity == 0)

        var halfway = CarShowroomTransition()
        halfway.holdsZoom = true
        halfway.homeReveal = 0.5
        #expect(abs(halfway.homeScale - (1 + (CarShowroomTransition.zoom - 1) / 2)) < 0.001)
        #expect(halfway.homeOpacity == 0.5)
        #expect(halfway.showroomOpacity == 0)

        let showroom = CarShowroomTransition.showroom
        #expect(showroom.homeOpacity == 0)
        #expect(showroom.homeScale == CarShowroomTransition.zoom)
        #expect(showroom.showroomOpacity == 1)

        let returned = CarShowroomTransition.showroomDeparted
        #expect(returned.homeOpacity == 0)
        #expect(returned.homeScale == 1)
        #expect(returned.showroomOpacity == 0)
    }

    @Test func showroomCatalogueCyclesModelsWhenTheAccountHasNoCars() {
        let idle = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [.init(vin: "5YJYGDEE5LF000001", din: "1", wallConnectorState: 0, wallConnectorPower: 0)]
        )
        let shopper = CarShowroom.select(
            data: idle,
            fallbackVIN: "",
            appearances: [:],
            solar: .panels,
            vehicles: [],
            charges: [:],
            displayBoost: 4,
            isDemoMode: false
        )
        let models = CarShowroom.catalogueModels
        #expect(models == VehicleModel.allCases.filter { $0 != .generic })
        #expect(shopper?.browsesCatalogue == true)
        #expect(shopper?.model == models.first)
        #expect(shopper?.lines == [CarShowroom.catalogueName(models[0])])

        let owner = CarShowroom.select(
            data: idle,
            fallbackVIN: "",
            appearances: [:],
            solar: .panels,
            vehicles: [FleetVehicle(vin: "5YJYGDEE5LF000001", displayName: "Daydream", state: "online")],
            charges: [:],
            displayBoost: 4,
            isDemoMode: false
        )
        #expect(owner == nil)
        let demo = CarShowroom.select(
            data: idle,
            fallbackVIN: "",
            appearances: [:],
            solar: .panels,
            vehicles: [],
            charges: [:],
            displayBoost: 1,
            isDemoMode: true
        )
        #expect(demo == nil)
        let parkedDemo = DemoHouseTour.parkedCar(at: 1)
        let demoCharging = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [.init(vin: parkedDemo.vehicle.vin, din: "1", wallConnectorState: 1, wallConnectorPower: 512)]
        )
        let demoShowroom = CarShowroom.select(
            data: demoCharging,
            fallbackVIN: "",
            appearances: [parkedDemo.vehicle.vin: parkedDemo.appearance],
            solar: .panels,
            vehicles: [FleetVehicle(vin: parkedDemo.vehicle.vin, displayName: parkedDemo.vehicle.displayName, state: "online")],
            charges: [:],
            displayBoost: 1,
            isDemoMode: true
        )
        let demoLines = demoShowroom?.lines.joined(separator: "\n") ?? ""
        #expect(demoShowroom?.lines.contains("80% battery · Charging") == true)
        #expect(demoLines.contains("45 minutes to full charge"))
        #expect(demoLines.contains(parkedDemo.vehicle.displayName))

        var seen: [VehicleModel] = []
        for index in 0..<models.count {
            let page = CarShowroom.catalogueRequest(index: index)
            seen.append(page.model)
            #expect(page.browsesCatalogue)
            #expect(page.lines == [CarShowroom.catalogueName(page.model)])
            #expect(!page.lines.joined(separator: "\n").lowercased().contains("minute"))
            #expect(!page.lines.joined(separator: "\n").contains("%"))
            let url = CarShowroom.orderURL(for: page.model)
            #expect(url.scheme == "https")
            #expect(url.host == "www.tesla.com")
        }
        #expect(seen == models)
        #expect(CarShowroom.catalogueRequest(index: models.count).model == models.first)
        #expect(CarShowroom.catalogueRequest(index: -1).model == models.last)
        #expect(CarShowroom.orderURL(for: .model3) == CarShowroom.orderURL(for: .model3Highland))
        #expect(CarShowroom.orderURL(for: .modelY) == CarShowroom.orderURL(for: .modelYJuniper))
        #expect(CarShowroom.orderURL(for: .modelS).path.contains("models"))
        #expect(CarShowroom.orderURL(for: .cybertruck).path.contains("cybertruck"))

        let charging = PowerwallData(
            battery: .init(instantPower: 0, count: 1),
            load: .init(instantPower: 0),
            solar: .init(instantPower: 0, energyExported: 0),
            site: .init(instantPower: 0),
            wallConnectors: [.init(vin: "5YJYGDEE5LF000001", din: "1", wallConnectorState: 1, wallConnectorPower: 2000)]
        )
        let parked = CarShowroom.select(
            data: charging,
            fallbackVIN: "",
            appearances: [:],
            solar: .panels,
            vehicles: [],
            charges: [:],
            displayBoost: 4,
            isDemoMode: false
        )
        #expect(parked?.browsesCatalogue == false)
        #expect(parked?.vin == GaragePresentation.connectedVIN(wallConnectors: charging.wallConnectors, fallbackVIN: ""))
    }

    private func ribbonColor(_ material: SCNMaterial, matches color: PowerFlowColor?) -> Bool {
        guard let color, let painted = material.diffuse.contents as? HouseColor else { return false }
        let resolved = painted.usingColorSpace(.sRGB) ?? painted
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return abs(Float(red) - color.r) < 0.02
            && abs(Float(green) - color.g) < 0.02
            && abs(Float(blue) - color.b) < 0.02
    }
}
