//
//  ContentView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

enum PowerwallRuntimeEstimator {
    private static let capacityWhPerBattery = 13_500.0
    /// Tesla pauses for optimised charging from 79% until the battery is full, when charge power is low.
    private static let optimisedChargingMinPercent = 79.0
    private static let optimisedChargingMaxPowerIntoWatts = 250.0

    /// True from 79% up to, but not including, 100% when less than 250W is flowing into the Powerwall.
    /// Negative `batteryWatts` means charging (power into the battery).
    static func isOptimisedCharging(batteryWatts: Double, batteryPercentage: Double?) -> Bool {
        guard let batteryPercentage else { return false }
        // Power into Powerwall is -batteryWatts when charging; idle (0) also counts as < 250W into.
        let powerIntoWatts = batteryWatts <= 0 ? -batteryWatts : Double.infinity
        return batteryPercentage >= optimisedChargingMinPercent
            && batteryPercentage < 100
            && powerIntoWatts < optimisedChargingMaxPowerIntoWatts
    }

    static func estimateString(
        batteryWatts: Double,
        batteryCount: Double,
        batteryPercentage: Double?,
        backupReservePercent: Double? = nil,
        idleThresholdWatts: Double
    ) -> String? {
        if isOptimisedCharging(batteryWatts: batteryWatts, batteryPercentage: batteryPercentage) {
            return "Optimised charging"
        }

        guard batteryCount > 0,
              let batteryPercentage = batteryPercentage,
              batteryPercentage > 0,
              batteryPercentage < 100,
              abs(batteryWatts) > idleThresholdWatts else {
            return nil
        }

        let totalCapacityWh = capacityWhPerBattery * batteryCount
        let backupReservePercent = max(0, min(100, backupReservePercent ?? 0))
        let targetPercentage = batteryWatts < 0 ? 100 : Int(backupReservePercent.rounded())
        let remainingPercentage = batteryWatts < 0
            ? 100 - batteryPercentage
            : batteryPercentage - backupReservePercent
        let remainingWh = totalCapacityWh * (remainingPercentage / 100)
        guard remainingWh > 0 else { return nil }

        let totalMinutes = Int((remainingWh / abs(batteryWatts) * 60).rounded())
        guard totalMinutes > 0 else { return nil }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            if remainingHours == 0 {
                return estimateWithTarget(formattedUnit(days, singular: "day"), targetPercentage: targetPercentage)
            }
            return estimateWithTarget(
                "\(formattedUnit(days, singular: "day")) \(formattedUnit(remainingHours, singular: "hour"))",
                targetPercentage: targetPercentage
            )
        }
        if hours == 0 {
            return estimateWithTarget(formattedUnit(minutes, singular: "minute"), targetPercentage: targetPercentage)
        }
        if minutes == 0 {
            return estimateWithTarget(formattedUnit(hours, singular: "hour"), targetPercentage: targetPercentage)
        }
        return estimateWithTarget(
            "\(formattedUnit(hours, singular: "hour")) \(formattedUnit(minutes, singular: "minute"))",
            targetPercentage: targetPercentage
        )
    }

    private static func estimateWithTarget(_ estimate: String, targetPercentage: Int) -> String {
        "\(estimate) to \(targetPercentage)%"
    }

    private static func formattedUnit(_ value: Int, singular: String) -> String {
        value == 1 ? "1 \(singular)" : "\(value) \(singular)s"
    }
}

private extension View {
    @ViewBuilder
    func numericUpdateAnimation<Value: Equatable>(for value: Value) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
            self
                .contentTransition(.numericText())
                .animation(.default, value: value)
        } else {
            self
        }
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var scheduleManager = PowerwallScheduleManager.shared
    @State private var demo = false
    @State private var animations = true
    private var weatherPrefetchIdentity: [String] {
        [viewModel.loginMode.rawValue, viewModel.energySiteId ?? "", viewModel.fleetBaseURL,
         viewModel.accessToken, String(showingSettings), String(viewModel.isDemoMode),
         UserDefaults.standard.string(forKey: "exportAdvisor_weatherLocation_" + (viewModel.energySiteId ?? "")) ?? ""]
    }

    @State private var showingSettings = false
    @State private var showingExportAdvisor = false
    @StateObject private var exportAdvisor = ExportAdvisor()
    @AppStorage("homeEnergyAdvisor_showButton") private var showHomeEnergyAdvisorButton = false
    @State private var showingGraph = false
    @State private var selectedGraph: GraphView.GraphType = .battery
    @State private var showingScheduler = false
    @State private var wiggleWatts = 40.0
    @State private var startAnimations = false
    @State private var showBackground = false
    @State private var showMetrics = false
    @State private var introAnimationTask: DispatchWorkItem?
    @State private var precision = "%.3f"
    @State private var detachedSiteSummaryFrame: CGRect = .zero
    @State private var metricFrames: [OverlayFrameKind: CGRect] = [:]
    @State private var controlsOverlayFrame: CGRect = .zero
    @State private var detachedSiteSummaryOverlapsScene = false
    @State private var controlsOverlayOverlapsScene = false
    @State private var hideDetachedSiteSummary = false
    @State private var hideControlsOverlay = false
    @State private var detachedSiteSummaryHideTask: DispatchWorkItem?
    @State private var controlsOverlayHideTask: DispatchWorkItem?
    @State private var showPowerwallRuntimeEstimate = false
    @State private var powerwallRuntimeEstimateTask: DispatchWorkItem?
    @State private var powerwallRuntimeEstimateTimerCycle = 0
    @State private var demoTourTick = 0
    @State private var lastPowerwallRuntimeEstimateTimerCycle: Int?
    @State private var houseCallouts: HouseCalloutPoints?
    @State private var carShowroom: CarShowroomRequest?
    @State private var showroomTransition = CarShowroomTransition()
    @State private var showroomTransitionID = 0
    @State private var showroomTransitionSettled = true
    @FocusState private var hasKeyboardFocus: Bool
    /// Takes focus on tvOS while the control buttons are hidden, so a remote press can bring them back.
    @FocusState private var overlayRevealFocused: Bool
    private let naturalSceneWidth: CGFloat = 1280
    private let naturalSceneHeight: CGFloat = 720
#if os(macOS)
    private let powerwallPercentageWidth: Double = 4
#else
    private let powerwallPercentageWidth: Double = 5
#endif
    private static let timerUpdateInterval: TimeInterval = 10
    private let timer = Timer.publish(every: Self.timerUpdateInterval, on: .main, in: .common).autoconnect()
    private let demoColourTimer = Timer.publish(every: DemoHouseTour.colourInterval, on: .main, in: .common).autoconnect()
    private let timerTodaysTotal = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let timerElectricityMaps = Timer.publish(every: 900, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let sceneSize = fittedSceneSize(in: geometry.size)
            let detachSiteSummary = shouldDetachSiteSummary(geometrySize: geometry.size, sceneSize: sceneSize)
            let sceneFrame = sceneFrame(
                in: geometry.size,
                sceneSize: sceneSize,
                showSiteSummaryInScene: !detachSiteSummary
            )
            let siteSummarySceneOverlap = OverlayAutoHide.summaryOverlaps(
                showsHouseScene: showsHouseScene,
                summaryIsInline: !detachSiteSummary,
                summaryFrame: detachedSiteSummaryFrame,
                sceneFrame: sceneFrame
            )
            // The 3D house ignores the safe area and covers the window. The flat home is a fitted
            // 16:9 image, so the same buttons sit in the letterbox and miss that rect.
            let controlsSceneOverlap = OverlayAutoHide.controlsOverlap(
                showsHouseScene: showsHouseScene,
                controlsFrame: controlsOverlayFrame,
                sceneFrame: sceneFrame
            )
            let metricShift = metricSceneShift(
                sceneSize: sceneSize,
                sceneFrame: sceneFrame,
                screenHeight: geometry.size.height,
                callouts: houseCallouts
            )
            ZStack {
                Color(red: 22/255, green: 23/255, blue: 24/255)
                    .ignoresSafeArea()

                ZStack {
                if showsHouseScene {
                    // The metric overlay stays in the 16:9 frame. The house itself fills the window.
                    HouseSceneView(viewModel: viewModel, onShowroom: { openCarShowroom() })
                        .ignoresSafeArea()
                        .opacity(showBackground ? 1 : 0)
                        .scaleEffect(showBackground ? 1 : 1.04)
                }

                if showsHouseScene, viewModel.isOffGrid(), let houseCallouts {
                    offGridImage(sceneSize: sceneSize)
                        .position(houseCallouts.gridRibbon)
                        .allowsHitTesting(false)
                        .opacity(showMetrics ? 1 : 0)
                }

                if showsHouseScene, let data = viewModel.data, let houseCallouts {
                    metricLeaderLines(
                        data: data,
                        sceneSize: sceneSize,
                        callouts: houseCallouts,
                        frames: metricFrames
                    )
                    .opacity(showMetrics ? 1 : 0)
                }

                ZStack {
                    if !showsHouseScene {
                        homeBackgroundImage
                            .frame(width: sceneSize.width, height: sceneSize.height)
                            .opacity(showBackground ? 1 : 0)
                            .scaleEffect(showBackground ? 1 : 1.04)
                    }

                    sceneOverlay(
                        in: sceneSize,
                        showSiteSummaryInScene: !detachSiteSummary,
                        metricShift: metricShift,
                        hideInlineSiteSummary: hideDetachedSiteSummary
                    )
                        .frame(width: sceneSize.width, height: sceneSize.height)
                        .opacity(showMetrics ? 1 : 0)
                }
                .frame(width: sceneSize.width, height: sceneSize.height)
                .position(x: sceneFrame.midX, y: sceneFrame.midY)

                detachedSiteSummaryOverlay(
                    geometrySize: geometry.size,
                    sceneSize: sceneSize,
                    sceneMinX: sceneFrame.minX,
                    enabled: detachSiteSummary,
                    useBlurredBackground: siteSummarySceneOverlap && viewModel.autoHideSummaryOnOverlap,
                    hidden: hideDetachedSiteSummary
                )
                .opacity(showMetrics ? 1 : 0)

                controlsOverlay(sceneSize: sceneSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding()
                    .opacity(showMetrics ? 1 : 0)

                #if os(tvOS)
                if hideControlsOverlay {
                    overlayRevealCatcher
                }
                #endif
                }
                .scaleEffect(showroomTransition.homeScale)
                .opacity(showroomTransition.homeOpacity)
                #if os(tvOS)
                // The showroom is an overlay on top of this stack. Disable the house so its
                // buttons and the scene do not keep the remote while the car is open.
                .disabled(carShowroom != nil)
                #endif
            }
            .coordinateSpace(name: "contentView")
            .onPreferenceChange(OverlayFramePreferenceKey.self) { frames in
                detachedSiteSummaryFrame = frames[.detachedSiteSummary] ?? .zero
                controlsOverlayFrame = frames[.controlsOverlay] ?? .zero
                metricFrames = frames
            }
            .onPreferenceChange(HouseCalloutKey.self) { houseCallouts = $0 }
            .onAppear {
                updateDetachedSiteSummaryOverlap(siteSummarySceneOverlap)
                updateControlsOverlayOverlap(controlsSceneOverlap)
            }
            .onChange(of: siteSummarySceneOverlap) { overlap in
                updateDetachedSiteSummaryOverlap(overlap)
            }
            .onChange(of: controlsSceneOverlap) { overlap in
                updateControlsOverlayOverlap(overlap)
            }
            .onChange(of: viewModel.autoHideSummaryOnOverlap) { _ in
                updateDetachedSiteSummaryOverlap(detachedSiteSummaryOverlapsScene)
            }
            .onChange(of: viewModel.autoHideButtonsOnOverlap) { _ in
                updateControlsOverlayOverlap(controlsOverlayOverlapsScene)
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        revealAutoHiddenOverlays()
                    }
            )
        }
