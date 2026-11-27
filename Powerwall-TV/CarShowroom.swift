//
//  CarShowroom.swift
//  Powerwall-TV
//
//  Fullscreen garage lineup, staged the way the Tesla app shows it (see ShowroomStage.swift):
//  the account's own cars first, then every model Tesla sells with a buy link.
//  The house shell stays out of this scene.
//

import SceneKit
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Which car a garage-door or charging-car select opens, and the Fleet lines already stored for it.
struct CarShowroomRequest: Equatable, Identifiable {
    var vin: String?
    var model: VehicleModel
    var exteriorColor: String?
    var paintColorOverride: String?
    var colorizerRemap: Bool
    /// 1 in demo, where the paint hex is already a display colour. Live Fleet albedos use 4.
    var displayBoost: CGFloat
    var lines: [String]
    /// A model Tesla sells, with no Fleet stats. iPhone, iPad and Mac show a Buy a Tesla button. tvOS hides it. No info panel.
    var browsesCatalogue: Bool = false
    /// The garage lineup this request opens on: the account's own cars first, then every
    /// catalogue model. Empty for a single car. The arrows step through it.
    var lineup: [CarShowroomRequest] = []
    /// Lineup entry the showroom opens on: the last car shown, when it is still in the lineup.
    var startIndex: Int = 0
    /// `vehicle_config.wheel_type`, saved per VIN. Nil, "" and catalogue cars get the model's standard
    /// wheels (`WheelChoice.resolve`). Edit mode sets `wearsChosenWheel` so a catalogue car can try one.
    var wheelType: String? = nil
    /// The showroom edit arrows picked this `wheelType`. Catalogue cars otherwise ignore it.
    var wearsChosenWheel: Bool = false

    var id: String { vin ?? model.rawValue }
}

/// How the showroom paints one car.
enum ShowroomPaint: Equatable {
    /// The colour exported in the file. Catalogue cars, Generic and a stainless Cybertruck.
    case file
    /// An account car whose paint is not known yet: the Tesla app's neutral fallback grey, never a file
    /// colour that could pass for a real paint (Highland's file is blue, Model Y's is white).
    case unknown
    /// A table paint, drawn with its readable display colour at boost 1 (`TeslaPaint.display`).
    case named(TeslaPaint)
    /// A `paint_color_override` with no paint name the table knows, at the request's boost.
    case custom(TeslaPaint)

    /// Name first, so a known paint always reads as itself, live or demo. The override is only used
    /// when the name is missing or unknown. `owned` is false for a catalogue car, which keeps its file colour.
    static func resolve(
        model: VehicleModel,
        exteriorColor: String?,
        paintColorOverride: String?,
        colorizerRemap: Bool,
        owned: Bool
    ) -> ShowroomPaint {
        let wrap = paintColorOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if model == .generic { return .file }
        if model == .cybertruck && wrap.isEmpty { return .file }
        if let name = exteriorColor, let paint = TeslaPaint(exteriorColor: name) {
            return .named(paint.display)
        }
        if !wrap.isEmpty, let paint = TeslaPaint(paintColorOverride: wrap, colorizerRemap: colorizerRemap) {
            return .custom(paint)
        }
        return owned ? .unknown : .file
    }

    static func resolve(for request: CarShowroomRequest) -> ShowroomPaint {
        let vin = request.vin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return resolve(
            model: request.model,
            exteriorColor: request.exteriorColor,
            paintColorOverride: request.paintColorOverride,
            colorizerRemap: request.colorizerRemap,
            owned: !request.browsesCatalogue && !vin.isEmpty
        )
    }

    /// Nil keeps the colour exported in the file. A named paint is already a display colour, so its boost is 1.
    /// An unknown owned car and a custom override still use `displayBoost` (4 for a live car, 1 in demo).
    func bodyPaint(displayBoost: CGFloat) -> (paint: TeslaPaint, boost: CGFloat)? {
        switch self {
        case .file:
            return nil
        case .unknown:
            return (TeslaPaint.fallback, displayBoost)
        case .named(let paint):
            return (paint, 1)
        case .custom(let paint):
            return (paint, displayBoost)
        }
    }

    var debugDescription: String {
        switch self {
        case .file: return "file colour"
        case .unknown: return "unknown → fallback grey"
        case .named(let paint): return "named \(paint.name) display #\(String(format: "%06X", paint.hex))"
        case .custom(let paint): return "override #\(String(format: "%06X", paint.hex))"
        }
    }
}

/// Where an owned car's paint came from.
enum PaintSourceKind: String {
    /// `vehicle_config` from `vehicle_data`, saved per VIN.
    case vehicleConfig = "vehicle_config (saved per VIN)"
    case productsColor = "products.color"
    case none = "none"
}

/// The last car shown in the showroom, saved so the next open starts there. A VIN for an owned car,
/// the model for a catalogue car, never an index. Demo neither reads nor writes it.
enum ShowroomLastCar {
    static let storageKey = "showroom_lastCar"

    static func key(for car: CarShowroomRequest) -> String {
        if !car.browsesCatalogue, let vin = car.vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty {
            return "vin:" + vin.uppercased()
        }
        return "model:" + car.model.rawValue
    }

    /// Where the saved car sits in this lineup, or nil when it is gone.
    static func index(of key: String?, in request: CarShowroomRequest) -> Int? {
        guard let key, !key.isEmpty else { return nil }
        let entries = request.lineup.isEmpty ? [request] : request.lineup
        return entries.firstIndex { Self.key(for: $0) == key }
    }

    static func load(from defaults: UserDefaults = .standard, isDemoMode: Bool) -> String? {
        isDemoMode ? nil : defaults.string(forKey: storageKey)
    }

    static func save(_ car: CarShowroomRequest, to defaults: UserDefaults = .standard, isDemoMode: Bool) {
        guard !isDemoMode else { return }
        let key = key(for: car)
        guard defaults.string(forKey: storageKey) != key else { return }
        defaults.set(key, forKey: storageKey)
    }

    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}

/// Garage open zooms the home in and fades it out, then fades the showroom in.
/// Close fades the showroom out, then fades the home back in at its resting scale.
struct CarShowroomTransition: Equatable {
    /// Extra scale at the end of the zoom into the garage.
    static let zoom: CGFloat = 1.25
    static let homeDuration: TimeInterval = 0.55
    static let showroomDuration: TimeInterval = 0.4

    /// 1 is the home fully shown. 0 is the home hidden.
    var homeReveal: Double = 1
    /// Keeps the zoom while the home is hidden. Cleared, still hidden, before it fades back.
    var holdsZoom = false
    /// 1 is the showroom fully shown.
    var showroomReveal: Double = 0

    var homeOpacity: Double { homeReveal }

    var homeScale: CGFloat {
        guard holdsZoom else { return 1 }
        return 1 + (1 - CGFloat(homeReveal)) * (Self.zoom - 1)
    }

    var showroomOpacity: Double { showroomReveal }

    /// Home has finished zooming out. The showroom is mounted and still invisible.
    static let homeDeparted = CarShowroomTransition(homeReveal: 0, holdsZoom: true, showroomReveal: 0)
    /// Showroom fully in. The home stays hidden at the zoomed scale.
    static let showroom = CarShowroomTransition(homeReveal: 0, holdsZoom: true, showroomReveal: 1)
    /// Showroom gone. Scale is back to rest while the home is still invisible.
    static let showroomDeparted = CarShowroomTransition(homeReveal: 0, holdsZoom: false, showroomReveal: 0)
}

enum CarShowroom {
    static let cameraName = "ShowroomCamera"

