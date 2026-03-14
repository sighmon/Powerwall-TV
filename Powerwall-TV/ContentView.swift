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

func formatPowerValue(_ value: Double, precision: String, showLessPrecision: Bool) -> String {
    let displayedValue = showLessPrecision ? abs(value) : value
    return String(format: precision, displayedValue)
}

struct ContentView: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @State private var demo = false
    @State private var animations = true
    @State private var showingSettings = false
    @State private var showingGraph = false
    @State private var wiggleWatts = 40.0
    @State private var startAnimations = false
    @State private var precision = "%.3f"
    @State private var detachedSiteSummaryFrame: CGRect = .zero
    @State private var controlsOverlayFrame: CGRect = .zero
    @State private var detachedSiteSummaryOverlapsScene = false
    @State private var controlsOverlayOverlapsScene = false
    @State private var hideDetachedSiteSummary = false
    @State private var hideControlsOverlay = false
    @State private var detachedSiteSummaryHideTask: DispatchWorkItem?
    @State private var controlsOverlayHideTask: DispatchWorkItem?
    @FocusState private var hasKeyboardFocus: Bool
    private let naturalSceneWidth: CGFloat = 1280
    private let naturalSceneHeight: CGFloat = 720
#if os(macOS)
    private let powerwallPercentageWidth: Double = 4
#else
    private let powerwallPercentageWidth: Double = 5
#endif
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
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
            let siteSummarySceneOverlap = detachSiteSummary
                && frameIntersectsScene(detachedSiteSummaryFrame, sceneFrame: sceneFrame)
            let controlsSceneOverlap = frameIntersectsScene(controlsOverlayFrame, sceneFrame: sceneFrame)
            ZStack {
                Color(red: 22/255, green: 23/255, blue: 24/255)
                    .ignoresSafeArea()

                ZStack {
                    homeBackgroundImage
                        .frame(width: sceneSize.width, height: sceneSize.height)

                    sceneOverlay(
                        in: sceneSize,
                        showSiteSummaryInScene: !detachSiteSummary
                    )
                        .frame(width: sceneSize.width, height: sceneSize.height)
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

                controlsOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding()
            }
            .coordinateSpace(name: "contentView")
            .onPreferenceChange(OverlayFramePreferenceKey.self) { frames in
                detachedSiteSummaryFrame = frames[.detachedSiteSummary] ?? .zero
                controlsOverlayFrame = frames[.controlsOverlay] ?? .zero
            }
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
                showInMenuBar: $viewModel.showInMenuBar,
                keepWindowInFront: $viewModel.keepWindowInFront,
                autoHideSummaryOnOverlap: $viewModel.autoHideSummaryOnOverlap,
                autoHideButtonsOnOverlap: $viewModel.autoHideButtonsOnOverlap,
                sceneScale: $viewModel.sceneScale,
                sceneHorizontalOffset: $viewModel.sceneHorizontalOffset,
                sceneVerticalOffset: $viewModel.sceneVerticalOffset,
                showingConfirmation: false,
                viewModel: viewModel
            )
            .background(
                Color.clear
                    .background(.regularMaterial)
                    .ignoresSafeArea()
            )
        }
        .sheet(isPresented: $showingGraph) {
            GraphView(viewModel: viewModel)
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
                showInMenuBar: $viewModel.showInMenuBar,
                keepWindowInFront: $viewModel.keepWindowInFront,
                autoHideSummaryOnOverlap: $viewModel.autoHideSummaryOnOverlap,
                autoHideButtonsOnOverlap: $viewModel.autoHideButtonsOnOverlap,
                sceneScale: $viewModel.sceneScale,
                sceneHorizontalOffset: $viewModel.sceneHorizontalOffset,
                sceneVerticalOffset: $viewModel.sceneVerticalOffset,
                showingConfirmation: false,
                viewModel: viewModel
            )
            .background(
                Color.clear
                    .background(.regularMaterial)
                    .ignoresSafeArea()
            )
        }
        .fullScreenCover(isPresented: $showingGraph) {
            GraphView(viewModel: viewModel)
                .background(
                    Color.clear
                        .background(.regularMaterial)
                        .ignoresSafeArea()
                )
        }