#if os(macOS)
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                loginMode: $viewModel.loginMode,
                ipAddress: $viewModel.ipAddress,
                wallConnectorIPAddress: $viewModel.wallConnectorIPAddress,
                username: $viewModel.username,
                password: $viewModel.password,
                accessToken: $viewModel.accessToken,
                fleetBaseURL: $viewModel.fleetBaseURL,
                electricityMapsAPIKey: $viewModel.electricityMapsAPIKey,
                electricityMapsZone: $viewModel.electricityMapsZone,
                preventScreenSaver: $viewModel.preventScreenSaver,
                showLessPrecision: $viewModel.showLessPrecision,
                alwaysShowPowerwallRuntimeEstimate: $viewModel.alwaysShowPowerwallRuntimeEstimate,
                showVehicles: $viewModel.showVehicles,
                showSchedulerButton: $viewModel.showSchedulerButton,
                showInMenuBar: $viewModel.showInMenuBar,
                keepWindowInFront: $viewModel.keepWindowInFront,
                autoHideSummaryOnOverlap: $viewModel.autoHideSummaryOnOverlap,
                autoHideButtonsOnOverlap: $viewModel.autoHideButtonsOnOverlap,
                sceneScale: $viewModel.sceneScale,
                sceneHorizontalOffset: $viewModel.sceneHorizontalOffset,
                sceneVerticalOffset: $viewModel.sceneVerticalOffset,
                lastChargingWallConnectorVIN: $viewModel.lastChargingWallConnectorVIN,
                showingConfirmation: false,
                viewModel: viewModel
            )
            .background(
                Color.clear
                    .background(.regularMaterial)
                    .ignoresSafeArea()
            )
        }
        .sheet(isPresented: $showingExportAdvisor) {
            ExportAdvisorView(advisor: exportAdvisor, viewModel: viewModel)
        }
        .sheet(isPresented: $showingGraph) {
            GraphView(viewModel: viewModel, initialGraph: selectedGraph)
                .id(selectedGraph)
                .background(
                    Color.clear
                        .background(.regularMaterial)
                        .ignoresSafeArea()
                )
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingScheduler) {
            SchedulerView(viewModel: viewModel)
                .background(
                    Color.clear
                        .background(.regularMaterial)
                        .ignoresSafeArea()
                )
        }
#else
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView(
                loginMode: $viewModel.loginMode,
                ipAddress: $viewModel.ipAddress,
                wallConnectorIPAddress: $viewModel.wallConnectorIPAddress,
                username: $viewModel.username,
                password: $viewModel.password,
                accessToken: $viewModel.accessToken,
                fleetBaseURL: $viewModel.fleetBaseURL,
                electricityMapsAPIKey: $viewModel.electricityMapsAPIKey,
                electricityMapsZone: $viewModel.electricityMapsZone,
                preventScreenSaver: $viewModel.preventScreenSaver,
                showLessPrecision: $viewModel.showLessPrecision,
                alwaysShowPowerwallRuntimeEstimate: $viewModel.alwaysShowPowerwallRuntimeEstimate,
                showVehicles: $viewModel.showVehicles,
                showSchedulerButton: $viewModel.showSchedulerButton,
                showInMenuBar: $viewModel.showInMenuBar,
                keepWindowInFront: $viewModel.keepWindowInFront,
                autoHideSummaryOnOverlap: $viewModel.autoHideSummaryOnOverlap,
                autoHideButtonsOnOverlap: $viewModel.autoHideButtonsOnOverlap,
                sceneScale: $viewModel.sceneScale,
                sceneHorizontalOffset: $viewModel.sceneHorizontalOffset,
                sceneVerticalOffset: $viewModel.sceneVerticalOffset,
                lastChargingWallConnectorVIN: $viewModel.lastChargingWallConnectorVIN,
                showingConfirmation: false,
                viewModel: viewModel
            )
#if os(tvOS)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
            .background(
                Color.clear
                    .background(.regularMaterial)
                    .ignoresSafeArea()
            )
        }
        .fullScreenCover(isPresented: $showingExportAdvisor) {
            ExportAdvisorView(advisor: exportAdvisor, viewModel: viewModel)
        }
        .fullScreenCover(isPresented: $showingGraph) {
            GraphView(viewModel: viewModel, initialGraph: selectedGraph)
                .id(selectedGraph)
                .background(
                    Color.clear
                        .background(.regularMaterial)
                        .ignoresSafeArea()
                )
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showingScheduler) {
            SchedulerView(viewModel: viewModel)
                .background(
                    Color.clear
                        .background(.regularMaterial)
                        .ignoresSafeArea()
                )
        }
#endif
        .overlay {
            if let request = carShowroom {
                CarShowroomView(request: request, onDismiss: closeCarShowroom)
                    .ignoresSafeArea()
                    .transition(.identity)
                    .opacity(showroomTransition.showroomOpacity)
            }
        }
        .task(id: weatherPrefetchIdentity) {
            guard !showingSettings, !viewModel.isDemoMode, viewModel.loginMode == .fleetAPI,
                  let siteID = viewModel.energySiteId, !viewModel.accessToken.isEmpty else { return }
            let service = ExportAdvisorService(baseURL: viewModel.fleetBaseURL, token: viewModel.accessToken, siteID: siteID)
            // Opportunistic: opening the advisor retries and presents any service error.
            try? await service.prefetchWeather()
        }
#if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("--advisor-focus-ui-test") || ProcessInfo.processInfo.arguments.contains("--advisor-close-ui-test") {
                showingExportAdvisor = true
            } else if ProcessInfo.processInfo.arguments.contains("--graph-close-ui-test") {
                showingGraph = true
            }
        }
#endif
        .onChange(of: viewModel.isDemoMode) { isDemo in
            exportAdvisor.invalidate()
            if isDemo {
                viewModel.demoSceneIndex = 0
                viewModel.demoColourIndex = 0
                demoTourTick = 0
                queueInitialDemoData()
            }
        }
        .onChange(of: showingSettings) { isShowing in
            if !isShowing && viewModel.isDemoMode { queueInitialDemoData() }
        }
        .onChange(of: viewModel.loginMode) { _ in
            exportAdvisor.invalidate()
        }
        .onChange(of: viewModel.energySiteId) { _ in
            exportAdvisor.invalidate()
        }
        .onReceive(timer) { _ in
            powerwallRuntimeEstimateTimerCycle += 1
            precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"
            if showingSettings {
                return
            }
            if !viewModel.isDemoMode && viewModel.loginMode == .fleetAPI {
                PowerwallScheduleManager.shared.applyDueSchedules(using: viewModel)
            }
            if viewModel.isDemoMode {
                demoTourTick += 1
                if demoTourTick.isMultiple(of: DemoHouseTour.powerTicksPerScene) {
                    viewModel.demoSceneIndex += 1
                }
                let homeLoad = Double(arc4random_uniform(4096)) + 256
                queueDemoPowerwallData(
                    batteryPower: homeLoad * 0.2,
                    batteryPercentage: 80,
                    loadPower: homeLoad,
                    solarPower: homeLoad * 0.7,
                    solarEnergyExported: 409600,
                    sitePower: homeLoad * 0.1,
                    gridStatus: "SystemGridConnected",
                    wallConnectorPower: homeLoad * 0.05
                )
            } else {
                switch viewModel.loginMode {
                case .local:
                    if hasGatewayAddressConfigured {
                        viewModel.fetchData()
                    }
                case .fleetAPI:
                    viewModel.fetchData()
                }
            }
        }
        .onReceive(demoColourTimer) { _ in
            guard viewModel.isDemoMode, !showingSettings else { return }
            viewModel.demoColourIndex += 1
            showDemoParkedCar()
        }
        .onReceive(timerTodaysTotal) { _ in
            if !viewModel.accessToken.isEmpty {
                viewModel.fetchSolarEnergyToday()
            }
        }
        .onReceive(timerElectricityMaps) { _ in
            if viewModel.isDemoMode {
                queueDemoElectricityGridData()
            } else {
                viewModel.fetchElectricityMapsData()
            }
        }
        .onReceive(viewModel.$data) { _ in
            DispatchQueue.main.async {
                cyclePowerwallRuntimeEstimateIfAvailable(for: powerwallRuntimeEstimateTimerCycle)
            }
        }
        .onAppear {
            precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"
            let isDemoMode = demo || viewModel.isDemoMode
            if demo {
                DispatchQueue.main.async {
                    viewModel.ipAddress = "demo"
                }
            }
            PowerwallScheduleManager.shared.scheduleBackgroundRefresh()
            if shouldAutoOpenSettingsOnLaunch {
                showingSettings = true
            } else if isDemoMode {
                queueInitialDemoData()
            } else {
                viewModel.fetchElectricityMapsData()
                viewModel.fetchData()
            }
            beginFirstLoadIntro()
            viewModel.noteSceneAttention(Self.attention(for: scenePhase))
#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = viewModel.preventScreenSaver
#endif
        }
        .onChange(of: scenePhase) { phase in
            viewModel.noteSceneAttention(Self.attention(for: phase))
        }
        .onDisappear {
            resetFirstLoadIntro()
            cancelOverlayHideTask(.detachedSiteSummary)
            cancelOverlayHideTask(.controlsOverlay)
        }
#if os(macOS)
        .background(
            WindowChromeVisibilityConfigurator(
                isHidden: shouldHideWindowChrome,
                keepWindowInFront: viewModel.keepWindowInFront,
                onMouseMove: revealHiddenOverlaysOnActivity,
                onBecomeKey: revealAutoHiddenOverlays,
                onAttention: { viewModel.noteWindowAttention($0) }
            )
        )
#endif
#if os(iOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    revealAutoHiddenOverlays()
                    // A vertical drag on the 3D house orbits the camera.
                    guard !showsHouseScene else { return }
                    handleSiteSwipe(value.translation)
                }
        )
#endif
#if !os(iOS)
        .onMoveCommand { direction in
            if hasHiddenAutoOverlay {
                revealAutoHiddenOverlays()
                return
            }
            if direction == .up {
                updateEnergySite(-1)
            }
            if direction == .down {
                updateEnergySite(+1)
            }
        }
