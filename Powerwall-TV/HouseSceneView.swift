import CoreLocation
import SceneKit
import SwiftUI
import WeatherKit
#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
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
        let span = modelVerticalSpan(viewport: localSize, eye: eye, aim: aim)
        return HouseCalloutPoints(
            solar: place(SIMD3(-0.40, 1.145, 0)),
            home: place(PowerFlowLayout.anchors["FlowAnchor_Home"] ?? .zero),
            battery: place(SIMD3(0.050, 0.17, 0.92)),
            vehicle: place(PowerFlowLayout.anchors["FlowAnchor_WallConnector"] ?? .zero),
            grid: place(PowerFlowLayout.anchors["FlowAnchor_Gateway"] ?? .zero),
            gridRibbon: place(PowerFlowLayout.point(along: "Grid_1A", fraction: 0.5) ?? .zero),
            modelTop: origin.y + span.top,
            modelBottom: origin.y + span.bottom
        )
    }

    /// Roof and walls the metric labels have to stay off. Ground plane to the solar-roof crown.
    static let modelMin = SIMD3<Float>(-3.82, 0, -1.67)
    static let modelMax = SIMD3<Float>(0.08, 1.76, 1.27)

    /// Top and bottom of the house on screen. Y grows downward, matching `project`.
    static func modelVerticalSpan(viewport: CGSize, eye: SIMD3<Float>, aim: SIMD3<Float>) -> (top: CGFloat, bottom: CGFloat) {
        var top = CGFloat.greatestFiniteMagnitude
        var bottom = -CGFloat.greatestFiniteMagnitude
        for x in [modelMin.x, modelMax.x] {
            for y in [modelMin.y, modelMax.y] {
                for z in [modelMin.z, modelMax.z] {
                    let point = project(SIMD3(x, y, z), viewport: viewport, eye: eye, aim: aim)
                    top = min(top, point.y)
                    bottom = max(bottom, point.y)
                }
            }
        }
        return (top, bottom)
    }

    /// Pulls a label centre above or below the house. A centre that is already clear stays put.
    static func clearedLabelCenter(
        windowY: CGFloat,
        halfHeight: CGFloat,
        spanTop: CGFloat,
        spanBottom: CGFloat,
        above: Bool,
        screenMin: CGFloat,
        screenMax: CGFloat
    ) -> CGFloat {
        let gap: CGFloat = 8
        let desired = above
            ? min(windowY, spanTop - halfHeight - gap)
            : max(windowY, spanBottom + halfHeight + gap)
        return min(max(desired, screenMin + halfHeight), screenMax - halfHeight)
    }

    /// Leader run that stays off the house. `innerY` is the label edge facing the callout.
    /// `outerY` is the far edge. When the facing edge is already on the house, the line
    /// still draws in the clear band so it does not disappear as the model grows.
    static func leaderSegment(
        innerY: CGFloat,
        outerY: CGFloat,
        calloutY: CGFloat,
        length: CGFloat,
        modelTop: CGFloat?,
        modelBottom: CGFloat?
    ) -> (start: CGFloat, end: CGFloat)? {
        let full = calloutY - innerY
        guard length > 2, abs(full) > 2 else { return nil }
        let natural = innerY + copysign(min(length, abs(full)), full)
        guard let modelTop, let modelBottom else {
            guard abs(natural - innerY) > 8 else { return nil }
            return (innerY, natural)
        }
        let gap: CGFloat = 10
        let stub: CGFloat = 28
        if full > 0 {
            let limit = modelTop - gap
            if innerY < limit - 2 {
                let end = min(natural, limit)
                if end > innerY + 2 { return (innerY, end) }
            }
            if outerY < limit - 2 { return (outerY, limit) }
            let end = limit
            let start = end - stub
            return end > start + 2 ? (start, end) : nil
        }
        let limit = modelBottom + gap
        if innerY > limit + 2 {
            let end = max(natural, limit)
            if end < innerY - 2 { return (innerY, end) }
        }
        if outerY > limit + 2 { return (outerY, limit) }
        let end = limit
        let start = end + stub
        return start > end + 2 ? (start, end) : nil
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
    /// First launch and Reset 3D view. Identity stays the unshifted camera used by framing math.
    static let preferred = HouseScenePose(
        yawDegrees: 6,
        pitchDegrees: -5,
        distanceScale: 0.70,
        panRight: 0.5
    )
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
        let base = preferred
        func value(_ key: String, fallback: Double) -> Double {
            defaults.object(forKey: key) as? Double ?? fallback
        }
        return HouseScenePose(
            yawDegrees: value(Key.yaw, fallback: base.yawDegrees),
            pitchDegrees: value(Key.pitch, fallback: base.pitchDegrees),
            distanceScale: value(Key.distance, fallback: base.distanceScale),
            panRight: value(Key.panRight, fallback: base.panRight),
            panUp: value(Key.panUp, fallback: base.panUp),
            panForward: value(Key.panForward, fallback: base.panForward)
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
    /// Top and bottom of the house body, in the same window space. Y grows downward.
    var modelTop: CGFloat
    var modelBottom: CGFloat
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
/// How often the house sky moves. A forecast refresh is step 0 and every 45 ticks
/// (15 minutes at 20 seconds). The ticks between only move the sun. A paused
/// window skips those, because each one rebuilds the sky gradient on the main thread.
enum HouseSkyCadence {
    static func advancesSun(paused: Bool, step: Int) -> Bool {
        step % 45 != 0 && !paused
    }
}

/// Where the window is. Hidden is off screen and always pauses playback.
/// Visible but unfocused pauses only when the macOS checkbox is on.
enum AppAttention: Equatable {
    case focused
    case visibleUnfocused
    case hidden

    /// macOS window visibility. Occluded, minimized, or hidden is off screen.
    /// A visible window whose app is not active is on screen without focus.
    static func macWindow(isVisible: Bool, isMiniaturized: Bool, occlusionVisible: Bool, appHidden: Bool, appActive: Bool) -> AppAttention {
        let onScreen = isVisible && !isMiniaturized && occlusionVisible && !appHidden
        guard onScreen else { return .hidden }
        return appActive ? .focused : .visibleUnfocused
    }
}

/// Holds the one SceneKit house. `@State` would build a new controller, and reload
/// the USDZ, on every parent refresh. `StateObject` runs this thunk once.
@MainActor
final class HouseSceneControllerStore: ObservableObject {
    let controller = HouseSceneController()
}

struct HouseSceneView: View {
    @ObservedObject var viewModel: PowerwallViewModel
    /// Garage door or parked car. Empty when the caller has nothing to open.
    var onShowroom: () -> Void = {}
    @AppStorage("houseHeadingDegrees") private var houseHeadingDegrees = 180.0
    @StateObject private var store = HouseSceneControllerStore()
    private var controller: HouseSceneController { store.controller }
    @State private var weatherMark: HouseWeatherMark?
    @State private var skyRain: Float = 0
    @State private var skySnow: Float = 0
    @State private var revealingWeather = false

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
                onPose: { viewModel.houseScenePose = $0 },
                rainIntensity: skyRain,
                snowIntensity: skySnow,
                powerSnapshot: powerFlowSnapshot,
                revealingWeather: revealingWeather,
                pauseWhenUnfocused: viewModel.pauseAnimationWhenUnfocused,
                attention: viewModel.appAttention,
                showsVehicle: viewModel.garagePresentation.showVehicle,
                onShowroom: onShowroom
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
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: HouseWeatherFade.duration), value: weatherMark?.markURL)
        .onAppear {
            controller.notePlayback(attention: viewModel.appAttention, pauseWhenUnfocused: viewModel.pauseAnimationWhenUnfocused)
            controller.onRevealChange = { revealing in
                revealingWeather = revealing
                noteSky()
            }
            controller.apply(pose: viewModel.houseScenePose)
            controller.prepareIfNeeded()
            controller.apply(
                viewModel.garagePresentation,
                heading: houseHeadingDegrees,
                displayBoost: viewModel.isDemoMode ? 1 : nil
            )
            controller.applyPowerFlow(powerFlowSnapshot, solar: viewModel.garagePresentation.solar)
            controller.setBatteryLevel(viewModel.batteryPercentage?.percentage)
            noteSky()
        }
        .onChange(of: viewModel.batteryPercentage?.percentage) { percentage in
            controller.setBatteryLevel(percentage)
        }
        .onChange(of: viewModel.garagePresentation) { presentation in
            controller.apply(presentation, heading: houseHeadingDegrees, displayBoost: viewModel.isDemoMode ? 1 : nil)
            controller.applyPowerFlow(powerFlowSnapshot, solar: presentation.solar)
        }
        .onChange(of: powerFlowSnapshot) { snapshot in
            controller.applyPowerFlow(snapshot, solar: viewModel.garagePresentation.solar)
        }
        .onChange(of: houseHeadingDegrees) { heading in
            controller.applyHeading(heading)
        }
        .onChange(of: viewModel.pauseAnimationWhenUnfocused) { _ in
            controller.notePlayback(attention: viewModel.appAttention, pauseWhenUnfocused: viewModel.pauseAnimationWhenUnfocused)
        }
        .onChange(of: viewModel.appAttention) { _ in
            controller.notePlayback(attention: viewModel.appAttention, pauseWhenUnfocused: viewModel.pauseAnimationWhenUnfocused)
        }
        .onChange(of: viewModel.demoSceneIndex) { _ in
            guard viewModel.isDemoMode else { return }
            showDemoSky()
        }
        .onDisappear {
            controller.cancelWeatherFade()
        }
        .task(id: weatherIdentity) {
            // The sun steps with the clock. WeatherKit is read again every 15 minutes
            // so the wisps follow the current hour without a forecast call every tick.
            // A paused window keeps that forecast and does not rebuild the sky bitmap.
            var step = 0
            while !Task.isCancelled {
                if step % 45 == 0 {
                    await loadWeather()
                } else if HouseSkyCadence.advancesSun(
                    paused: PresentationRefresh.pausesAnimation(
                        attention: viewModel.appAttention,
                        pauseWhenUnfocused: viewModel.pauseAnimationWhenUnfocused
                    ),
                    step: step
                ) {
                    controller.advanceSkyClock()
                    noteSky()
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
        guard !viewModel.isDemoMode else {
            weatherMark = nil
            showDemoSky()
            return
        }
        guard viewModel.loginMode == .fleetAPI,
              let siteID = viewModel.energySiteId,
              !viewModel.accessToken.isEmpty else {
            weatherMark = nil
            controller.clearWeather(heading: houseHeadingDegrees)
            noteSky()
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
            controller.apply(sample: sample, heading: houseHeadingDegrees, fadeIn: true)
            noteSky()
            weatherMark = HouseWeatherMark(
                legalPageURL: sample.legalPageURL,
                markURL: sample.combinedMarkDarkURL
            )
        } catch {
            guard !Task.isCancelled else { return }
            weatherMark = nil
            controller.clearWeather(heading: houseHeadingDegrees)
            noteSky()
        }
    }

    private func showDemoSky() {
        controller.applyDemoSky(
            DemoHouseTour.weather(at: viewModel.demoSceneIndex),
            heading: houseHeadingDegrees,
            fadeIn: true
        )
        noteSky()
    }

    private func noteSky() {
        skyRain = controller.rainIntensity
        skySnow = controller.snowIntensity
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
    /// The wheel usdz on the parked car, so a new `wheel_type` swaps them and nothing else does.
    private var appliedWheels: String?
    private var sample: HouseWeatherSample?
    private var demoSky: DemoWeatherScene?
    /// Set when a demo sky was stored before the house lights existed.
    private var demoSkyNeedsApply = false
    private var heading = 180.0
    private var viewport: CGSize = .zero
    private var pose = HouseScenePose.identity
    private var fadeTask: Task<Void, Never>?
    private var fadeTarget: HouseLightingParameters?
    private var fadeGeneration = 0
    private var isRevealingWeather = false
    private var playbackAttention = AppAttention.focused
    private var playbackPauseWhenUnfocused = false
    /// Tells the scene view to keep drawing while a forecast is blending in.
    var onRevealChange: ((Bool) -> Void)?
    /// Lift for a custom override or an unknown paint. A known paint name uses the showroom display colour at boost 1.
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
        if let demoSky {
            applyDemoSky(demoSky, heading: heading, fadeIn: true)
        } else if let sample {
            apply(sample: sample, heading: heading, fadeIn: true)
        } else {
            applyClockLighting(heading: heading, animated: false)
        }
        if viewport.width > 1 {
            lighting?.updateWeatherCoverage(camera: camera, viewport: viewport)
        }
        syncWeatherMotion()
    }

    func apply(_ presentation: GaragePresentation, heading: Double, displayBoost: CGFloat? = nil) {
        self.heading = heading
        guard let lighting else { return }
        lighting.setSolar(presentation.solar.sceneOption)
        lighting.showWallConnector(presentation.showWallConnector)
        lighting.showVehicle(presentation.showVehicle)
        guard presentation.showVehicle else {
            appliedModel = nil
            appliedPaint = nil
            appliedWheels = nil
            return
        }
        if appliedModel != presentation.model {
            lighting.setVehicleModel(presentation.model)
            appliedModel = presentation.model
            appliedPaint = nil
            appliedWheels = nil
        }
        let wheels = WheelChoice.resolve(wheelType: presentation.wheelType, model: presentation.model)
        if appliedWheels != wheels?.asset {
            lighting.setVehicleWheels(wheels)
            appliedWheels = wheels?.asset
        }
        // The baked generic body has no paint shell. Live cars and the demo both leave it.
        guard presentation.model != .generic else { return }
        // Cybertruck stays on the file's stainless mix unless Fleet sent a wrap or a demo colour.
        if presentation.model == .cybertruck && presentation.paintColorOverride == nil {
            return
        }
        // Same choice as the showroom: a known paint name draws TeslaPaint.display at boost 1.
        // Fleet's paint_color_override is a skybox albedo, so it only paints a car with no known name.
        let boost = displayBoost ?? paintDisplayBoost
        let paintKey = "\(presentation.exteriorColor ?? "")|\(presentation.paintColorOverride ?? "")|\(presentation.colorizerRemap)|\(boost)"
        guard appliedPaint != paintKey else { return }
        appliedPaint = paintKey
        guard let body = ShowroomPaint.resolve(
            model: presentation.model,
            exteriorColor: presentation.exteriorColor,
            paintColorOverride: presentation.paintColorOverride,
            colorizerRemap: presentation.colorizerRemap,
            owned: true
        ).bodyPaint(displayBoost: boost) else { return }
        lighting.setVehiclePaint(body.paint, displayBoost: body.boost)
    }

    func setBatteryLevel(_ percentage: Double?) {
        let fraction = percentage.map { Float(min(max($0 / 100, 0), 1)) }
        batteryBar?.setFraction(fraction)
    }

    func applyPowerFlow(_ snapshot: PowerFlowSnapshot, solar: GarageSolar) {
        powerFlow.setSolarTerminate(solar == .roof ? 1000 : 2.2)
        powerFlow.update(snapshot)
        lighting?.setInteriorLights(homeW: snapshot.homeW, vehicleW: snapshot.vehicleW)
    }

    func apply(sample: HouseWeatherSample, heading: Double, animated: Bool = true, fadeIn: Bool = false) {
        demoSky = nil
        demoSkyNeedsApply = false
        self.sample = sample
        self.heading = heading
        guard lighting != nil else { return }
        present(weatherParameters(sample, heading: heading), animated: animated, fadeIn: fadeIn)
    }

    /// Shows a scripted demo sky. Repeating the scene that is already up does
    /// not restart the fade. The clock does not move this sun.
    func applyDemoSky(_ scene: DemoWeatherScene, heading: Double, fadeIn: Bool) {
        let changed = demoSky != scene || sample != nil || demoSkyNeedsApply
        demoSky = scene
        sample = nil
        self.heading = heading
        guard lighting != nil else {
            demoSkyNeedsApply = true
            return
        }
        demoSkyNeedsApply = false
        guard changed || !fadeIn else { return }
        present(scene.parameters(heading: heading), animated: false, fadeIn: fadeIn && changed)
    }

    private func present(_ parameters: HouseLightingParameters, animated: Bool, fadeIn: Bool) {
        guard lighting != nil else { return }
        if fadeIn {
            // The forecast replaces the clock sky. Blend it in so clouds and
            // precipitation don't pop on when WeatherKit returns.
            startWeatherFade(to: parameters)
            return
        }
        if fadeTask != nil {
            fadeTarget = parameters
            return
        }
        lighting?.apply(parameters, animated: animated)
    }

    /// Stops a forecast blend. The next lighting apply owns the sky.
    func cancelWeatherFade() {
        fadeTask?.cancel()
        fadeTask = nil
        fadeTarget = nil
        guard isRevealingWeather else { return }
        isRevealingWeather = false
        onRevealChange?(false)
    }

    private func weatherParameters(_ sample: HouseWeatherSample, heading: Double) -> HouseLightingParameters {
        // The hourly sample carries cloud cover. The disc follows the actual time,
        // so a display left on keeps the sun moving between forecast refreshes.
        let sun = SolarPosition.compute(date: Date(), coordinate: sample.location.coordinate)
        return WeatherLighting(houseHeadingDegrees: heading).parameters(
            sunAltitude: sun.altitude,
            sunAzimuth: sun.azimuth,
            isDaylight: sun.altitude > -6,
            cloudCover: sample.cloudCover,
            condition: sample.condition,
            precipitationMillimetresPerHour: sample.precipitationMillimetresPerHour
        )
    }

    private func startWeatherFade(to target: HouseLightingParameters) {
        fadeTarget = target
        guard let lighting else { return }
        let from = lighting.currentParameters
        fadeGeneration += 1
        let generation = fadeGeneration
        fadeTask?.cancel()
        if !isRevealingWeather {
            isRevealingWeather = true
            onRevealChange?(true)
        }
        let task = Task { @MainActor in
            var elapsed: TimeInterval = 0
            var lastTick = Date()
            while !Task.isCancelled, fadeGeneration == generation {
                let now = Date()
                let interval = HouseWeatherFade.stepInterval(
                    attention: playbackAttention,
                    pauseWhenUnfocused: playbackPauseWhenUnfocused
                )
                if interval.isInfinite {
                    lastTick = now
                    do {
                        try await Task.sleep(nanoseconds: 200_000_000)
                    } catch {
                        return
                    }
                    continue
                }
                elapsed += now.timeIntervalSince(lastTick)
                lastTick = now
                let t = min(1, elapsed / HouseWeatherFade.duration)
                let goal = fadeTarget ?? target
                lighting.apply(from.interpolated(toward: goal, fraction: Float(HouseWeatherFade.ease(t))), animated: false)
                if t >= 1 { break }
                let nanos = UInt64((interval * 1_000_000_000).rounded())
                do {
                    try await Task.sleep(nanoseconds: max(nanos, 1))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, fadeGeneration == generation else { return }
            lighting.apply(fadeTarget ?? target, animated: false)
            fadeTask = nil
            fadeTarget = nil
            isRevealingWeather = false
            onRevealChange?(false)
        }
        fadeTask = task
    }

    /// The fade loop reads this so a focus change applies on the next step.
    func notePlayback(attention: AppAttention, pauseWhenUnfocused: Bool) {
        playbackAttention = attention
        playbackPauseWhenUnfocused = pauseWhenUnfocused
        syncWeatherMotion()
    }

    /// Rain, snow, and cloud drift. `scene.isPaused` does not stop particle emission.
    private func syncWeatherMotion() {
        lighting?.setWeatherMotionPaused(
            PresentationRefresh.pausesAnimation(
                attention: playbackAttention,
                pauseWhenUnfocused: playbackPauseWhenUnfocused
            )
        )
    }

    /// Repositions the sun from the clock without fetching WeatherKit again.
    func advanceSkyClock() {
        if demoSky != nil { return }
        if let sample {
            apply(sample: sample, heading: heading, animated: false)
        } else {
            applyClockLighting(heading: heading, animated: false)
        }
    }

    func applyHeading(_ heading: Double) {
        self.heading = heading
        if let demoSky {
            applyDemoSky(demoSky, heading: heading, fadeIn: false)
        } else if let sample {
            apply(sample: sample, heading: heading)
        } else {
            applyClockLighting(heading: heading)
        }
    }

    func clearWeather(heading: Double) {
        sample = nil
        demoSky = nil
        demoSkyNeedsApply = false
        cancelWeatherFade()
        applyClockLighting(heading: heading)
    }

    var rainIntensity: Float { lighting?.rainIntensity ?? 0 }
    var snowIntensity: Float { lighting?.snowIntensity ?? 0 }

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
    let rainIntensity: Float
    let snowIntensity: Float
    let powerSnapshot: PowerFlowSnapshot
    let revealingWeather: Bool
    let pauseWhenUnfocused: Bool
    let attention: AppAttention
    let showsVehicle: Bool
    let onShowroom: () -> Void

    var body: some View {
        #if os(macOS)
        HouseMetalSceneMac(scene: scene, pointOfView: pointOfView, powerFlow: powerFlow, pose: pose, onPose: onPose, rainIntensity: rainIntensity, snowIntensity: snowIntensity, powerSnapshot: powerSnapshot, revealingWeather: revealingWeather, pauseWhenUnfocused: pauseWhenUnfocused, attention: attention, showsVehicle: showsVehicle, onShowroom: onShowroom)
        #else
        HouseMetalSceneIOS(scene: scene, pointOfView: pointOfView, powerFlow: powerFlow, pose: pose, onPose: onPose, rainIntensity: rainIntensity, snowIntensity: snowIntensity, powerSnapshot: powerSnapshot, revealingWeather: revealingWeather, pauseWhenUnfocused: pauseWhenUnfocused, attention: attention, showsVehicle: showsVehicle, onShowroom: onShowroom)
        #endif
    }
}

/// How long a loaded forecast takes to replace the clock sky.
enum HouseWeatherFade {
    static let duration: TimeInterval = 5

    static func ease(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Seconds between blend steps. Matches the display refresh while the house
    /// is animating. A paused window does not step.
    static func stepInterval(attention: AppAttention, pauseWhenUnfocused: Bool, displayRefresh: TimeInterval? = nil) -> TimeInterval {
        let decision = PresentationRefresh.decision(
            interacting: false,
            rainIntensity: 0,
            snowIntensity: 0,
            snapshot: PowerFlowSnapshot(),
            revealingWeather: true,
            attention: attention,
            pauseWhenUnfocused: pauseWhenUnfocused
        )
        if decision.animationsPaused { return .infinity }
        return displayRefresh ?? displayRefreshInterval
    }

    static var displayRefreshInterval: TimeInterval {
        let fps: Int
        #if os(macOS)
        fps = NSScreen.main?.maximumFramesPerSecond ?? 60
        #elseif os(iOS) || os(tvOS)
        fps = UIScreen.main.maximumFramesPerSecond
        #else
        fps = 60
        #endif
        return 1.0 / Double(max(fps, 1))
    }
}

/// Idle house frames stay still. Dragging, rain, snow, a ribbon above the
/// solver's 10 W threshold, or a forecast still fading in is what keeps
/// SceneKit on the display refresh. A paused window never uses that loop.
enum HouseSceneRenderPolicy {
    static func needsContinuousRendering(interacting: Bool, rainIntensity: Float, snowIntensity: Float, snapshot: PowerFlowSnapshot, revealingWeather: Bool = false) -> Bool {
        let precipitation = rainIntensity > 0 || snowIntensity > 0
        let flowing = PowerFlowSolver.wires(for: snapshot).contains { $0.isFlowing }
        return interacting || precipitation || flowing || revealingWeather
    }

    static func apply(to view: SCNView, interacting: Bool, rainIntensity: Float, snowIntensity: Float, snapshot: PowerFlowSnapshot, revealingWeather: Bool = false, attention: AppAttention = .focused, pauseWhenUnfocused: Bool = false) {
        let decision = PresentationRefresh.decision(
            interacting: interacting,
            rainIntensity: rainIntensity,
            snowIntensity: snowIntensity,
            snapshot: snapshot,
            revealingWeather: revealingWeather,
            attention: attention,
            pauseWhenUnfocused: pauseWhenUnfocused
        )
        PresentationRefresh.apply(decision, to: view)
    }
}

/// macOS Display checkbox. Off until the user turns it on.
enum PauseAnimationWhenUnfocused {
    static let key = "pauseAnimationWhenUnfocused"

    static func stored(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? false
    }
}

/// One answer for "how soon is the next frame" on the 3D house and the flat home.
/// Playback is either the display refresh or fully stopped.
enum PresentationRefresh {
    struct Decision: Equatable {
        var rendersContinuously: Bool
        var isPlaying: Bool
        /// Zero lets SceneKit use the display refresh.
        var preferredFramesPerSecond: Int
        /// Off screen, or unfocused when the macOS checkbox is on.
        /// SceneKit is paused and power flows are chevrons on the grey track.
        var animationsPaused: Bool = false

        var usesDisplayRefresh: Bool {
            rendersContinuously && preferredFramesPerSecond == 0
        }
    }

    /// Hidden always pauses. A visible unfocused window pauses only when the checkbox is on.
    static func pausesAnimation(attention: AppAttention, pauseWhenUnfocused: Bool) -> Bool {
        if attention == .hidden { return true }
        return pauseWhenUnfocused && attention != .focused
    }

    static func decision(
        interacting: Bool,
        rainIntensity: Float,
        snowIntensity: Float,
        snapshot: PowerFlowSnapshot,
        revealingWeather: Bool = false,
        attention: AppAttention = .focused,
        pauseWhenUnfocused: Bool = false
    ) -> Decision {
        if pausesAnimation(attention: attention, pauseWhenUnfocused: pauseWhenUnfocused) {
            return Decision(
                rendersContinuously: false,
                isPlaying: false,
                preferredFramesPerSecond: 0,
                animationsPaused: true
            )
        }
        let moving = HouseSceneRenderPolicy.needsContinuousRendering(
            interacting: interacting,
            rainIntensity: rainIntensity,
            snowIntensity: snowIntensity,
            snapshot: snapshot,
            revealingWeather: revealingWeather
        )
        return Decision(
            rendersContinuously: moving,
            isPlaying: moving,
            preferredFramesPerSecond: 0,
            animationsPaused: false
        )
    }

    static func apply(_ decision: Decision, to view: SCNView) {
        view.preferredFramesPerSecond = decision.preferredFramesPerSecond
        view.rendersContinuously = decision.rendersContinuously
        view.isPlaying = decision.isPlaying
        view.antialiasingMode = .multisampling4X
        view.scene?.isPaused = decision.animationsPaused
        guard decision.animationsPaused else { return }
        #if os(macOS)
        view.setNeedsDisplay(view.bounds)
        #else
        view.setNeedsDisplay()
        #endif
    }
}

/// Orbit, pan, and zoom without SceneKit's camera controller, which fights `look(at:)`.
/// The view does not become first responder, so the arrow keys still change energy sites.
final class HouseCameraControlView: SCNView {
    var pose = HouseScenePose.identity
    var onPose: (HouseScenePose) -> Void = { _ in }
    var onShowroom: () -> Void = {}
    var showsVehicle = false
    private var revision = 0
    private var clickOrigin: CGPoint?
    private var pointerDragged = false
    private var syncedRevision = 0
    private var isAdjustingCamera = false
    private var rainIntensity: Float = 0
    private var snowIntensity: Float = 0
    private var powerSnapshot = PowerFlowSnapshot()
    private var revealingWeather = false
    private var pauseWhenUnfocused = false
    private var attention = AppAttention.focused

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

    /// The same call `HouseMetalScene` uses when it binds the live view.
    func applyPlayback(rainIntensity: Float, snowIntensity: Float, snapshot: PowerFlowSnapshot, interacting: Bool? = nil, revealingWeather: Bool? = nil, attention: AppAttention? = nil, pauseWhenUnfocused: Bool? = nil) {
        if let interacting { isAdjustingCamera = interacting }
        if let revealingWeather { self.revealingWeather = revealingWeather }
        if let attention { self.attention = attention }
        if let pauseWhenUnfocused { self.pauseWhenUnfocused = pauseWhenUnfocused }
        self.rainIntensity = rainIntensity
        self.snowIntensity = snowIntensity
        powerSnapshot = snapshot
        let decision = PresentationRefresh.decision(
            interacting: isAdjustingCamera,
            rainIntensity: rainIntensity,
            snowIntensity: snowIntensity,
            snapshot: snapshot,
            revealingWeather: self.revealingWeather,
            attention: self.attention,
            pauseWhenUnfocused: self.pauseWhenUnfocused
        )
        // The SwiftUI binding reaches this before `onChange` pushes the snapshot.
        // Give the driver that snapshot and, when the view is about to pause,
        // paint chevrons on the track. A paused view never ticks.
        if let driver = delegate as? HousePowerFlowDriver {
            // Record the pause before the snapshot. Attach and later solar-roof
            // rebuilds paint from this flag, because they run after the view has
            // already stopped.
            driver.setPresentation(playing: decision.isPlaying, solidFlows: decision.animationsPaused)
            driver.update(snapshot)
        }
        PresentationRefresh.apply(decision, to: self)
    }

    private func beginCameraAdjustment() {
        guard !isAdjustingCamera else { return }
        isAdjustingCamera = true
        refreshPlayback()
    }

    private func endCameraAdjustment() {
        guard isAdjustingCamera else { return }
        isAdjustingCamera = false
        refreshPlayback()
    }

    private func refreshPlayback() {
        applyPlayback(rainIntensity: rainIntensity, snowIntensity: snowIntensity, snapshot: powerSnapshot)
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(showroomTap(_:)))
        addGestureRecognizer(tap)
        #elseif os(tvOS)
        let tap = UITapGestureRecognizer(target: self, action: #selector(showroomTap(_:)))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        addGestureRecognizer(tap)
        #endif
    }

    /// A click that did not drag. The hidden garage door still counts while a car is parked.
    /// With no car, only the visible door opens the showroom, so a click on the wall does not.
    private func selectShowroom(at point: CGPoint) {
        if showsVehicle {
            let hits = hitTest(point, options: [
                SCNHitTestOption.ignoreHiddenNodes: false,
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue
            ])
            guard hits.contains(where: { isGarageDoorOrCar($0.node) }) else { return }
        } else {
            let hits = hitTest(point, options: [
                SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue
            ])
            guard let nearest = hits.first, isGarageDoor(nearest.node) else { return }
        }
        onShowroom()
    }

    private func isGarageDoorOrCar(_ node: SCNNode) -> Bool {
        if isGarageDoor(node) { return true }
        var current: SCNNode? = node
        while let cursor = current {
            let name = cursor.name ?? ""
            if name == "Vehicle" || name.hasPrefix("VehicleBody") || name.hasPrefix("VehicleModel") {
                return true
            }
            current = cursor.parent
        }
        return false
    }

    private func isGarageDoor(_ node: SCNNode) -> Bool {
        var current: SCNNode? = node
        while let cursor = current {
            if cursor.name?.hasPrefix("GarageDoor") == true { return true }
            current = cursor.parent
        }
        return false
    }

    #if os(iOS) || os(tvOS)
    @objc private func showroomTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        selectShowroom(at: gesture.location(in: self))
    }
    #endif

    #if os(tvOS)
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        guard presses.contains(where: { $0.type == .select }) else { return }
        selectShowroom(at: CGPoint(x: bounds.midX, y: bounds.midY))
    }
    #endif

    #if os(iOS)
    @objc private func orbitPan(_ gesture: UIPanGestureRecognizer) {
        noteCameraGesture(gesture.state)
        let delta = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        // UIKit Y grows downward. Passing it through matches the orbit the
        // device wants: a finger moving down raises the camera. Two-finger
        // pan still flips Y so the house follows the finger.
        orbit(deltaX: delta.x, deltaY: delta.y)
    }

    @objc private func twoFingerPan(_ gesture: UIPanGestureRecognizer) {
        noteCameraGesture(gesture.state)
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

    private func noteCameraGesture(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began, .changed:
            beginCameraAdjustment()
        case .ended, .cancelled, .failed:
            endCameraAdjustment()
        default:
            break
        }
    }
    #endif

    #if os(macOS)
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        clickOrigin = convert(event.locationInWindow, from: nil)
        pointerDragged = false
        beginCameraAdjustment()
    }

    override func mouseDragged(with event: NSEvent) {
        pointerDragged = true
        if event.modifierFlags.contains(.option) {
            pan(with: event)
        } else {
            // Drag deltaY is device space, so it is positive when the pointer moves down.
            // Adding it raises the camera, which is the same orbit iOS uses.
            orbit(deltaX: event.deltaX, deltaY: event.deltaY)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        beginCameraAdjustment()
    }

    override func rightMouseDragged(with event: NSEvent) {
        pan(with: event)
    }

    /// `pan` treats a positive deltaY as pointer-up. AppKit's drag deltaY grows downward.
    private func pan(with event: NSEvent) {
        pan(deltaX: event.deltaX, deltaY: -event.deltaY)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let origin = clickOrigin ?? point
        let moved = hypot(point.x - origin.x, point.y - origin.y)
        endCameraAdjustment()
        if !pointerDragged && moved < 5 {
            selectShowroom(at: point)
        }
        clickOrigin = nil
    }

    override func rightMouseUp(with event: NSEvent) {
        endCameraAdjustment()
    }

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
    let rainIntensity: Float
    let snowIntensity: Float
    let powerSnapshot: PowerFlowSnapshot
    let revealingWeather: Bool
    let pauseWhenUnfocused: Bool
    let attention: AppAttention
    let showsVehicle: Bool
    let onShowroom: () -> Void

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
        HouseSky.useWashShader(in: view)
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.focusRingType = .none
        view.sync(from: pose)
        view.onPose = onPose
        view.showsVehicle = showsVehicle
        view.onShowroom = onShowroom
        if view.delegate !== delegate { view.delegate = delegate }
        view.applyPlayback(rainIntensity: rainIntensity, snowIntensity: snowIntensity, snapshot: powerSnapshot, revealingWeather: revealingWeather, attention: attention, pauseWhenUnfocused: pauseWhenUnfocused)
    }
}
#else
private struct HouseMetalSceneIOS: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode
    let powerFlow: HousePowerFlowDriver
    let pose: HouseScenePose
    let onPose: (HouseScenePose) -> Void
    let rainIntensity: Float
    let snowIntensity: Float
    let powerSnapshot: PowerFlowSnapshot
    let revealingWeather: Bool
    let pauseWhenUnfocused: Bool
    let attention: AppAttention
    let showsVehicle: Bool
    let onShowroom: () -> Void

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
        HouseSky.useWashShader(in: view)
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.sync(from: pose)
        view.onPose = onPose
        view.showsVehicle = showsVehicle
        view.onShowroom = onShowroom
        if view.delegate !== delegate { view.delegate = delegate }
        view.applyPlayback(rainIntensity: rainIntensity, snowIntensity: snowIntensity, snapshot: powerSnapshot, revealingWeather: revealingWeather, attention: attention, pauseWhenUnfocused: pauseWhenUnfocused)
    }
}
#endif