#endif
        .onReceive(timer) { _ in
            precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"
            if showingSettings {
                return
            }
            if viewModel.ipAddress == "demo" {
                let homeLoad = Double(arc4random_uniform(4096)) + 256
                viewModel.data = PowerwallData(
                    battery: PowerwallData.Battery(instantPower: homeLoad * 0.2, count: 1),
                    load: PowerwallData.Load(instantPower: homeLoad),
                    solar: PowerwallData.Solar(
                        instantPower: homeLoad * 0.7,
                        energyExported: 409600
                    ),
                    site: PowerwallData.Site(instantPower: homeLoad * 0.1),
                    wallConnectors: [WallConnector(vin: "abc123", din: "def456", wallConnectorState: 1.0, wallConnectorPower: homeLoad * 0.05)]
                )
                viewModel.batteryPercentage = BatteryPercentage(percentage: 81)
                viewModel.gridStatus = GridStatus(status: "SystemGridConnected")
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
        .onReceive(timerTodaysTotal) { _ in
            if !viewModel.accessToken.isEmpty {
                viewModel.fetchSolarEnergyToday()
            }
        }
        .onReceive(timerElectricityMaps) { _ in
            viewModel.fetchElectricityMapsData()
        }
        .onAppear {
            precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"
            if demo {
                viewModel.ipAddress = "demo"
            }
            viewModel.fetchElectricityMapsData()
            if shouldAutoOpenSettingsOnLaunch {
                showingSettings = true
            } else if viewModel.ipAddress == "demo" {
                viewModel.data = PowerwallData(
                    battery: PowerwallData.Battery(instantPower: 256, count: 1),
                    load: PowerwallData.Load(instantPower: 2304),
                    solar: PowerwallData.Solar(
                        instantPower: 2048,
                        energyExported: 4096000
                    ),
                    site: PowerwallData.Site(instantPower: 1024),
                    wallConnectors: [WallConnector(vin: "abc123", din: "def456", wallConnectorState: 1.0, wallConnectorPower: 512)]
                )
                viewModel.batteryPercentage = BatteryPercentage(percentage: 100)
                //viewModel.gridStatus = GridStatus(status: "SystemIslandedActive")
                viewModel.siteName = "Home sweet home"
                // viewModel.errorMessage = "An error has occured"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startAnimations = true
                }
            } else {
                viewModel.fetchData()
                // Trigger animations after a slight delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startAnimations = true
                }
            }
#if !os(macOS)
            UIApplication.shared.isIdleTimerDisabled = viewModel.preventScreenSaver
#endif
        }
        .onDisappear {
            startAnimations = false
            cancelOverlayHideTask(.detachedSiteSummary)
            cancelOverlayHideTask(.controlsOverlay)
        }
#if os(macOS)
        .background(
            WindowChromeVisibilityConfigurator(
                isHidden: shouldHideWindowChrome,
                keepWindowInFront: viewModel.keepWindowInFront,
                onActivity: revealAutoHiddenOverlays
            )
        )
#endif
#if os(iOS)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    revealAutoHiddenOverlays()
                    handleSiteSwipe(value.translation)
                }
        )