#endif
#if os(macOS)
        .focusable(true)
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onAppear {
            hasKeyboardFocus = true
        }
        .onKeyPress(.upArrow, phases: .down) { _ in
            guard !showingGraph, !showingScheduler else { return .ignored }
            if hasHiddenAutoOverlay {
                revealAutoHiddenOverlays()
                return .handled
            }
            updateEnergySite(-1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            guard !showingGraph, !showingScheduler else { return .ignored }
            if hasHiddenAutoOverlay {
                revealAutoHiddenOverlays()
                return .handled
            }
            updateEnergySite(+1)
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { _ in
            exitFullScreenIfNeeded() ? .handled : .ignored
        }
#endif
    }

    private static let houseSceneAvailable = HouseLighting.resourceURL(name: "ResidentialClassic", ext: "usdz") != nil

    private var showsHouseScene: Bool {
        Self.houseSceneAvailable && viewModel.showHouseScene
    }

    @ViewBuilder
    private var homeBackgroundImage: some View {
        let imageName = currentHomeImageName
#if os(macOS)
        Image(nsImage: NSImage(named: imageName)!)
            .resizable()
            .scaledToFit()
#else
        Image(uiImage: UIImage(named: imageName)!)
            .resizable()
            .scaledToFit()
#endif
    }

    private var currentHomeImageName: String {
        let presentation = viewModel.garagePresentation
        if !presentation.showWallConnector {
            return "home.png"
        }
        if !presentation.showVehicle {
            return "home-charger-empty.png"
        }
        return presentation.model == .cybertruck ? "home-charger-cybertruck.png" : "home-charger.png"
    }

    private struct MetricSceneShift {
        var solar: CGFloat = 0
        var home: CGFloat = 0
        var vehicle: CGFloat = 0
        var summary: CGFloat = 0
        var lower: CGFloat = 0
    }

    /// While the camera is closer than the resting view, each upper metric moves on its own
    /// so a tall roof cannot pull the home readout back down onto the house.
    /// Lower labels keep the house bottom at least `lowerStandOff` away at any distance.
    private func metricSceneShift(sceneSize: CGSize, sceneFrame: CGRect, screenHeight: CGFloat, callouts: HouseCalloutPoints?) -> MetricSceneShift {
        guard showsHouseScene,
              let callouts,
              sceneSize.height > 1 else {
            return MetricSceneShift()
        }
        let zoomedCloser = viewModel.houseScenePose.distanceScale < 0.98
        let half = max(22, sceneHeight(0.05, in: sceneSize) * 0.5)
        let screenMin: CGFloat = 8
        let screenMax = screenHeight - 8
        // Previous lower clearance was 28pt plus the 8pt gap inside clearedLabelCenter.
        let lowerStandOff: CGFloat = 64
        func lift(_ sceneY: CGFloat, above: Bool, standOff: CGFloat) -> CGFloat {
            let anchor = sceneFrame.minY + sceneSize.height * (0.5 + sceneY)
            let cleared = HouseCameraFraming.clearedLabelCenter(
                windowY: anchor,
                halfHeight: half + standOff,
                spanTop: callouts.modelTop,
                spanBottom: callouts.modelBottom,
                above: above,
                screenMin: screenMin,
                screenMax: screenMax
            )
            return (cleared - anchor) / sceneSize.height
        }
        return MetricSceneShift(
            solar: zoomedCloser ? lift(-0.40, above: true, standOff: 28) : 0,
            home: zoomedCloser ? lift(-0.30, above: true, standOff: 28) : 0,
            vehicle: zoomedCloser ? lift(-0.40, above: true, standOff: 28) : 0,
            summary: zoomedCloser ? lift(-0.38, above: true, standOff: 28) : 0,
            lower: lift(0.40, above: false, standOff: lowerStandOff)
        )
    }

    @ViewBuilder
    private func sceneOverlay(in sceneSize: CGSize, showSiteSummaryInScene: Bool, metricShift: MetricSceneShift, hideInlineSiteSummary: Bool) -> some View {
        if viewModel.ipAddress.isEmpty && viewModel.loginMode == .local {
            Text("Please configure the gateway settings.")
                .foregroundColor(.gray)
        } else if let data = viewModel.data {
            sceneDataOverlay(
                data: data,
                sceneSize: sceneSize,
                showSiteSummaryInScene: showSiteSummaryInScene,
                metricShift: metricShift,
                hideInlineSiteSummary: hideInlineSiteSummary
            )
                .foregroundColor(.white)
        } else if viewModel.loginMode == .fleetAPI && !hasFleetAccessTokenConfigured {
            Button("Login with your Tesla account") {
                _ = viewModel.startFleetLoginManually()
            }
            .buttonStyle(.plain)
            .opacity(0.6)
            .fontWeight(.bold)
            .font(labelFont(for: sceneSize))
            .foregroundColor(.white)
            .position(scenePoint(x: 0.03, y: 0.4, in: sceneSize))
        }
    }

    private func sceneDataOverlay(data: PowerwallData, sceneSize: CGSize, showSiteSummaryInScene: Bool, metricShift: MetricSceneShift, hideInlineSiteSummary: Bool) -> some View {
        let batteryPercentage = max(0.0, min(1.0, (viewModel.batteryPercentage?.percentage ?? 0) / 100))
        let batteryIndicatorHeight = sceneHeight(0.076, in: sceneSize) * batteryPercentage
        let batteryIndicatorWidth = max(CGFloat(powerwallPercentageWidth), sceneWidth(0.0024, in: sceneSize))
        let valueFont = valueFont(for: sceneSize)
        let labelFont = labelFont(for: sceneSize)
        let summaryMessageWidth = siteSummaryMessageWidth(for: sceneSize)
        let surgeLineWidth = powerSurgeLineWidth(for: sceneSize)
        var homeAndGridXPosition = 0.26
        var gridCarbonXPosition = 0.04
#if os(tvOS)
        homeAndGridXPosition = 0.28
#elseif os(macOS)
        homeAndGridXPosition = 0.25
        gridCarbonXPosition = 0.03
#elseif os(iOS)
        gridCarbonXPosition = 0.035
#endif

        let showFlatPower = animations && !showsHouseScene
        let flatPaused = PresentationRefresh.decision(
            interacting: false,
            rainIntensity: 0,
            snowIntensity: 0,
            snapshot: PowerFlowSnapshot(
                solarW: data.solar.instantPower,
                batteryW: data.battery.instantPower,
                gridW: data.site.instantPower,
                homeW: data.load.instantPower
            ),
            revealingWeather: false,
            attention: viewModel.appAttention,
            pauseWhenUnfocused: viewModel.pauseAnimationWhenUnfocused
        ).animationsPaused
        return ZStack {
            if viewModel.isOffGrid(), !showsHouseScene {
                offGridImage(sceneSize: sceneSize)
                    .position(scenePoint(x: 0.151, y: 0.234, in: sceneSize))
                    .allowsHitTesting(false)
            }

            if showSiteSummaryInScene {
                siteSummaryView(data: data, valueFont: valueFont, labelFont: labelFont, messageWidth: summaryMessageWidth)
                    .opacity(hideInlineSiteSummary ? 0 : 1)
                    .allowsHitTesting(!hideInlineSiteSummary)
                    .position(scenePoint(x: inlineSiteSummaryX, y: -0.38 + metricShift.summary, in: sceneSize))
            }

            solarMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                .reportFrame(.metricSolar)
                .position(scenePoint(x: 0.087, y: -0.40 + metricShift.solar, in: sceneSize))

            homeMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                .reportFrame(.metricHome)
                .position(scenePoint(x: homeAndGridXPosition, y: -0.30 + metricShift.home, in: sceneSize))

            batteryMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                .reportFrame(.metricBattery)
                .position(scenePoint(x: 0.03, y: 0.40 + metricShift.lower, in: sceneSize))

            if !data.wallConnectors.isEmpty {
                wallConnectorMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                    .reportFrame(.metricVehicle)
                    .position(scenePoint(x: -0.104, y: -0.40 + metricShift.vehicle, in: sceneSize))
            }

            if !showsHouseScene {
                batteryPercentageIndicator(
                    indicatorWidth: batteryIndicatorWidth,
                    indicatorHeight: batteryIndicatorHeight
                )
                .position(sceneBottomPoint(
                    x: 0.014,
                    y: 0.244,
                    objectHeight: batteryIndicatorHeight,
                    in: sceneSize
                ))
            }

            gridMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                .reportFrame(.metricGrid)
                .position(scenePoint(x: viewModel.gridFossilFuelPercentage != nil ? homeAndGridXPosition + gridCarbonXPosition : homeAndGridXPosition, y: 0.40 + metricShift.lower, in: sceneSize))

            if showFlatPower && wallConnectorEnergyTotal(data: data) > 10 {
                PowerSurgeView(
                    color: leadingSupplyColor(data: data),
                    isForward: wallConnectorEnergyTotal(data: data) < 0,
                    duration: 2,
                    lineWidth: surgeLineWidth,
                    curve: ChargerToCar(),
                    shouldStart: startAnimations,
                    paused: flatPaused
                )
                .frame(width: sceneWidth(0.024, in: sceneSize), height: sceneHeight(0.145, in: sceneSize))
                .position(scenePoint(x: -0.12, y: 0.13, in: sceneSize))
                .id("charger_\(wallConnectorEnergyTotal(data: data) < 0)_\(startAnimations)")
            }

            if showFlatPower && data.solar.instantPower > 10 {
                PowerSurgeView(
                    color: .yellow,
                    isForward: true,
                    duration: 2,
                    lineWidth: surgeLineWidth,
                    curve: SolarToGateway(),
                    shouldStart: startAnimations,
                    paused: flatPaused
                )
                .frame(width: sceneWidth(0.021, in: sceneSize), height: sceneHeight(0.242, in: sceneSize))
                .position(scenePoint(x: 0.097, y: 0.13, in: sceneSize))
                .id("solar_\(data.solar.instantPower < 0)_\(startAnimations)")
            }

            if showFlatPower && data.load.instantPower > 10 {
                PowerSurgeView(
                    color: leadingSupplyColor(data: data),
                    isForward: true,
                    duration: 2,
                    startOffset: 1,
                    lineWidth: surgeLineWidth,
                    curve: GatewayToHome(),
                    shouldStart: startAnimations,
                    paused: flatPaused
                )
                .frame(width: sceneWidth(0.054, in: sceneSize), height: sceneHeight(0.056, in: sceneSize))
                .rotationEffect(Angle(degrees: 6))
                .position(scenePoint(x: 0.136, y: 0.142, in: sceneSize))
                .id("home_\(data.load.instantPower < 0)_\(startAnimations)")
            }

            if showFlatPower && (data.battery.instantPower > 10 || data.battery.instantPower < -10) {
                PowerSurgeView(
                    color: data.battery.instantPower > 0
                        ? .green
                        : data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : .gray,
                    isForward: data.battery.instantPower > 0,
                    duration: 2,
                    startOffset: data.battery.instantPower > 0 ? 0 : 1,
                    lineWidth: surgeLineWidth,
                    curve: PowerwallToGateway(),
                    shouldStart: startAnimations,
                    paused: flatPaused
                )
                .frame(width: sceneWidth(0.058, in: sceneSize), height: sceneHeight(0.065, in: sceneSize))
                .rotationEffect(Angle(degrees: 8))
                .position(scenePoint(x: 0.060, y: 0.176, in: sceneSize))
                .id("battery_\(data.battery.instantPower < 0)_\(startAnimations)")
            }

            if showFlatPower && !viewModel.isOffGrid() && (data.site.instantPower > 10 || data.site.instantPower < -10) {
                PowerSurgeView(
                    color: data.site.instantPower > 0
                        ? .gray
                        : data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : .green,
                    isForward: data.site.instantPower < 0,
                    duration: 2,
                    startOffset: data.site.instantPower > 0 ? 0 : 1,
                    lineWidth: surgeLineWidth,
                    curve: GatewayToGrid(),
                    shouldStart: startAnimations,
                    paused: flatPaused
                )
                .frame(width: sceneWidth(0.102, in: sceneSize), height: sceneHeight(0.134, in: sceneSize))
                .position(scenePoint(x: 0.152, y: 0.208, in: sceneSize))
                .id("grid_\(data.site.instantPower < 0)_\(startAnimations)")
            }
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
    }

    /// Vertical grey leaders beside the metric labels. Only the 3D scene publishes callouts.
    private func metricLeaderLines(data: PowerwallData, sceneSize: CGSize, callouts: HouseCalloutPoints, frames: [OverlayFrameKind: CGRect]) -> some View {
        var spots: [(OverlayFrameKind, CGRect, CGPoint)] = []
        if let frame = frames[.metricSolar] { spots.append((.metricSolar, frame, callouts.solar)) }
        if let frame = frames[.metricHome] { spots.append((.metricHome, frame, callouts.home)) }
        if let frame = frames[.metricBattery] { spots.append((.metricBattery, frame, callouts.battery)) }
        if let frame = frames[.metricGrid] { spots.append((.metricGrid, frame, callouts.grid)) }
        if !data.wallConnectors.isEmpty, let frame = frames[.metricVehicle] {
            spots.append((.metricVehicle, frame, callouts.vehicle))
        }
        let reach: CGFloat = 2.0 / 3.0
        let powerwallReach = spots.first { $0.0 == .metricBattery }.map { lineReach($0.1, to: $0.2) * reach }
        return Path { path in
            for (kind, label, callout) in spots where label.width > 1 && label.height > 1 {
                let x = label.midX
                let goingDown = callout.y >= label.midY
                let innerY = goingDown ? label.maxY + labelToLeaderPadding : label.minY - labelToLeaderPadding
                let outerY = goingDown ? label.minY : label.maxY
                let full = callout.y - innerY
                guard abs(full) > 8 else { continue }
                var length = abs(full) * reach
                if kind == .metricGrid, let powerwallReach, powerwallReach > 8 {
                    length = min(length, powerwallReach * 0.72)
                }
                // Solar, home, and vehicle leaders cross the house so they still aim at the callout.
                let aimsThroughTheHouse = kind == .metricSolar || kind == .metricHome || kind == .metricVehicle
                guard let segment = HouseCameraFraming.leaderSegment(
                    innerY: innerY,
                    outerY: outerY,
                    calloutY: callout.y,
                    length: length,
                    modelTop: aimsThroughTheHouse ? nil : callouts.modelTop,
                    modelBottom: aimsThroughTheHouse ? nil : callouts.modelBottom
                ) else { continue }
                path.move(to: CGPoint(x: x, y: segment.start))
                path.addLine(to: CGPoint(x: x, y: segment.end))
            }
        }
        .stroke(Color(white: 0.62), style: StrokeStyle(lineWidth: max(1.25, sceneSize.height / 520), lineCap: .round))
        .allowsHitTesting(false)
    }

    /// Space between a metric label's facing edge and the start of its grey leader.
    private var labelToLeaderPadding: CGFloat { 4 }

    private func lineReach(_ label: CGRect, to callout: CGPoint) -> CGFloat {
        let startY = callout.y >= label.midY ? label.maxY + labelToLeaderPadding : label.minY - labelToLeaderPadding
        return abs(callout.y - startY)
    }

    @ViewBuilder
    private func detachedSiteSummaryOverlay(
        geometrySize: CGSize,
        sceneSize: CGSize,
        sceneMinX: CGFloat,
        enabled: Bool,
        useBlurredBackground: Bool,
        hidden: Bool
    ) -> some View {
        if enabled,
           !(viewModel.ipAddress.isEmpty && viewModel.loginMode == .local),
           let data = viewModel.data {
            let leadingPadding = max(24, sceneMinX + sceneWidth(0.04, in: sceneSize))
            siteSummaryView(
                data: data,
                valueFont: valueFont(for: sceneSize),
                labelFont: labelFont(for: sceneSize),
                messageWidth: siteSummaryMessageWidth(for: sceneSize)
            )
                .foregroundColor(.white)
                .overlayChromeBackground(isVisible: !hidden, isOverlapping: useBlurredBackground)
                .compositingGroup()
                .opacity(hidden ? 0 : 1)
                .allowsHitTesting(!hidden)
                .reportFrame(.detachedSiteSummary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, leadingPadding)
                .padding(.top, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func siteSummaryView(data: PowerwallData, valueFont: Font, labelFont: Font, messageWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let siteName = viewModel.siteName {
                Text(siteName)
                    .fontWeight(.bold)
                    .font(valueFont)
                    .padding(.bottom, 4)
            }
            if data.solar.energyExported > 0 || viewModel.solarEnergyTodayWh != nil {
                let exportedEnergy = (data.solar.energyExported > 0 ? data.solar.energyExported : viewModel.solarEnergyTodayWh ?? 0) / 1000
                let specifier = exportedEnergy < 1000 ? precision : "%.0f"
                Text("\(exportedEnergy, specifier: specifier) kWh")
                    .fontWeight(.bold)
                    .font(valueFont)
                    .numericUpdateAnimation(for: exportedEnergy)
                Text("ENERGY GENERATED \(data.solar.energyExported > 0 ? "" : "TODAY")")
                    .opacity(0.6)
                    .fontWeight(.bold)
                    .font(labelFont)
                    .padding(.bottom, 4)
            }
            if let message = viewModel.errorMessage ?? viewModel.infoMessage {
                Text("\((viewModel.errorMessage != nil) ? "Error: " : "")\(message)")
                    .fontWeight(.bold)
                    .font(labelFont)
                    .foregroundColor(viewModel.errorMessage != nil ? .red : .green)
                    .opacity(viewModel.errorMessage != nil ? 1.0 : 0.6)
                    .frame(width: messageWidth, alignment: .leading)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(width: messageWidth, alignment: .leading)
#if !os(tvOS)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.cycleEnergySite()
        }
        .accessibilityAddTraits(viewModel.energySites.count > 1 ? .isButton : [])
        .accessibilityHint(viewModel.energySites.count > 1 ? "Shows the next home" : "")
#endif
    }

    private func solarMetricView(data: PowerwallData, valueFont: Font, labelFont: Font) -> some View {
        VStack(spacing: 2) {
            Text("\(fmt(data.solar.instantPower / 1000)) kW")
                .fontWeight(.bold)
                .font(valueFont)
                .numericUpdateAnimation(for: data.solar.instantPower)
            Text("SOLAR")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(labelFont)
        }
        .multilineTextAlignment(.center)
        .opensGraph(.solar, using: openGraph)
    }

    private func homeMetricView(data: PowerwallData, valueFont: Font, labelFont: Font) -> some View {
        VStack(spacing: 2) {
            Text("\(fmt(homeEnergyToDisplay(data: data) / 1000)) kW")
                .fontWeight(.bold)
                .font(valueFont)
                .numericUpdateAnimation(for: homeEnergyToDisplay(data: data))
            Text("HOME")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(labelFont)
        }
        .multilineTextAlignment(.center)
        .opensGraph(.home, using: openGraph)
    }

    private func batteryMetricView(data: PowerwallData, valueFont: Font, labelFont: Font) -> some View {
        VStack(spacing: 2) {
            (
                Text("\(fmt(data.battery.instantPower / 1000)) kW ")
                + Text(batteryArrow(wiggleWatts: wiggleWatts))
                    .foregroundColor(data.battery.instantPower > wiggleWatts || data.battery.instantPower < -wiggleWatts ? .green : .white)
                + Text(" \(viewModel.batteryPercentage?.percentage ?? 0, specifier: "%.1f")%")
            )
            .fontWeight(.bold)
            .font(valueFont)
            .numericUpdateAnimation(for: "\(data.battery.instantPower)-\(viewModel.batteryPercentage?.percentage ?? 0)")

            powerwallStatusLabel(data: data)
                .opacity(0.6)
                .fontWeight(.bold)
                .font(labelFont)
                .animation(.easeInOut(duration: 0.4), value: showPowerwallRuntimeEstimate)
        }
        .multilineTextAlignment(.center)
        .opensGraph(.battery, using: openGraph)
    }

    private func powerwallStatusLabel(data: PowerwallData) -> some View {
        let estimate = powerwallRuntimeEstimateString(data: data, batteryPercentage: viewModel.batteryPercentage?.percentage)
        let shouldShowEstimate = estimate != nil && (viewModel.alwaysShowPowerwallRuntimeEstimate || showPowerwallRuntimeEstimate)

        return ZStack {
            powerwallLabel
                .opacity(shouldShowEstimate ? 0 : 1)
            if let estimate = estimate {
                Text(estimate)
                    .opacity(shouldShowEstimate ? 1 : 0)
            }
        }
    }

    private var powerwallLabel: Text {
        let activeScheduleCount = scheduleManager.schedules.filter(\.isEnabled).count
        var label = Text("POWERWALL\(viewModel.batteryCountString())")

        if scheduleManager.isSchedulerEnabled && activeScheduleCount > 0 {
            label = label
                + Text(" · ")
                + Text(Image(systemName: "alarm.fill"))
                    .foregroundColor(isWithinEnabledScheduleWindow ? .green : .white)

            if activeScheduleCount > 1 {
                label = label + Text(" \(activeScheduleCount)")
            }
        }

        if viewModel.isStormWatchActive() {
            label = label
                + Text(" · ")
                + Text(Image(systemName: "cloud.bolt.fill"))
                    .foregroundColor(.cyan)
        }

        return label
    }

    private func cyclePowerwallRuntimeEstimateIfAvailable(for timerCycle: Int) {
        guard timerCycle > 0 else { return }
        guard timerCycle.isMultiple(of: 2) else { return }
        guard lastPowerwallRuntimeEstimateTimerCycle != timerCycle else { return }

        powerwallRuntimeEstimateTask?.cancel()
        powerwallRuntimeEstimateTask = nil

        guard let data = viewModel.data,
              powerwallRuntimeEstimateString(data: data, batteryPercentage: viewModel.batteryPercentage?.percentage) != nil else {
            withAnimation(.easeInOut(duration: 0.4)) {
                showPowerwallRuntimeEstimate = false
            }
            return
        }

        lastPowerwallRuntimeEstimateTimerCycle = timerCycle

        withAnimation(.easeInOut(duration: 0.4)) {
            showPowerwallRuntimeEstimate = true
        }

        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.4)) {
                showPowerwallRuntimeEstimate = false
            }
        }
        powerwallRuntimeEstimateTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + (Self.timerUpdateInterval / 2), execute: task)
    }

    private func powerwallRuntimeEstimateString(data: PowerwallData, batteryPercentage: Double?) -> String? {
        // Use live instant power so optimised charging still shows under the idle/average thresholds.
        if PowerwallRuntimeEstimator.isOptimisedCharging(
            batteryWatts: data.battery.instantPower,
            batteryPercentage: batteryPercentage
        ) {
            return "Optimised charging"
        }

        let wiggleWatts = wiggleWatts
        guard let batteryWatts = viewModel.averagedBatteryWattsForRuntimeEstimate(
            currentWatts: data.battery.instantPower,
            idleThresholdWatts: wiggleWatts
        ) else {
            return nil
        }
        let backupReservePercent = viewModel.loginMode == .fleetAPI ? viewModel.backupReservePercent : nil
        return PowerwallRuntimeEstimator.estimateString(
            batteryWatts: batteryWatts,
            batteryCount: data.battery.count,
            batteryPercentage: batteryPercentage,
            backupReservePercent: backupReservePercent,
            idleThresholdWatts: wiggleWatts
        )
    }

    private var isWithinEnabledScheduleWindow: Bool {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard let hour = components.hour, let minute = components.minute else { return false }

        let currentMinutes = (hour * 60) + minute
        return scheduleManager.schedules
            .filter(\.isEnabled)
            .contains { schedule in
                if schedule.startMinutes == schedule.endMinutes {
                    return true
                }

                if schedule.startMinutes < schedule.endMinutes {
                    return currentMinutes >= schedule.startMinutes && currentMinutes < schedule.endMinutes
                }

                return currentMinutes >= schedule.startMinutes || currentMinutes < schedule.endMinutes
            }
    }

    private func wallConnectorMetricView(data: PowerwallData, valueFont: Font, labelFont: Font) -> some View {
        Button(action: openCarShowroom) {
            VStack(spacing: 2) {
                Text(wallConnectorDisplay(data: data, precision: precision))
                    .fontWeight(.bold)
                    .font(valueFont)
                    .numericUpdateAnimation(for: wallConnectorDisplay(data: data, precision: precision))
                Text(vehicleMetricCaption(connectorCount: data.wallConnectors.count))
                    .opacity(0.6)
                    .fontWeight(.bold)
                    .font(labelFont)
                    .id(viewModel.isDemoMode ? viewModel.demoColourIndex : 0)
            }
            .multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
    }

    /// True when the account already has a car. Demo cars count. An empty Fleet list does not.
    private var userOwnsCars: Bool {
        viewModel.isDemoMode || !viewModel.vehicles.isEmpty
    }

    /// Garage door, parked car, and the charging readout. A parked car wins. With no cars on the
    /// account, the garage opens the model catalogue instead.
    private func openCarShowroom() {
        guard showroomTransitionSettled, carShowroom == nil else { return }
        guard let request = CarShowroom.select(
            data: viewModel.data,
            fallbackVIN: viewModel.lastChargingWallConnectorVIN,
            appearances: viewModel.vehicleAppearances,
            solar: viewModel.garageSolar,
            vehicles: viewModel.vehicles,
            charges: viewModel.vehicleChargeStates,
            displayBoost: viewModel.isDemoMode ? 1 : 4,
            isDemoMode: viewModel.isDemoMode
        ) else { return }
        showroomTransitionSettled = false
        showroomTransitionID += 1
        let transitionID = showroomTransitionID
        // Mount while invisible so the car loads during the zoom, without fading in yet.
        carShowroom = request
        withAnimation(.easeIn(duration: CarShowroomTransition.homeDuration), completionCriteria: .logicallyComplete) {
            showroomTransition = .homeDeparted
        } completion: {
            guard transitionID == showroomTransitionID else { return }
            withAnimation(.easeOut(duration: CarShowroomTransition.showroomDuration)) {
                showroomTransition = .showroom
            }
        }
    }

    /// The showroom close button, Escape, and the tvOS exit command.
    private func closeCarShowroom() {
        guard carShowroom != nil else { return }
        showroomTransitionID += 1
        let transitionID = showroomTransitionID
        // Escape during the zoom, before the showroom has appeared: ease the home back.
        if showroomTransition.showroomReveal == 0 {
            withAnimation(.easeOut(duration: CarShowroomTransition.homeDuration), completionCriteria: .logicallyComplete) {
                showroomTransition.homeReveal = 1
                carShowroom = nil
            } completion: {
                guard transitionID == showroomTransitionID else { return }
                showroomTransition.holdsZoom = false
                showroomTransitionSettled = true
            }
            return
        }
        withAnimation(.easeIn(duration: CarShowroomTransition.showroomDuration), completionCriteria: .logicallyComplete) {
            showroomTransition.showroomReveal = 0
        } completion: {
            guard transitionID == showroomTransitionID else { return }
            // The home is still invisible, so dropping the zoom here does not show a zoom-out.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showroomTransition = .showroomDeparted
                carShowroom = nil
            }
            withAnimation(.easeOut(duration: CarShowroomTransition.homeDuration), completionCriteria: .logicallyComplete) {
                showroomTransition.homeReveal = 1
            } completion: {
                guard transitionID == showroomTransitionID else { return }
                showroomTransitionSettled = true
            }
        }
    }

    private func gridMetricView(data: PowerwallData, valueFont: Font, labelFont: Font) -> some View {
        VStack(spacing: 2) {
            if let fossil = viewModel.gridFossilFuelPercentage {
                let renewables = max(0, min(100, 100 - fossil))
                (
                    Text("\(fmt(data.site.instantPower / 1000)) kW")
                    + Text(" · ")
                    + Text(String(format: "%.1f%%", renewables))
                        .foregroundColor(renewablesColor(renewables))
                )
                .fontWeight(.bold)
                .font(valueFont)
                .numericUpdateAnimation(for: "\(data.site.instantPower)-\(renewables)")
            } else {
                Text("\(fmt(data.site.instantPower / 1000)) kW")
                    .fontWeight(.bold)
                    .font(valueFont)
                    .numericUpdateAnimation(for: data.site.instantPower)
            }

            Text("\(viewModel.gridLabelText())\(viewModel.gridCarbonIntensity.map { " · \($0) gCO2" } ?? "")")
                .opacity(viewModel.isOffGrid() ? 1.0 : 0.6)
                .fontWeight(.bold)
                .font(labelFont)
                .foregroundColor(viewModel.isOffGrid() ? .orange : .white)
                .numericUpdateAnimation(for: "\(viewModel.gridLabelText())-\(viewModel.gridCarbonIntensity.map(String.init) ?? "")")
        }
        .multilineTextAlignment(.center)
        .opensGraph(.grid, using: openGraph)
    }

    private func batteryPercentageIndicator(indicatorWidth: CGFloat, indicatorHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color.green)
            .frame(width: indicatorWidth, height: indicatorHeight)
            .cornerRadius(1)
    }

    private func offGridImage(sceneSize: CGSize) -> some View {
#if os(macOS)
        Image(nsImage: NSImage(named: "off-grid.png")!)
            .resizable()
            .frame(width: sceneWidth(0.052, in: sceneSize), height: sceneHeight(0.056, in: sceneSize))
#else
        Image(uiImage: UIImage(named: "off-grid.png")!)
            .resizable()
            .frame(width: sceneWidth(0.052, in: sceneSize), height: sceneHeight(0.056, in: sceneSize))
#endif
    }

    private func controlsOverlay(sceneSize: CGSize) -> some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .center, spacing: 16) {
            HStack(spacing: controlsButtonSpacing) {
                Button(action: {
                    revealAutoHiddenOverlays()
                    showingSettings = true
                }) {
                    ZStack {
                        Image(systemName: "gear")
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
                }
                .overlayControlButtonStyle()
                .accessibilityLabel("Settings")

                #if os(tvOS)
                if showsHouseScene, viewModel.garagePresentation.showVehicle || !userOwnsCars {
                    Button(action: {
                        revealAutoHiddenOverlays()
                        openCarShowroom()
                    }) {
                        ZStack {
                            Image(systemName: "car.fill")
                                .font(.title3)
                                .frame(width: 80, height: 80)
                        }
                    }
                    .overlayControlButtonStyle()
                    .accessibilityLabel("Car")
                }
                #endif

                if viewModel.isDemoMode || viewModel.loginMode == .fleetAPI {
                    if viewModel.loginMode == .fleetAPI && !viewModel.isDemoMode && viewModel.showSchedulerButton {
                        Button(action: {
                            revealAutoHiddenOverlays()
                            showingScheduler = true
                        }) {
                            ZStack {
                                Image(systemName: "calendar.badge.clock")
#if os(macOS)
                                    .font(.system(size: 18, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 40)
#elseif os(iOS)
                                    .font(.system(size: 24, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.gray)
                                    .frame(width: 40, height: 40)
#else
                                    .font(.title3)
                                    .frame(width: 80, height: 80)
#endif
                            }
                        }
                        .overlayControlButtonStyle()
                        .accessibilityLabel("Scheduler")
                    }

                    Button(action: {
                        openGraph(.battery)
                    }) {
                        ZStack {
                            Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
#if os(macOS)
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
#elseif os(iOS)
                                .font(.system(size: 24, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.gray)
                                .frame(width: 40, height: 40)
#else
                                .font(.title3)
                                .frame(width: 80, height: 80)
#endif
                        }
                    }
                    .overlayControlButtonStyle()
                    .accessibilityLabel("Chart")
                    if showHomeEnergyAdvisorButton || viewModel.isDemoMode {
                        Button {
                            revealAutoHiddenOverlays()
                            showingExportAdvisor = true
                        } label: {
                            Image(systemName: "sparkles")
#if os(macOS)
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
#elseif os(iOS)
                                .font(.system(size: 24, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.gray)
                                .frame(width: 40, height: 40)
#else
                                .font(.title3)
                                .frame(width: 80, height: 80)
#endif
                        }
                        .overlayControlButtonStyle()
                        .accessibilityLabel("Home Energy Advisor")
                        .accessibilityHint("Open again to ask follow-up questions")
                        .accessibilityIdentifier("homeEnergyAdvisorButton")
                    }
                }
            }
            .overlayGlassButtonCluster()
            .overlayChromeBackground(
                isVisible: !hideControlsOverlay,
                isOverlapping: controlsOverlayOverlapsScene && viewModel.autoHideButtonsOnOverlap
            )
            .compositingGroup()
            .opacity(hideControlsOverlay ? 0 : 1)
            .overlayHideInteraction(hidden: hideControlsOverlay)
            .reportFrame(.controlsOverlay)
            .overlayDarkChrome()

            if showsLoadingLabel {
                LoadingEllipsis()
                    .fontWeight(.bold)
                    .font(labelFont(for: sceneSize))
                    .foregroundColor(.white)
                    .opacity(0.6)
            }
            }

            Spacer()

            if showsVehicleChips {
                HStack {
                    ForEach(viewModel.vehicles, id: \.vin) { vehicle in
                        vehicleStatusView(vehicle: vehicle, labelFont: labelFont(for: sceneSize))
                    }
                }
                .overlayChromeBackground(
                    isVisible: !hideControlsOverlay,
                    isOverlapping: controlsOverlayOverlapsScene && viewModel.autoHideButtonsOnOverlap
                )
                .compositingGroup()
                .opacity(hideControlsOverlay ? 0 : 1)
                .overlayHideInteraction(hidden: hideControlsOverlay)
                .overlayDarkChrome()
            }
        }
    }

    #if os(tvOS)
    /// Holds focus while the buttons are hidden so the remote can bring them back.
    /// A full-screen button is drawn as the selected control, so this stays a 1pt focusable view with no focus effect.
    /// Menu is left alone so it still exits.
    private var overlayRevealCatcher: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .focusable(interactions: .activate)
            .focusEffectDisabled()
            .focused($overlayRevealFocused)
            .accessibilityLabel("Show controls")
            .onTapGesture { revealAutoHiddenOverlays() }
            .onMoveCommand { _ in
                revealAutoHiddenOverlays()
            }
            .onPlayPauseCommand {
                revealAutoHiddenOverlays()
            }
    }
    #endif

    private var controlsButtonSpacing: CGFloat? {
#if os(tvOS)
        24
#else
        nil
#endif
    }

    private func vehicleStatusView(vehicle: FleetVehicle, labelFont: Font) -> some View {
        VStack(spacing: 1) {
            if let batteryDisplay = vehicleBatteryDisplay(vehicle: vehicle) {
                Text(batteryDisplay)
                    .fontWeight(.bold)
                    .font(labelFont)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .numericUpdateAnimation(for: batteryDisplay)
            } else {
                Image(systemName: "zzz")
                    .font(labelFont)
                    .foregroundColor(.white)
            }

            Image(systemName: "car.fill")
#if os(macOS)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.white)
                .opacity(0.6)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 40, height: 24)
#elseif os(iOS)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.white)
                .opacity(0.6)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 40, height: 30)
                .padding(4)
#else
                .font(.title2)
                .opacity(0.6)
                .frame(width: 80, height: 36)
                .padding()
#endif

            Text(vehicleChipTitle(vehicle))
                .fontWeight(.bold)
                .font(labelFont)
                .foregroundColor(.white)
                .opacity(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .id(viewModel.isDemoMode ? viewModel.demoColourIndex : 0)
        }
#if os(tvOS) || os(macOS)
        .frame(minWidth: 80, maxWidth: viewModel.isDemoMode ? 280 : 80)
#else
        .frame(minWidth: 40, maxWidth: viewModel.isDemoMode ? 220 : 40)
#endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vehicleAccessibilityLabel(vehicle: vehicle))
    }

    private func vehicleBatteryDisplay(vehicle: FleetVehicle) -> String? {
        guard let batteryLevel = viewModel.vehicleChargeStates[vehicle.vin]?.batteryLevel else {
            return nil
        }
        return "\(Int(batteryLevel.rounded()))%"
    }

    /// Corner chips. Demo always shows the parked car, even when the Fleet vehicle list is off.
    private var showsVehicleChips: Bool {
        guard !viewModel.vehicles.isEmpty else { return false }
        if viewModel.isDemoMode { return true }
        return viewModel.loginMode == .fleetAPI && viewModel.showVehicles
    }

    /// The caption under the charger readout. Demo appends the paint name.
    private func vehicleMetricCaption(connectorCount: Int) -> String {
        let base = connectorCount > 1 ? "VEHICLES (\(connectorCount))" : "VEHICLE"
        guard viewModel.isDemoMode else { return base }
        let parked = DemoHouseTour.parkedCar(at: viewModel.demoColourIndex)
        return DemoHouseTour.vehicleLabel(displayName: base, exteriorColor: parked.appearance.exteriorColor)
    }

    private func vehicleChipTitle(_ vehicle: FleetVehicle) -> String {
        guard viewModel.isDemoMode else { return vehicleFirstName(vehicle) }
        let parked = DemoHouseTour.parkedCar(at: viewModel.demoColourIndex)
        return DemoHouseTour.vehicleLabel(
            displayName: parked.vehicle.displayName,
            exteriorColor: parked.appearance.exteriorColor
        )
    }

    private func vehicleAccessibilityLabel(vehicle: FleetVehicle) -> String {
        let name = vehicleChipTitle(vehicle)
        guard let batteryDisplay = vehicleBatteryDisplay(vehicle: vehicle) else {
            return name
        }
        return "\(name) \(batteryDisplay)"
    }

    private func configureDemoVehicleData(vehicle: DemoVehicle) {
        viewModel.vehicles = [
            FleetVehicle(vin: vehicle.vin, displayName: vehicle.displayName, state: "online")
        ]
        viewModel.vehicleChargeStates[vehicle.vin] = DemoHouseTour.exampleCharge
        viewModel.showVehicles = true
    }

    private func configureDemoElectricityGridData() {
        viewModel.gridCarbonIntensity = 256
        viewModel.gridFossilFuelPercentage = 58
    }

    private func queueInitialDemoData() {
        queueDemoPowerwallData(
            batteryPower: 256,
            batteryPercentage: 100,
            loadPower: 2304,
            solarPower: 2048,
            solarEnergyExported: 4096000,
            sitePower: 1024,
            gridStatus: "SystemIslandedActive",
            wallConnectorPower: 512,
            siteName: "Home sweet home"
        )
    }

    private func queueDemoPowerwallData(
        batteryPower: Double,
        batteryPercentage: Double,
        loadPower: Double,
        solarPower: Double,
        solarEnergyExported: Double,
        sitePower: Double,
        gridStatus: String,
        wallConnectorPower: Double,
        siteName: String? = nil
    ) {
        let parked = DemoHouseTour.parkedCar(at: viewModel.demoColourIndex)
        let vehicle = parked.vehicle
        DispatchQueue.main.async {
            guard viewModel.isDemoMode else { return }
            viewModel.data = PowerwallData(
                battery: PowerwallData.Battery(instantPower: batteryPower, count: 1),
                load: PowerwallData.Load(instantPower: loadPower),
                solar: PowerwallData.Solar(
                    instantPower: solarPower,
                    energyExported: solarEnergyExported
                ),
                site: PowerwallData.Site(instantPower: sitePower),
                wallConnectors: [WallConnector(vin: vehicle.vin, din: "def456", wallConnectorState: 1.0, wallConnectorPower: wallConnectorPower)]
            )
            viewModel.batteryPercentage = BatteryPercentage(percentage: batteryPercentage)
            viewModel.gridStatus = GridStatus(status: gridStatus)
            // Preview Storm Watch icon / menu ☂︎ and GRID DOWN label / menu ⛔︎.
            viewModel.stormModeActive = true
            viewModel.islandStatus = "off_grid_unintentional"
            if let siteName {
                viewModel.siteName = siteName
            }
            configureDemoVehicleData(vehicle: vehicle)
            var appearances = viewModel.vehicleAppearances
            appearances[vehicle.vin] = parked.appearance
            viewModel.vehicleAppearances = appearances
            configureDemoElectricityGridData()
        }
    }

    /// Swaps the parked demo car without drawing a new power sample.
    private func showDemoParkedCar() {
        let parked = DemoHouseTour.parkedCar(at: viewModel.demoColourIndex)
        let connectorPower = viewModel.data?.wallConnectors.first?.wallConnectorPower ?? 512
        guard let data = viewModel.data else { return }
        viewModel.data = PowerwallData(
            battery: data.battery,
            load: data.load,
            solar: data.solar,
            site: data.site,
            wallConnectors: [
                WallConnector(vin: parked.vehicle.vin, din: "def456", wallConnectorState: 1, wallConnectorPower: connectorPower)
            ]
        )
        var appearances = viewModel.vehicleAppearances
        appearances[parked.vehicle.vin] = parked.appearance
        viewModel.vehicleAppearances = appearances
        configureDemoVehicleData(vehicle: parked.vehicle)
    }

    private func queueDemoElectricityGridData() {
        DispatchQueue.main.async {
            configureDemoElectricityGridData()
        }
    }

    /// Background is off screen. Inactive is visible without focus, including the app switcher and another frontmost app.
    private static func attention(for phase: ScenePhase) -> AppAttention {
        switch phase {
        case .background:
            return .hidden
        case .inactive:
            return .visibleUnfocused
        case .active:
            return .focused
        @unknown default:
            return .focused
        }
    }

    private func beginFirstLoadIntro() {
        introAnimationTask?.cancel()
        withAnimation(.easeOut(duration: 1.4)) {
            showBackground = true
        }
        let task = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.7)) {
                showMetrics = true
            }
            startAnimations = true
        }
        introAnimationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }

    private func resetFirstLoadIntro() {
        introAnimationTask?.cancel()
        introAnimationTask = nil
        showBackground = false
        showMetrics = false
        startAnimations = false
    }

    /// Shown beside the settings buttons, on their vertical centre, until the first sample arrives.
    private var showsLoadingLabel: Bool {
        if viewModel.ipAddress.isEmpty && viewModel.loginMode == .local { return false }
        if viewModel.data != nil { return false }
        if viewModel.loginMode == .fleetAPI && !hasFleetAccessTokenConfigured { return false }
        return true
    }

    private func vehicleFirstName(_ vehicle: FleetVehicle) -> String {
        let displayName = vehicle.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return displayName.split(separator: " ").first.map(String.init) ?? "Car"
    }

    private func valueFont(for sceneSize: CGSize) -> Font {
#if os(macOS)
        return .system(size: 18 * textScaleFactor(for: sceneSize))
#elseif os(tvOS)
        return .headline
#else
        return .title2
#endif
    }

    private func labelFont(for sceneSize: CGSize) -> Font {
#if os(macOS)
        return .system(size: 12 * textScaleFactor(for: sceneSize))
#elseif os(tvOS)
        return .footnote
#else
        return .subheadline
#endif
    }

    private func fittedSceneSize(in available: CGSize) -> CGSize {
        guard available.width > 0, available.height > 0 else { return .zero }
        let widthScale = available.width / naturalSceneWidth
        let heightScale = available.height / naturalSceneHeight
        let scale = max(1.0, min(widthScale, heightScale)) * clampSceneScale(viewModel.sceneScale)
        return CGSize(
            width: naturalSceneWidth * scale,
            height: naturalSceneHeight * scale
        )
    }

    private func isPortraitIPad(_ size: CGSize) -> Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad && size.height > size.width
