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
    @State private var showingSettings = false
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init() {
        let ip = UserDefaults.standard.string(forKey: "gatewayIP") ?? ""
        let username = UserDefaults.standard.string(forKey: "username") ?? ""
        let password = KeychainWrapper.standard.string(forKey: "gatewayPassword") ?? ""
        _viewModel = StateObject(wrappedValue: PowerwallViewModel(ipAddress: ip, username: username, password: password))
    }

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.ipAddress.isEmpty {
                Text("Please configure the gateway settings.")
                    .foregroundColor(.gray)
            } else if let data = viewModel.data {
                Text("⚡️ Grid: \(data.site.instantPower / 1000, specifier: "%.3f") kW")
                Text("🔋 Powerwall: \(data.battery.instantPower / 1000, specifier: "%.3f") kW")
                Text("🏡 Home: \(data.load.instantPower / 1000, specifier: "%.3f") kW")
                Text("☀️ Solar: \(data.solar.instantPower / 1000, specifier: "%.3f") kW")
                Text("💛 Total: \(data.solar.energyExported / 1000, specifier: "%.0f") kWh")
            } else if let errorMessage = viewModel.errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
            } else {
                Text("Loading...")
            }

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
            .padding(.top, 100)
        }
        .padding()
        .sheet(isPresented: $showingSettings) {
            SettingsView(ipAddress: $viewModel.ipAddress, username: $viewModel.username, password: $viewModel.password)
        }
        .onReceive(timer) { _ in
            if !viewModel.ipAddress.isEmpty {
                viewModel.fetchData()
            }
        }
        .onAppear {
            if viewModel.ipAddress.isEmpty {
                showingSettings = true
            } else {
                viewModel.fetchData()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