    /// Graph close padding, measured from the safe area. The showroom draws full bleed, and on iPad
    /// the full-bleed reader can report no inset while the graph still sits below the status bar.
    /// The larger of the two insets keeps the symbols on the same row.
    static func closePadding(reportedSafe: CGFloat, windowSafe: CGFloat, extra: CGFloat) -> CGFloat {
        max(reportedSafe, windowSafe) + extra
    }
    /// Same point the ground plate is built around.
    static var stageCentre: SIMD3<Float> {
        (HouseCameraFraming.modelMin + HouseCameraFraming.modelMax) * 0.5
    }

    /// Exported Tesla models. The generic placeholder is not a car Tesla sells.
    static var catalogueModels: [VehicleModel] {
        VehicleModel.allCases.filter { $0 != .generic }
    }

    /// The garage lineup. The parked car comes first when the house is showing one, then the
    /// other cars on the account (from `/api/1/products`), then every catalogue model with its buy link.
    /// With no cars, or when products could not be read, it is the catalogue alone. Demo cars carry
    /// the sample charge lines.
    static func select(
        data: PowerwallData?,
        fallbackVIN: String,
        appearances: [String: VehicleAppearance],
        solar: GarageSolar,
        vehicles: [FleetVehicle],
        charges: [String: VehicleChargeSnapshot],
        displayBoost: CGFloat,
        isDemoMode: Bool,
        lastCar: String? = nil
    ) -> CarShowroomRequest {
        var owned: [CarShowroomRequest] = []
        if let parked = request(
            data: data,
            fallbackVIN: fallbackVIN,
            appearances: appearances,
            solar: solar,
            vehicles: vehicles,
            charges: charges,
            displayBoost: displayBoost
        ) {
            owned.append(parked)
        }
        for vehicle in vehicles {
            let vin = vehicle.vin.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !vin.isEmpty, !owned.contains(where: { $0.vin?.caseInsensitiveCompare(vin) == .orderedSame }) else { continue }
            owned.append(ownedRequest(vin: vin, appearances: appearances, vehicles: vehicles, charges: charges, displayBoost: displayBoost))
        }
        owned = owned.map { repainted($0, appearances: appearances, vehicles: vehicles) }
        if isDemoMode {
            owned = owned.map(DemoHouseTour.applyingExampleFleetData)
        }
        var opened = lineup(owned: owned)
        opened.startIndex = ShowroomLastCar.index(of: lastCar, in: opened) ?? 0
        return opened
    }

    /// The paint this owned car should wear: `vehicle_config` (live `vehicle_data` or
    /// `vehicle_data_cached`, saved per VIN), then products `color` or `option_codes`. Nil leaves the
    /// file colour. Catalogue cars are never touched.
    static func paintSource(vin: String?, appearances: [String: VehicleAppearance], vehicles: [FleetVehicle]) -> VehicleAppearance? {
        paintSourceDetail(vin: vin, appearances: appearances, vehicles: vehicles).appearance
    }

    static func paintSourceDetail(
        vin: String?,
        appearances: [String: VehicleAppearance],
        vehicles: [FleetVehicle]
    ) -> (kind: PaintSourceKind, appearance: VehicleAppearance?) {
        guard let vin = vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty else { return (.none, nil) }
        let stored = appearances[vin] ?? appearances.first { $0.key.caseInsensitiveCompare(vin) == .orderedSame }?.value
        if let stored, stored.hasPaint { return (.vehicleConfig, stored) }
        let vehicle = vehicles.first { $0.vin.caseInsensitiveCompare(vin) == .orderedSame }
        guard let name = vehicle?.paintName else { return (.none, nil) }
        return (.productsColor, VehicleAppearance(exteriorColor: name, paintColorOverride: nil, colorizerRemap: false, carType: stored?.carType))
    }

    /// One `-debugPaint` line for a car on stage: raw Fleet fields, the source used, and the result.
    /// The VIN is cut to its last 4 and the car's own name is left out.
    static func paintReport(for car: CarShowroomRequest, appearances: [String: VehicleAppearance], vehicles: [FleetVehicle]) -> String {
        let vin = car.vin
        let vehicle = vin.flatMap { vin in vehicles.first { $0.vin.caseInsensitiveCompare(vin) == .orderedSame } }
        let stored = vin.flatMap { vin in
            appearances[vin] ?? appearances.first { $0.key.caseInsensitiveCompare(vin) == .orderedSame }?.value
        }
        let source = car.browsesCatalogue ? "catalogue" : paintSourceDetail(vin: vin, appearances: appearances, vehicles: vehicles).kind.rawValue
        let resolved = ShowroomPaint.resolve(for: car)
        let glow = ShowroomStage.highlight(for: car)
        let glowHex = String(format: "%02X%02X%02X", Int(glow.x * 255), Int(glow.y * 255), Int(glow.z * 255))
        return [
            "car \(PaintDebug.redact(vin)) model=\(car.model.rawValue)",
            "products.color=\(PaintDebug.raw(vehicle?.color)) option_codes=\(PaintDebug.raw(vehicle?.optionCodes)) (ignored)",
            "saved vehicle_config exterior_color=\(PaintDebug.raw(stored?.exteriorColor)) paint_color_override=\(PaintDebug.raw(stored?.paintColorOverride)) car_type=\(PaintDebug.raw(stored?.carType)) wheel_type=\(PaintDebug.raw(stored?.wheelType))",
            "source=\(source) exterior=\(PaintDebug.raw(car.exteriorColor)) → \(resolved.debugDescription) glow #\(glowHex)",
            "wheels " + WheelChoice.debugDescription(wheelType: car.wheelType, choice: WheelChoice.resolve(for: car)),
        ].joined(separator: " | ")
    }

    /// Re-reads an owned car's paint and wheels, so a `vehicle_data` reply that arrives while the showroom
    /// is open repaints it and swaps its wheels. The title's colour suffix follows. Catalogue cars come
    /// back unchanged.
    static func repainted(_ car: CarShowroomRequest, appearances: [String: VehicleAppearance], vehicles: [FleetVehicle]) -> CarShowroomRequest {
        guard !car.browsesCatalogue else { return car }
        var copy = car
        if let vin = car.vin,
           let wheelType = (appearances[vin] ?? appearances.first { $0.key.caseInsensitiveCompare(vin) == .orderedSame }?.value)?.wheelType {
            copy.wheelType = wheelType
        }
        guard let source = paintSource(vin: car.vin, appearances: appearances, vehicles: vehicles) else { return copy }
        func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        copy.exteriorColor = clean(source.exteriorColor)
        copy.paintColorOverride = clean(source.paintColorOverride)
        copy.colorizerRemap = source.colorizerRemap
        if let title = copy.lines.first {
            copy.lines[0] = DemoHouseTour.vehicleLabel(displayName: bareTitle(title), exteriorColor: copy.exteriorColor)
        }
        return copy
    }

    /// Drops a " · Colour" suffix so a new colour does not stack.
    static func bareTitle(_ line: String) -> String {
        guard let dot = line.range(of: " · ") else { return line }
        return String(line[..<dot.lowerBound])
    }

    /// Owned cars, then every catalogue model. The first entry carries the whole list.
    static func lineup(owned: [CarShowroomRequest]) -> CarShowroomRequest {
        let entries = owned.map { car -> CarShowroomRequest in
            var car = car
            car.browsesCatalogue = false
            car.lineup = []
            return car
        } + catalogueModels.indices.map(catalogueRequest(index:))
        var first = entries[0]
        first.lineup = entries
        return first
    }

    /// The car the arrows have reached. The index wraps. A single car is itself.
    static func entry(in request: CarShowroomRequest, at index: Int) -> CarShowroomRequest {
        guard !request.lineup.isEmpty else { return request }
        return request.lineup[wrapped(index, count: request.lineup.count)]
    }