#else
        false
#endif
    }

    private func shouldDetachSiteSummary(geometrySize: CGSize, sceneSize: CGSize) -> Bool {
#if os(iOS)
        if isPortraitIPad(geometrySize) {
            return true
        }
        return !canFitInlineSiteSummary(availableSize: geometrySize, sceneSize: sceneSize)
#else
        return isNarrowMacOSWindow(geometrySize)
#endif
    }

    private func isNarrowMacOSWindow(_ geometrySize: CGSize) -> Bool {
#if os(macOS)
        geometrySize.width < naturalSceneWidth
#else
        false
#endif
    }

    private func rightContentBound() -> CGFloat {
#if os(macOS) || os(iOS)
        if viewModel.gridFossilFuelPercentage == nil && viewModel.gridCarbonIntensity == nil {
            return 0.34
        }
#endif
        return 0.40
    }

    private func sceneFrame(in available: CGSize, sceneSize: CGSize, showSiteSummaryInScene _: Bool) -> CGRect {
        let centeredMinX = (available.width - sceneSize.width) / 2
        let userOffset = available.width * clampSceneHorizontalOffset(viewModel.sceneHorizontalOffset)
        let verticalOffset = available.height * clampSceneVerticalOffset(viewModel.sceneVerticalOffset)
#if os(macOS) || os(iOS)
        // Keep the scene centered by default, but once the right-side labels hit
        // the viewport edge, shift left just enough so they stay visible.
        let biasedMinX = centeredMinX - (available.width * 0.10)
        let rightContentBound = rightContentBound()
        let rightContentX = sceneSize.width * (0.5 + rightContentBound)
        let minXToKeepRightContentVisible = available.width - rightContentX
        let desiredMinX = min(biasedMinX, minXToKeepRightContentVisible) + userOffset
#else
        let desiredMinX = centeredMinX - (available.width * 0.10) + userOffset
#endif
        let lowerBound = min(0, available.width - sceneSize.width)
        let upperBound = max(0, available.width - sceneSize.width)
        let minX = min(upperBound, max(lowerBound, desiredMinX))
        let centeredMinY = (available.height - sceneSize.height) / 2
        let lowerYBound = min(0, available.height - sceneSize.height)
        let upperYBound = max(0, available.height - sceneSize.height)
        let minY = min(upperYBound, max(lowerYBound, centeredMinY + verticalOffset))
        return CGRect(x: minX, y: minY, width: sceneSize.width, height: sceneSize.height)
    }

    private var inlineSiteSummaryX: CGFloat {
#if os(macOS)
        return -0.3
#elseif os(tvOS)
        return -0.38
#else
        return -0.39
#endif
    }

    private func sceneScaleFactor(_ sceneSize: CGSize) -> CGFloat {
        guard naturalSceneWidth > 0 else { return 1.0 }
        return max(1.0, sceneSize.width / naturalSceneWidth)
    }

    private func textScaleFactor(for sceneSize: CGSize) -> CGFloat {
#if os(macOS)
        return sceneScaleFactor(sceneSize)
#else
        return 1.0
#endif
    }

    private func siteSummaryMessageWidth(for sceneSize: CGSize) -> CGFloat {
#if os(tvOS)
        _ = sceneSize
        return 400
#else
        260 * textScaleFactor(for: sceneSize)
#endif
    }

    private func canFitInlineSiteSummary(availableSize: CGSize, sceneSize: CGSize) -> Bool {
        let inlineFrame = sceneFrame(
            in: availableSize,
            sceneSize: sceneSize,
            showSiteSummaryInScene: true
        )
        let summaryCenterX = scenePoint(x: inlineSiteSummaryX, y: -0.38, in: sceneSize).x
        let summaryHalfWidth = siteSummaryMessageWidth(for: sceneSize) / 2
        let leftEdge = inlineFrame.minX + summaryCenterX - summaryHalfWidth
        let rightEdge = inlineFrame.minX + summaryCenterX + summaryHalfWidth
        let horizontalInset: CGFloat = 12
        return leftEdge >= horizontalInset && rightEdge <= (availableSize.width - horizontalInset)
    }

    private func frameIntersectsScene(_ frame: CGRect, sceneFrame: CGRect) -> Bool {
        OverlayAutoHide.frameIntersects(frame, sceneFrame)
    }

    private func updateDetachedSiteSummaryOverlap(_ overlaps: Bool) {
        detachedSiteSummaryOverlapsScene = overlaps
        updateOverlayAutoHide(for: .detachedSiteSummary, overlaps: overlaps)
    }

    private func updateControlsOverlayOverlap(_ overlaps: Bool) {
        controlsOverlayOverlapsScene = overlaps
        updateOverlayAutoHide(for: .controlsOverlay, overlaps: overlaps)
    }

    private func updateOverlayAutoHide(for kind: OverlayAutoHideTarget, overlaps: Bool) {
        if overlaps && isAutoHideEnabled(kind) {
            if !isOverlayHidden(kind) {
                scheduleOverlayHide(for: kind)
            }
        } else {
            cancelOverlayHideTask(kind)
            setOverlayHidden(kind, hidden: false)
        }
    }

    private var hasHiddenAutoOverlay: Bool {
        hideDetachedSiteSummary || hideControlsOverlay
    }

    /// Pointer motion only brings overlays back after they have hidden. Resetting the idle timer on
    /// every move kept the buttons up, because a trackpad never sits still for the full three seconds.
    private func revealHiddenOverlaysOnActivity() {
        guard hasHiddenAutoOverlay else { return }
        revealAutoHiddenOverlays()
    }

    private func revealAutoHiddenOverlays() {
        cancelOverlayHideTask(.detachedSiteSummary)
        cancelOverlayHideTask(.controlsOverlay)
        setOverlayHidden(.detachedSiteSummary, hidden: false)
        setOverlayHidden(.controlsOverlay, hidden: false)

        if detachedSiteSummaryOverlapsScene && isAutoHideEnabled(.detachedSiteSummary) {
            scheduleOverlayHide(for: .detachedSiteSummary)
        }
        if controlsOverlayOverlapsScene && isAutoHideEnabled(.controlsOverlay) {
            scheduleOverlayHide(for: .controlsOverlay)
        }
    }

    private func scheduleOverlayHide(for kind: OverlayAutoHideTarget) {
        cancelOverlayHideTask(kind)
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.25)) {
                setOverlayHidden(kind, hidden: true)
            }
        }
        storeOverlayHideTask(workItem, for: kind)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func cancelOverlayHideTask(_ kind: OverlayAutoHideTarget) {
        switch kind {
        case .detachedSiteSummary:
            detachedSiteSummaryHideTask?.cancel()
            detachedSiteSummaryHideTask = nil
        case .controlsOverlay:
            controlsOverlayHideTask?.cancel()
            controlsOverlayHideTask = nil
        }
    }

    private func storeOverlayHideTask(_ task: DispatchWorkItem, for kind: OverlayAutoHideTarget) {
        switch kind {
        case .detachedSiteSummary:
            detachedSiteSummaryHideTask = task
        case .controlsOverlay:
            controlsOverlayHideTask = task
        }
    }

    private func isOverlayHidden(_ kind: OverlayAutoHideTarget) -> Bool {
        switch kind {
        case .detachedSiteSummary:
            return hideDetachedSiteSummary
        case .controlsOverlay:
            return hideControlsOverlay
        }
    }

    private func isAutoHideEnabled(_ kind: OverlayAutoHideTarget) -> Bool {
        switch kind {
        case .detachedSiteSummary:
            return viewModel.autoHideSummaryOnOverlap
        case .controlsOverlay:
            return viewModel.autoHideButtonsOnOverlap
        }
    }

    private func setOverlayHidden(_ kind: OverlayAutoHideTarget, hidden: Bool) {
        switch kind {
        case .detachedSiteSummary:
            hideDetachedSiteSummary = hidden
        case .controlsOverlay:
            hideControlsOverlay = hidden
            #if os(tvOS)
            if hidden {
                // The catcher is inserted in this update. Focus it on the next turn, once it is in the tree.
                DispatchQueue.main.async {
                    guard hideControlsOverlay else { return }
                    overlayRevealFocused = true
                }
            } else {
                overlayRevealFocused = false
            }
            #endif
        }
    }

    private var shouldHideWindowChrome: Bool {
#if os(macOS) || os(iOS)
        let statusVisible = !detachedSiteSummaryOverlapsScene || !hideDetachedSiteSummary
        let controlsVisible = !controlsOverlayOverlapsScene || !hideControlsOverlay
        return !(statusVisible || controlsVisible)
#else
        false
#endif
    }

    private func powerSurgeLineWidth(for sceneSize: CGSize) -> CGFloat {
#if os(macOS)
        return max(5.0, 5.0 * sceneScaleFactor(sceneSize))
#else
        return 6.0
#endif
    }

    // Coordinates are measured from the center of the scene container:
    // x/y = -0.5...0.5 maps to leading/top ... trailing/bottom.
    private func scenePoint(x: CGFloat, y: CGFloat, in sceneSize: CGSize) -> CGPoint {
        CGPoint(
            x: sceneSize.width * (0.5 + x),
            y: sceneSize.height * (0.5 + y)
        )
    }

    private func sceneBottomPoint(x: CGFloat, y: CGFloat, objectHeight: CGFloat, in sceneSize: CGSize) -> CGPoint {
        let bottomAnchor = scenePoint(x: x, y: y, in: sceneSize)
        return CGPoint(x: bottomAnchor.x, y: bottomAnchor.y - (objectHeight / 2))
    }

    private func sceneWidth(_ fraction: CGFloat, in sceneSize: CGSize) -> CGFloat {
        sceneSize.width * fraction
    }

    private func sceneHeight(_ fraction: CGFloat, in sceneSize: CGSize) -> CGFloat {
        sceneSize.height * fraction
    }

    private var hasGatewayAddressConfigured: Bool {
        !viewModel.ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasFleetAccessTokenConfigured: Bool {
        !viewModel.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldAutoOpenSettingsOnLaunch: Bool {
        viewModel.loginMode == .local && !hasGatewayAddressConfigured
    }

    private func updateEnergySite(_ delta: Int) {
        revealAutoHiddenOverlays()
        viewModel.selectEnergySite(at: viewModel.currentEnergySiteIndex + delta)
    }

    private func openGraph(_ graph: GraphView.GraphType) {
        revealAutoHiddenOverlays()
        selectedGraph = graph
        showingGraph = true
    }

#if os(macOS)
    private func exitFullScreenIfNeeded() -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        guard window.styleMask.contains(.fullScreen) else { return false }
        window.toggleFullScreen(nil)
        return true
    }
#endif

    private func handleSiteSwipe(_ translation: CGSize) {
        guard !showingGraph, !showingScheduler else { return }
        let threshold: CGFloat = 40
        let absX = abs(translation.width)
        let absY = abs(translation.height)
        guard absY > absX, absY >= threshold else { return }
        if translation.height < 0 {
            updateEnergySite(-1)
        } else {
            updateEnergySite(+1)
        }
    }

    private func homeEnergyToDisplay(data: PowerwallData) -> Double {
        return data.load.instantPower - self.wallConnectorEnergyTotal(data: data)
    }

    /// Same solar / Powerwall / grid choice as the 3D wall-connector cable.
    private func leadingSupplyColor(data: PowerwallData) -> Color {
        switch PowerFlowSupply.dominant(
            solarW: data.solar.instantPower,
            batteryW: data.battery.instantPower,
            gridW: data.site.instantPower,
            biasW: wiggleWatts
        ) {
        case .solar: return .yellow
        case .battery: return .green
        case .grid: return .gray
        }
    }

    private func wallConnectorEnergyTotal(data: PowerwallData?) -> Double {
        return data?.wallConnectors.reduce(0.0) { $0 + ($1.wallConnectorPower ?? 0.0) } ?? 0.0
    }

    private func wallConnectorIsCharging(data: PowerwallData?) -> Bool {
        data?.wallConnectors.contains { $0.wallConnectorState == 1.0 } ?? false
    }

    private func wallConnectorHasConnectedVehicle(data: PowerwallData?) -> Bool {
        data?.wallConnectors.contains(where: \.isVehicleConnected) ?? false
    }

    private func wallConnectorDisplay(data: PowerwallData?, precision: String) -> String {
        guard let data = data else { return "Idle" }

        if let chargingConnector = data.wallConnectors.first(where: \.isVehicleCharging) {
            let powerKW = self.wallConnectorEnergyTotal(data: data) / 1000
            if let vin = chargingConnector.vin,
               let batteryLevel = viewModel.vehicleChargeStates[vin]?.batteryLevel {
                return "\(fmt(powerKW)) kW · \(Int(batteryLevel.rounded()))%"
            }
            return "\(fmt(powerKW)) kW"
        }

        if let connectedConnector = data.wallConnectors.first(where: \.isVehicleConnected) {
            if let vin = connectedConnector.vin,
               let batteryLevel = viewModel.vehicleChargeStates[vin]?.batteryLevel {
                return "Plugged in · \(Int(batteryLevel.rounded()))%"
            }
            return "Plugged in"
        }
        return "Idle"
    }

    func fmt(_ value: Double) -> String {
        formatPowerValue(value, precision: precision, showLessPrecision: viewModel.showLessPrecision)
    }

    func batteryArrow(wiggleWatts: Double) -> String {
        let battWatts = viewModel.data?.battery.instantPower ?? 0
        if battWatts > wiggleWatts { return "▼" }
        if battWatts < -wiggleWatts { return "▲" }
        return "·"
    }

    private func renewablesColor(_ renewables: Double) -> Color {
        let clamped = max(0, min(100, renewables))
        if clamped < 25 { return .brown }
        if clamped < 50 { return .orange }
        if clamped < 75 { return .yellow }
        return .green
    }
}

