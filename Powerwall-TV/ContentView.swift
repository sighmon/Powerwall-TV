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
    @State private var animations = false
    @State private var showingSettings = false
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init() {
        let ip = UserDefaults.standard.string(forKey: "gatewayIP") ?? ""
        let username = UserDefaults.standard.string(forKey: "username") ?? ""
        let password = KeychainWrapper.standard.string(forKey: "gatewayPassword") ?? ""
        _viewModel = StateObject(wrappedValue: PowerwallViewModel(ipAddress: ip, username: username, password: password))
    }

    var body: some View {
        ZStack {
            Image(uiImage: UIImage(named: "home.png")!)
                .resizable()
                .ignoresSafeArea()
            ZStack {
                if viewModel.ipAddress.isEmpty {
                    Text("Please configure the gateway settings.")
                        .foregroundColor(.gray)
                } else if let data = viewModel.data {
                    ZStack {
                        VStack {
                            HStack {
                                VStack {
                                    Text("\(data.solar.energyExported / 1000, specifier: "%.0f") kWh")
                                        .fontWeight(.bold)
                                        .font(.headline)
                                    Text("ENERGY EXPORTED")
                                        .opacity(0.6)
                                        .fontWeight(.bold)
                                        .font(.footnote)
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
                                    Text("POWERWALL · \(data.battery.count, specifier: "%.0f")x")
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
                                    Text("GRID")
                                        .opacity(0.6)
                                        .fontWeight(.bold)
                                        .font(.footnote)
                                }
                            }
                        }
                        // Solar to Gateway animation
                        if animations && data.solar.instantPower > 10 {
                            HStack {
                                Spacer().frame(width: 370)
                                VStack {
                                    Spacer().frame(height: 285)
                                    PowerSurgeView(
                                        color: .yellow,
                                        direction: FlowDirection.forward,
                                        duration: 1,
                                        curve: SolarToGateway()
                                    )
                                    .frame(width: 40, height: 265)
                                }
                            }
                        }
                    }
                    .foregroundColor(.white)
                } else if let errorMessage = viewModel.errorMessage {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer().frame(width: 120)
                            VStack {
                                Text("Error: \(errorMessage)")
                                    .opacity(0.6)
                                    .fontWeight(.bold)
                                    .font(.footnote)
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
                                    .frame(width: 40, height: 40)
                                Image(systemName: "gear")
                                    .font(.title)
                            }
                        }
                        .accessibilityLabel("Settings")
                        Spacer()
                    }
                }
            }
            .padding()
            .sheet(isPresented: $showingSettings) {
                SettingsView(ipAddress: $viewModel.ipAddress, username: $viewModel.username, password: $viewModel.password)
            }
            .onReceive(timer) { _ in
                if viewModel.ipAddress == "demo" {
                    viewModel.data = PowerwallData(
                        battery: PowerwallData.Battery(instantPower: Double(arc4random_uniform(4096)) + 256, count: 1),
                        load: PowerwallData.Load(instantPower: Double(arc4random_uniform(4096)) + 256),
                        solar: PowerwallData.Solar(
                            instantPower: Double(arc4random_uniform(4096)) + 256,
                            energyExported: 409600
                        ),
                        site: PowerwallData.Site(instantPower: Double(arc4random_uniform(4096)) + 256)
                    )
                    viewModel.batteryPercentage = BatteryPercentage(percentage: 81)
                } else if !viewModel.ipAddress.isEmpty {
                    viewModel.fetchData()
                }
            }
            .onAppear {
                if viewModel.ipAddress.isEmpty {
                    showingSettings = true
                } else if viewModel.ipAddress == "demo" {
                    viewModel.data = PowerwallData(
                        battery: PowerwallData.Battery(instantPower: 256, count: 1),
                        load: PowerwallData.Load(instantPower: 256),
                        solar: PowerwallData.Solar(
                            instantPower: 2048,
                            energyExported: 4096000
                        ),
                        site: PowerwallData.Site(instantPower: 1024)
                    )
                    viewModel.batteryPercentage = BatteryPercentage(percentage: 100)
                } else {
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