    /// A car on the account that is not parked: mesh from `car_type` or the VIN, paint from the last
    /// `vehicle_data` the app already made, and any charge lines already stored. No Fleet call.
    static func ownedRequest(
        vin: String,
        appearances: [String: VehicleAppearance],
        vehicles: [FleetVehicle],
        charges: [String: VehicleChargeSnapshot],
        displayBoost: CGFloat
    ) -> CarShowroomRequest {
        let appearance = appearances[vin] ?? appearances.first { $0.key.caseInsensitiveCompare(vin) == .orderedSame }?.value
        let model = GarageVehicleModel.resolve(vin: vin, carType: appearance?.carType)
        let exterior = appearance?.exteriorColor?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrap = appearance?.paintColorOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = displayName(vin: vin, vehicles: vehicles)
        if name == "Vehicle", model != .generic { name = catalogueName(model) }
        return CarShowroomRequest(
            vin: vin,
            model: model,
            exteriorColor: exterior?.isEmpty == false ? exterior : nil,
            paintColorOverride: wrap?.isEmpty == false ? wrap : nil,
            colorizerRemap: appearance?.colorizerRemap ?? false,
            displayBoost: displayBoost,
            lines: statLines(displayName: name, exteriorColor: exterior?.isEmpty == false ? exterior : nil, snapshot: charge(for: vin, in: charges)),
            wheelType: appearance?.wheelType
        )
    }

    /// One exported model, with no Fleet stats. The index wraps.
    static func catalogueRequest(index: Int) -> CarShowroomRequest {
        let models = catalogueModels
        let model = models[wrapped(index, count: models.count)]
        return CarShowroomRequest(
            vin: nil,
            model: model,
            exteriorColor: nil,
            paintColorOverride: nil,
            colorizerRemap: false,
            displayBoost: 1,
            lines: [catalogueName(model)],
            browsesCatalogue: true
        )
    }

    static func catalogueName(_ model: VehicleModel) -> String {
        switch model {
        case .generic: return "Generic"
        case .model3: return "Model 3"
        case .model3Highland: return "Model 3 Highland"
        case .modelY: return "Model Y"
        case .modelYJuniper: return "Model Y Juniper"
        case .modelS: return "Model S"
        case .modelX: return "Model X"
        case .cybertruck: return "Cybertruck"
        }
    }

    /// Tesla's own order page for this model. Highland and Juniper use the current Model 3 and Model Y pages.
    static func orderURL(for model: VehicleModel) -> URL {
        let path: String
        switch model {
        case .model3, .model3Highland: path = "model3/design"
        case .modelY, .modelYJuniper: path = "modely/design"
        case .modelS: path = "models/design"
        case .modelX: path = "modelx/design"
        case .cybertruck: path = "cybertruck/design"
        case .generic: path = ""
        }
        let string = path.isEmpty ? "https://www.tesla.com/" : "https://www.tesla.com/\(path)"
        return URL(string: string) ?? URL(string: "https://www.tesla.com/")!
    }

    /// Nil when the house is not showing a vehicle. Otherwise the VIN is `GaragePresentation.connectedVIN`
    /// for these connectors, and the lines are frozen so a later demo colour step does not retint the cover.
    static func request(
        data: PowerwallData?,
        fallbackVIN: String,
        appearances: [String: VehicleAppearance],
        solar: GarageSolar,
        vehicles: [FleetVehicle],
        charges: [String: VehicleChargeSnapshot],
        displayBoost: CGFloat
    ) -> CarShowroomRequest? {
        let presentation = GaragePresentation.make(
            data: data,
            fallbackVIN: fallbackVIN,
            appearances: appearances,
            solar: solar
        )
        guard presentation.showVehicle else { return nil }
        let connectors = data?.wallConnectors ?? []
        let vin = GaragePresentation.connectedVIN(wallConnectors: connectors, fallbackVIN: fallbackVIN)
        let name = displayName(vin: vin, vehicles: vehicles)
        return CarShowroomRequest(
            vin: vin,
            model: presentation.model,
            exteriorColor: presentation.exteriorColor,
            paintColorOverride: presentation.paintColorOverride,
            colorizerRemap: presentation.colorizerRemap,
            displayBoost: displayBoost,
            lines: statLines(displayName: name, exteriorColor: presentation.exteriorColor, snapshot: charge(for: vin, in: charges)),
            wheelType: presentation.wheelType
        )
    }

    /// Name, then "80% battery · Charging" on one line, then minutes to full. A nil or blank field is left out,
    /// and the dot only appears when both halves are there.
    /// Colour is the same suffix the demo chips use, and only when this car has an exterior colour.
    static func statLines(displayName: String, exteriorColor: String?, snapshot: VehicleChargeSnapshot?) -> [String] {
        var lines = [DemoHouseTour.vehicleLabel(displayName: displayName, exteriorColor: exteriorColor)]
        var battery: [String] = []
        if let batteryLevel = snapshot?.batteryLevel {
            battery.append("\(Int(batteryLevel.rounded()))% battery")
        }
        if let chargingState = snapshot?.chargingState?.trimmingCharacters(in: .whitespacesAndNewlines), !chargingState.isEmpty {
            battery.append(chargingState)
        }
        if !battery.isEmpty {
            lines.append(battery.joined(separator: " · "))
        }
        if let minutesToFullCharge = snapshot?.minutesToFullCharge {
            lines.append("\(Int(minutesToFullCharge.rounded())) minutes to full charge")
        }
        return lines
    }

    /// The parked car on the Tesla app's showroom stage (`ShowroomStage`): studio panorama
    /// lighting, a faded mirror floor, the car's baked contact shadow, and a paint-coloured glow.
    /// The car is the only thing marked for the mirror.
    static func scene(for request: CarShowroomRequest) -> SCNScene {
        let scene = SCNScene()
        let centre = stageCentre
        let carPosition = SIMD3<Float>(centre.x, 0, centre.z)

        let cameraNode = SCNNode()
        cameraNode.name = cameraName
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(CarShowroomOrbit.verticalFieldOfViewDegrees)
        camera.zNear = 0.05
        camera.zFar = 150
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        CarShowroomOrbit().aim(cameraNode, around: centre)

        ShowroomStage.install(
            in: scene,
            carPosition: carPosition,
            model: request.model,
            highlight: ShowroomStage.highlight(for: request)
        )
        ShowroomStage.updateGlow(in: scene, camera: cameraNode, centre: centre)

        let vehicle = loadVehicle(model: request.model)
        vehicle.simdPosition = carPosition
        if let body = ShowroomPaint.resolve(for: request).bodyPaint(displayBoost: request.displayBoost) {
            applyPaint(body.paint, to: vehicle, displayBoost: body.boost)
        }
        // Before the mirror, which clones the car with its wheels.
        VehicleWheels.mount(WheelChoice.resolve(for: request), on: vehicle, look: .showroom)
        scene.rootNode.addChildNode(vehicle)
        scene.rootNode.addChildNode(ShowroomStage.makeMirror(of: vehicle))
        return scene
    }