private extension View {
    /// iOS and macOS open the matching history. tvOS keeps the remote on the scene.
    func opensGraph(_ graph: GraphView.GraphType, using open: @escaping (GraphView.GraphType) -> Void) -> some View {
        #if os(tvOS)
        return self
        #else
        return contentShape(Rectangle())
            .onTapGesture { open(graph) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the \(graph.title) graph")
        #endif
    }
}

private enum OverlayAutoHideTarget {
    case detachedSiteSummary
    case controlsOverlay
}

/// Decides when the summary and the corner buttons cover the home presentation.
enum OverlayAutoHide {
    /// The house scene fills the window, including the band under a 16:9 frame.
    /// The flat image does not. Once the buttons have a frame, they still cover that presentation.
    static func controlsOverlap(showsHouseScene: Bool, controlsFrame: CGRect, sceneFrame: CGRect) -> Bool {
        if showsHouseScene { return true }
        if frameIntersects(controlsFrame, sceneFrame) { return true }
        return !controlsFrame.isEmpty && !sceneFrame.isEmpty
    }

    /// An inline summary is drawn on the flat image. A detached summary on the flat home
    /// sits in the same letterbox the fitted scene rect misses.
    static func summaryOverlaps(
        showsHouseScene: Bool,
        summaryIsInline: Bool,
        summaryFrame: CGRect,
        sceneFrame: CGRect
    ) -> Bool {
        if summaryIsInline { return !showsHouseScene }
        if showsHouseScene { return frameIntersects(summaryFrame, sceneFrame) }
        return !summaryFrame.isEmpty && !sceneFrame.isEmpty
    }

