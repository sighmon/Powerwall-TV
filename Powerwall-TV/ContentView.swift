//
//  ContentView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//

import SwiftUI
import SwiftData


struct ContentView: View {
    @ObservedObject var viewModel: PowerwallViewModel
    @State private var demo = false
    @State private var animations = true
    @State private var showingSettings = false
    @State private var showingGraph = false
    @State private var wiggleWatts = 40.0
    @State private var startAnimations = false
    @State private var precision = "%.3f"
    @FocusState private var hasKeyboardFocus: Bool
#if os(macOS)
    private let powerwallPercentageWidth: Double = 4
#else
    private let powerwallPercentageWidth: Double = 5
#endif
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private let timerTodaysTotal = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let timerElectricityMaps = Timer.publish(every: 900, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
#if os(macOS)
            Image(nsImage: NSImage(named: viewModel.data?.wallConnectors.isEmpty ?? true ? "home.png" : wallConnectorEnergyTotal(data: viewModel.data) > 10 || wallConnectorDisplay(data: viewModel.data, precision: precision) == "Plugged in" ? "home-charger.png" : "home-charger-empty.png")!)
                .resizable()
                .scaledToFit()
#elseif os(iOS)
            Image(uiImage: UIImage(named: viewModel.data?.wallConnectors.isEmpty ?? true ? "home.png" : wallConnectorEnergyTotal(data: viewModel.data) > 10 || wallConnectorDisplay(data: viewModel.data, precision: precision) == "Plugged in" ? "home-charger.png" : "home-charger-empty.png")!)
                .resizable()
                .scaledToFit()
#else
            Image(uiImage: UIImage(named: viewModel.data?.wallConnectors.isEmpty ?? true ? "home.png" : wallConnectorEnergyTotal(data: viewModel.data) > 10 || wallConnectorDisplay(data: viewModel.data, precision: precision) == "Plugged in" ? "home-charger.png" : "home-charger-empty.png")!)
                .resizable()
                .ignoresSafeArea()
#endif
            ZStack {
                if (viewModel.ipAddress.isEmpty && viewModel.loginMode == .local) {
                    Text("Please configure the gateway settings.")
                        .foregroundColor(.gray)
                } else if let data = viewModel.data {
                    ZStack {
                        VStack {
                            HStack {
                                VStack {
                                    if (viewModel.siteName != nil) {
                                        Text(viewModel.siteName ?? "")
                                            .fontWeight(.bold)
#if os(macOS)
                                            .font(.title2)
#else
                                            .font(.headline)
#endif
                                            .padding(.bottom)
                                    }
                                    if data.solar.energyExported > 0 || (viewModel.solarEnergyTodayWh != nil) {
                                        let exportedEnergy = (data.solar.energyExported > 0 ? data.solar.energyExported : viewModel.solarEnergyTodayWh ?? 0) / 1000
                                        let specifier = exportedEnergy < 1000 ? precision : "%.0f"
                                        Text("\(exportedEnergy, specifier: specifier) kWh")
                                            .fontWeight(.bold)
#if os(macOS)
                                            .font(.title2)
#else
                                            .font(.headline)
#endif
                                        Text("ENERGY GENERATED \(data.solar.energyExported > 0 ? "" : "TODAY")")
                                            .opacity(0.6)
                                            .fontWeight(.bold)
#if os(macOS)
                                            .font(.subheadline)
#else
                                            .font(.footnote)
#endif
                                            .padding(.bottom)
                                    }
                                    if let message = viewModel.errorMessage ?? viewModel.infoMessage {
                                        Text("\((viewModel.errorMessage != nil) ? "Error: " : "")\(message)")
                                            .fontWeight(.bold)
#if os(macOS)
                                            .font(.subheadline)
#else
                                            .font(.footnote)
#endif
                                            .foregroundColor(viewModel.errorMessage != nil ? .red : .green)
                                            .opacity(viewModel.errorMessage != nil ? 1.0 : 0.6)
                                            .frame(width: 200)
                                    }
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                        VStack {
#if os(macOS)
                            Spacer().frame(height: 60)
#endif
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 220)
#else
                                Spacer().frame(width: 340)
#endif
                                VStack {
                                    Text("\(data.solar.instantPower / 1000, specifier: precision) kW")
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.title2)
#else
                                        .font(.headline)
#endif
                                    Text("SOLAR")
                                        .opacity(0.6)
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.subheadline)
#else
                                        .font(.footnote)
#endif
                                }
                            }
                            Spacer()
                        }
                        VStack {
#if os(macOS)
                            Spacer().frame(height: 120)
#else
                            Spacer().frame(height: 100)
#endif
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 600)
#else
                                Spacer().frame(width: 980)
#endif
                                VStack {
                                    Text("\(self.homeEnergyToDisplay(data: data) / 1000, specifier: precision) kW")
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.title2)
#else
                                        .font(.headline)
#endif
                                    Text("HOME")
                                        .opacity(0.6)
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.subheadline)
#else
                                        .font(.footnote)
#endif
                                }
                            }
                            Spacer()
                        }
                        VStack {
                            Spacer()
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 80)
#else
                                Spacer().frame(width: 120)