    /// World-space corners of the car meshes. The ground plate is not included.
    static func fitPoints(in scene: SCNScene) -> [SIMD3<Float>] {
        guard let vehicle = scene.rootNode.childNode(withName: "Vehicle", recursively: true) else { return [] }
        var points: [SIMD3<Float>] = []
        vehicle.enumerateHierarchy { node, _ in
            guard let box = node.geometry?.boundingBox else { return }
            for x in [box.min.x, box.max.x] {
                for y in [box.min.y, box.max.y] {
                    for z in [box.min.z, box.max.z] {
                        points.append(node.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: nil))
                    }
                }
            }
        }
        return points
    }

    private static func displayName(vin: String?, vehicles: [FleetVehicle]) -> String {
        guard let vin = vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty else { return "Vehicle" }
        let match = vehicles.first { $0.vin.caseInsensitiveCompare(vin) == .orderedSame }
        let name = match?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Vehicle" : name
    }

    private static func charge(for vin: String?, in charges: [String: VehicleChargeSnapshot]) -> VehicleChargeSnapshot? {
        guard let vin = vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty else { return nil }
        if let exact = charges[vin] { return exact }
        return charges.first { $0.key.caseInsensitiveCompare(vin) == .orderedSame }?.value
    }

    private static func loadVehicle(model: VehicleModel) -> SCNNode {
        let wrapper = SCNNode()
        wrapper.name = "Vehicle"
        guard let url = HouseLighting.resourceURL(name: model.rawValue, ext: "usdz"),
              let loaded = try? SCNScene(url: url, options: nil) else {
            return wrapper
        }
        for child in loaded.rootNode.childNodes {
            wrapper.addChildNode(child)
        }
        wrapper.enumerateHierarchy { node, _ in
            node.geometry?.materials.forEach { VehicleGlass.reveal($0) }
        }
        VehicleLamps.dress(wrapper, model: model)
        return wrapper
    }

    /// Next catalogue colour. `current` nil starts at the first colour for a positive step
    /// and the last colour for a negative step.
    static func colourIndex(after current: Int?, delta: Int) -> Int {
        let count = max(TeslaPaint.catalogue.count, 1)
        let base = current ?? (delta >= 0 ? -1 : 0)
        return wrapped(base + delta, count: count)
    }

    /// Next wheel in `names`. With no index yet, a positive step moves on from `currentName`
    /// when that name is in the list, otherwise it starts at the first wheel.
    static func wheelIndex(after index: Int?, names: [String], currentName: String?, delta: Int) -> Int? {
        guard !names.isEmpty else { return nil }
        if let index { return wrapped(index + delta, count: names.count) }
        let start = currentName.flatMap { name in
            names.firstIndex { $0.caseInsensitiveCompare(name) == .orderedSame }
        } ?? (delta >= 0 ? -1 : 0)
        return wrapped(start + delta, count: names.count)
    }

    private static func applyPaint(_ paint: TeslaPaint, to vehicle: SCNNode, displayBoost: CGFloat) {
        vehicle.enumerateHierarchy { node, _ in
            node.geometry?.materials.filter { $0.name == "Paint" }.forEach {
                paint.apply(to: $0, displayBoost: displayBoost, clearCoat: 0)
            }
        }
    }

    private static func wrapped(_ index: Int, count: Int) -> Int {
        let count = max(count, 1)
        let wrapped = index % count
        return wrapped >= 0 ? wrapped : wrapped + count
    }
}

/// Orbit around the showroom car. Identity matches the camera `CarShowroom.scene` installs.
struct CarShowroomOrbit: Equatable {
    var yawDegrees: Float = 0
    var pitchDegrees: Float = 0
    var distanceScale: Float = 1
    /// Sideways look-point shift at the current zoom. A three-quarter view makes the near
    /// end project larger, so this pulls the car back to the horizontal centre of the window.
    var centreBias = SIMD3<Float>.zero
    /// Extra look-point shift from a pan. Same ±3 m limit as the house camera.
    var pan = SIMD3<Float>.zero
    static let panRange: ClosedRange<Float> = -3...3

    /// Relative to the resting view, which already looks down about 13°.
    static let pitchRange: ClosedRange<Float> = -20...40
    /// Wide enough that a portrait window can still back up to fit a Cybertruck.
    static let distanceRange: ClosedRange<Float> = 0.2...6
    /// Eye minus the look target at the resting view. The car's nose is −Z, and this
    /// offset sits on the car's left so that nose points toward the left of the screen.
    /// The ground position is the Tesla app's PARKED camera (Snapshots.gd: yaw −138°).
    /// The height above the look point is half of that camera's 2.958 m, so the view
    /// sits lower on the same yaw.
    static let restingOffset = SIMD3<Float>(-4.244, 2.958 * 0.5, -4.713)
    static let lookHeight: Float = 0.72
    /// Share of the window the fitted car may use. The rest stays clear of the edges.
    static let fitFill: Float = 0.9
    /// Snapshots.gd PARKED `cam_fov`.
    static let verticalFieldOfViewDegrees: Float = 30