    static func frameIntersects(_ frame: CGRect, _ sceneFrame: CGRect) -> Bool {
        !frame.isEmpty && frame.intersects(sceneFrame)
    }
}

private enum OverlayFrameKind: Hashable {
    case detachedSiteSummary
    case controlsOverlay
    case metricSolar
    case metricHome
    case metricBattery
    case metricGrid
    case metricVehicle
}

private struct OverlayFramePreferenceKey: PreferenceKey {
    static var defaultValue: [OverlayFrameKind: CGRect] = [:]

    static func reduce(value: inout [OverlayFrameKind: CGRect], nextValue: () -> [OverlayFrameKind: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#if os(macOS)
/// Bordered macOS buttons are NSButtons. A parent opacity does not fade them.
/// Before Liquid Glass (macOS 26), draw a SwiftUI material circle so the hide animation still applies.
private struct MacOverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.5 : 0.32), lineWidth: 0.7)
                    }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

private struct WindowChromeVisibilityConfigurator: NSViewRepresentable {
    let isHidden: Bool
    let keepWindowInFront: Bool
    let onMouseMove: () -> Void
    let onBecomeKey: () -> Void
    let onAttention: (AppAttention) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onMouseMove: onMouseMove, onBecomeKey: onBecomeKey, onAttention: onAttention)
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMouseMove = context.coordinator.handleMouseMove
        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.onMouseMove = onMouseMove
        context.coordinator.onBecomeKey = onBecomeKey
        context.coordinator.onAttention = onAttention
        nsView.onMouseMove = context.coordinator.handleMouseMove
        DispatchQueue.main.async {
            configureWindow(for: nsView, coordinator: context.coordinator)
        }
    }

    static func dismantleNSView(_ nsView: TrackingView, coordinator: Coordinator) {
        if let window = nsView.window {
            coordinator.stopObserving(window: window)
        }
    }

    private func configureWindow(for view: TrackingView, coordinator: Coordinator) {
        guard let window = view.window else { return }

        view.windowDidChange()
        window.acceptsMouseMovedEvents = true
        coordinator.applyWindowLevel(keepWindowInFront, to: window)
        coordinator.applyTrafficLightsHidden(isHidden, to: window)
        coordinator.startObserving(window: window)
    }

    final class Coordinator {
        private var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        var onMouseMove: () -> Void
        var onBecomeKey: () -> Void
        var onAttention: (AppAttention) -> Void
        private var lastTrafficLightsHidden: Bool?
        private var lastKeepWindowInFront: Bool?

        init(onMouseMove: @escaping () -> Void, onBecomeKey: @escaping () -> Void, onAttention: @escaping (AppAttention) -> Void) {
            self.onMouseMove = onMouseMove
            self.onBecomeKey = onBecomeKey
            self.onAttention = onAttention
        }

        func handleMouseMove() {
            onMouseMove()
        }

        func handleBecomeKey() {
            onBecomeKey()
        }

        func startObserving(window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObserving(window: observedWindow)
            observedWindow = window
            lastTrafficLightsHidden = nil
            lastKeepWindowInFront = nil
            let center = NotificationCenter.default
            observe(center, NSWindow.didBecomeKeyNotification, object: window) { coordinator in
                coordinator.handleBecomeKey()
                coordinator.publishAttention()
            }
            observe(center, NSWindow.didChangeOcclusionStateNotification, object: window) { $0.publishAttention() }
            observe(center, NSWindow.didMiniaturizeNotification, object: window) { $0.publishAttention() }
            observe(center, NSWindow.didDeminiaturizeNotification, object: window) { $0.publishAttention() }
            observe(center, NSApplication.didBecomeActiveNotification, object: nil) { $0.publishAttention() }
            observe(center, NSApplication.didResignActiveNotification, object: nil) { $0.publishAttention() }
            observe(center, NSApplication.didHideNotification, object: nil) { $0.publishAttention() }
            observe(center, NSApplication.didUnhideNotification, object: nil) { $0.publishAttention() }
            publishAttention()
        }

        private func observe(_ center: NotificationCenter, _ name: Notification.Name, object: Any?, body: @escaping (Coordinator) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                guard let self else { return }
                body(self)
            })
        }

        func publishAttention() {
            guard let window = observedWindow else { return }
            onAttention(AppAttention.macWindow(
                isVisible: window.isVisible,
                isMiniaturized: window.isMiniaturized,
                occlusionVisible: window.occlusionState.contains(.visible),
                appHidden: NSApp.isHidden,
                appActive: NSApp.isActive
            ))
        }

        func applyWindowLevel(_ keepWindowInFront: Bool, to window: NSWindow) {
            let desiredLevel: NSWindow.Level = keepWindowInFront ? .floating : .normal
            guard lastKeepWindowInFront != keepWindowInFront || window.level != desiredLevel else { return }
            window.level = desiredLevel
            lastKeepWindowInFront = keepWindowInFront
        }

        func applyTrafficLightsHidden(_ isHidden: Bool, to window: NSWindow) {
            let closeHidden = window.standardWindowButton(.closeButton)?.isHidden ?? false
            let miniHidden = window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false
            let zoomHidden = window.standardWindowButton(.zoomButton)?.isHidden ?? false
            let needsUpdate =
                lastTrafficLightsHidden != isHidden
                || closeHidden != isHidden
                || miniHidden != isHidden
                || zoomHidden != isHidden

            guard needsUpdate else { return }
            window.standardWindowButton(.closeButton)?.isHidden = isHidden
            window.standardWindowButton(.miniaturizeButton)?.isHidden = isHidden
            window.standardWindowButton(.zoomButton)?.isHidden = isHidden
            lastTrafficLightsHidden = isHidden
        }

        func stopObserving(window: NSWindow?) {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            if observedWindow === window {
                observedWindow = nil
                lastTrafficLightsHidden = nil
                lastKeepWindowInFront = nil
            }
        }

        deinit {
            stopObserving(window: observedWindow)
        }
    }

    final class TrackingView: NSView {
        var onMouseMove: (() -> Void)?
        private var trackingAreaRef: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }
            let newTrackingArea = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(newTrackingArea)
            trackingAreaRef = newTrackingArea
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            onMouseMove?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            windowDidChange()
        }

        func windowDidChange() {
            window?.acceptsMouseMovedEvents = true
            needsDisplay = true
        }
    }
}
#endif

