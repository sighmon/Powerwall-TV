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
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init() {
        _viewModel = StateObject(wrappedValue: PowerwallViewModel())
    }

    var body: some View {
        ZStack {
            Image(uiImage: UIImage(named: "home.png")!)
                .resizable()
                .ignoresSafeArea()
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
                                            .font(.headline)
                                            .padding(.bottom)
                                    }
                                    if data.solar.energyExported > 0 {
                                        Text("\(data.solar.energyExported / 1000, specifier: "%.0f") kWh")
                                            .fontWeight(.bold)
                                            .font(.headline)
                                        Text("ENERGY GENERATED")
                                            .opacity(0.6)
                                            .fontWeight(.bold)
                                            .font(.footnote)
                                            .padding(.bottom)
                                    }
                                    if let errorMessage = viewModel.errorMessage {
                                        Text("Error: \(errorMessage)")
                                            .fontWeight(.bold)
                                            .font(.footnote)
                                            .foregroundColor(.red)
                                    }
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                        VStack {
                            HStack {
                                Spacer().frame(width: 340)
                                VStack {
                                    Text("\(data.solar.instantPower / 1000, specifier: "%.3f") kW")
                                        .fontWeight(.bold)
                                        .font(.headline)
                                    Text("SOLAR")
                                        .opacity(0.6)
                                        .fontWeight(.bold)
                                        .font(.footnote)
                                }
                            }
                            Spacer()
                        }
                        VStack {
                            Spacer().frame(height: 100)
                            HStack {
                                Spacer().frame(width: 980)
                                VStack {
                                    Text("\(data.load.instantPower / 1000, specifier: "%.3f") kW")
                                        .fontWeight(.bold)
                                        .font(.headline)
                                    Text("HOME")
                                        .opacity(0.6)
                                        .fontWeight(.bold)
                                        .font(.footnote)
                                }
                            }
                            Spacer()
                        }
                        VStack {
                            Spacer()
                            HStack {
                                Spacer().frame(width: 120)
                                VStack {
                                    Text("\(data.battery.instantPower / 1000, specifier: "%.3f") kW · \(viewModel.batteryPercentage?.percentage ?? 0, specifier: "%.1f")%")
                                        .fontWeight(.bold)
                                        .font(.headline)
                                    Text("POWERWALL\(viewModel.batteryCountString())")
                                        .opacity(0.6)
                                        .fontWeight(.bold)
                                        .font(.footnote)
                                }
                            }
                        }
                        HStack {
                            Spacer().frame(width: 59)
                            VStack {
                                Spacer().frame(height: 526)
                                GeometryReader { geometry in
                                    Rectangle()
                                        .fill(Color.green) // Lime green color
                                        .frame(width: 5, height: geometry.size.height * (viewModel.batteryPercentage?.percentage ?? 0 / 100))
                                        .cornerRadius(1)
                                }
                                .frame(width: 0.8, height: 0.84)
                                    .rotationEffect(Angle(degrees: 180))
                            }
                        }
                        VStack {
                            Spacer()
                            HStack {
                                Spacer().frame(width: 980)
                                VStack {
                                    Text("\(data.site.instantPower / 1000, specifier: "%.3f") kW")
                                        .fontWeight(.bold)
                                        .font(.headline)
                                    Text("\(viewModel.isOffGrid() ? "OFF-" : "")GRID")
                                        .opacity(viewModel.isOffGrid() ? 1.0 : 0.6)
                                        .fontWeight(.bold)
                                        .font(.footnote)
                                        .foregroundColor(viewModel.isOffGrid() ? .orange : .white)
                                }
                            }
                        }
                        // Solar to Gateway animation
                        if animations && data.solar.instantPower > 10 {
                            HStack {
                                Spacer().frame(width: 370)
                                VStack {
                                    Spacer().frame(height: 300)
                                    PowerSurgeView(
                                        color: .yellow,
                                        isForward: true,
                                        duration: 2,
                                        curve: SolarToGateway(),
                                        shouldStart: startAnimations
                                    )
                                    .frame(width: 40, height: 295)
                                    .id("solar_\(data.solar.instantPower < 0)_\(startAnimations)")
                                }
                            }
                        }
                        // Gateway to Home animation
                        if animations && data.load.instantPower > 10 {
                            HStack {
                                Spacer().frame(width: 530)
                                VStack {
                                    Spacer().frame(height: 295)
                                    PowerSurgeView(
                                        color: data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : data.battery.instantPower + wiggleWatts > data.site.instantPower ? .green : .gray,
                                        isForward: true,
                                        duration: 2,
                                        startOffset: 1,
                                        curve: GatewayToHome(),
                                        shouldStart: startAnimations
                                    )
                                    .frame(width: 110, height: 60)
                                    .id("home_\(data.load.instantPower < 0)_\(startAnimations)")
                                }
                            }
                        }
                        // Powerwall to Gateway animation
                        if animations && (data.battery.instantPower > 10 || data.battery.instantPower < -10) {
                            HStack {
                                Spacer().frame(width: 240)
                                VStack {
                                    Spacer().frame(height: 360)
                                    PowerSurgeView(
                                        color: data.battery.instantPower > 0 ? .green : data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : .gray,
                                        isForward: data.battery.instantPower > 0,
                                        duration: 2,
                                        startOffset: data.battery.instantPower > 0 ? 0 : 1,
                                        curve: PowerwallToGateway(),
                                        shouldStart: startAnimations
                                    )
                                    .frame(width: 125, height: 60)
                                    .id("battery_\(data.battery.instantPower < 0)_\(startAnimations)")
                                }
                            }
                        }
                        // Gateway to Grid animation
                        if animations && !viewModel.isOffGrid() && (data.site.instantPower > 10 || data.site.instantPower < -10) {
                            HStack {
                                Spacer().frame(width: 580)
                                VStack {
                                    Spacer().frame(height: 462)
                                    PowerSurgeView(
                                        color: data.site.instantPower > 0 ? .gray : data.solar.instantPower + wiggleWatts > data.battery.instantPower ? .yellow : .green,
                                        isForward: data.site.instantPower < 0,
                                        duration: 2,
                                        startOffset: data.site.instantPower > 0 ? 0 : 1,
                                        curve: GatewayToGrid(),
                                        shouldStart: startAnimations
                                    )
                                    .frame(width: 190, height: 120)
                                    .id("grid_\(data.site.instantPower < 0)_\(startAnimations)")
                                }
                            }
                        }
                        if viewModel.isOffGrid() {
                            HStack {
                                Spacer().frame(width: 580)
                                VStack {
                                    Spacer().frame(height: 505)
                                    Image(uiImage: UIImage(named: "off-grid.png")!)
                                        .resizable()
                                        .frame(width: 100, height: 60)
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
                                    .font(.footnote)
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
                                Circle()
                                    .fill(Color.gray)
                                    .frame(width: 30, height: 30)
                                Image(systemName: "gear")
                                    .font(.title2)
                                    .frame(width: 80, height: 80)
                            }
                        }
                        .accessibilityLabel("Settings")

                        if viewModel.loginMode == .fleetAPI {
                            Button(action: {
                                showingGraph = true
                            }) {
                                ZStack {
                                    Image(systemName: "chart.bar.xaxis.ascending.badge.clock")
                                        .font(.title3)
                                        .frame(width: 80, height: 80)
                                }
                            }
                            .accessibilityLabel("Chart")
                        }
                        Spacer()
                    }
                }
            }
            .padding()
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    loginMode: $viewModel.loginMode,
                    ipAddress: $viewModel.ipAddress,
                    username: $viewModel.username,
                    password: $viewModel.password,
                    accessToken: $viewModel.accessToken,
                    preventScreenSaver: $viewModel.preventScreenSaver,
                    showingConfirmation: false
                )
            }
            .sheet(isPresented: $showingGraph) {
                GraphView(viewModel: viewModel)
            }
            .onReceive(timer) { _ in
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
                } else if !viewModel.ipAddress.isEmpty {
                    viewModel.fetchData()
                }
            }
            .onAppear {
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
                UIApplication.shared.isIdleTimerDisabled = viewModel.preventScreenSaver
            }
            .onDisappear {
                startAnimations = false
            }
            .onMoveCommand { direction in
                if direction == .up && viewModel.currentEnergySiteIndex > 0 {
                    viewModel.currentEnergySiteIndex -= 1
                    UserDefaults.standard.set(viewModel.currentEnergySiteIndex, forKey: "currentEnergySiteIndex")
                    viewModel.fetchData()
                }
                if direction == .down && viewModel.currentEnergySiteIndex < viewModel.energySites.count - 1 {
                    viewModel.currentEnergySiteIndex += 1
                    UserDefaults.standard.set(viewModel.currentEnergySiteIndex, forKey: "currentEnergySiteIndex")
                    viewModel.fetchData()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