    func clamped() -> CarShowroomOrbit {
        var copy = self
        copy.pitchDegrees = min(max(pitchDegrees, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
        copy.distanceScale = min(max(distanceScale, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
        return copy
    }

    func target(around centre: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(centre.x, Self.lookHeight, centre.z) + centreBias + pan
    }

    /// Adds a world-space pan and keeps each axis inside `panRange`.
    mutating func pan(by world: SIMD3<Float>) {
        pan += world
        pan.x = min(max(pan.x, Self.panRange.lowerBound), Self.panRange.upperBound)
        pan.y = min(max(pan.y, Self.panRange.lowerBound), Self.panRange.upperBound)
        pan.z = min(max(pan.z, Self.panRange.lowerBound), Self.panRange.upperBound)
    }

    /// Moves the look point so the car follows the pointer.
    /// `screenX` is positive to the right. `screenY` is positive up.
    mutating func pan(screenX: Float, screenY: Float, viewHeight: Float, around centre: SIMD3<Float>) {
        let eyePoint = eye(around: centre)
        let look = target(around: centre)
        let forward = look - eyePoint
        let distance = simd_length(forward)
        guard distance > 0.001, viewHeight > 1 else { return }
        let direction = forward / distance
        var right = simd_cross(direction, SIMD3<Float>(0, 1, 0))
        guard simd_length(right) > 0.001 else { return }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(right, direction))
        let metresPerPoint = distance * tan(Self.verticalFieldOfViewDegrees * .pi / 180 / 2) * 2 / viewHeight
        pan(by: -right * screenX * metresPerPoint - up * screenY * metresPerPoint)
    }

    /// Sideways look shift that centres the points at this zoom.
    /// Aspect is not an input: a narrower frame changes the normalized position and the frustum together.
    static func centreBias(
        fitting points: [SIMD3<Float>],
        around centre: SIMD3<Float>,
        yawDegrees: Float,
        pitchDegrees: Float,
        distanceScale: Float
    ) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        var bias = SIMD3<Float>.zero
        for _ in 0..<3 {
            var pose = CarShowroomOrbit()
            pose.yawDegrees = yawDegrees
            pose.pitchDegrees = pitchDegrees
            pose.distanceScale = distanceScale
            pose.centreBias = bias
            let target = pose.target(around: centre)
            let eye = pose.eye(around: centre)
            let forward = simd_normalize(target - eye)
            var right = simd_cross(forward, SIMD3<Float>(0, 1, 0))
            guard simd_length(right) > 0.001 else { return bias }
            right = simd_normalize(right)
            var minX = Float.greatestFiniteMagnitude
            var maxX = -Float.greatestFiniteMagnitude
            for point in points {
                let from = point - eye
                let depth = simd_dot(from, forward)
                guard depth > 0.001 else { continue }
                let x = simd_dot(from, right) / depth
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
            guard minX < maxX else { return bias }
            bias += right * ((minX + maxX) * 0.5 * simd_length(eye - target))
        }
        return bias
    }

    /// Distance that places every point inside the window at this orbit angle.
    /// `aspect` is view width divided by height. The vertical field of view stays 30°.
    static func distanceScale(
        fitting points: [SIMD3<Float>],
        around centre: SIMD3<Float>,
        yawDegrees: Float,
        pitchDegrees: Float,
        aspect: Float
    ) -> Float {
        guard !points.isEmpty, aspect > 0.01 else { return 1 }
        var pose = CarShowroomOrbit()
        pose.yawDegrees = yawDegrees
        pose.pitchDegrees = pitchDegrees
        pose.distanceScale = 1
        let target = pose.target(around: centre)
        let offset = pose.eye(around: centre) - target
        let length = simd_length(offset)
        guard length > 0.001 else { return 1 }
        let forward = -offset / length
        var right = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        if simd_length(right) < 0.001 {
            right = SIMD3(1, 0, 0)
        } else {
            right = simd_normalize(right)
        }
        let up = simd_normalize(simd_cross(right, forward))
        let tanY = tan(Self.verticalFieldOfViewDegrees * .pi / 180 / 2)
        let tanX = tanY * aspect
        let fill = max(Self.fitFill, 0.05)
        var scale = Self.distanceRange.lowerBound
        for point in points {
            let fromTarget = point - target
            let depthAtRest = simd_dot(fromTarget, forward)
            let needX = (abs(simd_dot(fromTarget, right)) / (tanX * fill) - depthAtRest) / length
            let needY = (abs(simd_dot(fromTarget, up)) / (tanY * fill) - depthAtRest) / length
            scale = max(scale, needX, needY)
        }
        return min(max(scale, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }

    func eye(around centre: SIMD3<Float>) -> SIMD3<Float> {
        let pose = clamped()
        let yaw = pose.yawDegrees * .pi / 180
        let pitch = pose.pitchDegrees * .pi / 180
        var offset = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)).act(Self.restingOffset)
        let flat = SIMD3<Float>(offset.x, 0, offset.z)
        let flatLength = simd_length(flat)
        if flatLength > 0.001 {
            let right = simd_normalize(cross(flat, SIMD3<Float>(0, 1, 0)))
            offset = simd_quatf(angle: pitch, axis: right).act(offset)
        }
        return target(around: centre) + offset * pose.distanceScale
    }

    /// SceneKit's camera looks down the node's −Z. The up axis stays world +Y.
    func aim(_ camera: SCNNode, around centre: SIMD3<Float>) {
        let eye = eye(around: centre)
        let target = target(around: centre)
        let direction = simd_normalize(target - eye)
        let up = SIMD3<Float>(0, 1, 0)
        var right = simd_cross(direction, up)
        if simd_length(right) < 0.001 {
            right = SIMD3(1, 0, 0)
        } else {
            right = simd_normalize(right)
        }
        let correctedUp = simd_normalize(simd_cross(right, direction))
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4(right, 0)
        transform.columns.1 = SIMD4(correctedUp, 0)
        transform.columns.2 = SIMD4(-direction, 0)
        transform.columns.3 = SIMD4(eye, 1)
        camera.simdTransform = transform
    }
}

struct CarShowroomView: View {
    let request: CarShowroomRequest
    /// `vehicle_data_cached` rows for an owned car, or the demo sample. Nil hides the panel.
    var info: (CarShowroomRequest) -> VehicleInfo? = { _ in nil }
    /// Runs while one car is on stage and is cancelled when the arrows move on or the showroom closes.
    var whileShowing: (CarShowroomRequest) async -> Void = { _ in }
    /// Re-reads an owned car's paint from the latest stored copy (`CarShowroom.repainted`).
    var refreshed: (CarShowroomRequest) -> CarShowroomRequest = { $0 }
    var onDismiss: () -> Void
    /// Same key as Settings → Display → Tyre pressure. The details tap only writes this; it never calls Fleet.
    @AppStorage(TyrePressureSetting.storageKey) private var tyrePressureSetting = TyrePressureSetting.automatic.rawValue
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var scene: SCNScene?
    /// The car the current scene was built for, so one change builds one scene.
    @State private var builtFor: CarShowroomRequest?
    @State private var browseIndex = 0
    /// Nil keeps the file or Fleet colour. Edit-mode arrows walk `TeslaPaint.catalogue`.
    @State private var colourIndex: Int?
    /// Nil keeps the car's own wheels. Edit-mode arrows walk `TeslaWheel.demoNames`.
    @State private var wheelIndex: Int?
    /// Double tap (double click on Mac) freezes orbit and pan and shows the colour and wheel arrows.
    @State private var editing = false
    /// Hides the stage while the next model is fitted, so it does not pop on at the unfitted size.
    @State private var modelOpacity: Double = 1
    @State private var modelFadingOut = false
    @State private var pendingModelStep = 0
    #if os(tvOS)
    private enum ShowroomFocus: Hashable {
        case previous
        case next
        case close
        case details
    }
    @FocusState private var showroomFocus: ShowroomFocus?

    /// Left and right move between the lineup arrows. Up walks to the details panel on an owned car,
    /// then Close. Down from those returns to the next-car arrow. Elsewhere, up and down change colour.
    private struct ShowroomRemote: ViewModifier {
        let item: ShowroomFocus
        let browses: Bool
        var hasDetails = false
        var focus: FocusState<ShowroomFocus?>.Binding
        let shift: (Int) -> Void

        func body(content: Content) -> some View {
            content.onMoveCommand { direction in
                switch direction {
                case .left where !browses && item == .close:
                    focus.wrappedValue = .details
                case .right where item == .details:
                    focus.wrappedValue = .close
                case .left where browses:
                    focus.wrappedValue = .previous
                case .right where browses:
                    focus.wrappedValue = .next
                case .up where browses && (item == .previous || item == .next):
                    focus.wrappedValue = hasDetails ? .details : .close
                case .up where browses && item == .details:
                    focus.wrappedValue = .close
                case .down where browses && (item == .details || item == .close):
                    focus.wrappedValue = .next
                case .up:
                    shift(1)
                case .down:
                    shift(-1)
                default:
                    break
                }
            }
        }
    }
    #endif

    /// More than one car: the arrows show.
    private var browses: Bool { request.lineup.count > 1 }

    /// The lineup car the arrows have reached, before any colour step.
    private var current: CarShowroomRequest { refreshed(CarShowroom.entry(in: request, at: browseIndex)) }

    private var displayed: CarShowroomRequest {
        var shown = current
        if let colourIndex, shown.model != .generic {
            let paint = TeslaPaint.catalogue[colourIndex % TeslaPaint.catalogue.count]
            shown.exteriorColor = paint.name
            shown.paintColorOverride = paint.demoOverride
            shown.colorizerRemap = false
            shown.displayBoost = 1
            let bareName = shown.lines.first.map(CarShowroom.bareTitle) ?? CarShowroom.catalogueName(shown.model)
            if shown.lines.isEmpty {
                shown.lines = [DemoHouseTour.vehicleLabel(displayName: bareName, exteriorColor: paint.name)]
            } else {
                shown.lines[0] = DemoHouseTour.vehicleLabel(displayName: bareName, exteriorColor: paint.name)
            }
        }
        return withChosenWheel(shown)
    }

    /// The edit arrows' wheel, including on a catalogue car that would otherwise keep the standard set.
    private func withChosenWheel(_ car: CarShowroomRequest) -> CarShowroomRequest {
        guard let wheelIndex else { return car }
        let names = TeslaWheel.demoNames(for: car.model)
        guard !names.isEmpty else { return car }
        var shown = car
        shown.wheelType = names[wheelIndex % names.count]
        shown.wearsChosenWheel = true
        return shown
    }

    var body: some View {
        GeometryReader { proxy in
            let valueFont = showroomValueFont(for: proxy.size)
            let labelFont = showroomLabelFont(for: proxy.size)
            ZStack {
                Color(red: 22 / 255, green: 23 / 255, blue: 24 / 255)
                    .ignoresSafeArea()
                if let scene {
                    CarShowroomMetalView(
                        scene: scene,
                        editing: editing,
                        onToggleEdit: { editing.toggle() },
                        onColour: { shiftColour($0) }
                    )
                        .ignoresSafeArea()
                        .opacity(modelOpacity)
                }
            }
            .overlay(alignment: .topLeading) {
                carDetails(valueFont: valueFont, labelFont: labelFont, width: labelWidth(in: proxy))
                    .padding(.top, chromeInset(proxy.safeAreaInsets.top))
                    .padding(.leading, chromeInset(proxy.safeAreaInsets.leading))
            }
            .overlay(alignment: .topTrailing) {
                closeButton
                    .padding(.top, closeInset(proxy.safeAreaInsets.top))
                    .padding(.trailing, closeInset(proxy.safeAreaInsets.trailing, edge: .trailing))
            }
            .overlay(alignment: .bottomLeading) {
                if browses {
                    catalogueArrows
                        .padding(.leading, chromeInset(proxy.safeAreaInsets.leading))
                        .padding(.bottom, chromeInset(proxy.safeAreaInsets.bottom))
                }
            }
            .overlay(alignment: .bottom) {
                #if !os(tvOS)
                if editing {
                    editControls
                        .padding(.bottom, editBottomInset(proxy))
                }
                #endif
            }
        }
        .onAppear {
            if scene == nil {
                browseIndex = request.startIndex
                rebuildScene()
            }
        }
        // A step, a colour, or a paint that arrives from Fleet while open: one new scene, new glow.
        .onChange(of: displayed) { rebuildScene() }
        .task(id: current.id) { await whileShowing(current) }
        #if os(tvOS)
        .focusSection()
        .defaultFocus($showroomFocus, browses ? .next : .close, priority: .userInitiated)
        #endif
        #if !os(iOS)
        .onExitCommand(perform: onDismiss)
        #endif
    }

    /// Lifts the edit arrows above the catalogue pair on a narrow phone.
    private func editBottomInset(_ proxy: GeometryProxy) -> CGFloat {
        let base = chromeInset(proxy.safeAreaInsets.bottom)
        let narrow = proxy.size.width < 700
        return base + (browses && narrow ? 72 : 0)
    }

    #if !os(tvOS)
    private var editControls: some View {
        VStack(spacing: 12) {
            if cyclesColour {
                editRow(
                    caption: colourCaption,
                    previous: "Previous colour",
                    next: "Next colour",
                    previousKey: .downArrow,
                    nextKey: .upArrow,
                    step: shiftColour
                )
            }
            if cyclesWheels {
                editRow(
                    caption: wheelCaption,
                    previous: "Previous wheels",
                    next: "Next wheels",
                    previousKey: nil,
                    nextKey: nil,
                    step: shiftWheel
                )
            }
        }
    }

    private var cyclesColour: Bool { displayed.model != .generic && !TeslaPaint.catalogue.isEmpty }

    private var cyclesWheels: Bool { !TeslaWheel.demoNames(for: displayed.model).isEmpty }

    private var colourCaption: String {
        guard let name = displayed.exteriorColor, !name.isEmpty else { return "Colour" }
        return TeslaPaint.spacedName(name)
    }

    private var wheelCaption: String {
        let model = displayed.model
        let names = TeslaWheel.demoNames(for: model)
        let chosen = wheelIndex.flatMap { names.isEmpty ? nil : names[$0 % names.count] } ?? displayed.wheelType
        if let wheel = WheelChoice.resolve(wheelType: chosen, model: model)?.wheel {
            return wheel.rawValue.replacingOccurrences(of: "_", with: " ")
        }
        return "Wheels"
    }

    private func editRow(
        caption: String,
        previous: String,
        next: String,
        previousKey: KeyEquivalent?,
        nextKey: KeyEquivalent?,
        step: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            editArrow(title: previous, systemImage: "chevron.left", key: previousKey) { step(-1) }
            Text(caption)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 96, maxWidth: 220)
            editArrow(title: next, systemImage: "chevron.right", key: nextKey) { step(1) }
        }
        .foregroundColor(.white)
        .homeSettingsButtonCluster()
        .homeSettingsDarkChrome()
    }

    private func editArrow(title: String, systemImage: String, key: KeyEquivalent?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                #if os(macOS)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 40, height: 40)
                #else
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.gray)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 40, height: 40)
                #endif
        }
        .homeSettingsButtonChrome()
        .accessibilityLabel(title)
        .modifier(ShowroomEditKey(key: key))
    }
    #endif

    private func carDetails(valueFont: Font, labelFont: Font, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = displayed.lines.first {
                Text(title)
                    .fontWeight(.bold)
                    .font(valueFont)
                    .padding(.bottom, 8)
            }
            ForEach(Array(displayed.lines.dropFirst().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .fontWeight(.bold)
                    .font(labelFont)
                    .opacity(0.6)
            }
            if !current.browsesCatalogue, let info = info(current) {
                vehicleInfoPanel(info, labelFont: labelFont)
                    .padding(.top, 12)
            }
            #if !os(tvOS)
            if current.browsesCatalogue {
                buyButton(labelFont: labelFont)
            }
            #endif
        }
        .foregroundColor(.white)
        .multilineTextAlignment(.leading)
        .frame(width: width, alignment: .leading)
    }

    #if !os(tvOS)
    /// Opens Tesla's order page in the system browser. A SwiftUI `Link` in this overlay presents
    /// from the hosting view, and on iPad that presentation is dropped.
    private func buyButton(labelFont: Font) -> some View {
        Button {
            openOrderPage(displayed.model)
        } label: {
            Text("Buy a Tesla")
                .fontWeight(.bold)
                .font(labelFont)
                .opacity(0.6)
                .padding(.top, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Buy a Tesla")
    }

    private func openOrderPage(_ model: VehicleModel) {
        let url = CarShowroom.orderURL(for: model)
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
    #endif

    /// The owned car's panel is a button only when it has a tyre row to step.
    private var detailsFocusable: Bool {
        guard !current.browsesCatalogue, let info = info(current) else { return false }
        return info.nextPressureSetting(current: pressureSetting) != nil
    }

    private var pressureSetting: TyrePressureSetting {
        TyrePressureSetting(stored: tyrePressureSetting)
    }

    /// Left column under the charge lines: one SF Symbol per row, same bold label font and 60% white.
    /// Rows Fleet did not send are not drawn. With a tyre row, a tap, click or tvOS select steps the
    /// tyre unit psi → bar → kPa. That only changes the stored setting and redraws from memory.
    @ViewBuilder
    private func vehicleInfoPanel(_ info: VehicleInfo, labelFont: Font) -> some View {
        if let next = info.nextPressureSetting(current: pressureSetting) {
            Button {
                tyrePressureSetting = next.rawValue
            } label: {
                vehicleInfoRows(info, labelFont: labelFont)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vehicle details")
            .accessibilityHint("Shows tyre pressure in \(next.title)")
            #if os(tvOS)
            .focused($showroomFocus, equals: .details)
            .modifier(ShowroomRemote(item: .details, browses: browses, hasDetails: true, focus: $showroomFocus, shift: { shiftColour($0) }))
            #endif
        } else {
            vehicleInfoRows(info, labelFont: labelFont)
        }
    }

    private func vehicleInfoRows(_ info: VehicleInfo, labelFont: Font) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(info.rows(now: context.date, pressureSetting: pressureSetting)) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: row.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: infoIconWidth, alignment: .center)
                            .accessibilityHidden(true)
                        Text(row.text)
                    }
                    .fontWeight(.bold)
                    .font(labelFont)
                    .opacity(row.id == "updated" ? 0.4 : 0.6)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var infoIconWidth: CGFloat {
        #if os(tvOS)
        32
        #else
        20
        #endif
    }

    /// The showroom is full bleed, so the close control adds the graph's 12 pt top and 16 pt
    /// trailing inset on top of the safe area. On iPad that reader inset can be 0, so the window
    /// inset is used when it is larger. tvOS keeps the larger bezel inset.
    private func closeInset(_ safe: CGFloat, edge: Edge = .top) -> CGFloat {
        #if os(tvOS)
        chromeInset(safe)
        #else
        CarShowroom.closePadding(reportedSafe: safe, windowSafe: windowSafe(edge), extra: edge == .trailing ? 16 : 12)
        #endif
    }

    private func windowSafe(_ edge: Edge) -> CGFloat {
        #if os(iOS)
        let insets = ShowroomWindowSafeArea.insets
        switch edge {
        case .top: return insets.top
        case .bottom: return insets.bottom
        case .leading: return layoutDirection == .rightToLeft ? insets.right : insets.left
        case .trailing: return layoutDirection == .rightToLeft ? insets.left : insets.right
        }
        #else
        0
        #endif
    }

    /// Clears the window edge, and any safe area the full-bleed scene draws under.
    private func chromeInset(_ safe: CGFloat) -> CGFloat {
        #if os(tvOS)
        max(80, safe + 28)
        #else
        max(48, safe + 20)
        #endif
    }

    /// Keeps the title clear of the close button on a narrow phone.
    private func labelWidth(in proxy: GeometryProxy) -> CGFloat {
        let horizontal = chromeInset(proxy.safeAreaInsets.leading) + chromeInset(proxy.safeAreaInsets.trailing) + 64
        return min(showroomMessageWidth, max(160, proxy.size.width - horizontal))
    }

    /// Same close glyph and 48-point target as the graph. tvOS keeps a larger symbol for the remote.
    private var closeButton: some View {
        Button(action: onDismiss) {
            #if os(tvOS)
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .padding(10)
            #else
            OverlayCloseButtonLabel()
            #endif
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        #if os(tvOS)
        .focused($showroomFocus, equals: .close)
        .modifier(ShowroomRemote(item: .close, browses: browses, focus: $showroomFocus, shift: { shiftColour($0) }))
        #else
        .keyboardShortcut(.cancelAction)
        #endif
    }

#if os(iOS)
    /// The key window's inset. The showroom's own reader can miss it once the view ignores the safe area.
    private enum ShowroomWindowSafeArea {
        static var insets: UIEdgeInsets {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
            return window?.safeAreaInsets ?? .zero
        }
    }
#endif

    /// Same glass circles as the home settings buttons, along the bottom leading edge.
    private var catalogueArrows: some View {
        HStack(spacing: catalogueArrowSpacing) {
            catalogueArrow(delta: -1, title: "Previous car", systemImage: "chevron.left", key: .leftArrow)
            catalogueArrow(delta: 1, title: "Next car", systemImage: "chevron.right", key: .rightArrow)
        }
        .homeSettingsButtonCluster()
        .homeSettingsDarkChrome()
    }

    private var catalogueArrowSpacing: CGFloat? {
        #if os(tvOS)
        24
        #else
        nil
        #endif
    }

    private func catalogueArrow(delta: Int, title: String, systemImage: String, key: KeyEquivalent) -> some View {
        Button(action: { step(delta) }) {
            Image(systemName: systemImage)
                #if os(macOS)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 40, height: 40)
                #elseif os(iOS)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.gray)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 40, height: 40)
                #else
                .font(.title2)
                .frame(width: 80, height: 80)
                #endif
        }
        .homeSettingsButtonChrome()
        .accessibilityLabel(title)
        #if os(tvOS)
        .focused($showroomFocus, equals: delta > 0 ? .next : .previous)
        .modifier(ShowroomRemote(
            item: delta > 0 ? .next : .previous,
            browses: true,
            hasDetails: detailsFocusable,
            focus: $showroomFocus,
            shift: { shiftColour($0) }
        ))
        #else
        .keyboardShortcut(key, modifiers: [])
        #endif
    }

    private var showroomMessageWidth: CGFloat {
        #if os(tvOS)
        400
        #else
        260
        #endif
    }

    private func showroomValueFont(for size: CGSize) -> Font {
        #if os(macOS)
        .system(size: 18 * showroomTextScale(for: size))
        #elseif os(tvOS)
        .headline
        #else
        .title2
        #endif
    }

    private func showroomLabelFont(for size: CGSize) -> Font {
        #if os(macOS)
        .system(size: 12 * showroomTextScale(for: size))
        #elseif os(tvOS)
        .footnote
        #else
        .subheadline
        #endif
    }

    private func showroomTextScale(for size: CGSize) -> CGFloat {
        #if os(macOS)
        guard size.width > 0 else { return 1 }
        return max(1, size.width / 1280)
        #else
        _ = size
        return 1
        #endif
    }

    /// Every car arrives in its own paint: a colour tried on one car never carries to the next.
    /// The stage fades out first. The next model is fitted while it is invisible, then fades in,
    /// so the unfitted mesh never flashes larger than the window.
    private func step(_ delta: Int) {
        guard browses else { return }
        pendingModelStep += delta
        guard !modelFadingOut else { return }
        modelFadingOut = true
        withAnimation(.easeInOut(duration: Self.modelFadeOut)) { modelOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.modelFadeOut) {
            let jump = pendingModelStep
            pendingModelStep = 0
            modelFadingOut = false
            if jump != 0 {
                browseIndex += jump
                colourIndex = nil
                wheelIndex = nil
            }
            withAnimation(.easeInOut(duration: Self.modelFadeIn)) { modelOpacity = 1 }
        }
    }

    private static let modelFadeOut: TimeInterval = 0.2
    private static let modelFadeIn: TimeInterval = 0.25

    private func shiftColour(_ delta: Int) {
        guard displayed.model != .generic, !TeslaPaint.catalogue.isEmpty else { return }
        colourIndex = CarShowroom.colourIndex(after: colourIndex, delta: delta)
    }

    private func shiftWheel(_ delta: Int) {
        let names = TeslaWheel.demoNames(for: displayed.model)
        wheelIndex = CarShowroom.wheelIndex(after: wheelIndex, names: names, currentName: current.wheelType, delta: delta)
    }

    private func rebuildScene() {
        let car = displayed
        guard car != builtFor || scene == nil else { return }
        builtFor = car
        scene = CarShowroom.scene(for: car)
    }
}

private struct CarShowroomMetalView: View {
    let scene: SCNScene
    var editing: Bool
    var onToggleEdit: () -> Void
    var onColour: (Int) -> Void

    var body: some View {
        #if os(macOS)
        CarShowroomMac(scene: scene, editing: editing, onToggleEdit: onToggleEdit, onColour: onColour)
        #else
        CarShowroomIOS(scene: scene, editing: editing, onToggleEdit: onToggleEdit, onColour: onColour)
        #endif
    }
}

/// Drag orbits the car. Option-drag, right-drag, and a two-finger drag pan.
/// Scroll, pinch, and magnify zoom. A double tap or double click toggles edit mode,
/// which stops orbit and pan. The orbit survives a model change.
final class CarShowroomControlView: SCNView {
    var orbit = CarShowroomOrbit()
    var editing = false
    var onToggleEdit: (() -> Void)?
    /// tvOS remote up and down still step the colour. Touch and Mac use the edit arrows.
    var onColour: ((Int) -> Void)?
    private var lastColourStep = Date.distantPast
    /// Set once the viewer pinches or scrolls. Until then the car is fitted to the window.
    private var userZoomed = false
    private var fittedScene: SCNScene?
    private var fittedSize = CGSize.zero
    private var cachedFitPoints: [SIMD3<Float>] = []
    private var cachedFitScene: SCNScene?

    override init(frame frameRect: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frameRect, options: options)
        installGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installGestures()
    }

    func present(_ scene: SCNScene) {
        if self.scene !== scene {
            self.scene = scene
        }
        allowsCameraControl = false
        antialiasingMode = .multisampling4X
        rendersContinuously = false
        backgroundColor = ShowroomStage.backgroundColour
        fitToWindow()
        aim()
    }

    /// Pulls the resting camera in or out so the car fills the current view.
    private func fitToWindow() {
        guard !userZoomed, bounds.width > 1, bounds.height > 1, let scene else { return }
        if fittedScene === scene, fittedSize == bounds.size { return }
        let points = fitPoints()
        guard !points.isEmpty else { return }
        let scale = CarShowroomOrbit.distanceScale(
            fitting: points,
            around: CarShowroom.stageCentre,
            yawDegrees: orbit.yawDegrees,
            pitchDegrees: orbit.pitchDegrees,
            aspect: Float(bounds.width / bounds.height)
        )
        fittedScene = scene
        fittedSize = bounds.size
        guard abs(scale - orbit.distanceScale) > 0.001 else { return }
        orbit.distanceScale = scale
        orbit = orbit.clamped()
        aim()
    }

    #if os(macOS)
    override func layout() {
        super.layout()
        fitToWindow()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        fitToWindow()
    }
    #endif

    private func fitPoints() -> [SIMD3<Float>] {
        guard let scene else { return [] }
        if cachedFitScene === scene { return cachedFitPoints }
        cachedFitPoints = CarShowroom.fitPoints(in: scene)
        cachedFitScene = scene
        return cachedFitPoints
    }

    /// Keeps the car's screen bounds on the horizontal centre as the orbit turns.
    private func alignToCentre() {
        orbit.centreBias = CarShowroomOrbit.centreBias(
            fitting: fitPoints(),
            around: CarShowroom.stageCentre,
            yawDegrees: orbit.yawDegrees,
            pitchDegrees: orbit.pitchDegrees,
            distanceScale: orbit.clamped().distanceScale
        )
    }

    private func aim() {
        guard let camera = scene?.rootNode.childNode(withName: CarShowroom.cameraName, recursively: true) else { return }
        alignToCentre()
        orbit.aim(camera, around: CarShowroom.stageCentre)
        if let scene {
            ShowroomStage.updateGlow(in: scene, camera: camera, centre: CarShowroom.stageCentre)
        }
        pointOfView = camera
        #if os(macOS)
        setNeedsDisplay(bounds)
        #else
        setNeedsDisplay()
        #endif
    }

    private func orbit(by deltaX: CGFloat, deltaY: CGFloat) {
        guard !editing else { return }
        let degreesPerPoint = CarShowroomOrbit.verticalFieldOfViewDegrees / Float(max(bounds.height, 1))
        orbit.yawDegrees -= Float(deltaX) * degreesPerPoint
        orbit.pitchDegrees += Float(deltaY) * degreesPerPoint
        orbit = orbit.clamped()
        aim()
    }

    private func pan(screenX: Float, screenY: Float) {
        guard !editing else { return }
        orbit.pan(
            screenX: screenX,
            screenY: screenY,
            viewHeight: Float(bounds.height),
            around: CarShowroom.stageCentre
        )
        aim()
    }

    private func zoom(multiplier: Float) {
        guard multiplier.isFinite, multiplier > 0 else { return }
        userZoomed = true
        orbit.distanceScale *= multiplier
        orbit = orbit.clamped()
        aim()
    }

    private func installGestures() {
        #if os(iOS)
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(orbitPan(_:)))
        orbit.maximumNumberOfTouches = 1
        addGestureRecognizer(orbit)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(twoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        addGestureRecognizer(pan)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinchZoom(_:))))
        let edit = UITapGestureRecognizer(target: self, action: #selector(toggleEdit))
        edit.numberOfTapsRequired = 2
        addGestureRecognizer(edit)
        #elseif os(tvOS)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(orbitPan(_:))))
        #endif
    }

    #if os(iOS)
    @objc private func toggleEdit() {
        onToggleEdit?()
    }
    #endif

    private func emitColour(_ delta: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastColourStep) > 0.3 else { return }
        lastColourStep = now
        onColour?(delta)
    }

    #if os(iOS) || os(tvOS)
    @objc private func orbitPan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state != .cancelled, gesture.state != .failed else { return }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        orbit(by: delta.x, deltaY: delta.y)
    }

    #if os(iOS)
    @objc private func pinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed || gesture.state == .ended else { return }
        let factor = gesture.scale
        gesture.scale = 1
        guard factor > 0 else { return }
        zoom(multiplier: Float(1 / factor))
    }

    @objc private func twoFingerPan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        // UIKit Y grows downward. The pan wants pointer-up to be positive.
        pan(screenX: Float(delta.x), screenY: Float(-delta.y))
    }
    #endif
    #endif

    #if os(tvOS)
    /// The next-car arrow is the remote's focus. A focusable scene would take it.
    override var canBecomeFocused: Bool { false }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if presses.contains(where: { $0.type == .upArrow }) {
            emitColour(1)
            return
        }
        if presses.contains(where: { $0.type == .downArrow }) {
            emitColour(-1)
            return
        }
        super.pressesEnded(presses, with: event)
    }
    #endif

    #if os(macOS)
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else { return }
        onToggleEdit?()
    }

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            pan(with: event)
            return
        }
        orbit(by: event.deltaX, deltaY: event.deltaY)
    }

    override func rightMouseDown(with event: NSEvent) {}

    override func rightMouseDragged(with event: NSEvent) {
        pan(with: event)
    }

    /// `pan` treats a positive screen Y as pointer-up. AppKit's drag deltaY grows downward.
    private func pan(with event: NSEvent) {
        pan(screenX: Float(event.deltaX), screenY: Float(-event.deltaY))
    }

    override func scrollWheel(with event: NSEvent) {
        let pixels = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 28
        zoom(multiplier: Float(exp(-Double(pixels) * 0.005)))
    }

    override func magnify(with event: NSEvent) {
        let factor = 1 + event.magnification
        guard factor > 0.05 else { return }
        zoom(multiplier: Float(1 / factor))
    }

    override func menu(for event: NSEvent) -> NSMenu? { nil }
    #endif
}