/// Steps the ellipsis so the word stays put and the dots fill in one at a time.
private struct LoadingEllipsis: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.45)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 3
            HStack(spacing: 0) {
                Text("Loading")
                ForEach(0..<3, id: \.self) { index in
                    Text(".")
                        .opacity(index <= phase ? 1 : 0.22)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

private struct OverlayMaterialPlate: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                }
        }
    }
}

private extension View {
    @ViewBuilder
    func overlayChromeBackground(isVisible: Bool, isOverlapping: Bool) -> some View {
        if isVisible && isOverlapping {
            overlayGlassPlate(cornerRadius: 22)
        } else {
            self
        }
    }

    /// Liquid Glass on OS 26. Earlier systems use a material plate so the group still reads as glass.
    @ViewBuilder
    func overlayGlassPlate(cornerRadius: CGFloat) -> some View {
        let padded = self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
#if compiler(>=6.2) && !ADVISOR_LEGACY_GLASS
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            padded.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            padded.modifier(OverlayMaterialPlate(cornerRadius: cornerRadius))
        }
#else
        padded.modifier(OverlayMaterialPlate(cornerRadius: cornerRadius))
#endif
    }

    /// Lets neighbouring glass buttons blend into one surface.
    @ViewBuilder
    func overlayGlassButtonCluster() -> some View {
#if compiler(>=6.2) && !ADVISOR_LEGACY_GLASS
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            GlassEffectContainer { self }
        } else {
            self
        }