#endif
                                VStack {
                                    (
                                        Text("\(data.battery.instantPower / 1000, specifier: precision) kW ")
                                        + Text(self.batteryArrow(wiggleWatts: wiggleWatts))
                                            .foregroundColor(data.battery.instantPower > wiggleWatts || data.battery.instantPower < -wiggleWatts ? .green : .white)
                                        + Text(" \(viewModel.batteryPercentage?.percentage ?? 0, specifier: "%.1f")%")
                                    )
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.title2)
#else
                                        .font(.headline)
#endif

                                    Text("POWERWALL\(viewModel.batteryCountString())")
                                        .opacity(0.6)
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.subheadline)
#else
                                        .font(.footnote)
#endif
                                }
                            }
#if os(macOS)
                            Spacer().frame(height: 60)
#endif
                        }
                        if !data.wallConnectors.isEmpty {
                            VStack {
    #if os(macOS)
                                Spacer().frame(height: 60)
    #endif
                                HStack {
                                    VStack {
                                        Text(self.wallConnectorDisplay(data: data, precision: precision))
                                            .fontWeight(.bold)
    #if os(macOS)
                                            .font(.title2)
    #else
                                            .font(.headline)
    #endif
                                        Text("VEHICLE\(data.wallConnectors.count > 1 ? "S (\(data.wallConnectors.count))" : "")")
                                            .opacity(0.6)
                                            .fontWeight(.bold)
    #if os(macOS)
                                            .font(.subheadline)
    #else
                                            .font(.footnote)
    #endif
                                    }
    #if os(macOS)
                                    Spacer().frame(width: 260)
    #else
                                    Spacer().frame(width: 390)
    #endif
                                }
                                Spacer()
                            }
                        }
                        HStack {
#if os(macOS)
                            Spacer().frame(width: 40)
#elseif os(iOS)
                            Spacer().frame(width: 40)
#else
                            Spacer().frame(width: 59)
#endif
                            VStack {
#if os(macOS)
                                Spacer().frame(height: 350)
#elseif os(iOS)
                                Spacer().frame(height: 375)
#else
                                Spacer().frame(height: 526)
#endif
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(Color.green) // Lime green color
                                        .frame(width: powerwallPercentageWidth, height: geometry.size.height * (viewModel.batteryPercentage?.percentage ?? 0 / 100))
                                        .cornerRadius(1)
                                }
#if os(macOS)
                                    .frame(width: 0.8, height: 0.54)
#elseif os(iOS)
                                    .frame(width: 0.8, height: 0.58)
#else
                                    .frame(width: 0.8, height: 0.84)
#endif
                                    .rotationEffect(Angle(degrees: 180))
                            }
                        }
                        VStack {
                            Spacer()
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 510)
#else
                                Spacer().frame(width: viewModel.gridFossilFuelPercentage != nil ? 1140 : 980)
#endif
                                VStack {
                                    if let fossil = viewModel.gridFossilFuelPercentage {
                                        let renewables = max(0, min(100, 100 - fossil))
                                        (
                                            Text("\(data.site.instantPower / 1000, specifier: precision) kW")
                                            + Text(" · ")
                                            + Text(String(format: "%.1f%%", renewables))
                                                .foregroundColor(renewablesColor(renewables))
                                        )
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.title2)
#else
                                        .font(.headline)
#endif
                                    } else {
                                        Text("\(data.site.instantPower / 1000, specifier: precision) kW")
                                            .fontWeight(.bold)
#if os(macOS)
                                            .font(.title2)
#else
                                            .font(.headline)
#endif
                                    }
                                    Text("\(viewModel.isOffGrid() ? "OFF-" : "")GRID\(viewModel.gridCarbonIntensity.map { " · \($0) gCO2" } ?? "")")
                                        .opacity(viewModel.isOffGrid() ? 1.0 : 0.6)
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.subheadline)
#else
                                        .font(.footnote)
#endif
                                        .foregroundColor(viewModel.isOffGrid() ? .orange : .white)
                                }
                            }
#if os(macOS)
                            Spacer().frame(height: 20)
