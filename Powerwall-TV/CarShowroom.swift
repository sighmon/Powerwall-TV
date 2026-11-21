//
//  CarShowroom.swift
//  Powerwall-TV
//
//  Fullscreen view of the car already parked in the garage. The plate is the
//  home ground glass. The house shell stays out of this scene.
//

import SceneKit
import SwiftUI

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
    /// No Fleet vehicle on the account. The cover can step through the exported models.
    var browsesCatalogue: Bool = false

    var id: String { vin ?? model.rawValue }
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
    /// Same point the ground plate is built around.
    static var stageCentre: SIMD3<Float> {
        (HouseCameraFraming.modelMin + HouseCameraFraming.modelMax) * 0.5
    }

    /// Exported Tesla models. The generic placeholder is not a car Tesla sells.
    static var catalogueModels: [VehicleModel] {
        VehicleModel.allCases.filter { $0 != .generic }
    }

    /// The parked car when the house is showing one. Otherwise, when the account has no cars
    /// and this is not the demo tour, the first catalogue model. An owner with nothing plugged in stays closed.
    static func select(
        data: PowerwallData?,
        fallbackVIN: String,
        appearances: [String: VehicleAppearance],
        solar: GarageSolar,
        vehicles: [FleetVehicle],
        charges: [String: VehicleChargeSnapshot],
        displayBoost: CGFloat,
        isDemoMode: Bool
    ) -> CarShowroomRequest? {
        if let owned = request(
            data: data,
            fallbackVIN: fallbackVIN,
            appearances: appearances,
            solar: solar,
            vehicles: vehicles,
            charges: charges,
            displayBoost: displayBoost
        ) {
            return isDemoMode ? DemoHouseTour.applyingExampleFleetData(to: owned) : owned
        }
        guard !isDemoMode, vehicles.isEmpty else { return nil }
        return catalogueRequest(index: 0)
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
            lines: statLines(displayName: name, exteriorColor: presentation.exteriorColor, snapshot: charge(for: vin, in: charges))
        )
    }

    /// Name, then battery, charging state, and minutes to full. A nil or blank field is left out.
    /// Colour is the same suffix the demo chips use, and only when this car has an exterior colour.
    static func statLines(displayName: String, exteriorColor: String?, snapshot: VehicleChargeSnapshot?) -> [String] {
        var lines = [DemoHouseTour.vehicleLabel(displayName: displayName, exteriorColor: exteriorColor)]
        if let batteryLevel = snapshot?.batteryLevel {
            lines.append("\(Int(batteryLevel.rounded()))% battery")
        }
        if let chargingState = snapshot?.chargingState?.trimmingCharacters(in: .whitespacesAndNewlines), !chargingState.isEmpty {
            lines.append(chargingState)
        }
        if let minutesToFullCharge = snapshot?.minutesToFullCharge {
            lines.append("\(Int(minutesToFullCharge.rounded())) minutes to full charge")
        }
        return lines
    }

    /// The parked car on a plate from `HouseGroundPlate.install`. The car is marked for the mirror
    /// after install, because that install clears the reflection bit on vehicle names.
    static func scene(for request: CarShowroomRequest) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = HouseColor(red: 22 / 255, green: 23 / 255, blue: 24 / 255, alpha: 1)
        let centre = stageCentre

        let cameraNode = SCNNode()
        cameraNode.name = cameraName
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(CarShowroomOrbit.verticalFieldOfViewDegrees)
        camera.zNear = 0.05
        camera.zFar = 80
        cameraNode.camera = camera
        cameraNode.simdPosition = SIMD3(centre.x + 3.1, 1.25, centre.z - 5.4)
        scene.rootNode.addChildNode(cameraNode)
        cameraNode.look(at: SCNVector3(centre.x, 0.72, centre.z))

        addLight(named: "ShowroomKey", type: .directional, intensity: 900, at: cameraNode.simdPosition, lookingAt: centre, in: scene)
        addLight(named: "ShowroomFill", type: .ambient, intensity: 280, at: centre, lookingAt: nil, in: scene)

        HouseGroundPlate.install(on: scene.rootNode)

        let vehicle = loadVehicle(model: request.model)
        vehicle.simdPosition = SIMD3(centre.x, 0, centre.z)
        // Catalogue cars keep the colour exported in the file until a colour step sets a wrap.
        // An owned car still uses Fleet paint.
        let wrap = request.paintColorOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !request.browsesCatalogue || !wrap.isEmpty {
            paint(
                vehicle,
                model: request.model,
                exteriorColor: request.exteriorColor,
                paintColorOverride: request.paintColorOverride,
                colorizerRemap: request.colorizerRemap,
                displayBoost: request.displayBoost
            )
        }
        scene.rootNode.addChildNode(vehicle)
        includeInReflection(vehicle)
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
        return wrapper
    }

    /// Next catalogue colour. `current` nil starts at the first colour for a positive step
    /// and the last colour for a negative step.
    static func colourIndex(after current: Int?, delta: Int) -> Int {
        let count = max(TeslaPaint.catalogue.count, 1)
        let base = current ?? (delta >= 0 ? -1 : 0)
        return wrapped(base + delta, count: count)
    }

    /// Generic keeps its file colour. Cybertruck stays stainless unless a wrap or a demo colour is set.
    private static func paint(
        _ vehicle: SCNNode,
        model: VehicleModel,
        exteriorColor: String?,
        paintColorOverride: String?,
        colorizerRemap: Bool,
        displayBoost: CGFloat
    ) {
        guard model != .generic else { return }
        let wrap = paintColorOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if model == .cybertruck && wrap.isEmpty { return }
        let resolved = TeslaPaint.resolve(
            exteriorColor: exteriorColor,
            paintColorOverride: paintColorOverride,
            colorizerRemap: colorizerRemap
        )
        vehicle.enumerateHierarchy { node, _ in
            node.geometry?.materials.filter { $0.name == "Paint" }.forEach {
                resolved.apply(to: $0, displayBoost: displayBoost, clearCoat: 0)
            }
        }
    }

    private static func wrapped(_ index: Int, count: Int) -> Int {
        let count = max(count, 1)
        let wrapped = index % count
        return wrapped >= 0 ? wrapped : wrapped + count
    }

    private static func includeInReflection(_ node: SCNNode) {
        node.categoryBitMask |= HouseGroundPlate.reflectionBit
        for child in node.childNodes {
            includeInReflection(child)
        }
    }

    private static func addLight(
        named name: String,
        type: SCNLight.LightType,
        intensity: CGFloat,
        at position: SIMD3<Float>,
        lookingAt centre: SIMD3<Float>?,
        in scene: SCNScene
    ) {
        let node = SCNNode()
        node.name = name
        let light = SCNLight()
        light.type = type
        light.intensity = intensity
        node.light = light
        node.simdPosition = position
        scene.rootNode.addChildNode(node)
        if let centre {
            node.look(at: SCNVector3(centre.x, 0.6, centre.z))
        }
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

    static let pitchRange: ClosedRange<Float> = -20...50
    /// Wide enough that a portrait window can still back up to fit a Cybertruck.
    static let distanceRange: ClosedRange<Float> = 0.2...6
    /// Eye minus the look target at the resting view. The car's nose is −Z.
    static let restingOffset = SIMD3<Float>(3.1, 0.53, -5.4)
    static let lookHeight: Float = 0.72
    /// Share of the window the fitted car may use. The rest stays clear of the edges.
    static let fitFill: Float = 0.9
    static let verticalFieldOfViewDegrees: Float = 28

    func clamped() -> CarShowroomOrbit {
        var copy = self
        copy.pitchDegrees = min(max(pitchDegrees, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
        copy.distanceScale = min(max(distanceScale, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
        return copy
    }

    func target(around centre: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(centre.x, Self.lookHeight, centre.z) + centreBias
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
    /// `aspect` is view width divided by height. The vertical field of view stays 28°.
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
    var onDismiss: () -> Void
    @State private var scene: SCNScene?
    @State private var browseIndex = 0
    /// Nil keeps the file or Fleet colour. Up and down walk `TeslaPaint.catalogue`.
    @State private var colourIndex: Int?

    private var displayed: CarShowroomRequest {
        var shown = request.browsesCatalogue ? CarShowroom.catalogueRequest(index: browseIndex) : request
        guard let colourIndex, shown.model != .generic else { return shown }
        let paint = TeslaPaint.catalogue[colourIndex % TeslaPaint.catalogue.count]
        shown.exteriorColor = paint.name
        shown.paintColorOverride = paint.demoOverride
        shown.colorizerRemap = false
        shown.displayBoost = 1
        let bareName = shown.lines.first.map(Self.bareTitle) ?? CarShowroom.catalogueName(shown.model)
        if shown.lines.isEmpty {
            shown.lines = [DemoHouseTour.vehicleLabel(displayName: bareName, exteriorColor: paint.name)]
        } else {
            shown.lines[0] = DemoHouseTour.vehicleLabel(displayName: bareName, exteriorColor: paint.name)
        }
        return shown
    }

    /// Drops a previous " · Colour" suffix so the next colour does not stack.
    private static func bareTitle(_ line: String) -> String {
        guard let dot = line.range(of: " · ") else { return line }
        return String(line[..<dot.lowerBound])
    }

    var body: some View {
        GeometryReader { proxy in
            let valueFont = showroomValueFont(for: proxy.size)
            let labelFont = showroomLabelFont(for: proxy.size)
            ZStack {
                Color(red: 22 / 255, green: 23 / 255, blue: 24 / 255)
                    .ignoresSafeArea()
                if let scene {
                    CarShowroomMetalView(scene: scene) { shiftColour($0) }
                        .ignoresSafeArea()
                }
            }
            .overlay(alignment: .topLeading) {
                carDetails(valueFont: valueFont, labelFont: labelFont, width: labelWidth(in: proxy))
                    .padding(.top, chromeInset(proxy.safeAreaInsets.top))
                    .padding(.leading, chromeInset(proxy.safeAreaInsets.leading))
            }
            .overlay(alignment: .topTrailing) {
                closeButton
                    .padding(.top, chromeInset(proxy.safeAreaInsets.top))
                    .padding(.trailing, chromeInset(proxy.safeAreaInsets.trailing))
            }
            .overlay(alignment: .bottomLeading) {
                if request.browsesCatalogue {
                    catalogueArrows
                        .padding(.leading, chromeInset(proxy.safeAreaInsets.leading))
                        .padding(.bottom, chromeInset(proxy.safeAreaInsets.bottom))
                }
            }
        }
        .background {
            #if !os(tvOS)
            colourKey(delta: 1, key: .upArrow, label: "Next colour")
            colourKey(delta: -1, key: .downArrow, label: "Previous colour")
            #endif
        }
        .onAppear {
            if scene == nil {
                scene = CarShowroom.scene(for: displayed)
            }
        }
        #if os(tvOS)
        .focusable(true)
        .onMoveCommand { direction in
            switch direction {
            case .up: shiftColour(1)
            case .down: shiftColour(-1)
            default: break
            }
        }
        #endif
        #if !os(iOS)
        .onExitCommand(perform: onDismiss)
        #endif
    }

    private func colourKey(delta: Int, key: KeyEquivalent, label: String) -> some View {
        Button(action: { shiftColour(delta) }) { Color.clear.frame(width: 1, height: 1) }
            .buttonStyle(.plain)
            .keyboardShortcut(key, modifiers: [])
            .accessibilityLabel(label)
            .opacity(0)
            .allowsHitTesting(false)
    }

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
            if request.browsesCatalogue {
                Link("Buy a Tesla", destination: CarShowroom.orderURL(for: displayed.model))
                    .fontWeight(.bold)
                    .font(labelFont)
                    .opacity(0.6)
                    .padding(.top, 8)
                    .accessibilityLabel("Buy a Tesla")
            }
        }
        .foregroundColor(.white)
        .multilineTextAlignment(.leading)
        .frame(width: width, alignment: .leading)
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

    /// The system close glyph, top right.
    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
                .padding(10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        #if !os(tvOS)
        .keyboardShortcut(.cancelAction)
        #endif
    }

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
        #if !os(tvOS)
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

    private func step(_ delta: Int) {
        guard request.browsesCatalogue, !CarShowroom.catalogueModels.isEmpty else { return }
        browseIndex += delta
        scene = CarShowroom.scene(for: displayed)
    }

    private func shiftColour(_ delta: Int) {
        guard displayed.model != .generic, !TeslaPaint.catalogue.isEmpty else { return }
        colourIndex = CarShowroom.colourIndex(after: colourIndex, delta: delta)
        scene = CarShowroom.scene(for: displayed)
    }
}

private struct CarShowroomMetalView: View {
    let scene: SCNScene
    var onColour: (Int) -> Void

    var body: some View {
        #if os(macOS)
        CarShowroomMac(scene: scene, onColour: onColour)
        #else
        CarShowroomIOS(scene: scene, onColour: onColour)
        #endif
    }
}

/// Drag orbits the car. Scroll, pinch, and magnify zoom. A vertical swipe steps the colour.
/// The orbit survives a model change.
final class CarShowroomControlView: SCNView {
    var orbit = CarShowroomOrbit()
    var onColour: ((Int) -> Void)?
    private var swipeTranslation = CGPoint.zero
    private var swipeBegan = Date.distantPast
    private var swipeActive = false
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
        backgroundColor = HouseColor(red: 22 / 255, green: 23 / 255, blue: 24 / 255, alpha: 1)
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
        pointOfView = camera
        #if os(macOS)
        setNeedsDisplay(bounds)
        #else
        setNeedsDisplay()
        #endif
    }

    private func orbit(by deltaX: CGFloat, deltaY: CGFloat) {
        let degreesPerPoint = CarShowroomOrbit.verticalFieldOfViewDegrees / Float(max(bounds.height, 1))
        orbit.yawDegrees -= Float(deltaX) * degreesPerPoint
        orbit.pitchDegrees += Float(deltaY) * degreesPerPoint
        orbit = orbit.clamped()
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
        #if os(iOS) || os(tvOS)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(orbitPan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinchZoom(_:))))
        #endif
    }

    private func beginSwipe() {
        swipeTranslation = .zero
        swipeBegan = Date()
        swipeActive = true
    }

    private func trackSwipe(deltaX: CGFloat, deltaY: CGFloat) {
        if !swipeActive { beginSwipe() }
        swipeTranslation.x += deltaX
        swipeTranslation.y += deltaY
    }

    /// A short vertical flick changes colour and puts the orbit back. A slow drag still orbits.
    private func finishSwipe() {
        defer {
            swipeActive = false
            swipeTranslation = .zero
        }
        guard swipeActive else { return }
        let elapsed = Date().timeIntervalSince(swipeBegan)
        let translation = swipeTranslation
        guard elapsed < 0.45, abs(translation.y) > 80, abs(translation.y) > abs(translation.x) * 2.2 else { return }
        orbit(by: -translation.x, deltaY: -translation.y)
        emitColour(translation.y < 0 ? 1 : -1)
    }

    private func emitColour(_ delta: Int) {
        let now = Date()
        guard now.timeIntervalSince(lastColourStep) > 0.3 else { return }
        lastColourStep = now
        onColour?(delta)
    }

    #if os(iOS) || os(tvOS)
    @objc private func orbitPan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .cancelled || gesture.state == .failed {
            swipeActive = false
            swipeTranslation = .zero
            return
        }
        if gesture.state == .began { beginSwipe() }
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        trackSwipe(deltaX: delta.x, deltaY: delta.y)
        orbit(by: delta.x, deltaY: delta.y)
        if gesture.state == .ended { finishSwipe() }
    }

    @objc private func pinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed || gesture.state == .ended else { return }
        let factor = gesture.scale
        gesture.scale = 1
        guard factor > 0 else { return }
        zoom(multiplier: Float(1 / factor))
    }
    #endif

    #if os(tvOS)
    override var canBecomeFocused: Bool { true }

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
        beginSwipe()
    }

    override func mouseDragged(with event: NSEvent) {
        trackSwipe(deltaX: event.deltaX, deltaY: event.deltaY)
        orbit(by: event.deltaX, deltaY: event.deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        finishSwipe()
    }

    override func swipe(with event: NSEvent) {
        let vertical = event.deltaY
        guard abs(vertical) > abs(event.deltaX), vertical != 0 else { return }
        emitColour(vertical > 0 ? 1 : -1)
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
    var onColour: (Int) -> Void

    func makeNSView(context: Context) -> CarShowroomControlView { CarShowroomControlView(frame: .zero) }
    func updateNSView(_ view: CarShowroomControlView, context: Context) {
        view.onColour = onColour
        view.present(scene)
    }
}
#else
private struct CarShowroomIOS: UIViewRepresentable {
    let scene: SCNScene
    var onColour: (Int) -> Void

    func makeUIView(context: Context) -> CarShowroomControlView { CarShowroomControlView(frame: .zero) }
    func updateUIView(_ view: CarShowroomControlView, context: Context) {
        view.onColour = onColour
        view.present(scene)
    }
}
#endif