#endif
#if !os(iOS)
        .onMoveCommand { direction in
            if direction == .up && viewModel.currentEnergySiteIndex > 0 {
                viewModel.currentEnergySiteIndex -= 1
                UserDefaults.standard.set(viewModel.currentEnergySiteIndex, forKey: "currentEnergySiteIndex")
                viewModel.fetchData()
                viewModel.fetchSolarEnergyToday()
                viewModel.fetchSiteInfo()
            }
            if direction == .down && viewModel.currentEnergySiteIndex < viewModel.energySites.count - 1 {
                viewModel.currentEnergySiteIndex += 1
                UserDefaults.standard.set(viewModel.currentEnergySiteIndex, forKey: "currentEnergySiteIndex")
                viewModel.fetchData()
                viewModel.fetchSolarEnergyToday()
                viewModel.fetchSiteInfo()
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
            guard !showingGraph else { return .ignored }
            updateEnergySite(-1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
            guard !showingGraph else { return .ignored }
            updateEnergySite(+1)
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { _ in
            exitFullScreenIfNeeded() ? .handled : .ignored
        }
#endif
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
        let hasWallConnector = !(viewModel.data?.wallConnectors.isEmpty ?? true)
        if !hasWallConnector {
            return "home.png"
        }
        let chargerActive = wallConnectorEnergyTotal(data: viewModel.data) > 10
            || wallConnectorDisplay(data: viewModel.data, precision: precision) == "Plugged in"
        return chargerActive ? "home-charger.png" : "home-charger-empty.png"
    }

    @ViewBuilder
    private func sceneOverlay(in sceneSize: CGSize, showSiteSummaryInScene: Bool) -> some View {
        if viewModel.ipAddress.isEmpty && viewModel.loginMode == .local {
            Text("Please configure the gateway settings.")
                .foregroundColor(.gray)
        } else if let data = viewModel.data {
            sceneDataOverlay(
                data: data,
                sceneSize: sceneSize,
                showSiteSummaryInScene: showSiteSummaryInScene
            )
                .foregroundColor(.white)
        } else {
            Group {
                if viewModel.loginMode == .fleetAPI && !hasFleetAccessTokenConfigured {
                    Button("Login with your Tesla account") {
                        _ = viewModel.startFleetLoginManually()
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Loading...")
                }
            }
            .opacity(0.6)
            .fontWeight(.bold)
            .font(labelFont(for: sceneSize))
            .foregroundColor(.white)
            .position(scenePoint(x: 0.03, y: 0.4, in: sceneSize))
        }
    }

    private func sceneDataOverlay(data: PowerwallData, sceneSize: CGSize, showSiteSummaryInScene: Bool) -> some View {
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

        return ZStack {
            if showSiteSummaryInScene {
                siteSummaryView(data: data, valueFont: valueFont, labelFont: labelFont, messageWidth: summaryMessageWidth)
                    .position(scenePoint(x: inlineSiteSummaryX, y: -0.38, in: sceneSize))
            }

            solarMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                .position(scenePoint(x: 0.087, y: -0.40, in: sceneSize))

            homeMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                .position(scenePoint(x: homeAndGridXPosition, y: -0.30, in: sceneSize))

            batteryMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                .position(scenePoint(x: 0.03, y: 0.40, in: sceneSize))

            if !data.wallConnectors.isEmpty {
                wallConnectorMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                    .position(scenePoint(x: -0.104, y: -0.40, in: sceneSize))
            }

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

            gridMetricView(data: data, valueFont: valueFont, labelFont: labelFont)
                .position(scenePoint(x: viewModel.gridFossilFuelPercentage != nil ? homeAndGridXPosition + gridCarbonXPosition : homeAndGridXPosition, y: 0.40, in: sceneSize))

            if animations && wallConnectorEnergyTotal(data: data) > 10 {
                PowerSurgeView(
                    color: data.solar.instantPower + wiggleWatts > data.battery.instantPower
                        ? .yellow
                        : data.battery.instantPower + wiggleWatts > data.site.instantPower ? .green : .gray,
                    isForward: wallConnectorEnergyTotal(data: data) < 0,
                    duration: 2,
                    lineWidth: surgeLineWidth,
                    curve: ChargerToCar(),
                    shouldStart: startAnimations
                )
                .frame(width: sceneWidth(0.024, in: sceneSize), height: sceneHeight(0.145, in: sceneSize))
                .position(scenePoint(x: -0.12, y: 0.13, in: sceneSize))
                .id("charger_\(wallConnectorEnergyTotal(data: data) < 0)_\(startAnimations)")
            }

            if animations && data.solar.instantPower > 10 {
                PowerSurgeView(
                    color: .yellow,
                    isForward: true,
                    duration: 2,
                    lineWidth: surgeLineWidth,
                    curve: SolarToGateway(),
                    shouldStart: startAnimations
                )
                .frame(width: sceneWidth(0.021, in: sceneSize), height: sceneHeight(0.242, in: sceneSize))
                .position(scenePoint(x: 0.097, y: 0.13, in: sceneSize))
                .id("solar_\(data.solar.instantPower < 0)_\(startAnimations)")
            }

            if animations && data.load.instantPower > 10 {
                PowerSurgeView(
                    color: data.solar.instantPower + wiggleWatts > data.battery.instantPower
                        ? .yellow
                        : data.battery.instantPower + wiggleWatts > data.site.instantPower ? .green : .gray,
                    isForward: true,
                    duration: 2,
                    startOffset: 1,
                    lineWidth: surgeLineWidth,
                    curve: GatewayToHome(),
                    shouldStart: startAnimations
                )
                .frame(width: sceneWidth(0.054, in: sceneSize), height: sceneHeight(0.056, in: sceneSize))
                .rotationEffect(Angle(degrees: 6))
                .position(scenePoint(x: 0.136, y: 0.142, in: sceneSize))
                .id("home_\(data.load.instantPower < 0)_\(startAnimations)")
            }

            if animations && (data.battery.instantPower > 10 || data.battery.instantPower < -10) {
                PowerSurgeView(
                    color: data.battery.instantPower > 0
                        ? .green
                        : data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : .gray,
                    isForward: data.battery.instantPower > 0,
                    duration: 2,
                    startOffset: data.battery.instantPower > 0 ? 0 : 1,
                    lineWidth: surgeLineWidth,
                    curve: PowerwallToGateway(),
                    shouldStart: startAnimations
                )
                .frame(width: sceneWidth(0.058, in: sceneSize), height: sceneHeight(0.065, in: sceneSize))
                .rotationEffect(Angle(degrees: 8))
                .position(scenePoint(x: 0.060, y: 0.176, in: sceneSize))
                .id("battery_\(data.battery.instantPower < 0)_\(startAnimations)")
            }

            if animations && !viewModel.isOffGrid() && (data.site.instantPower > 10 || data.site.instantPower < -10) {
                PowerSurgeView(
                    color: data.site.instantPower > 0
                        ? .gray
                        : data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : .green,
                    isForward: data.site.instantPower < 0,
                    duration: 2,
                    startOffset: data.site.instantPower > 0 ? 0 : 1,
                    lineWidth: surgeLineWidth,
                    curve: GatewayToGrid(),
                    shouldStart: startAnimations
                )
                .frame(width: sceneWidth(0.102, in: sceneSize), height: sceneHeight(0.134, in: sceneSize))
                .position(scenePoint(x: 0.152, y: 0.208, in: sceneSize))
                .id("grid_\(data.site.instantPower < 0)_\(startAnimations)")
            }

            if viewModel.isOffGrid() {
                offGridImage(sceneSize: sceneSize)
                    .position(scenePoint(x: 0.151, y: -0.003, in: sceneSize))
            }
        }
        .frame(width: sceneSize.width, height: sceneSize.height)
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
    }

    private func solarMetricView(data: PowerwallData, valueFont: Font, labelFont: Font) -> some View {
        VStack(spacing: 2) {
            Text("\(fmt(data.solar.instantPower / 1000)) kW")
                .fontWeight(.bold)
                .font(valueFont)
            Text("SOLAR")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(labelFont)
        }
        .multilineTextAlignment(.center)
    }

    private func homeMetricView(data: PowerwallData, valueFont: Font, labelFont: Font) -> some View {
        VStack(spacing: 2) {
            Text("\(fmt(homeEnergyToDisplay(data: data) / 1000)) kW")
                .fontWeight(.bold)
                .font(valueFont)
            Text("HOME")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(labelFont)
        }
        .multilineTextAlignment(.center)
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

            Text("POWERWALL\(viewModel.batteryCountString())")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(labelFont)
        }
        .multilineTextAlignment(.center)
    }

    private func wallConnectorMetricView(data: PowerwallData, valueFont: Font, labelFont: Font) -> some View {
        VStack(spacing: 2) {
            Text(wallConnectorDisplay(data: data, precision: precision))
                .fontWeight(.bold)
                .font(valueFont)
            Text("VEHICLE\(data.wallConnectors.count > 1 ? "S (\(data.wallConnectors.count))" : "")")
                .opacity(0.6)
                .fontWeight(.bold)
                .font(labelFont)
        }
        .multilineTextAlignment(.center)
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
            } else {
                Text("\(fmt(data.site.instantPower / 1000)) kW")
                    .fontWeight(.bold)
                    .font(valueFont)
            }

            Text("\(viewModel.isOffGrid() ? "OFF-" : "")GRID\(viewModel.gridCarbonIntensity.map { " · \($0) gCO2" } ?? "")")
                .opacity(viewModel.isOffGrid() ? 1.0 : 0.6)
                .fontWeight(.bold)
                .font(labelFont)
                .foregroundColor(viewModel.isOffGrid() ? .orange : .white)
        }
        .multilineTextAlignment(.center)
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

    private var controlsOverlay: some View {
        HStack {
            HStack {
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
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Settings")
                .environment(\.colorScheme, .dark)

                if viewModel.loginMode == .fleetAPI {
                    Button(action: {
                        revealAutoHiddenOverlays()
                        showingGraph = true
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
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityLabel("Chart")
                    .environment(\.colorScheme, .dark)
                }
            }
            .overlayChromeBackground(
                isVisible: !hideControlsOverlay,
                isOverlapping: controlsOverlayOverlapsScene && viewModel.autoHideButtonsOnOverlap
            )
            .opacity(hideControlsOverlay ? 0 : 1)
            .allowsHitTesting(!hideControlsOverlay)
            .reportFrame(.controlsOverlay)

            Spacer()
        }
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
        !frame.isEmpty && frame.intersects(sceneFrame)
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
#if os(macOS) || os(iOS)
        if overlaps && isAutoHideEnabled(kind) {
            if !isOverlayHidden(kind) {
                scheduleOverlayHide(for: kind)
            }
        } else {
            cancelOverlayHideTask(kind)
            setOverlayHidden(kind, hidden: false)
        }
#else
        _ = kind
        _ = overlaps
#endif
    }

    private func revealAutoHiddenOverlays() {
#if os(macOS) || os(iOS)
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
#endif
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
        let next = max(0, min(viewModel.currentEnergySiteIndex + delta,
                              max(0, viewModel.energySites.count - 1)))
        guard next != viewModel.currentEnergySiteIndex else { return }
        viewModel.currentEnergySiteIndex = next
        UserDefaults.standard.set(next, forKey: "currentEnergySiteIndex")
        viewModel.fetchData()
        viewModel.fetchSolarEnergyToday()
        viewModel.fetchSiteInfo()
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
        guard !showingGraph else { return }
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

    private func wallConnectorEnergyTotal(data: PowerwallData?) -> Double {
        return data?.wallConnectors.reduce(0.0) { $0 + ($1.wallConnectorPower ?? 0.0) } ?? 0.0
    }

    private func wallConnectorDisplay(data: PowerwallData?, precision: String) -> String {
        let hasCharging = data?.wallConnectors.contains { $0.wallConnectorState == 1.0 } ?? false
        if hasCharging {
            let powerKW = self.wallConnectorEnergyTotal(data: data!) / 1000
            return "\(fmt(powerKW)) kW"
        }
        let hasPluggedIn = data?.wallConnectors.contains { $0.wallConnectorState == 4.0 } ?? false
        if hasPluggedIn {
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

private enum OverlayAutoHideTarget {
    case detachedSiteSummary
    case controlsOverlay
}

private enum OverlayFrameKind: Hashable {
    case detachedSiteSummary
    case controlsOverlay
}

private struct OverlayFramePreferenceKey: PreferenceKey {
    static var defaultValue: [OverlayFrameKind: CGRect] = [:]

    static func reduce(value: inout [OverlayFrameKind: CGRect], nextValue: () -> [OverlayFrameKind: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#if os(macOS)
private struct WindowChromeVisibilityConfigurator: NSViewRepresentable {
    let isHidden: Bool
    let keepWindowInFront: Bool
    let onActivity: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onActivity: onActivity)
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMouseMove = context.coordinator.handleActivity
        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMouseMove = context.coordinator.handleActivity
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
        private var keyObserver: NSObjectProtocol?
        private let onActivity: () -> Void
        private var lastTrafficLightsHidden: Bool?
        private var lastKeepWindowInFront: Bool?

        init(onActivity: @escaping () -> Void) {
            self.onActivity = onActivity
        }

        func handleActivity() {
            onActivity()
        }

        func startObserving(window: NSWindow) {
            guard observedWindow !== window else { return }
            stopObserving(window: observedWindow)
            observedWindow = window
            lastTrafficLightsHidden = nil
            lastKeepWindowInFront = nil
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.handleActivity()
            }
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
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
                self.keyObserver = nil
            }
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

private extension View {
    private var overlayChromeDarkenOpacity: Double { 0.1 }

    @ViewBuilder
    func overlayChromeBackground(isVisible: Bool, isOverlapping: Bool) -> some View {
#if os(macOS) || os(iOS)
        if isVisible && isOverlapping {
            self
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.black.opacity(overlayChromeDarkenOpacity))
                                .blendMode(.multiply)
                        }
                }
        } else {
            self
        }
#else
        self
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

#if os(macOS)
enum MenuBarLabelMetric: String, CaseIterable, Identifiable {
    case solar, load, site, battery
    var id: String { rawValue }

    var title: String {
        switch self {
        case .solar: return "Solar"
        case .load: return "Home"
        case .site: return "Grid"
        case .battery: return "Battery"
        }
    }

    var symbol: String {
        switch self {
        case .solar: return "sun.max.fill"
        case .load: return "house.fill"
        case .site: return "bolt.horizontal.fill"
        case .battery: return "battery.100percent"
        }
    }

    var shortPrefix: String {
        switch self {
        case .solar: return "☀︎"
        case .load: return "⌂"
        case .site: return "⇄"
        case .battery: return "⚡︎"
        }
    }
}

private struct PowerwallMenuBarLabel: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @AppStorage("menuBarLabelMetric") private var menuBarLabelMetricRaw: String = MenuBarLabelMetric.solar.rawValue

    private var metric: MenuBarLabelMetric {
        MenuBarLabelMetric(rawValue: menuBarLabelMetricRaw) ?? .solar
    }

    private func batteryTrendGlyph(wiggleWatts: Double) -> String {
        let battWatts = viewModel.data?.battery.instantPower ?? 0
        if battWatts > wiggleWatts { return "↓" }
        if battWatts < -wiggleWatts { return "↑" }
        return ""
    }

    var body: some View {
        guard viewModel.showInMenuBar else { return AnyView(EmptyView()) }

        let precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"
        let trend = batteryTrendGlyph(wiggleWatts: 175.0)

        let solarKW = (viewModel.data?.solar.instantPower ?? 0) / 1000
        let loadKW  = (viewModel.data?.load.instantPower ?? 0) / 1000
        let siteKW  = (viewModel.data?.site.instantPower ?? 0) / 1000
        let batteryKW  = (viewModel.data?.battery.instantPower ?? 0) / 1000
        let batteryPercentage = viewModel.batteryPercentage?.percentage ?? 0

        let left: String = {
            func fmt(_ value: Double) -> String {
                formatPowerValue(value, precision: precision, showLessPrecision: viewModel.showLessPrecision)
            }
            switch metric {
            case .solar:
                return "\(metric.shortPrefix) \(fmt(solarKW)) kW"
            case .load:
                return "\(metric.shortPrefix) \(fmt(loadKW)) kW"
            case .site:
                return "\(metric.shortPrefix) \(fmt(siteKW)) kW"
            case .battery:
                return "\(metric.shortPrefix) \(fmt(batteryKW)) kW"
            }
        }()

        return AnyView(
            Text("\(left) · \(batteryPercentage, specifier: "%.0f")% \(trend)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        )
    }
}

private struct PowerwallMenuBarPopover: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @AppStorage("menuBarLabelMetric") private var menuBarLabelMetricRaw: String = MenuBarLabelMetric.solar.rawValue

    var body: some View {
        guard viewModel.showInMenuBar else { return AnyView(EmptyView()) }

        let precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"

        return AnyView(
            VStack(alignment: .center, spacing: 16) {

                Picker("Menu bar label", selection: $menuBarLabelMetricRaw) {
                    ForEach(MenuBarLabelMetric.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                let batteryPercentage = viewModel.batteryPercentage?.percentage ?? 0
                Gauge(value: batteryPercentage, in: 0...100) {
                    Label("Battery", systemImage: "bolt.fill")
                } currentValueLabel: {
                    Text("\(batteryPercentage, specifier: "%.0f")%")
                        .monospacedDigit()
                }
                .tint(batteryPercentage >= 60 ? .green : (batteryPercentage >= 25 ? .yellow : .red))
                .gaugeStyle(.accessoryCircular)
                .frame(width: 56, height: 56)

                HStack(alignment: .center, spacing: 20) {
                    VStack {
                        Text("\(formatPowerValue((viewModel.data?.solar.instantPower ?? 0) / 1000, precision: precision, showLessPrecision: viewModel.showLessPrecision)) kW")
                            .fontWeight(.bold)
                            .font(.title2)
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
                        Text("GRID")
                            .opacity(0.6)
                            .fontWeight(.bold)
                            .font(.subheadline)
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
