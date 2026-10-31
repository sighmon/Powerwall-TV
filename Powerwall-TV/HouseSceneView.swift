import CoreLocation
import SceneKit
import SwiftUI
import WeatherKit

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
        let eye = eye(viewport: viewport)
        let aim = explicitAim ?? target(viewport: viewport)
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

    static func callouts(localSize: CGSize, origin: CGPoint) -> HouseCalloutPoints {
        func place(_ world: SIMD3<Float>) -> CGPoint {
            let local = project(world, viewport: localSize)
            return CGPoint(x: origin.x + local.x, y: origin.y + local.y)
        }
        return HouseCalloutPoints(
            solar: place(SIMD3(-0.40, 1.145, 0)),
            home: place(PowerFlowLayout.anchors["FlowAnchor_Home"] ?? .zero),
            battery: place(SIMD3(0.050, 0.17, 0.92)),
            vehicle: place(PowerFlowLayout.anchors["FlowAnchor_WallConnector"] ?? .zero),
            grid: place(PowerFlowLayout.anchors["FlowAnchor_Gateway"] ?? .zero)
        )
    }
}

struct HouseCalloutPoints: Equatable {
    var solar: CGPoint
    var home: CGPoint
    var battery: CGPoint
    var vehicle: CGPoint
    var grid: CGPoint
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
                                origin: local.frame(in: .named("contentView")).origin
                            )
                        )
                    }
                }
                .onAppear { controller.updateViewport(proxy.size) }
                .onChange(of: proxy.size) { controller.updateViewport($0) }
        }
    }

    private func scene(in size: CGSize) -> some View {
        ZStack(alignment: .bottomTrailing) {
            HouseMetalScene(scene: controller.scene, pointOfView: controller.camera, powerFlow: controller.powerFlow)
                .frame(width: size.width, height: size.height)
                .focusable(false)
                .allowsHitTesting(false)
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
            await loadWeather()
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
    /// Tesla's paint albedos assume a skybox. This lift keeps them readable under SceneKit lights.
    private let paintDisplayBoost: CGFloat = 4

    init() {
        scene = ResidentialClassicScene.load() ?? SCNScene()
        let node = SCNNode()
        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(HouseCameraFraming.verticalFOVDegrees)
        node.camera = camera
        self.camera = node
        aimCamera(viewport: CGSize(width: 16, height: 9))
    }

    func updateViewport(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        viewport = size
        aimCamera(viewport: size)
        lighting?.updateWeatherCoverage(camera: camera, viewport: size)
    }

    /// 1.5× further than (4.5, 4, 6.5), looking at the same point so the house stays centred.
    private func aimCamera(viewport: CGSize) {
        let eye = HouseCameraFraming.eye(viewport: viewport)
        let target = HouseCameraFraming.target(viewport: viewport)
        camera.position = SCNVector3(CGFloat(eye.x), CGFloat(eye.y), CGFloat(eye.z))
        camera.look(at: SCNVector3(CGFloat(target.x), CGFloat(target.y), CGFloat(target.z)))
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

    func apply(sample: HouseWeatherSample, heading: Double) {
        self.sample = sample
        self.heading = heading
        guard lighting != nil else { return }
        let sun = SolarPosition.compute(date: sample.date, coordinate: sample.location.coordinate)
        let parameters = WeatherLighting(houseHeadingDegrees: heading).parameters(
            sunAltitude: sun.altitude,
            sunAzimuth: sun.azimuth,
            isDaylight: sample.isDaylight,
            cloudCover: sample.cloudCover,
            condition: sample.condition,
            precipitationMillimetresPerHour: sample.precipitationMillimetresPerHour
        )
        lighting?.apply(parameters)
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

    private func applyClockLighting(heading: Double) {
        self.heading = heading
        guard lighting != nil else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        let daylight = (6..<19).contains(hour)
        let parameters = WeatherLighting(houseHeadingDegrees: heading).parameters(
            sunAltitude: daylight ? 35 : -10,
            sunAzimuth: 180,
            isDaylight: daylight,
            cloudCover: 0.2,
            condition: .clear,
            precipitationMillimetresPerHour: 0
        )
        lighting?.apply(parameters)
    }
}

/// SceneView does not expose multisampling. Thin roof edges alias into gaps without it.
private struct HouseMetalScene: View {
    let scene: SCNScene
    let pointOfView: SCNNode
    let powerFlow: HousePowerFlowDriver

    var body: some View {
        #if os(macOS)
        HouseMetalSceneMac(scene: scene, pointOfView: pointOfView, powerFlow: powerFlow)
        #else
        HouseMetalSceneIOS(scene: scene, pointOfView: pointOfView, powerFlow: powerFlow)
        #endif
    }
}

#if os(macOS)
private struct HouseMetalSceneMac: NSViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode
    let powerFlow: HousePowerFlowDriver

    func makeCoordinator() -> HousePowerFlowDriver { powerFlow }
    func makeNSView(context: Context) -> SCNView { configured(context.coordinator) }
    func updateNSView(_ view: SCNView, context: Context) { bind(view, delegate: context.coordinator) }

    private func configured(_ delegate: HousePowerFlowDriver) -> SCNView {
        let view = SCNView()
        bind(view, delegate: delegate)
        return view
    }

    private func bind(_ view: SCNView, delegate: HousePowerFlowDriver) {
        if view.scene !== scene { view.scene = scene }
        if view.pointOfView !== pointOfView { view.pointOfView = pointOfView }
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isPlaying = true
        view.focusRingType = .none
        if view.delegate !== delegate { view.delegate = delegate }
    }
}
#else
private struct HouseMetalSceneIOS: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode
    let powerFlow: HousePowerFlowDriver

    func makeCoordinator() -> HousePowerFlowDriver { powerFlow }
    func makeUIView(context: Context) -> SCNView { configured(context.coordinator) }
    func updateUIView(_ view: SCNView, context: Context) { bind(view, delegate: context.coordinator) }

    private func configured(_ delegate: HousePowerFlowDriver) -> SCNView {
        let view = SCNView()
        bind(view, delegate: delegate)
        return view
    }

    private func bind(_ view: SCNView, delegate: HousePowerFlowDriver) {
        if view.scene !== scene { view.scene = scene }
        if view.pointOfView !== pointOfView { view.pointOfView = pointOfView }
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isPlaying = true
        if view.delegate !== delegate { view.delegate = delegate }
    }
}
#endif
