//
//  SettingsView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//


import SwiftUI

struct SettingsView: View {
    @Binding var loginMode: LoginMode
    @Binding var ipAddress: String
    @Binding var wallConnectorIPAddress: String
    @Binding var username: String
    @Binding var password: String
    @Binding var accessToken: String
    @Binding var fleetBaseURL: String
    @Binding var electricityMapsAPIKey: String
    @Binding var electricityMapsZone: String
    @Binding var preventScreenSaver: Bool
    @Binding var showLessPrecision: Bool
    @Binding var showInMenuBar: Bool
    @State var showingConfirmation: Bool
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: PowerwallViewModel

    var body: some View {
#if os(macOS)
        macOSBody
#else
        tvOSBody
#endif
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            // Section for selecting login mode
            Section(header: Text("Login Mode")) {
                Picker("Mode", selection: $loginMode) {
                    Text("Local").tag(LoginMode.local)
                    Text("Fleet API").tag(LoginMode.fleetAPI)
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Gateway settings section, shown only for local mode
            if loginMode == .local {
                Section(header: Text("Gateway Settings")) {
                    TextField("IP Address", text: $ipAddress)
                        .textContentType(.URL)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                Section(header: Text("Wall Connector Settings")) {
                    TextField("IP Address", text: $wallConnectorIPAddress)
                        .textContentType(.URL)
                }
            } else {
                Section(header: Text("Fleet API Settings")) {
                    SecureField("Access token", text: $accessToken)
                        .textContentType(.password)
                }
            }

            // New section for screen saver prevention
            Section(header: Text("Electricity Maps Settings")) {
                SecureField("API key", text: $electricityMapsAPIKey)
                    .textContentType(.password)
                TextField("Zone (e.g. AU-SA)", text: $electricityMapsZone)
            }

            Section(header: Text("Display Settings")) {
#if os(macOS)
                Toggle("Show in menu bar", isOn: $showInMenuBar)
#endif
                Toggle("Limit data to one decimal place", isOn: $showLessPrecision)
                Toggle("Prevent screen saver from showing", isOn: $preventScreenSaver)
                if preventScreenSaver {
                    Text("Warning: keeping the screen on may increase power usage and risk burn-in.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                }
            }

            if loginMode == .fleetAPI {
                Section(header: Text("Delete all settings")) {
                    Button("Delete") {
                            showingConfirmation = true
                        }
                        .confirmationDialog(
                            "Are you sure you want to delete all settings?",
                            isPresented: $showingConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                clearAllSettings()
                            }
                            Button("Cancel", role: .cancel) { }
                        }
                }
            }

            Section(header: Text("Information")) {
                Group {
                    Text("Version: \(appVersionAndBuild())")
                    Text("Firmware: \(viewModel.version ?? "-")")
                    Text("Installed: \(viewModel.installationDate?.formatted(date: .long, time: .omitted) ?? "-")")
                    Text("Base: \(fleetBaseURL)")
#if os(tvOS)
                    Button("Save") { saveAndDismiss() }
#endif
                }
                .font(.footnote)
                .opacity(0.6)
#if os(macOS)
                .textSelection(.enabled)
#endif
            }
        }
    }
#if os(macOS)
    // MARK: – macOS
    private var macOSBody: some View {
        formContent
            .padding()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Save") { saveAndDismiss() }
                }
            }
    }
#else
    // MARK: – tvOS / iOS
    private var tvOSBody: some View {
        NavigationView {
            formContent
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") { saveAndDismiss() }
                    }
                }
                .padding()
        }
    }
#endif
    // MARK: – Actions
    private func saveAndDismiss() {
        UserDefaults.standard.set(loginMode.rawValue, forKey: "loginMode")
        if loginMode == .local {
            UserDefaults.standard.set(ipAddress, forKey: "gatewayIP")
            UserDefaults.standard.set(wallConnectorIPAddress, forKey: "wallConnectorIP")
            UserDefaults.standard.set(username, forKey: "username")
            KeychainWrapper.standard.set(password, forKey: "gatewayPassword")
        } else {
            KeychainWrapper.standard.set(accessToken, forKey: "fleetAPI_accessToken")
        }
        KeychainWrapper.standard.set(electricityMapsAPIKey, forKey: "electricityMaps_apiKey")
        UserDefaults.standard.set(electricityMapsZone, forKey: "electricityMaps_zone")
        UserDefaults.standard.set(preventScreenSaver, forKey: "preventScreenSaver")
        UserDefaults.standard.set(showLessPrecision, forKey: "showLessPrecision")
        UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar")
        viewModel.fetchElectricityMapsData()
        presentationMode.wrappedValue.dismiss()
    }

    private func clearAllSettings() {
        accessToken = ""
        KeychainWrapper.standard.set("", forKey: "fleetAPI_accessToken")
        KeychainWrapper.standard.set("", forKey: "fleetAPI_refreshToken")
        KeychainWrapper.standard.set("", forKey: "electricityMaps_apiKey")
        UserDefaults.standard.removeObject(forKey: "currentEnergySiteIndex")
        UserDefaults.standard.removeObject(forKey: "fleetAPI_tokenExpiration")
        UserDefaults.standard.removeObject(forKey: "fleetBaseURL")
        UserDefaults.standard.removeObject(forKey: "electricityMaps_zone")
    }
}

func appVersionAndBuild() -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    return "\(version) (\(build))"
}

// Preview provider (optional, for testing)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            loginMode: .constant(LoginMode.local),
            ipAddress: .constant("192.168.1.100"),
            wallConnectorIPAddress: .constant("192.168.1.101"),
            username: .constant("user@example.com"),
            password: .constant("password"),
            accessToken: .constant("accessToken"),
            fleetBaseURL: .constant("https://fleet-api.prd.na.vn.cloud.tesla.com"),
            electricityMapsAPIKey: .constant(""),
            electricityMapsZone: .constant(""),
            preventScreenSaver: .constant(false),
            showLessPrecision: .constant(false),
            showInMenuBar: .constant(false),
            showingConfirmation: false,
            viewModel: PowerwallViewModel()
        )
    }
}