#endif
                        }
                        // Wall Connector to car animation
                        if animations && self.wallConnectorEnergyTotal(data: data) > 10 {
                            HStack {
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 190)
#elseif os(iOS)
                                    Spacer().frame(height: 200)
#else
                                    Spacer().frame(height: 265)
#endif
                                    PowerSurgeView(
                                        color: data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : data.battery.instantPower + wiggleWatts > data.site.instantPower ? .green : .gray,
                                        isForward: self.wallConnectorEnergyTotal(data: data) < 0,
                                        duration: 2,
                                        curve: ChargerToCar(),
                                        shouldStart: startAnimations
                                    )
#if os(macOS)
                                    .frame(width: 40, height: 115)
#elseif os(iOS)
                                    .frame(width: 40, height: 115)
#else
                                    .frame(width: 45, height: 155)
#endif
                                    .id("charger_\(self.wallConnectorEnergyTotal(data: data) < 0)_\(startAnimations)")
                                }
#if os(macOS)
                                Spacer().frame(width: 305)
#elseif os(iOS)
                                Spacer().frame(width: 325)
#else
                                Spacer().frame(width: 465)
#endif
                            }
                        }
                        // Solar to Gateway animation
                        if animations && data.solar.instantPower > 10 {
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 240)
#elseif os(iOS)
                                Spacer().frame(width: 260)
#else
                                Spacer().frame(width: 370)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 195)
#elseif os(iOS)
                                    Spacer().frame(height: 205)
#else
                                    Spacer().frame(height: 300)
#endif
                                    PowerSurgeView(
                                        color: .yellow,
                                        isForward: true,
                                        duration: 2,
                                        curve: SolarToGateway(),
                                        shouldStart: startAnimations
                                    )
#if os(macOS)
                                    .frame(width: 40, height: 190)
#elseif os(iOS)
                                    .frame(width: 40, height: 190)
#else
                                    .frame(width: 40, height: 295)
#endif
                                    .id("solar_\(data.solar.instantPower < 0)_\(startAnimations)")
                                }
                            }
                        }
                        // Gateway to Home animation
                        if animations && data.load.instantPower > 10 {
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 350)
#elseif os(iOS)
                                Spacer().frame(width: 370)
#else
                                Spacer().frame(width: 530)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 164)
#elseif os(iOS)
                                    Spacer().frame(height: 178)
#else
                                    Spacer().frame(height: 295)
#endif
                                    PowerSurgeView(
                                        color: data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : data.battery.instantPower + wiggleWatts > data.site.instantPower ? .green : .gray,
                                        isForward: true,
                                        duration: 2,
                                        startOffset: 1,
                                        curve: GatewayToHome(),
                                        shouldStart: startAnimations
                                    )
#if os(macOS)
                                    .frame(width: 70, height: 2)
                                    .rotationEffect(Angle(degrees: 7))
#elseif os(iOS)
                                    .frame(width: 70, height: 2)
                                    .rotationEffect(Angle(degrees: 7))
#else
                                    .frame(width: 110, height: 60)
#endif
                                    .id("home_\(data.load.instantPower < 0)_\(startAnimations)")
                                }
                            }
                        }
                        // Powerwall to Gateway animation
                        if animations && (data.battery.instantPower > 10 || data.battery.instantPower < -10) {
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 150)
#elseif os(iOS)
                                Spacer().frame(width: 165)
#else
                                Spacer().frame(width: 240)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 260)
#elseif os(iOS)
                                    Spacer().frame(height: 267)
#else
                                    Spacer().frame(height: 360)
#endif
                                    PowerSurgeView(
                                        color: data.battery.instantPower > 0 ? .green : data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : .gray,
                                        isForward: data.battery.instantPower > 0,
                                        duration: 2,
                                        startOffset: data.battery.instantPower > 0 ? 0 : 1,
                                        curve: PowerwallToGateway(),
                                        shouldStart: startAnimations
                                    )
#if os(macOS)
                                    .frame(width: 72, height: 60)
                                    .rotationEffect(Angle(degrees: 9))
#elseif os(iOS)
                                    .frame(width: 78, height: 50)
                                    .rotationEffect(Angle(degrees: 7))
#else
                                    .frame(width: 125, height: 60)
#endif
                                    .id("battery_\(data.battery.instantPower < 0)_\(startAnimations)")
                                }
                            }
                        }
                        // Gateway to Grid animation
                        if animations && !viewModel.isOffGrid() && (data.site.instantPower > 10 || data.site.instantPower < -10) {
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 390)
#elseif os(iOS)
                                Spacer().frame(width: 410)
#else
                                Spacer().frame(width: 580)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 300)
#elseif os(iOS)
                                    Spacer().frame(height: 320)
#else
                                    Spacer().frame(height: 462)