#if os(macOS)
private struct CarShowroomMac: NSViewRepresentable {
    let scene: SCNScene
    var editing: Bool
    var onToggleEdit: () -> Void
    var onColour: (Int) -> Void

    func makeNSView(context: Context) -> CarShowroomControlView { CarShowroomControlView(frame: .zero) }
    func updateNSView(_ view: CarShowroomControlView, context: Context) {
        view.editing = editing
        view.onToggleEdit = onToggleEdit
        view.onColour = onColour
        view.present(scene)
    }
}
#else
private struct CarShowroomIOS: UIViewRepresentable {
    let scene: SCNScene
    var editing: Bool
    var onToggleEdit: () -> Void
    var onColour: (Int) -> Void

    func makeUIView(context: Context) -> CarShowroomControlView { CarShowroomControlView(frame: .zero) }
    func updateUIView(_ view: CarShowroomControlView, context: Context) {
        view.editing = editing
        view.onToggleEdit = onToggleEdit
        view.onColour = onColour
        view.present(scene)
    }
}
#endif

#if !os(tvOS)
/// Up and down step colour while the edit arrows are on screen. Wheels have no key.
private struct ShowroomEditKey: ViewModifier {
    let key: KeyEquivalent?

    @ViewBuilder func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: [])
        } else {
            content
        }
    }
}
#endif
