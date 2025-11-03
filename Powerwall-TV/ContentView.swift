//
//  ContentView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//

import SwiftUI
import SwiftData


struct ContentView: View {
    @StateObject private var viewModel: PowerwallViewModel
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

    init() {
        _viewModel = StateObject(wrappedValue: PowerwallViewModel())
    }

    var body: some View {
        ZStack {
#if os(macOS)
            Image(nsImage: NSImage(named: "home.png")!)
                .resizable()
                .scaledToFit()
#else
            Image(uiImage: UIImage(named: "home.png")!)
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
                                    if let errorMessage = viewModel.errorMessage {
                                        Text("Error: \(errorMessage)")
                                            .fontWeight(.bold)
#if os(macOS)
                                            .font(.subheadline)
#else
                                            .font(.footnote)
#endif
                                            .foregroundColor(.red)
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
                                    Text("\(data.load.instantPower / 1000, specifier: precision) kW")
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
                                    Text("\(data.battery.instantPower / 1000, specifier: precision) kW · \(viewModel.batteryPercentage?.percentage ?? 0, specifier: "%.1f")%")
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
                        HStack {
#if os(macOS)
                            Spacer().frame(width: 40)
#else
                            Spacer().frame(width: 59)
#endif
                            VStack {
#if os(macOS)
                                Spacer().frame(height: 350)
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
                                Spacer().frame(width: 980)
#endif
                                VStack {
                                    Text("\(data.site.instantPower / 1000, specifier: precision) kW")
                                        .fontWeight(.bold)
#if os(macOS)
                                        .font(.title2)
#else
                                        .font(.headline)
#endif
                                    Text("\(viewModel.isOffGrid() ? "OFF-" : "")GRID")
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
                        // Solar to Gateway animation
                        if animations && data.solar.instantPower > 10 {
                            HStack {
#if os(macOS)
                                Spacer().frame(width: 240)
#else
                                Spacer().frame(width: 370)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 195)
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
#else
                                Spacer().frame(width: 530)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 164)
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
#else
                                Spacer().frame(width: 240)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 260)
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
#else
                                Spacer().frame(width: 580)
#endif
                                VStack {
#if os(macOS)
                                    Spacer().frame(height: 300)
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
#if os(macOS)
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
#if os(macOS)
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
                    username: $viewModel.username,
                    password: $viewModel.password,
                    accessToken: $viewModel.accessToken,
                    fleetBaseURL: $viewModel.fleetBaseURL,
                    preventScreenSaver: $viewModel.preventScreenSaver,
                    showLessPrecision: $viewModel.showLessPrecision,
                    showingConfirmation: false
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
                    username: $viewModel.username,
                    password: $viewModel.password,
                    accessToken: $viewModel.accessToken,
                    fleetBaseURL: $viewModel.fleetBaseURL,
                    preventScreenSaver: $viewModel.preventScreenSaver,
                    showLessPrecision: $viewModel.showLessPrecision,
                    showingConfirmation: false
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
                        site: PowerwallData.Site(instantPower: homeLoad * 0.1)
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
            .onAppear {
                precision = viewModel.showLessPrecision ? "%.1f" : "%.3f"
                if demo {
                    viewModel.ipAddress = "demo"
                }
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
                        site: PowerwallData.Site(instantPower: 0)
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
            .onMoveCommand { direction in
                if direction == .up && viewModel.currentEnergySiteIndex > 0 {
                    viewModel.currentEnergySiteIndex -= 1
                    UserDefaults.standard.set(viewModel.currentEnergySiteIndex, forKey: "currentEnergySiteIndex")
                    viewModel.fetchData()
                    viewModel.fetchSolarEnergyToday()
                }
                if direction == .down && viewModel.currentEnergySiteIndex < viewModel.energySites.count - 1 {
                    viewModel.currentEnergySiteIndex += 1
                    UserDefaults.standard.set(viewModel.currentEnergySiteIndex, forKey: "currentEnergySiteIndex")
                    viewModel.fetchData()
                    viewModel.fetchSolarEnergyToday()
                }
            }
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
            updateEnergySite(-1)
            return .handled
        }
        .onKeyPress(.downArrow, phases: .down) { _ in
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
