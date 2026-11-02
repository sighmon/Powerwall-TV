import CoreLocation
import SceneKit
import SwiftUI
import WeatherKit
#if os(iOS)
import UIKit
#endif

struct HouseWeatherMark: Equatable {
    let legalPageURL: URL
    let markURL: URL
}

/// Where the metric labels meet the house. Shared by the camera and the grey leader lines.
enum HouseCameraFraming {
    static let verticalFOVDegrees: Float = 30
    /// Horizontal picture shift as a fraction of the view width. Zero keeps the house centred.
    static let rightShiftFraction: Float = 0
    static let subject = SIMD3<Float>(-1.6, 0.6, 0)
    static var position: SIMD3<Float> {
        let framed = SIMD3<Float>(4.5, 4.0, 6.5)
        return subject + (framed - subject) * 1.5
    }

    /// Same view direction as the centred camera. Stepping the camera left moves the house right.
    static func offset(viewport: CGSize) -> SIMD3<Float> {
        let forward = simd_normalize(subject - position)
        let right = simd_normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
        let distance = simd_length(position - subject)
        let halfHeight = distance * tan(verticalFOVDegrees * .pi / 180 / 2)
        let aspect = Float(viewport.width / max(viewport.height, 1))
        let fullWidth = halfHeight * max(aspect, 0.01) * 2
        return -right * (fullWidth * rightShiftFraction)
    }

    static func eye(viewport: CGSize) -> SIMD3<Float> { position + offset(viewport: viewport) }

    static func target(viewport: CGSize) -> SIMD3<Float> { subject + offset(viewport: viewport) }

    /// Top-left origin, matching SwiftUI. `viewport` is the SceneKit view's size.
    static func project(_ world: SIMD3<Float>, viewport: CGSize, aim explicitAim: SIMD3<Float>? = nil) -> CGPoint {
        project(
            world,
            viewport: viewport,
            eye: eye(viewport: viewport),
            aim: explicitAim ?? target(viewport: viewport)
        )
    }

    /// Top-left origin, matching SwiftUI. `eye` and `aim` are the live camera, so leader lines follow a saved pose.
    static func project(_ world: SIMD3<Float>, viewport: CGSize, eye: SIMD3<Float>, aim: SIMD3<Float>) -> CGPoint {
        let forward = simd_normalize(aim - eye)
        let right = simd_normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = cross(right, forward)
        let offset = world - eye
        let x = simd_dot(offset, right)
        let y = simd_dot(offset, up)
        let depth = max(simd_dot(offset, forward), 0.001)
        let tanY = tan(verticalFOVDegrees * .pi / 180 / 2)
        let aspect = Float(viewport.width / max(viewport.height, 1))
        let ndcX = (x / depth) / (tanY * aspect)
        let ndcY = (y / depth) / tanY
        return CGPoint(
            x: CGFloat(ndcX * 0.5 + 0.5) * viewport.width,
            y: CGFloat(0.5 - ndcY * 0.5) * viewport.height
        )
    }

    static func callouts(localSize: CGSize, origin: CGPoint, pose: HouseScenePose = .identity) -> HouseCalloutPoints {
        let eye = pose.eye
        let aim = pose.target
        func place(_ world: SIMD3<Float>) -> CGPoint {
            let local = project(world, viewport: localSize, eye: eye, aim: aim)
            return CGPoint(x: origin.x + local.x, y: origin.y + local.y)
        }
        return HouseCalloutPoints(
            solar: place(SIMD3(-0.40, 1.145, 0)),
            home: place(PowerFlowLayout.anchors["FlowAnchor_Home"] ?? .zero),
            battery: place(SIMD3(0.050, 0.17, 0.92)),
            vehicle: place(PowerFlowLayout.anchors["FlowAnchor_WallConnector"] ?? .zero),
            grid: place(PowerFlowLayout.anchors["FlowAnchor_Gateway"] ?? .zero),
            gridRibbon: place(PowerFlowLayout.point(along: "Grid_1A", fraction: 0.5) ?? .zero)
        )
    }
}