#else
        self
#endif
    }

    @ViewBuilder
    func overlayControlButtonStyle() -> some View {
#if compiler(>=6.2) && !ADVISOR_LEGACY_GLASS
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.legacyOverlayControlButtonStyle()
        }
#else
        self.legacyOverlayControlButtonStyle()
#endif
    }

    @ViewBuilder
    func legacyOverlayControlButtonStyle() -> some View {
#if os(macOS)
        buttonStyle(MacOverlayButtonStyle())
#else
        buttonStyle(.bordered)
            .controlSize(.large)
#endif
    }

    /// Glass and materials follow the system appearance. The house plate is always dark, so the controls stay in dark mode.
    func overlayDarkChrome() -> some View {
        self
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
    }

    /// tvOS keeps disabled hidden buttons out of the focus system so the reveal catcher can take the remote.
    @ViewBuilder
    func overlayHideInteraction(hidden: Bool) -> some View {
#if os(tvOS)
        self.disabled(hidden).allowsHitTesting(!hidden)
#else
        self.allowsHitTesting(!hidden)
#endif
    }

    func reportFrame(_ kind: OverlayFrameKind) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: OverlayFramePreferenceKey.self,
                        value: [kind: proxy.frame(in: .named("contentView"))]
                    )
            }
        )
    }
}

extension View {
    /// The glass circle used by the home settings buttons.
    func homeSettingsButtonChrome() -> some View {
        overlayControlButtonStyle()
    }

    func homeSettingsButtonCluster() -> some View {
        overlayGlassButtonCluster()
    }

    func homeSettingsDarkChrome() -> some View {
        overlayDarkChrome()
    }
}

#if os(macOS)
enum MenuBarLabelMetric: String, CaseIterable, Identifiable {
    case auto, solar, load, site, battery
    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .solar: return "Solar"
        case .load: return "Home"
        case .site: return "Grid"
        case .battery: return "Battery"
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "wand.and.sparkles"
        case .solar: return "sun.max.fill"
        case .load: return "house.fill"
        case .site: return "bolt.horizontal.fill"
        case .battery: return "battery.100percent"
        }
    }

    var shortPrefix: String {
        switch self {
        case .auto: return ""
        case .solar: return "☀︎"
        case .load: return "⌂"
        case .site: return "⇄"
        case .battery: return "⚡︎"
        }
    }
}

func automaticMenuBarLabelMetric(
    solarWatts: Double,
    loadWatts: Double,
    siteWatts: Double,
    batteryWatts: Double
) -> MenuBarLabelMetric {
    let flows: [(metric: MenuBarLabelMetric, watts: Double)] = [
        (.solar, solarWatts),
        (.load, loadWatts),
        (.site, siteWatts),
        (.battery, batteryWatts)
    ]
    return flows.max { abs($0.watts) < abs($1.watts) }?.metric ?? .solar
}

struct MenuBarLabelSelection {
    static func metrics(from rawValue: String) -> [MenuBarLabelMetric] {
        let selectedRawValues = Set(
            rawValue
                .split(separator: ",")
                .map(String.init)
        )
        let metrics = MenuBarLabelMetric.allCases.filter { selectedRawValues.contains($0.rawValue) }
        return metrics.isEmpty ? [.solar] : metrics
    }

    static func rawValue(for metrics: some Sequence<MenuBarLabelMetric>) -> String {
        let selectedMetrics = Set(metrics)
        let orderedMetrics = MenuBarLabelMetric.allCases.filter(selectedMetrics.contains)
        return (orderedMetrics.isEmpty ? [.solar] : orderedMetrics)
            .map(\.rawValue)
            .joined(separator: ",")
    }

    static func toggling(
        _ metric: MenuBarLabelMetric,
        in rawValue: String
    ) -> String {
        var selectedMetrics = Set(metrics(from: rawValue))
        if selectedMetrics.contains(metric) {
            guard selectedMetrics.count > 1 else { return Self.rawValue(for: selectedMetrics) }
            selectedMetrics.remove(metric)
        } else {
            selectedMetrics.insert(metric)
        }
        return Self.rawValue(for: selectedMetrics)
    }
}

private struct PowerwallMenuBarLabel: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @AppStorage("menuBarLabelMetric") private var menuBarLabelMetricsRaw: String = MenuBarLabelMetric.solar.rawValue

    private var metrics: [MenuBarLabelMetric] {
        MenuBarLabelSelection.metrics(from: menuBarLabelMetricsRaw)
    }

    private func batteryTrendGlyph(wiggleWatts: Double) -> String {
        let battWatts = viewModel.data?.battery.instantPower ?? 0
        if battWatts > wiggleWatts { return "▼" }
        if battWatts < -wiggleWatts { return "▲" }
        return ""
    }

    var body: some View {
        guard viewModel.showInMenuBar else { return AnyView(EmptyView()) }

        let precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"
        let trend = batteryTrendGlyph(wiggleWatts: 40.0)

        let solarWatts = viewModel.data?.solar.instantPower ?? 0
        let loadWatts = viewModel.data?.load.instantPower ?? 0
        let siteWatts = viewModel.data?.site.instantPower ?? 0
        let batteryWatts = viewModel.data?.battery.instantPower ?? 0
        let solarKW = solarWatts / 1000
        let loadKW = loadWatts / 1000
        let siteKW = siteWatts / 1000
        let batteryKW = batteryWatts / 1000
        let batteryPercentage = viewModel.batteryPercentage?.percentage ?? 0

        func fmt(_ value: Double) -> String {
            formatPowerValue(value, precision: precision, showLessPrecision: viewModel.showLessPrecision)
        }

        let automaticMetric = automaticMenuBarLabelMetric(
            solarWatts: solarWatts,
            loadWatts: loadWatts,
            siteWatts: siteWatts,
            batteryWatts: batteryWatts
        )
        var renderedMetrics = [MenuBarLabelMetric]()
        for metric in metrics {
            let resolvedMetric = metric == .auto ? automaticMetric : metric
            if !renderedMetrics.contains(resolvedMetric) {
                renderedMetrics.append(resolvedMetric)
            }
        }

        let selectedValues = renderedMetrics.map { metric in
            switch metric {
            case .auto:
                return ""
            case .solar:
                return "\(metric.shortPrefix) \(fmt(solarKW)) kW"
            case .load:
                return "\(metric.shortPrefix) \(fmt(loadKW)) kW"
            case .site:
                return "\(metric.shortPrefix) \(fmt(siteKW)) kW"
            case .battery:
                return "\(metric.shortPrefix) \(fmt(batteryKW)) kW"
            }
        }
        let batteryStatus = "\(String(format: "%.0f", batteryPercentage))% \(trend)"
            .trimmingCharacters(in: .whitespaces)
        var label = (selectedValues + [batteryStatus])
            .joined(separator: " · ")

        // Status symbols sit far right of the menu text, after the battery trend arrow.
        if viewModel.isStormWatchActive() {
            label += " ☂︎"
        }
        if viewModel.isGridDown() {
            label += " ⛔︎"
        }

        return AnyView(
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .numericUpdateAnimation(for: "\(label)-\(batteryPercentage)-\(trend)")
        )
    }
}

private struct PowerwallMenuBarPopover: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @AppStorage("menuBarLabelMetric") private var menuBarLabelMetricsRaw: String = MenuBarLabelMetric.solar.rawValue

    private var selectedMetrics: [MenuBarLabelMetric] {
        MenuBarLabelSelection.metrics(from: menuBarLabelMetricsRaw)
    }

    private func selectionBinding(for metric: MenuBarLabelMetric) -> Binding<Bool> {
        Binding {
            selectedMetrics.contains(metric)
        } set: { isSelected in
            let isCurrentlySelected = selectedMetrics.contains(metric)
            guard isSelected != isCurrentlySelected else { return }
            menuBarLabelMetricsRaw = MenuBarLabelSelection.toggling(
                metric,
                in: menuBarLabelMetricsRaw
            )
        }
    }

    var body: some View {
        guard viewModel.showInMenuBar else { return AnyView(EmptyView()) }

        let precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"

        return AnyView(
            VStack(alignment: .center, spacing: 16) {

                Menu {
                    ForEach(MenuBarLabelMetric.allCases) { option in
                        Toggle(isOn: selectionBinding(for: option)) {
                            Label(option.title, systemImage: option.symbol)
                        }
                        .disabled(selectedMetrics.count == 1 && selectedMetrics.contains(option))
                    }
                } label: {
                    Label(
                        selectedMetrics.map(\.title).joined(separator: ", "),
                        systemImage: "menubar.rectangle"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                let batteryPercentage = viewModel.batteryPercentage?.percentage ?? 0
                Gauge(value: batteryPercentage, in: 0...100) {
                    Label("Battery", systemImage: "bolt.fill")
                } currentValueLabel: {
                    Text("\(batteryPercentage, specifier: "%.0f")%")
                        .monospacedDigit()
                        .numericUpdateAnimation(for: batteryPercentage)
                }
                .tint(batteryPercentage >= 60 ? .green : (batteryPercentage >= 25 ? .yellow : .red))
                .gaugeStyle(.accessoryCircular)
                .frame(width: 56, height: 56)

                HStack(alignment: .center, spacing: 20) {
                    VStack {
                        Text("\(formatPowerValue((viewModel.data?.solar.instantPower ?? 0) / 1000, precision: precision, showLessPrecision: viewModel.showLessPrecision)) kW")
                            .fontWeight(.bold)
                            .font(.title2)
                            .numericUpdateAnimation(for: viewModel.data?.solar.instantPower ?? 0)
                        Text("SOLAR")
                            .opacity(0.6)
                            .fontWeight(.bold)
                            .font(.subheadline)
                    }
                    .frame(width: 100)

                    VStack {
                        Text("\(formatPowerValue((viewModel.data?.load.instantPower ?? 0) / 1000, precision: precision, showLessPrecision: viewModel.showLessPrecision)) kW")
                            .fontWeight(.bold)
                            .font(.title2)
                            .numericUpdateAnimation(for: viewModel.data?.load.instantPower ?? 0)
                        Text("HOME")
                            .opacity(0.6)
                            .fontWeight(.bold)
                            .font(.subheadline)
                    }
                    .frame(width: 100)
                }
                .padding(.bottom, 10)

                HStack(alignment: .center, spacing: 20) {
                    VStack {
                        Text("\(formatPowerValue((viewModel.data?.battery.instantPower ?? 0) / 1000, precision: precision, showLessPrecision: viewModel.showLessPrecision)) kW")
                            .fontWeight(.bold)
                            .font(.title2)
                            .numericUpdateAnimation(for: viewModel.data?.battery.instantPower ?? 0)
                        Text("POWERWALL")
                            .opacity(0.6)
                            .fontWeight(.bold)
                            .font(.subheadline)
                    }
                    .frame(width: 100)

                    VStack {
                        Text("\(formatPowerValue((viewModel.data?.site.instantPower ?? 0) / 1000, precision: precision, showLessPrecision: viewModel.showLessPrecision)) kW")
                            .fontWeight(.bold)
                            .font(.title2)
                            .numericUpdateAnimation(for: viewModel.data?.site.instantPower ?? 0)
                        Text(viewModel.gridLabelText())
                            .opacity(viewModel.isOffGrid() ? 1.0 : 0.6)
                            .fontWeight(.bold)
                            .font(.subheadline)
                            .foregroundColor(viewModel.isOffGrid() ? .orange : .primary)
                    }
                    .frame(width: 100)
                }
            }
            .padding(20)
            .frame(width: 250)
        )
    }
}

@SceneBuilder
func MenuBar(viewModel: PowerwallViewModel) -> some Scene {
    MenuBarExtra {
        PowerwallMenuBarPopover(viewModel: viewModel)
    } label: {
        PowerwallMenuBarLabel(viewModel: viewModel)
    }
    .menuBarExtraStyle(.window)
}
#endif

#Preview {
    ContentView(viewModel: PowerwallViewModel())
        .modelContainer(for: Item.self, inMemory: true)
}