#endif
                                    PowerSurgeView(
                                        color: data.site.instantPower > 0 ? .gray : data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : .green,
                                        isForward: data.site.instantPower < 0,
                                        duration: 2,
                                        startOffset: data.site.instantPower > 0 ? 0 : 1,
                                        curve: GatewayToGrid(),
                                        shouldStart: startAnimations
                                    )
#if os(macOS)
                                    .frame(width: 130, height: 98)
                                    .rotationEffect(Angle(degrees: 0))
#elseif os(iOS)
                                    .frame(width: 130, height: 98)
                                    .rotationEffect(Angle(degrees: 0))
#else
                                    .frame(width: 190, height: 120)
#endif
                                    .id("grid_\(data.site.instantPower < 0)_\(startAnimations)")
                                }
                            }
                        }
                        if viewModel.isOffGrid() {
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 380)
#else
                                Spacer().frame(width: 580)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 335)
                                    Image(nsImage: NSImage(named: "off-grid.png")!)
                                        .resizable()
                                        .frame(width: 80, height: 48)
#else
                                    Spacer().frame(height: 505)
                                    Image(uiImage: UIImage(named: "off-grid.png")!)
                                        .resizable()
                                        .frame(width: 100, height: 60)
#endif
                                }
                            }
                        }
                    }
                    .foregroundColor(.white)
                } else {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer().frame(width: 120)
                            VStack {
                                Text("Loading...")
                                    .opacity(0.6)
                                    .fontWeight(.bold)
#if os(macOS)
                                    .font(.subheadline)
#else
                                    .font(.footnote)
#endif
                            }
                        }
                    }
                    .foregroundColor(.white)
                }

                VStack {
                    Spacer()
                    HStack {
                        Button(action: {
                            showingSettings = true
                        }) {
                            ZStack {
                                Image(systemName: "gear")
#if os(macOS) || os(iOS)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.primary)
                                    .font(.system(size: 20, weight: .semibold))
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
                                showingGraph = true
                            }) {
                                ZStack {
                                    Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
#if os(macOS) || os(iOS)
                                        .font(.system(size: 18, weight: .semibold))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.primary)
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
                        Spacer()
                    }
                }
            }
            .padding()
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
                } else if !viewModel.ipAddress.isEmpty || !viewModel.accessToken.isEmpty {
                    viewModel.fetchData()
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
                if viewModel.ipAddress.isEmpty && viewModel.loginMode == .local {
                    showingSettings = true
                } else if viewModel.ipAddress == "demo" {
                    viewModel.data = PowerwallData(
                        battery: PowerwallData.Battery(instantPower: 256, count: 1),
                        load: PowerwallData.Load(instantPower: 2304),
                        solar: PowerwallData.Solar(
                            instantPower: 2048,
                            energyExported: 4096000
                        ),
                        site: PowerwallData.Site(instantPower: 0),
                        wallConnectors: [WallConnector(vin: "abc123", din: "def456", wallConnectorState: 1.0, wallConnectorPower: 512)]
                    )
                    viewModel.batteryPercentage = BatteryPercentage(percentage: 100)
                    viewModel.gridStatus = GridStatus(status: "SystemIslandedActive")
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
            }
#if os(iOS)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
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
        }
        .background(Color(red: 22/255, green: 23/255, blue: 24/255))
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
#endif
    }

    private func updateEnergySite(_ delta: Int) {
        let next = max(0, min(viewModel.currentEnergySiteIndex + delta,
                              max(0, viewModel.energySites.count - 1)))
        guard next != viewModel.currentEnergySiteIndex else { return }
        viewModel.currentEnergySiteIndex = next
        UserDefaults.standard.set(next, forKey: "currentEnergySiteIndex")
        viewModel.fetchData()
        viewModel.fetchSolarEnergyToday()
        viewModel.fetchSiteInfo()
    }

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
        String(format: precision, value)
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
                String(format: precision, value)
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
                        Text("\((viewModel.data?.solar.instantPower ?? 0) / 1000, specifier: precision) kW")
                            .fontWeight(.bold)
                            .font(.title2)
                        Text("SOLAR")
                            .opacity(0.6)
                            .fontWeight(.bold)
                            .font(.subheadline)
                    }
                    .frame(width: 100)

                    VStack {
                        Text("\((viewModel.data?.load.instantPower ?? 0) / 1000, specifier: precision) kW")
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
                        Text("\((viewModel.data?.battery.instantPower ?? 0) / 1000, specifier: precision) kW")
                            .fontWeight(.bold)
                            .font(.title2)
                        Text("POWERWALL")
                            .opacity(0.6)
                            .fontWeight(.bold)
                            .font(.subheadline)
                    }
                    .frame(width: 100)

                    VStack {
                        Text("\((viewModel.data?.site.instantPower ?? 0) / 1000, specifier: precision) kW")
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