/// User framing of the centred camera. Identity reproduces `HouseCameraFraming.position` and `.subject`.
/// Yaw and pitch orbit the aim point. Pan is stored in the default camera's right/up/forward basis.
struct HouseScenePose: Equatable {
    var yawDegrees: Double = 0
    var pitchDegrees: Double = 0
    var distanceScale: Double = 1
    var panRight: Double = 0
    var panUp: Double = 0
    var panForward: Double = 0

    static let identity = HouseScenePose()
    static let yawRange: ClosedRange<Double> = -180...180
    static let distanceRange: ClosedRange<Double> = 0.45...2.2
    static let panRange: ClosedRange<Double> = -3...3
    static var pitchRange: ClosedRange<Double> {
        let pitch0 = Double(basis.pitch * 180 / .pi)
        return (8 - pitch0)...(80 - pitch0)
    }

    enum Key {
        static let show = "showHouseScene"
        static let yaw = "houseYawDegrees"
        static let pitch = "housePitchDegrees"
        static let distance = "houseDistanceScale"
        static let panRight = "housePanRight"
        static let panUp = "housePanUp"
        static let panForward = "housePanForward"
        static let all = [show, yaw, pitch, distance, panRight, panUp, panForward]
    }

    struct Basis {
        let forward: SIMD3<Float>
        let right: SIMD3<Float>
        let up: SIMD3<Float>
        let distance: Float
        let yaw: Float
        let pitch: Float
    }

    static let basis: Basis = {
        let offset = HouseCameraFraming.position - HouseCameraFraming.subject
        let distance = simd_length(offset)
        let forward = simd_normalize(HouseCameraFraming.subject - HouseCameraFraming.position)
        let right = simd_normalize(cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_normalize(cross(right, forward))
        return Basis(
            forward: forward,
            right: right,
            up: up,
            distance: distance,
            yaw: atan2(offset.x, offset.z),
            pitch: asin(offset.y / distance)
        )
    }()

    var eye: SIMD3<Float> { placement.eye }
    var target: SIMD3<Float> { placement.target }

    var placement: (eye: SIMD3<Float>, target: SIMD3<Float>) {
        let basis = Self.basis
        let shift = basis.right * Float(panRight) + basis.up * Float(panUp) + basis.forward * Float(panForward)
        let target = HouseCameraFraming.subject + shift
        let resting = abs(yawDegrees) < 1e-7 && abs(pitchDegrees) < 1e-7 && abs(distanceScale - 1) < 1e-7
        if resting {
            return (HouseCameraFraming.position + shift, target)
        }
        let yaw = basis.yaw + Float(yawDegrees) * .pi / 180
        let pitch = basis.pitch + Float(pitchDegrees) * .pi / 180
        let radius = basis.distance * Float(distanceScale)
        let eye = target + SIMD3<Float>(
            sin(yaw) * cos(pitch) * radius,
            sin(pitch) * radius,
            cos(yaw) * cos(pitch) * radius
        )
        return (eye, target)
    }

    func clamped() -> HouseScenePose {
        var copy = self
        copy.yawDegrees = Self.wrapYaw(yawDegrees)
        let pitch0 = Double(Self.basis.pitch)
        let absolute = min(max(pitch0 + pitchDegrees * .pi / 180, 8 * .pi / 180), 80 * .pi / 180)
        copy.pitchDegrees = (absolute - pitch0) * 180 / .pi
        copy.distanceScale = min(max(distanceScale, Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
        copy.panRight = min(max(panRight, Self.panRange.lowerBound), Self.panRange.upperBound)
        copy.panUp = min(max(panUp, Self.panRange.lowerBound), Self.panRange.upperBound)
        copy.panForward = min(max(panForward, Self.panRange.lowerBound), Self.panRange.upperBound)
        return copy
    }

    /// World transform with the camera's up kept in the plane of world up, so yaw cannot roll the house.
    var levelTransform: simd_float4x4 {
        let eye = eye
        let back = simd_normalize(eye - target)
        let side = simd_cross(SIMD3<Float>(0, 1, 0), back)
        let right = simd_length(side) > 0.0001 ? simd_normalize(side) : SIMD3<Float>(1, 0, 0)
        let up = simd_normalize(simd_cross(back, right))
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4<Float>(right.x, right.y, right.z, 0)
        transform.columns.1 = SIMD4<Float>(up.x, up.y, up.z, 0)
        transform.columns.2 = SIMD4<Float>(back.x, back.y, back.z, 0)
        transform.columns.3 = SIMD4<Float>(eye.x, eye.y, eye.z, 1)
        return transform
    }

    func panned(by world: SIMD3<Float>) -> HouseScenePose {
        let basis = Self.basis
        let current = basis.right * Float(panRight) + basis.up * Float(panUp) + basis.forward * Float(panForward)
        let next = current + world
        var copy = self
        copy.panRight = Double(simd_dot(next, basis.right))
        copy.panUp = Double(simd_dot(next, basis.up))
        copy.panForward = Double(simd_dot(next, basis.forward))
        return copy
    }

    static func stored() -> HouseScenePose {
        let defaults = UserDefaults.standard
        func value(_ key: String) -> Double { defaults.object(forKey: key) as? Double ?? 0 }
        return HouseScenePose(
            yawDegrees: value(Key.yaw),
            pitchDegrees: value(Key.pitch),
            distanceScale: defaults.object(forKey: Key.distance) as? Double ?? 1,
            panRight: value(Key.panRight),
            panUp: value(Key.panUp),
            panForward: value(Key.panForward)
        ).clamped()
    }

    func write() {
        let defaults = UserDefaults.standard
        defaults.set(yawDegrees, forKey: Key.yaw)
        defaults.set(pitchDegrees, forKey: Key.pitch)
        defaults.set(distanceScale, forKey: Key.distance)
        defaults.set(panRight, forKey: Key.panRight)
        defaults.set(panUp, forKey: Key.panUp)
        defaults.set(panForward, forKey: Key.panForward)
    }

    static func removeStored() {
        Key.all.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func wrapYaw(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}

struct HouseCalloutPoints: Equatable {
    var solar: CGPoint
    var home: CGPoint
    var battery: CGPoint
    var vehicle: CGPoint
    var grid: CGPoint
    /// Halfway along the grid ribbon, in the same window space as the other callouts.
    var gridRibbon: CGPoint
}

struct HouseCalloutKey: PreferenceKey {
    static var defaultValue: HouseCalloutPoints? = nil
    static func reduce(value: inout HouseCalloutPoints?, nextValue: () -> HouseCalloutPoints?) {
        value = nextValue() ?? value
    }
}

/// SceneKit stand-in for the flat home background. Lighting comes from the same
/// WeatherKit forecast cache as Home Energy Advisor. The parked car follows the
/// wall connector, using cached Fleet paint when `vehicle_data` has already returned it.
struct HouseSceneView: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @AppStorage("houseHeadingDegrees") private var houseHeadingDegrees = 180.0
    @State private var controller = HouseSceneController()
    @State private var weatherMark: HouseWeatherMark?

    var body: some View {
        GeometryReader { proxy in
            scene(in: proxy.size)
                .background {
                    GeometryReader { local in
                        Color.clear.preference(
                            key: HouseCalloutKey.self,
                            value: HouseCameraFraming.callouts(
                                localSize: local.size,
                                origin: local.frame(in: .named("contentView")).origin,
                                pose: viewModel.houseScenePose
                            )
                        )
                    }
                }
                .onAppear {
                    controller.apply(pose: viewModel.houseScenePose)
                    controller.updateViewport(proxy.size)
                }
                .onChange(of: proxy.size) { controller.updateViewport($0) }
                .onChange(of: viewModel.houseScenePose) { controller.apply(pose: $0) }
        }
    }

    private func scene(in size: CGSize) -> some View {
        ZStack(alignment: .bottomTrailing) {
            HouseMetalScene(
                scene: controller.scene,
                pointOfView: controller.camera,
                powerFlow: controller.powerFlow,
                pose: viewModel.houseScenePose,
                onPose: { viewModel.houseScenePose = $0 }
            )
                .frame(width: size.width, height: size.height)
                .focusable(false)
                .accessibilityHidden(true)

            if let weatherMark {
                Link(destination: weatherMark.legalPageURL) {
                    AsyncImage(url: weatherMark.markURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text("Apple Weather")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(width: 72, height: 18)
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("Apple Weather legal attribution")
            }
        }
        .onAppear {
            controller.apply(pose: viewModel.houseScenePose)
            controller.prepareIfNeeded()
            controller.apply(viewModel.garagePresentation, heading: houseHeadingDegrees)
            controller.applyPowerFlow(powerFlowSnapshot, solar: viewModel.garagePresentation.solar)
            controller.setBatteryLevel(viewModel.batteryPercentage?.percentage)
        }
        .onChange(of: viewModel.batteryPercentage?.percentage) { percentage in
            controller.setBatteryLevel(percentage)
        }
        .onChange(of: viewModel.garagePresentation) { presentation in
            controller.apply(presentation, heading: houseHeadingDegrees)
            controller.applyPowerFlow(powerFlowSnapshot, solar: presentation.solar)
        }
        .onChange(of: powerFlowSnapshot) { snapshot in
            controller.applyPowerFlow(snapshot, solar: viewModel.garagePresentation.solar)
        }
        .onChange(of: houseHeadingDegrees) { heading in
            controller.applyHeading(heading)
        }
        .task(id: weatherIdentity) {
            // The sun steps with the clock. WeatherKit is read again every 15 minutes
            // so the wisps follow the current hour without a forecast call every tick.
            var step = 0
            while !Task.isCancelled {
                if step % 45 == 0 {
                    await loadWeather()
                } else {
                    controller.advanceSkyClock()
                }
                step += 1
                do {
                    try await Task.sleep(nanoseconds: 20_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    private var powerFlowSnapshot: PowerFlowSnapshot {
        PowerFlowSnapshot(
            data: viewModel.data,
            presentation: viewModel.garagePresentation,
            batteryCount: viewModel.batteryCount
        )
    }

    private var weatherIdentity: String {
        [
            viewModel.loginMode.rawValue,
            viewModel.energySiteId ?? "",
            viewModel.fleetBaseURL,
            String(viewModel.accessToken.isEmpty),
            String(viewModel.isDemoMode),
            UserDefaults.standard.string(forKey: "exportAdvisor_weatherLocation_" + (viewModel.energySiteId ?? "")) ?? ""
        ].joined(separator: "|")
    }

    private func loadWeather() async {
        guard !viewModel.isDemoMode,
              viewModel.loginMode == .fleetAPI,
              let siteID = viewModel.energySiteId,
              !viewModel.accessToken.isEmpty else {
            weatherMark = nil
            controller.clearWeather(heading: houseHeadingDegrees)
            return
        }

        let service = ExportAdvisorService(
            baseURL: viewModel.fleetBaseURL,
            token: viewModel.accessToken,
            siteID: siteID
        )
        do {
            let sample = try await service.houseWeather()
            guard !Task.isCancelled else { return }
            controller.apply(sample: sample, heading: houseHeadingDegrees)
            weatherMark = HouseWeatherMark(
                legalPageURL: sample.legalPageURL,
                markURL: sample.combinedMarkDarkURL
            )
        } catch {
            guard !Task.isCancelled else { return }
            weatherMark = nil
            controller.clearWeather(heading: houseHeadingDegrees)
        }
    }
}

@MainActor
final class HouseSceneController {
    let scene: SCNScene
    let camera: SCNNode
    let powerFlow = HousePowerFlowDriver()
    private var lighting: HouseLighting?
    private var batteryBar: PowerwallLevelBar?
    private var prepared = false
    private var appliedModel: VehicleModel?
    private var appliedPaint: String?
    private var sample: HouseWeatherSample?
    private var heading = 180.0
    private var viewport: CGSize = .zero
    private var pose = HouseScenePose.identity
    /// Tesla's paint albedos assume a skybox. This lift keeps them readable under SceneKit lights.
    private let paintDisplayBoost: CGFloat = 4

    init() {
        scene = ResidentialClassicScene.load() ?? SCNScene()
        let node = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(HouseCameraFraming.verticalFOVDegrees)
        node.camera = camera
        self.camera = node
        aim(pose)
    }

    func updateViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        viewport = size
        aim(pose)
        lighting?.updateWeatherCoverage(camera: camera, viewport: size)
    }

    /// Moves the camera without touching the ribbons. Identity is the centred view.
    func apply(pose: HouseScenePose) {
        self.pose = pose.clamped()
        aim(self.pose)
        guard viewport.width > 1 else { return }
        lighting?.updateWeatherCoverage(camera: camera, viewport: viewport)
    }

    private func aim(_ pose: HouseScenePose) {
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        // look(at:) keeps the previous up vector and rolls the house as the yaw changes.
        camera.simdTransform = pose.levelTransform
        SCNTransaction.commit()
    }

    func prepareIfNeeded() {
        guard !prepared else { return }
        prepared = true
        scene.background.contents = HouseColor(red: 22 / 255, green: 23 / 255, blue: 24 / 255, alpha: 1)
        if camera.parent == nil { scene.rootNode.addChildNode(camera) }
        let house = scene.rootNode.childNode(withName: "ResidentialClassic", recursively: true) ?? scene.rootNode
        lighting = HouseLighting(root: house)
        PowerFlowObstacles.coverFlows(house: house)
        let cameraPosition = SIMD3<Float>(Float(camera.position.x), Float(camera.position.y), Float(camera.position.z))
        batteryBar = PowerwallLevelBar(house: house, cameraPosition: cameraPosition)
        powerFlow.attach(house: house, cameraPosition: cameraPosition)
        if let sample {
            apply(sample: sample, heading: heading)
        } else {
            applyClockLighting(heading: heading)
        }
        if viewport.width > 1 {
            lighting?.updateWeatherCoverage(camera: camera, viewport: viewport)
        }
    }

    func apply(_ presentation: GaragePresentation, heading: Double) {
        self.heading = heading
        guard let lighting else { return }
        lighting.setSolar(presentation.solar.sceneOption)
        lighting.showWallConnector(presentation.showWallConnector)
        lighting.showVehicle(presentation.showVehicle)
        guard presentation.showVehicle else {
            appliedModel = nil
            appliedPaint = nil
            return
        }
        if appliedModel != presentation.model {
            lighting.setVehicleModel(presentation.model)
            appliedModel = presentation.model
            appliedPaint = nil
        }
        guard presentation.model != .generic else { return }
        // Cybertruck stays on the file's stainless mix unless Fleet sent a wrap override.
        if presentation.model == .cybertruck && presentation.paintColorOverride == nil {
            return
        }
        let paintKey = "\(presentation.exteriorColor ?? "")|\(presentation.paintColorOverride ?? "")|\(presentation.colorizerRemap)"
        guard appliedPaint != paintKey else { return }
        lighting.setVehiclePaint(
            exteriorColor: presentation.exteriorColor,
            paintColorOverride: presentation.paintColorOverride,
            colorizerRemap: presentation.colorizerRemap,
            displayBoost: paintDisplayBoost
        )
        appliedPaint = paintKey
    }

    func setBatteryLevel(_ percentage: Double?) {
        let fraction = percentage.map { Float(min(max($0 / 100, 0), 1)) }
        batteryBar?.setFraction(fraction)
    }

    func applyPowerFlow(_ snapshot: PowerFlowSnapshot, solar: GarageSolar) {
        powerFlow.setSolarTerminate(solar == .roof ? 1000 : 2.2)
        powerFlow.update(snapshot)
    }

    func apply(sample: HouseWeatherSample, heading: Double, animated: Bool = true) {
        self.sample = sample
        self.heading = heading
        guard lighting != nil else { return }
        // The hourly sample carries cloud cover. The disc follows the actual time,
        // so a display left on keeps the sun moving between forecast refreshes.
        let sun = SolarPosition.compute(date: Date(), coordinate: sample.location.coordinate)
        let parameters = WeatherLighting(houseHeadingDegrees: heading).parameters(
            sunAltitude: sun.altitude,
            sunAzimuth: sun.azimuth,
            isDaylight: sun.altitude > -6,
            cloudCover: sample.cloudCover,
            condition: sample.condition,
            precipitationMillimetresPerHour: sample.precipitationMillimetresPerHour
        )
        lighting?.apply(parameters, animated: animated)
    }

    /// Repositions the sun from the clock without fetching WeatherKit again.
    func advanceSkyClock() {
        if let sample {
            apply(sample: sample, heading: heading, animated: false)
        } else {
            applyClockLighting(heading: heading, animated: false)
        }
    }

    func applyHeading(_ heading: Double) {
        self.heading = heading
        if let sample {
            apply(sample: sample, heading: heading)
        } else {
            applyClockLighting(heading: heading)
        }
    }

    func clearWeather(heading: Double) {
        sample = nil
        applyClockLighting(heading: heading)
    }

    private func applyClockLighting(heading: Double, animated: Bool = true) {
        self.heading = heading
        guard lighting != nil else { return }
        let sun = HouseSky.clockSun(at: Date(), heading: heading)
        let parameters = WeatherLighting(houseHeadingDegrees: heading).parameters(
            sunAltitude: sun.altitude,
            sunAzimuth: sun.azimuth,
            isDaylight: sun.altitude > 0,
            cloudCover: 0.2,
            condition: .clear,
            precipitationMillimetresPerHour: 0
        )
        lighting?.apply(parameters, animated: animated)
    }
}

/// SceneView does not expose multisampling. Thin roof edges alias into gaps without it.
private struct HouseMetalScene: View {
    let scene: SCNScene
    let pointOfView: SCNNode
    let powerFlow: HousePowerFlowDriver
    let pose: HouseScenePose
    let onPose: (HouseScenePose) -> Void

    var body: some View {
        #if os(macOS)
        HouseMetalSceneMac(scene: scene, pointOfView: pointOfView, powerFlow: powerFlow, pose: pose, onPose: onPose)
        #else
        HouseMetalSceneIOS(scene: scene, pointOfView: pointOfView, powerFlow: powerFlow, pose: pose, onPose: onPose)
        #endif
    }
}

/// Orbit, pan, and zoom without SceneKit's camera controller, which fights `look(at:)`.
/// The view does not become first responder, so the arrow keys still change energy sites.
final class HouseCameraControlView: SCNView {
    var pose = HouseScenePose.identity
    var onPose: (HouseScenePose) -> Void = { _ in }
    private var revision = 0
    private var syncedRevision = 0

    override init(frame frameRect: CGRect, options: [String: Any]? = nil) {
        super.init(frame: frameRect, options: options)
        installPlatformGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installPlatformGestures()
    }

    /// Keeps a drag in charge until SwiftUI has caught up with the pose it published.
    func sync(from incoming: HouseScenePose) {
        if revision == syncedRevision {
            pose = incoming
        }
        syncedRevision = revision
    }

    fileprivate func publish(_ next: HouseScenePose) {
        let clamped = next.clamped()
        revision += 1
        pose = clamped
        onPose(clamped)
    }

    fileprivate func orbit(deltaX: CGFloat, deltaY: CGFloat) {
        let degreesPerPoint = CGFloat(HouseCameraFraming.verticalFOVDegrees) / max(bounds.height, 1)
        var next = pose
        next.yawDegrees -= Double(deltaX * degreesPerPoint)
        next.pitchDegrees += Double(deltaY * degreesPerPoint)
        publish(next)
    }

    fileprivate func pan(deltaX: CGFloat, deltaY: CGFloat) {
        let eye = pose.eye
        let target = pose.target
        let forward = target - eye
        let distance = simd_length(forward)
        guard distance > 0.001 else { return }
        let direction = forward / distance
        let right = simd_normalize(cross(direction, SIMD3<Float>(0, 1, 0)))
        let up = simd_normalize(cross(right, direction))
        let halfHeight = distance * tan(HouseCameraFraming.verticalFOVDegrees * .pi / 180 / 2)
        let metresPerPoint = halfHeight * 2 / Float(max(bounds.height, 1))
        // Truck opposite the drag so the house stays under the cursor.
        let world = right * (Float(-deltaX) * metresPerPoint) + up * (Float(-deltaY) * metresPerPoint)
        publish(pose.panned(by: world))
    }

    fileprivate func zoom(multiplier: Double) {
        guard multiplier.isFinite, multiplier > 0 else { return }
        var next = pose
        next.distanceScale *= multiplier
        publish(next)
    }

    private func installPlatformGestures() {
        #if os(iOS)
        let orbit = UIPanGestureRecognizer(target: self, action: #selector(orbitPan(_:)))
        orbit.maximumNumberOfTouches = 1
        addGestureRecognizer(orbit)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(twoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        addGestureRecognizer(pan)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinchZoom(_:))))
        #endif
    }

    #if os(iOS)
    @objc private func orbitPan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        // UIKit Y grows downward. Passing it through matches the orbit the
        // device wants: a finger moving down raises the camera. Two-finger
        // pan still flips Y so the house follows the finger.
        orbit(deltaX: delta.x, deltaY: delta.y)
    }

    @objc private func twoFingerPan(_ gesture: UIPanGestureRecognizer) {
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        pan(deltaX: delta.x, deltaY: -delta.y)
    }

    @objc private func pinchZoom(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed || gesture.state == .ended else { return }
        let factor = gesture.scale
        gesture.scale = 1
        guard factor > 0 else { return }
        zoom(multiplier: 1 / Double(factor))
    }
    #endif

    #if os(macOS)
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            pan(with: event)
        } else {
            // Drag deltaY is device space, so it is positive when the pointer moves down.
            // Adding it raises the camera, which is the same orbit iOS uses.
            orbit(deltaX: event.deltaX, deltaY: event.deltaY)
        }
    }

    override func rightMouseDown(with event: NSEvent) {}

    override func rightMouseDragged(with event: NSEvent) {
        pan(with: event)
    }

    /// `pan` treats a positive deltaY as pointer-up. AppKit's drag deltaY grows downward.
    private func pan(with event: NSEvent) {
        pan(deltaX: event.deltaX, deltaY: -event.deltaY)
    }

    override func rightMouseUp(with event: NSEvent) {}

    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func scrollWheel(with event: NSEvent) {
        let pixels = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 28
        zoom(multiplier: exp(-Double(pixels) * 0.005))
    }

    override func magnify(with event: NSEvent) {
        let factor = 1 + event.magnification
        guard factor > 0.05 else { return }
        zoom(multiplier: 1 / Double(factor))
    }
    #endif
}

#if os(macOS)
private struct HouseMetalSceneMac: NSViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode
    let powerFlow: HousePowerFlowDriver
    let pose: HouseScenePose
    let onPose: (HouseScenePose) -> Void

    func makeCoordinator() -> HousePowerFlowDriver { powerFlow }
    func makeNSView(context: Context) -> HouseCameraControlView { configured(context.coordinator) }
    func updateNSView(_ view: HouseCameraControlView, context: Context) { bind(view, delegate: context.coordinator) }

    private func configured(_ delegate: HousePowerFlowDriver) -> HouseCameraControlView {
        let view = HouseCameraControlView(frame: .zero)
        bind(view, delegate: delegate)
        return view
    }

    private func bind(_ view: HouseCameraControlView, delegate: HousePowerFlowDriver) {
        if view.scene !== scene { view.scene = scene }
        if view.pointOfView !== pointOfView { view.pointOfView = pointOfView }
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isPlaying = true
        view.focusRingType = .none
        view.sync(from: pose)
        view.onPose = onPose
        if view.delegate !== delegate { view.delegate = delegate }
    }
}
#else
private struct HouseMetalSceneIOS: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode
    let powerFlow: HousePowerFlowDriver
    let pose: HouseScenePose
    let onPose: (HouseScenePose) -> Void

    func makeCoordinator() -> HousePowerFlowDriver { powerFlow }
    func makeUIView(context: Context) -> HouseCameraControlView { configured(context.coordinator) }
    func updateUIView(_ view: HouseCameraControlView, context: Context) { bind(view, delegate: context.coordinator) }

    private func configured(_ delegate: HousePowerFlowDriver) -> HouseCameraControlView {
        let view = HouseCameraControlView(frame: .zero)
        bind(view, delegate: delegate)
        return view
    }

    private func bind(_ view: HouseCameraControlView, delegate: HousePowerFlowDriver) {
        if view.scene !== scene { view.scene = scene }
        if view.pointOfView !== pointOfView { view.pointOfView = pointOfView }
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isPlaying = true
        view.sync(from: pose)
        view.onPose = onPose
        if view.delegate !== delegate { view.delegate = delegate }
    }
}
#endif
